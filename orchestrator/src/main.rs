//! Orchestrator entrypoint.
//!
//! Drives Business Central over its APIs: authenticate, pull `validated`
//! invoices from the staging DB, import them into BC as drafts, and record the
//! result. Server-side batch posting (slice 3) is triggered separately.

mod bc_client;
mod config;
mod post;
mod reconcile;
mod retry;
mod throttle;
mod validate;

use std::collections::{HashMap, HashSet};
use std::sync::Arc;

use futures::stream::{self, StreamExt};
use ingestion::staging::PostgresStaging;
use ingestion::{DocType, Status};

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    tracing_subscriber::fmt()
        .with_env_filter(tracing_subscriber::EnvFilter::from_default_env())
        .init();

    let cfg = config::Config::from_env()?;
    let database_url = std::env::var("DATABASE_URL")
        .map_err(|_| anyhow::anyhow!("missing env var DATABASE_URL"))?;

    tracing::info!(env = %cfg.environment, "orchestrator starting");

    let staging = Arc::new(PostgresStaging::connect(&database_url).await?);
    staging.migrate().await?;

    // Adaptive concurrency limiter: starts at the configured concurrency,
    // backs off on 429, recovers as calls succeed.
    let limiter = throttle::AdaptiveLimiter::new(cfg.import_concurrency);

    let client = Arc::new(bc_client::BcClient::authenticate(&cfg, Arc::clone(&limiter)).await?);
    tracing::info!("authenticated against BC");

    // Subcommand: `orchestrator sync-refs` populates ref_entity from BC and exits.
    if std::env::args().nth(1).as_deref() == Some("sync-refs") {
        sync_references(&client, &staging).await?;
        return Ok(());
    }

    // Subcommand: `orchestrator reprocess` requeues previously invalid/failed
    // documents (clearing their errors), then continues into a normal run so
    // only those are retried — e.g. after fixing master data or mappings.
    if std::env::args().nth(1).as_deref() == Some("reprocess") {
        let n = staging.requeue_invalid_and_failed().await?;
        tracing::info!(requeued = n, "reprocessing previously invalid/failed documents");
    }

    // Each chunk gets its own batch code, so its server-side post job targets
    // exactly that chunk — letting us post chunk N while chunk N+1 imports.
    let run_code = new_batch_code()?;
    tracing::info!(%run_code, "run code");

    // Drain the whole validated backlog in chunks. Importing flips rows out of
    // `validated`, so the next fetch returns the next chunk until none remain.
    let mut imported = 0usize;
    let mut failed = 0usize;
    let mut chunk_idx = 0usize;
    // Post+reconcile of each chunk runs as a background task so it overlaps the
    // import of later chunks; joined at the end. Bounded so import can't run
    // more than `max_concurrent_chunks` ahead of posting (backpressure + caps
    // in-flight memory).
    let max_inflight = cfg.max_concurrent_chunks.max(1);
    let mut post_tasks: std::collections::VecDeque<tokio::task::JoinHandle<()>> =
        std::collections::VecDeque::new();
    // Guards against an infinite loop if rows can't leave `validated`
    // (e.g. a persistent staging-update error would keep re-fetching them).
    let mut seen: std::collections::HashSet<String> = std::collections::HashSet::new();

    tracing::info!(
        chunk_size = cfg.import_chunk_size,
        concurrency = cfg.import_concurrency,
        "draining validated backlog"
    );

    loop {
        let chunk = staging
            .fetch_by_status(Status::Validated, cfg.import_chunk_size as i64)
            .await?;
        if chunk.is_empty() {
            break;
        }

        // Only process invoices we haven't already attempted this run.
        let fresh: Vec<ingestion::Invoice> = chunk
            .into_iter()
            .filter(|i| !seen.contains(&i.idempotency_key))
            .collect();
        if fresh.is_empty() {
            tracing::warn!("fetched only already-attempted rows; stopping to avoid a loop");
            break;
        }
        for i in &fresh {
            seen.insert(i.idempotency_key.clone());
        }

        let n = fresh.len();
        let chunk_code = format!("{run_code}-{chunk_idx}"); // fits Code[20]
        chunk_idx += 1;

        let outcomes = import_batch(
            &client,
            &staging,
            &limiter,
            &chunk_code,
            cfg.require_party_mapping,
            cfg.require_item_mapping,
            cfg.validate_references,
            fresh,
        )
        .await;

        // Aggregate this chunk.
        let mut chunk_map: HashMap<String, String> = HashMap::new();
        let mut types: HashSet<DocType> = HashSet::new();
        let mut chunk_imported = 0usize;
        for outcome in outcomes {
            match outcome {
                Ok(o) if o.imported => {
                    imported += 1;
                    chunk_imported += 1;
                    types.insert(o.doc_type);
                    chunk_map.insert(o.ext, o.key);
                }
                Ok(_) => failed += 1,
                Err(e) => {
                    failed += 1;
                    tracing::error!(error = %e, "staging update error during import");
                }
            }
        }
        tracing::info!(chunk = n, chunk_imported, total_imported = imported, %chunk_code, "chunk imported");

        // Fire this chunk's posting + reconciliation in the background.
        if chunk_imported > 0 {
            let client = Arc::clone(&client);
            let staging = Arc::clone(&staging);
            let concurrency = cfg.import_concurrency;
            let handle = tokio::spawn(async move {
                if let Err(e) =
                    post_and_reconcile_chunk(&client, &staging, &chunk_code, types, chunk_map, concurrency).await
                {
                    tracing::error!(%chunk_code, error = %e, "post/reconcile failed");
                }
            });
            post_tasks.push_back(handle);

            // Backpressure: if too many chunks are posting, wait for the oldest.
            while post_tasks.len() >= max_inflight {
                if let Some(oldest) = post_tasks.pop_front() {
                    let _ = oldest.await;
                }
            }
        }
    }

    tracing::info!(imported, failed, chunks = chunk_idx, "import complete; awaiting posting");

    // Wait for any remaining chunk post/reconcile tasks to finish.
    while let Some(handle) = post_tasks.pop_front() {
        let _ = handle.await;
    }

    // Observability: end-of-run status counts + top error codes.
    tracing::info!("--- run summary ---");
    for (status, n) in staging.status_counts().await? {
        tracing::info!(%status, count = n, "status");
    }
    let buckets = staging.error_summary(15).await?;
    if !buckets.is_empty() {
        tracing::info!("--- top error codes ---");
        for (code, n) in buckets {
            tracing::warn!(count = n, %code, "error");
        }
    }

    tracing::info!("run complete");
    Ok(())
}

