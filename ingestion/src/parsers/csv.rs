//! CSV parser.
//!
//! Expects a flat CSV where each row is one invoice line. Rows are grouped into
//! invoices by (doc_type, external_document_no, partner_no). Expected header:
//!
//! ```text
//! doc_type,external_document_no,partner_no,document_date,currency_code,item_no,description,quantity,unit_price
//! ```
//!
//! `doc_type` is one of: sales | purchase | service.

use std::collections::BTreeMap;

use serde::Deserialize;

use crate::canonical::{DocType, Document, DocumentLine, Invoice};
use crate::parsers::{Parser, SourceFormat};
use crate::{IngestError, Result};

pub struct CsvParser;

/// One raw CSV row, before grouping/typing.
#[derive(Debug, Deserialize)]
struct Row {
    doc_type: String,
    external_document_no: String,
    partner_no: String,
    document_date: String,
    currency_code: String,
    item_no: String,
    description: String,
    quantity: f64,
    unit_price: f64,
}

fn parse_doc_type(s: &str) -> Result<DocType> {
    DocType::from_tag(s).ok_or_else(|| IngestError::Validation(format!("unknown doc_type '{s}'")))
}

impl Parser for CsvParser {
    fn format(&self) -> SourceFormat {
        SourceFormat::Csv
    }

    fn parse(&self, file_name: &str, bytes: &[u8]) -> Result<Vec<Invoice>> {
        let mut reader = csv::ReaderBuilder::new()
            .has_headers(true)
            .trim(csv::Trim::All)
            .from_reader(bytes);

        // Preserve first-seen order of invoices while grouping their lines.
        let mut order: Vec<String> = Vec::new();
        let mut grouped: BTreeMap<String, Invoice> = BTreeMap::new();

        for result in reader.deserialize::<Row>() {
            let row = result.map_err(|e| IngestError::Parse {
                file: file_name.to_string(),
                source: e.into(),
            })?;

            let doc_type = parse_doc_type(&row.doc_type)?;
            let key = Document::idempotency_key(doc_type, &row.external_document_no, &row.partner_no);

            let line = DocumentLine::new(row.item_no, row.description, row.quantity, row.unit_price);

            grouped
                .entry(key.clone())
                .or_insert_with(|| {
                    order.push(key.clone());
                    Document::new(
                        doc_type,
                        row.external_document_no,
                        row.partner_no,
                        row.document_date,
                        row.currency_code,
                        Vec::new(),
                    )
                })
                .lines
                .push(line);
        }

        // Return in first-seen order rather than key order.
        Ok(order
            .into_iter()
            .filter_map(|k| grouped.remove(&k))
            .collect())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const SAMPLE: &str = "\
doc_type,external_document_no,partner_no,document_date,currency_code,item_no,description,quantity,unit_price
sales,INV-1001,C10000,2026-07-10,EUR,ITEM-A,Widget A,2,15.50
sales,INV-1001,C10000,2026-07-10,EUR,ITEM-B,Widget B,1,40.00
purchase,PINV-5001,V20000,2026-07-09,USD,ITEM-C,Raw material,10,3.25
";

    #[test]
    fn groups_lines_into_invoices() {
        let invoices = CsvParser.parse("sample.csv", SAMPLE.as_bytes()).unwrap();
        assert_eq!(invoices.len(), 2);

        let inv = &invoices[0];
        assert_eq!(inv.doc_type, DocType::Sales);
        assert_eq!(inv.external_document_no, "INV-1001");
        assert_eq!(inv.lines.len(), 2);
        assert_eq!(inv.lines[1].no, "ITEM-B");

        assert_eq!(invoices[1].doc_type, DocType::Purchase);
        assert_eq!(invoices[1].lines.len(), 1);
    }

    #[test]
    fn rejects_unknown_doc_type() {
        let bad = "doc_type,external_document_no,partner_no,document_date,currency_code,item_no,description,quantity,unit_price\n\
                   quote,X,Y,2026-07-10,EUR,I,d,1,1\n";
        assert!(CsvParser.parse("bad.csv", bad.as_bytes()).is_err());
    }
}
