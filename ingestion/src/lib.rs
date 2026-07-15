//! Ingestion: turn messy source files into clean, validated, staged invoices.
//!
//! Pipeline: detect format -> parse -> canonical model -> validate/dedup -> stage.
//! Nothing here talks to Business Central; that is the orchestrator's job.

pub mod canonical;
pub mod errors;
pub mod parsers;
pub mod staging;
pub mod validation;

pub use canonical::{DocType, Document, DocumentLine, Invoice, InvoiceLine};
pub use errors::{DocError, ErrorScope, ErrorSource};
pub use parsers::{detect_format, Parser, ParserRegistry, SourceFormat};
pub use staging::{Staging, Status};
pub use validation::Validated;

/// Summary of ingesting one file's worth of invoices.
#[derive(Debug, Default, PartialEq, Eq)]
pub struct IngestReport {
    pub parsed: usize,
    pub staged: usize,
    pub duplicates: usize,
    pub rejected: usize,
}

/// Run the full ingestion pipeline for one file:
/// detect + parse -> dedup -> validate -> stage.
///
/// Rejected and duplicate invoices are counted but not staged as `Validated`;
/// this is the single entry point the orchestrator (or a CLI) drives.
pub async fn ingest_file(
    registry: &ParserRegistry,
    staging: &mut dyn Staging,
    file_name: &str,
    bytes: &[u8],
) -> Result<IngestReport> {
    let parsed = registry.parse_file(file_name, bytes)?;
    let mut report = IngestReport {
        parsed: parsed.len(),
        ..Default::default()
    };

    let before = parsed.len();
    let unique = validation::dedup(parsed);
    report.duplicates = before - unique.len();

    for invoice in unique {
        match validation::validate(invoice)? {
            Validated::Ok(inv) => {
                let newly = staging
                    .upsert(&inv, Status::Validated)
                    .await
                    .map_err(|e| IngestError::Staging(e.to_string()))?;
                if newly {
                    report.staged += 1;
                } else {
                    report.duplicates += 1;
                }
            }
            Validated::Rejected { invoice, reason } => {
                report.rejected += 1;
                staging
                    .upsert(&invoice, Status::Failed)
                    .await
                    .map_err(|e| IngestError::Staging(e.to_string()))?;
                tracing::warn!(key = %invoice.idempotency_key, %reason, "invoice rejected");
            }
        }
    }

    Ok(report)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::staging::InMemoryStaging;

    const CSV: &str = "\
doc_type,external_document_no,partner_no,document_date,currency_code,item_no,description,quantity,unit_price
sales,INV-1001,C10000,2026-07-10,EUR,ITEM-A,Widget A,2,15.50
sales,INV-1001,C10000,2026-07-10,EUR,ITEM-B,Widget B,1,40.00
purchase,PINV-5001,V20000,2026-07-09,USD,ITEM-C,Raw material,10,3.25
";

    #[tokio::test]
    async fn ingest_file_stages_validated_invoices() {
        let registry = ParserRegistry::with_defaults();
        let mut staging = InMemoryStaging::default();

        let report = ingest_file(&registry, &mut staging, "batch.csv", CSV.as_bytes())
            .await
            .unwrap();

        assert_eq!(report.parsed, 2);
        assert_eq!(report.staged, 2);
        assert_eq!(report.rejected, 0);
        assert_eq!(staging.count(Status::Validated).await.unwrap(), 2);
    }

    #[tokio::test]
    async fn rerun_is_idempotent() {
        let registry = ParserRegistry::with_defaults();
        let mut staging = InMemoryStaging::default();

        ingest_file(&registry, &mut staging, "batch.csv", CSV.as_bytes())
            .await
            .unwrap();
        let second = ingest_file(&registry, &mut staging, "batch.csv", CSV.as_bytes())
            .await
            .unwrap();

        // Nothing new staged on the second run; same two rows counted as dupes.
        assert_eq!(second.staged, 0);
        assert_eq!(second.duplicates, 2);
        assert_eq!(staging.count(Status::Validated).await.unwrap(), 2);
    }
}

/// Errors surfaced by the ingestion pipeline.
#[derive(Debug, thiserror::Error)]
pub enum IngestError {
    #[error("could not detect the format of {0}")]
    UnknownFormat(String),

    #[error("parse error in {file}: {source}")]
    Parse {
        file: String,
        #[source]
        source: anyhow::Error,
    },

    #[error("validation failed: {0}")]
    Validation(String),

    #[error("staging error: {0}")]
    Staging(String),
}

pub type Result<T> = std::result::Result<T, IngestError>;
