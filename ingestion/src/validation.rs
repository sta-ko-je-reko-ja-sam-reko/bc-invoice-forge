//! Business/schema validation and dedup, run before anything reaches BC.

use crate::canonical::Invoice;
use crate::errors::DocError;
use crate::Result;

/// Accumulate ALL structural/field errors for a document (header + every line).
/// Unlike [`validate`], this does not stop at the first problem — the caller
/// stores the full list so nothing is lost. Reference-data checks (unknown
/// customer/vendor/item) are layered on top by the orchestrator.
pub fn validate_fields(doc: &Invoice) -> Vec<DocError> {
    let mut errors = Vec::new();

    if doc.external_document_no.trim().is_empty() {
        errors.push(DocError::header(
            "MISSING_DOCUMENT_NO",
            Some("external_document_no"),
            "external document number is empty",
        ));
    }
    if doc.partner_no.trim().is_empty() {
        errors.push(DocError::header(
            "MISSING_PARTNER",
            Some("partner_no"),
            "partner (customer/vendor) is empty",
        ));
    }
    if doc.lines.is_empty() {
        errors.push(DocError::header("NO_LINES", None, "document has no lines"));
    }

    for (i, line) in doc.lines.iter().enumerate() {
        let ln = (i + 1) as i32;
        if line.no.trim().is_empty() {
            errors.push(DocError::line(ln, "MISSING_ITEM_NO", Some("no"), "line item number is empty"));
        }
        if line.quantity <= 0.0 {
            errors.push(DocError::line(
                ln,
                "INVALID_QUANTITY",
                Some("quantity"),
                format!("quantity must be > 0 (got {})", line.quantity),
            ));
        }
    }

    errors
}

/// Outcome of validating a single invoice.
#[derive(Debug, Clone)]
pub enum Validated {
    Ok(Invoice),
    Rejected { invoice: Invoice, reason: String },
}

/// Validate one invoice against schema + basic business rules.
///
/// Placeholder rules — extend with: mandatory fields, positive amounts,
/// currency present, date parseable, at least one line, master-data refs.
pub fn validate(invoice: Invoice) -> Result<Validated> {
    if invoice.external_document_no.trim().is_empty() {
        return Ok(Validated::Rejected {
            invoice,
            reason: "external_document_no is empty".into(),
        });
    }
    if invoice.lines.is_empty() {
        return Ok(Validated::Rejected {
            invoice,
            reason: "invoice has no lines".into(),
        });
    }
    Ok(Validated::Ok(invoice))
}

/// Drop duplicates by idempotency key, keeping first occurrence.
pub fn dedup(invoices: Vec<Invoice>) -> Vec<Invoice> {
    let mut seen = std::collections::HashSet::new();
    invoices
        .into_iter()
        .filter(|i| seen.insert(i.idempotency_key.clone()))
        .collect()
}
