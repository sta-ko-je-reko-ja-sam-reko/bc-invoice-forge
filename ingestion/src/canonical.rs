//! The canonical document model.
//!
//! One internal representation for **all** source formats and **all** document
//! kinds (invoices + orders). Everything downstream of parsing works against
//! `Document` and never cares where it came from. Kind-specific data that
//! doesn't fit the common fields rides along in `header_fields` / `line_fields`.
//!
//! `Invoice` / `InvoiceLine` remain as aliases for backward compatibility.

use std::collections::BTreeMap;

use serde::{Deserialize, Serialize};

/// Which BC document + posting path this belongs to.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum DocType {
    /// Sales invoice; posted via Sales-Post (CU 80).
    Sales,
    /// Purchase invoice; posted via Purch-Post (CU 90).
    Purchase,
    /// Service invoice; posted via Service-Post (custom API page).
    Service,
    /// Purchase order; received + invoiced.
    PurchaseOrder,
    /// Production order; output/finish posting.
    ProductionOrder,
    /// Assembly order; posted via Assembly-Post.
    AssemblyOrder,
    /// Transfer order; ship + receive.
    TransferOrder,
}

impl DocType {
    /// Canonical lowercase tag used in keys and cross-format parsing.
    pub fn tag(self) -> &'static str {
        match self {
            DocType::Sales => "sales",
            DocType::Purchase => "purchase",
            DocType::Service => "service",
            DocType::PurchaseOrder => "purchase_order",
            DocType::ProductionOrder => "production_order",
            DocType::AssemblyOrder => "assembly_order",
            DocType::TransferOrder => "transfer_order",
        }
    }

    /// Parse a doc-type tag (case-insensitive). Accepts short invoice aliases
    /// (`sales`/`purchase`/`service`) and the explicit order tags.
    pub fn from_tag(s: &str) -> Option<DocType> {
        match s.trim().to_lowercase().as_str() {
            "sales" | "sales_invoice" => Some(DocType::Sales),
            "purchase" | "purchase_invoice" => Some(DocType::Purchase),
            "service" | "service_invoice" => Some(DocType::Service),
            "purchase_order" | "po" => Some(DocType::PurchaseOrder),
            "production_order" | "prod_order" => Some(DocType::ProductionOrder),
            "assembly_order" | "asm_order" => Some(DocType::AssemblyOrder),
            "transfer_order" | "transfer" => Some(DocType::TransferOrder),
            _ => None,
        }
    }

    /// Reference kind for this document's party, or None if it has no
    /// customer/vendor party (production/assembly/transfer). Drives party
    /// resolution + validation without per-call-site matches (the "registry").
    pub fn party_kind(self) -> Option<&'static str> {
        match self {
            DocType::Sales | DocType::Service => Some("customer"),
            DocType::Purchase | DocType::PurchaseOrder => Some("vendor"),
            DocType::ProductionOrder | DocType::AssemblyOrder | DocType::TransferOrder => None,
        }
    }

    /// AL enum value name (matches the `BIF Doc Type` enum) sent to BC as the
    /// batch-post job's `docType`.
    pub fn enum_name(self) -> &'static str {
        match self {
            DocType::Sales => "Sales",
            DocType::Purchase => "Purchase",
            DocType::Service => "Service",
            DocType::PurchaseOrder => "PurchaseOrder",
            DocType::ProductionOrder => "ProductionOrder",
            DocType::AssemblyOrder => "AssemblyOrder",
            DocType::TransferOrder => "TransferOrder",
        }
    }

    /// Whether this is an order (vs. an invoice). Orders post differently.
    pub fn is_order(self) -> bool {
        matches!(
            self,
            DocType::PurchaseOrder
                | DocType::ProductionOrder
                | DocType::AssemblyOrder
                | DocType::TransferOrder
        )
    }
}

