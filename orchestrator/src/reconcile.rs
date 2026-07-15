//! Reconciliation: after posting is triggered, poll BC for the job's outcome
//! and update per-invoice staging status (`posting -> posted | failed`).
//!
//! Results are matched back to staged invoices by their external document
//! number, so the caller supplies an external-no -> idempotency-key map built
//! from the invoices it imported this run.

use std::collections::HashMap;

use ingestion::staging::PostgresStaging;
use ingestion::Status;
use serde::Deserialize;

use crate::bc_client::BcClient;

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct JobDto {
    status: String,
    posted_count: i64,
    failed_count: i64,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct ResultDto {
    source_document_no: String,
    #[allow(dead_code)]
    posted_document_no: String,
    success: bool,
    #[serde(default)]
    error_message: String,
}

#[derive(Debug, Deserialize)]
struct ODataList<T> {
    value: Vec<T>,
}

/// Poll each job to a terminal state, then apply the batch's per-document
/// results to staging. `ext_to_key` maps external document number ->
/// idempotency key. All jobs share one batch code, so results are fetched once.
pub async fn reconcile(
    client: &BcClient,
    staging: &PostgresStaging,
    job_ids: &[String],
    batch_code: &str,
    ext_to_key: &HashMap<String, String>,
) -> anyhow::Result<()> {
    // Poll each job until its background posting session finishes (or we give up).
    for job_id in job_ids {
        for attempt in 0..30u32 {
            let job: JobDto = serde_json::from_value(client.get_batch_post_job(job_id).await?)?;
            tracing::info!(
                %job_id,
                status = %job.status,
                posted = job.posted_count,
                failed = job.failed_count,
                "job poll"
            );
            if job.status == "Completed" || job.status == "Failed" {
                break;
            }
            tokio::time::sleep(crate::retry::backoff_delay(attempt.min(4))).await;
        }
    }

    // Apply per-document outcomes (covers every job under this batch code).
    let list: ODataList<ResultDto> =
        serde_json::from_value(client.list_post_results(batch_code).await?)?;

    let mut posted = 0usize;
    let mut failed = 0usize;
    for r in list.value {
        match ext_to_key.get(&r.source_document_no) {
            Some(key) if r.success => {
                staging.update_status(key, Status::Posted).await?;
                posted += 1;
            }
            Some(key) => {
                let msg = if r.error_message.is_empty() {
                    "post failed".to_string()
                } else {
                    r.error_message.clone()
                };
                staging.record_errors(key, &[ingestion::DocError::bc(msg)]).await?;
                staging.update_status(key, Status::Failed).await?;
                failed += 1;
                tracing::warn!(src = %r.source_document_no, reason = %r.error_message, "post failed");
            }
            None => {
                tracing::warn!(src = %r.source_document_no, "result had no matching staged invoice");
            }
        }
    }

    tracing::info!(posted, failed, "reconciliation complete");
    Ok(())
}