/// Flip a chunk's imported documents to `posting`, trigger one server-side post
/// job per document kind present, then reconcile the results back into staging.
async fn post_and_reconcile_chunk(
    client: &Arc<bc_client::BcClient>,
    staging: &Arc<PostgresStaging>,
    batch_code: &str,
    types: HashSet<DocType>,
    ext_to_key: HashMap<String, String>,
    concurrency: usize,
) -> anyhow::Result<()> {
    // Flip to `posting` concurrently.
    let keys: Vec<String> = ext_to_key.values().cloned().collect();
    let flips: Vec<anyhow::Result<()>> = stream::iter(keys.into_iter().map(|key| {
        let staging = Arc::clone(staging);
        async move { staging.update_status(&key, Status::Posting).await }
    }))
    .buffer_unordered(concurrency)
    .collect()
    .await;
    for r in flips {
        r?;
    }

    // One post job per kind present; the AL enum resolves each to its poster.
    let mut job_ids: Vec<String> = Vec::new();
    for dt in &types {
        job_ids.push(post::trigger_batch_post(client, batch_code, dt.enum_name()).await?);
    }

    reconcile::reconcile(client, staging, &job_ids, batch_code, &ext_to_key).await
}

/// Import one chunk of invoices concurrently with bounded backpressure.
/// `buffer_unordered` keeps at most `concurrency` requests in flight; the BC
/// client backs off on 429 per call. Each task writes its own staging updates
/// over the shared pool.
async fn import_batch(
    client: &Arc<bc_client::BcClient>,
    staging: &Arc<PostgresStaging>,
    limiter: &Arc<throttle::AdaptiveLimiter>,
    batch_code: &str,
    require_party: bool,
    require_item: bool,
    validate_refs: bool,
    invoices: Vec<ingestion::Invoice>,
) -> Vec<anyhow::Result<ImportOutcome>> {
    let cap = limiter.max();
    stream::iter(invoices.into_iter().map(|inv| {
        let client = Arc::clone(client);
        let staging = Arc::clone(staging);
        let limiter = Arc::clone(limiter);
        let batch_code = batch_code.to_string();
        async move {
            // Hold an adaptive permit for the whole invoice; concurrency shrinks
            // under 429 pressure and recovers as calls succeed.
            let _permit = limiter.acquire().await;
            let doc_type = inv.doc_type;
            let ext = inv.external_document_no.clone();
            let key = inv.idempotency_key.clone();
            let make = |imported| ImportOutcome { imported, doc_type, ext: ext.clone(), key: key.clone() };

            // Collect validation errors instead of stopping at the first, so the
            // full picture for every document lands in the external error store.
            let mut errors: Vec<ingestion::DocError> = Vec::new();

            // Resolve the source party to a BC customer/vendor number.
            let mut inv = inv;
            match resolve_party(&staging, &inv).await? {
                PartyResolution::Resolved(bc_no) => inv.partner_no = bc_no,
                PartyResolution::Passthrough => {} // keep source id as-is
                PartyResolution::Unmapped => {
                    if require_party {
                        errors.push(ingestion::DocError::header(
                            "UNMAPPED_PARTY",
                            Some("partner_no"),
                            format!("no party mapping for '{}'", inv.partner_no),
                        ));
                    }
                }
            }

            // Resolve each line's item code to a BC item number.
            if let Some(unmapped) = resolve_items(&staging, &mut inv, require_item).await? {
                errors.push(ingestion::DocError::header(
                    "UNMAPPED_ITEM",
                    Some("no"),
                    format!("no item mapping for '{unmapped}'"),
                ));
            }

            // Field + reference-data validation (accumulates all errors).
            errors.extend(validate::validate_document(&staging, &inv, validate_refs).await?);

            if !errors.is_empty() {
                staging.record_errors(&key, &errors).await?;
                staging.update_status(&key, Status::Invalid).await?;
                tracing::warn!(%key, errors = errors.len(), "invalid; not sent to BC");
                return anyhow::Ok(make(false));
            }

            match import_one(&client, &inv, &batch_code).await {
                Ok(number) => {
                    staging.set_bc_document_no(&key, &number).await?;
                    staging.update_status(&key, Status::Imported).await?;
                    tracing::info!(%key, number = %number, "imported");
                    anyhow::Ok(make(true))
                }
                Err(e) => {
                    // BC rejected it — capture the error, roll status back to failed.
                    staging.record_errors(&key, &[ingestion::DocError::bc(e.to_string())]).await?;
                    staging.update_status(&key, Status::Failed).await?;
                    tracing::error!(%key, error = %e, "import failed");
                    anyhow::Ok(make(false))
                }
            }
        }
    }))
    .buffer_unordered(cap)
    .collect()
    .await
}

