//! JSON invoice parser.
//!
//! Accepts either a single invoice object or an array of them. The JSON shape
//! mirrors the canonical model (camelCase):
//!
//! ```json
//! {
//!   "docType": "sales",
//!   "externalDocumentNo": "INV-1",
//!   "partnerNo": "C10000",
//!   "documentDate": "2026-07-10",
//!   "currencyCode": "EUR",
//!   "lines": [ { "no": "ITEM-A", "description": "Widget", "quantity": 2, "unitPrice": 15.5 } ]
//! }
//! ```

use serde::Deserialize;

use crate::canonical::{DocType, Document, DocumentLine, Invoice};
use crate::parsers::{Parser, SourceFormat};
use crate::{IngestError, Result};

pub struct JsonParser;

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct JsonInvoice {
    doc_type: String,
    external_document_no: String,
    partner_no: String,
    document_date: String,
    currency_code: String,
    #[serde(default)]
    lines: Vec<JsonLine>,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct JsonLine {
    no: String,
    #[serde(default)]
    description: String,
    quantity: f64,
    unit_price: f64,
}

/// Accept `[ {...}, {...} ]` or a single `{...}`.
#[derive(Debug, Deserialize)]
#[serde(untagged)]
enum OneOrMany {
    Many(Vec<JsonInvoice>),
    One(JsonInvoice),
}

impl Parser for JsonParser {
    fn format(&self) -> SourceFormat {
        SourceFormat::Json
    }

    fn parse(&self, file_name: &str, bytes: &[u8]) -> Result<Vec<Invoice>> {
        let parsed: OneOrMany = serde_json::from_slice(bytes).map_err(|e| IngestError::Parse {
            file: file_name.to_string(),
            source: e.into(),
        })?;

        let raw = match parsed {
            OneOrMany::Many(v) => v,
            OneOrMany::One(o) => vec![o],
        };

        raw.into_iter().map(convert).collect()
    }
}

fn convert(j: JsonInvoice) -> Result<Invoice> {
    let doc_type = DocType::from_tag(&j.doc_type)
        .ok_or_else(|| IngestError::Validation(format!("unknown docType '{}'", j.doc_type)))?;

    let lines = j
        .lines
        .into_iter()
        .map(|l| DocumentLine::new(l.no, l.description, l.quantity, l.unit_price))
        .collect();

    Ok(Document::new(
        doc_type,
        j.external_document_no,
        j.partner_no,
        j.document_date,
        j.currency_code,
        lines,
    ))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_single_object() {
        let json = br#"{
            "docType": "sales",
            "externalDocumentNo": "INV-J1",
            "partnerNo": "C10000",
            "documentDate": "2026-07-10",
            "currencyCode": "EUR",
            "lines": [ { "no": "ITEM-A", "description": "Widget", "quantity": 2, "unitPrice": 15.5 } ]
        }"#;
        let invoices = JsonParser.parse("inv.json", json).unwrap();
        assert_eq!(invoices.len(), 1);
        assert_eq!(invoices[0].doc_type, DocType::Sales);
        assert_eq!(invoices[0].external_document_no, "INV-J1");
        assert_eq!(invoices[0].lines.len(), 1);
        assert_eq!(invoices[0].lines[0].unit_price, 15.5);
    }

    #[test]
    fn parses_array() {
        let json = br#"[
            {"docType":"sales","externalDocumentNo":"A","partnerNo":"C1","documentDate":"2026-07-10","currencyCode":"EUR","lines":[]},
            {"docType":"purchase","externalDocumentNo":"B","partnerNo":"V1","documentDate":"2026-07-10","currencyCode":"USD","lines":[]}
        ]"#;
        let invoices = JsonParser.parse("inv.json", json).unwrap();
        assert_eq!(invoices.len(), 2);
        assert_eq!(invoices[1].doc_type, DocType::Purchase);
    }
}
