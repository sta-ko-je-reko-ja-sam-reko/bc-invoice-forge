//! Triggering server-side posting.
//!
//! The throughput lever: instead of posting each invoice over HTTP, we create a
//! batch-post job and fire its bound `run` action once. The AL `BatchPost`
//! codeunit then loops and posts all invoices in that batch inside BC, in a
//! background session.

use crate::bc_client::BcClient;

/// Create a batch-post job for `batch_code` and trigger it server-side.
/// `doc_type` is one of: "Sales" | "Purchase" | "Service".
/// Returns the job's systemId so the caller can reconcile its results.
pub async fn trigger_batch_post(
    client: &BcClient,
    batch_code: &str,
    doc_type: &str,
) -> anyhow::Result<String> {
    let job_id = client.create_batch_post_job(batch_code, doc_type).await?;
    client.run_batch_post_job(&job_id).await?;
    tracing::info!(%batch_code, %doc_type, %job_id, "batch post triggered");
    Ok(job_id)
}