/// Outcome of resolving an invoice's party against the map.
enum PartyResolution {
    /// Found a BC number.
    Resolved(String),
    /// No map row, but caller may pass the source id through.
    Unmapped,
    /// Source id is already usable (empty map lookups skipped) — treated as
    /// pass-through. Currently only produced when the lookup itself is skipped.
    Passthrough,
}

/// Look up the document's party via the doc-type registry (customer/vendor).
/// Party-less kinds (production/assembly/transfer) or empty ids pass through.
async fn resolve_party(
    staging: &PostgresStaging,
    inv: &ingestion::Invoice,
) -> anyhow::Result<PartyResolution> {
    let Some(kind) = inv.doc_type.party_kind() else {
        return Ok(PartyResolution::Passthrough);
    };
    if inv.partner_no.trim().is_empty() {
        return Ok(PartyResolution::Passthrough);
    }
    match staging.resolve_party(kind, &inv.partner_no).await? {
        Some(bc_no) => Ok(PartyResolution::Resolved(bc_no)),
        None => Ok(PartyResolution::Unmapped),
    }
}

/// Resolve each line's item code to a BC item number in place. Returns the first
/// unmapped code when `require` is set (caller fails the invoice); otherwise
/// unmapped codes pass through unchanged.
async fn resolve_items(
    staging: &PostgresStaging,
    inv: &mut ingestion::Invoice,
    require: bool,
) -> anyhow::Result<Option<String>> {
    for line in &mut inv.lines {
        if line.no.trim().is_empty() {
            continue;
        }
        match staging.resolve_item(&line.no).await? {
            Some(bc_no) => line.no = bc_no,
            None => {
                if require {
                    return Ok(Some(line.no.clone()));
                }
            }
        }
    }
    Ok(None)
}