/// A single document, format- and source-agnostic.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Document {
    pub doc_type: DocType,
    /// Document number from the source system (external reference).
    pub external_document_no: String,
    /// Customer/vendor no (empty for party-less docs like production orders).
    pub partner_no: String,
    /// ISO date, e.g. "2026-07-10".
    pub document_date: String,
    pub currency_code: String,
    /// Kind-specific header data (location code, order date, output item, ...).
    #[serde(default)]
    pub header_fields: BTreeMap<String, String>,
    pub lines: Vec<DocumentLine>,
    /// Deterministic dedup/idempotency key; see `idempotency_key`.
    pub idempotency_key: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DocumentLine {
    /// Item/GL/resource number.
    pub no: String,
    pub description: String,
    pub quantity: f64,
    pub unit_price: f64,
    /// Kind-specific line data (location, routing, bin, dimensions, ...).
    #[serde(default)]
    pub line_fields: BTreeMap<String, String>,
}

/// Backward-compatible aliases.
pub type Invoice = Document;
pub type InvoiceLine = DocumentLine;

impl Document {
    /// Build a document, computing its idempotency key. `header_fields` start
    /// empty; add with [`Document::with_header_field`].
    pub fn new(
        doc_type: DocType,
        external_document_no: String,
        partner_no: String,
        document_date: String,
        currency_code: String,
        lines: Vec<DocumentLine>,
    ) -> Self {
        let idempotency_key = Self::idempotency_key(doc_type, &external_document_no, &partner_no);
        Self {
            doc_type,
            external_document_no,
            partner_no,
            document_date,
            currency_code,
            header_fields: BTreeMap::new(),
            lines,
            idempotency_key,
        }
    }

    /// Builder helper for a kind-specific header field.
    pub fn with_header_field(mut self, key: &str, value: impl Into<String>) -> Self {
        self.header_fields.insert(key.to_string(), value.into());
        self
    }

    /// Deterministic idempotency key from the business key (doc type + partner +
    /// external document number). Fields are normalized (trim + lowercase) and
    /// length-prefixed before hashing, so no value can be crafted to collide via
    /// delimiter injection. Returns a 64-char blake3 hex digest.
    pub fn idempotency_key(doc_type: DocType, external_document_no: &str, partner_no: &str) -> String {
        let parts = [
            doc_type.tag().to_string(),
            partner_no.trim().to_lowercase(),
            external_document_no.trim().to_lowercase(),
        ];

        let mut hasher = blake3::Hasher::new();
        for part in &parts {
            hasher.update(&(part.len() as u64).to_le_bytes());
            hasher.update(part.as_bytes());
        }
        hasher.finalize().to_hex().to_string()
    }
}

impl DocumentLine {
    /// Build a line with empty `line_fields`.
    pub fn new(no: String, description: String, quantity: f64, unit_price: f64) -> Self {
        Self {
            no,
            description,
            quantity,
            unit_price,
            line_fields: BTreeMap::new(),
        }
    }

    /// Builder helper for a kind-specific line field.
    pub fn with_line_field(mut self, key: &str, value: impl Into<String>) -> Self {
        self.line_fields.insert(key.to_string(), value.into());
        self
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn key_is_stable_and_normalized() {
        let a = Document::idempotency_key(DocType::Sales, "INV-1", "C10");
        let b = Document::idempotency_key(DocType::Sales, " inv-1 ", "c10");
        assert_eq!(a, b, "normalization should make these equal");
        assert_eq!(a.len(), 64);
    }

    #[test]
    fn distinct_fields_do_not_collide() {
        let a = Document::idempotency_key(DocType::Sales, "ab", "c");
        let b = Document::idempotency_key(DocType::Sales, "a", "bc");
        assert_ne!(a, b);
    }

    #[test]
    fn doc_type_changes_key() {
        let s = Document::idempotency_key(DocType::Sales, "X", "P");
        let p = Document::idempotency_key(DocType::Purchase, "X", "P");
        assert_ne!(s, p);
    }

    #[test]
    fn tag_roundtrips() {
        for dt in [
            DocType::Sales,
            DocType::Purchase,
            DocType::Service,
            DocType::PurchaseOrder,
            DocType::ProductionOrder,
            DocType::AssemblyOrder,
            DocType::TransferOrder,
        ] {
            assert_eq!(DocType::from_tag(dt.tag()), Some(dt));
        }
    }
}
