//! Pre-import validation: accumulate ALL of a document's errors (fields +
//! reference data) so invalid documents are stored with full detail and never
//! sent to BC. Runs after party/item resolution, so `partner_no` / line `no`
//! are already the resolved BC numbers.

use ingestion::staging::PostgresStaging;
use ingestion::{DocError, Invoice};

/// Return every error for `doc` (empty vec == valid). When `check_refs` is on,
/// resolved parties/items are checked against synced BC reference data.
pub async fn validate_document(
    staging: &PostgresStaging,
    doc: &Invoice,
    check_refs: bool,
) -> anyhow::Result<Vec<DocError>> {
    // Field/structural checks (never touch the DB).
    let mut errors = ingestion::validation::validate_fields(doc);

    if !check_refs {
        return Ok(errors);
    }

    // Reference-data checks against ref_entity (party kind from the registry).
    if let Some(kind) = doc.doc_type.party_kind() {
        if !doc.partner_no.trim().is_empty() && !staging.ref_exists(kind, &doc.partner_no).await? {
            errors.push(DocError::header(
                "UNKNOWN_PARTY",
                Some("partner_no"),
                format!("{kind} '{}' not found in BC reference data", doc.partner_no),
            ));
        }
    }

    for (i, line) in doc.lines.iter().enumerate() {
        if !line.no.trim().is_empty() && !staging.ref_exists("item", &line.no).await? {
            errors.push(DocError::line(
                (i + 1) as i32,
                "UNKNOWN_ITEM",
                Some("no"),
                format!("item '{}' not found in BC reference data", line.no),
            ));
        }
    }

    Ok(errors)
}