/// Outcome of importing one invoice (used to aggregate the concurrent run).
struct ImportOutcome {
    imported: bool,
    doc_type: DocType,
    ext: String,
    key: String,
}

/// Create a draft invoice for the invoice's document type and stamp it with the
/// batch code. Returns the BC document number.
async fn import_one(
    client: &bc_client::BcClient,
    inv: &ingestion::Invoice,
    batch_code: &str,
) -> anyhow::Result<String> {
    match inv.doc_type {
        DocType::Sales => {
            let created = client.create_sales_invoice(inv).await?;
            client.tag_sales_invoice(&created.id, batch_code).await?;
            Ok(created.number)
        }
        DocType::Purchase => {
            let created = client.create_purchase_invoice(inv).await?;
            client.tag_purchase_invoice(&created.id, batch_code).await?;
            Ok(created.number)
        }
        DocType::Service => {
            // The custom service API sets the batch code inline (no tag call).
            let created = client.create_service_invoice(inv, batch_code).await?;
            Ok(created.number)
        }
        DocType::PurchaseOrder => Ok(client.create_purchase_order(inv, batch_code).await?.number),
        DocType::AssemblyOrder => Ok(client.create_assembly_order(inv, batch_code).await?.number),
        DocType::ProductionOrder => Ok(client.create_production_order(inv, batch_code).await?.number),
        DocType::TransferOrder => Ok(client.create_transfer_order(inv, batch_code).await?.number),
    }
}

/// Sync BC reference data (customers/vendors/items) into `ref_entity`, so
/// external validation can reject unknown parties/items without touching BC.
/// Posting-group errors remain caught by the BC safety net during posting.
async fn sync_references(
    client: &bc_client::BcClient,
    staging: &PostgresStaging,
) -> anyhow::Result<()> {
    for (entity, kind) in [("customers", "customer"), ("vendors", "vendor"), ("items", "item")] {
        let rows = client.list_reference(entity).await?;
        for (no, name) in &rows {
            staging.ref_upsert(kind, no, name.as_deref()).await?;
        }
        tracing::info!(kind, count = rows.len(), "synced references");
    }
    tracing::info!("reference sync complete — set VALIDATE_REFERENCES=true to enable checks");
    Ok(())
}

/// A short unique-ish batch code (max 20 chars for the AL Code[20] field).
fn new_batch_code() -> anyhow::Result<String> {
    let secs = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)?
        .as_secs();
    Ok(format!("B{secs}"))
}
