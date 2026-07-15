//! UBL (PEPPOL BIS Billing 3.0) invoice XML parser.
//!
//! Parses a single `<Invoice>` document into the canonical model. UBL is
//! namespaced (cbc:/cac:), so we match on **local** element names and use the
//! element path to disambiguate the many `ID` fields.
//!
//! A received supplier invoice maps to a **purchase** invoice in BC. The
//! supplier's party identifier becomes `partner_no` — resolving it to a real BC
//! vendor number is a downstream mapping concern (see TODO).

use quick_xml::events::{BytesEnd, BytesStart, Event};
use quick_xml::name::QName;
use quick_xml::reader::Reader;

use crate::canonical::{DocType, Document, DocumentLine, Invoice};
use crate::parsers::{Parser, SourceFormat};
use crate::{IngestError, Result};

/// Wrap any XML error type (read/unescape errors differ across quick-xml
/// versions) into an `IngestError::Parse`.
fn parse_err<E>(file: &str, e: E) -> IngestError
where
    E: std::error::Error + Send + Sync + 'static,
{
    IngestError::Parse {
        file: file.to_string(),
        source: e.into(),
    }
}

pub struct XmlParser;

impl Parser for XmlParser {
    fn format(&self) -> SourceFormat {
        SourceFormat::Xml
    }

    fn parse(&self, file_name: &str, bytes: &[u8]) -> Result<Vec<Invoice>> {
        Ok(parse_invoice_xml(file_name, bytes)?.into_iter().collect())
    }
}

/// Parse a UBL or UN/CEFACT CII invoice XML into the canonical model.
/// Shared entry point reused by the PDF (Factur-X/ZUGFeRD) parser.
pub(crate) fn parse_invoice_xml(file_name: &str, bytes: &[u8]) -> Result<Option<Invoice>> {
    // Strip a leading UTF-8 BOM if present.
    let bytes = bytes.strip_prefix(&[0xEF, 0xBB, 0xBF]).unwrap_or(bytes);
    parse_inner(file_name, bytes)
}

#[derive(Default)]
struct InvoiceBuilder {
    external: String,
    partner: String,
    date: String,
    currency: String,
    lines: Vec<DocumentLine>,
}

#[derive(Default)]
struct LineBuilder {
    no: String,
    description: String,
    quantity: f64,
    price: f64,
}

fn local(q: QName) -> String {
    String::from_utf8_lossy(q.local_name().as_ref()).into_owned()
}

/// True if `stack`'s tail equals `parts`.
fn tail_is(stack: &[String], parts: &[&str]) -> bool {
    stack.len() >= parts.len()
        && stack[stack.len() - parts.len()..]
            .iter()
            .zip(parts)
            .all(|(a, b)| a == b)
}

/// Root elements that start an invoice (UBL `Invoice`, CII `CrossIndustryInvoice`).
fn is_invoice_root(name: &str) -> bool {
    name == "Invoice" || name == "CrossIndustryInvoice"
}

/// Elements that start a line (UBL / CII).
fn is_line_start(name: &str) -> bool {
    name == "InvoiceLine" || name == "IncludedSupplyChainTradeLineItem"
}

fn parse_inner(file_name: &str, bytes: &[u8]) -> Result<Option<Invoice>> {
    let mut reader = Reader::from_reader(bytes);
    let mut buf = Vec::new();
    let mut stack: Vec<String> = Vec::new();
    let mut inv: Option<InvoiceBuilder> = None;
    let mut cur_line: Option<LineBuilder> = None;

    loop {
        match reader.read_event_into(&mut buf).map_err(|e| parse_err(file_name, e))? {
            Event::Start(e) => {
                let name = local_of_start(&e);
                if is_invoice_root(&name) {
                    inv = Some(InvoiceBuilder::default());
                } else if is_line_start(&name) {
                    cur_line = Some(LineBuilder::default());
                }
                stack.push(name);
            }
            Event::Text(t) => {
                let text = t.unescape().map_err(|e| parse_err(file_name, e))?.trim().to_string();
                if !text.is_empty() {
                    assign(&mut inv, &mut cur_line, &stack, text);
                }
            }
            Event::End(e) => {
                let name = local_of_end(&e);
                if is_line_start(&name) {
                    if let (Some(ib), Some(lb)) = (inv.as_mut(), cur_line.take()) {
                        ib.lines.push(DocumentLine::new(lb.no, lb.description, lb.quantity, lb.price));
                    }
                }
                stack.pop();
            }
            Event::Eof => break,
            _ => {}
        }
        buf.clear();
    }

    Ok(inv.map(|ib| {
        // A received UBL/CII invoice is a purchase invoice in BC.
        Document::new(
            DocType::Purchase,
            ib.external,
            ib.partner,
            ib.date,
            ib.currency,
            ib.lines,
        )
    }))
}

fn local_of_start(e: &BytesStart) -> String {
    local(e.name())
}

fn local_of_end(e: &BytesEnd) -> String {
    local(e.name())
}

/// Route a text value to the right field based on the current element path.
fn assign(inv: &mut Option<InvoiceBuilder>, cur_line: &mut Option<LineBuilder>, stack: &[String], text: String) {
    let Some(ib) = inv.as_mut() else { return };

    // Line-scoped fields take priority when inside a line element.
    if let Some(lb) = cur_line.as_mut() {
        // --- UBL ---
        if tail_is(stack, &["Item", "SellersItemIdentification", "ID"]) {
            lb.no = text;
            return;
        }
        if tail_is(stack, &["Item", "StandardItemIdentification", "ID"]) {
            if lb.no.is_empty() {
                lb.no = text;
            }
            return;
        }
        if tail_is(stack, &["Item", "Name"]) {
            lb.description = text;
            return;
        }
        if tail_is(stack, &["InvoiceLine", "InvoicedQuantity"]) {
            lb.quantity = text.parse().unwrap_or(0.0);
            return;
        }
        if tail_is(stack, &["Price", "PriceAmount"]) {
            lb.price = text.parse().unwrap_or(0.0);
            return;
        }
        // --- CII (Factur-X/ZUGFeRD) ---
        if tail_is(stack, &["SpecifiedTradeProduct", "SellerAssignedID"]) {
            lb.no = text;
            return;
        }
        if tail_is(stack, &["SpecifiedTradeProduct", "Name"]) {
            lb.description = text;
            return;
        }
        if tail_is(stack, &["SpecifiedLineTradeDelivery", "BilledQuantity"]) {
            lb.quantity = text.parse().unwrap_or(0.0);
            return;
        }
        if tail_is(stack, &["NetPriceProductTradePrice", "ChargeAmount"]) {
            lb.price = text.parse().unwrap_or(0.0);
            return;
        }
    }

    // Invoice-header fields.
    // --- UBL ---
    if tail_is(stack, &["Invoice", "ID"]) {
        ib.external = text;
    } else if tail_is(stack, &["Invoice", "IssueDate"]) {
        ib.date = text;
    } else if tail_is(stack, &["Invoice", "DocumentCurrencyCode"]) {
        ib.currency = text;
    } else if tail_is(stack, &["AccountingSupplierParty", "Party", "PartyIdentification", "ID"]) {
        // Prefer the party identification (vendor-number-like) over EndpointID,
        // regardless of document order. TODO: map supplier id -> BC vendor no.
        ib.partner = text;
    } else if tail_is(stack, &["AccountingSupplierParty", "Party", "EndpointID"]) {
        if ib.partner.is_empty() {
            ib.partner = text;
        }
    // --- CII (Factur-X/ZUGFeRD) ---
    } else if tail_is(stack, &["ExchangedDocument", "ID"]) {
        ib.external = text;
    } else if tail_is(stack, &["IssueDateTime", "DateTimeString"]) {
        ib.date = text;
    } else if tail_is(stack, &["ApplicableHeaderTradeSettlement", "InvoiceCurrencyCode"]) {
        ib.currency = text;
    } else if tail_is(stack, &["SellerTradeParty", "ID"]) {
        ib.partner = text;
    } else if tail_is(stack, &["SellerTradeParty", "Name"]) {
        if ib.partner.is_empty() {
            ib.partner = text;
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const UBL: &str = r#"<?xml version="1.0" encoding="UTF-8"?>
<Invoice xmlns="urn:oasis:names:specification:ubl:schema:xsd:Invoice-2"
         xmlns:cac="urn:oasis:names:specification:ubl:schema:xsd:CommonAggregateComponents-2"
         xmlns:cbc="urn:oasis:names:specification:ubl:schema:xsd:CommonBasicComponents-2">
  <cbc:ID>INV-XML-1</cbc:ID>
  <cbc:IssueDate>2026-07-10</cbc:IssueDate>
  <cbc:DocumentCurrencyCode>EUR</cbc:DocumentCurrencyCode>
  <cac:AccountingSupplierParty>
    <cac:Party>
      <cac:PartyIdentification><cbc:ID>V-SUP-1</cbc:ID></cac:PartyIdentification>
    </cac:Party>
  </cac:AccountingSupplierParty>
  <cac:InvoiceLine>
    <cbc:ID>1</cbc:ID>
    <cbc:InvoicedQuantity unitCode="EA">3</cbc:InvoicedQuantity>
    <cac:Item>
      <cbc:Name>Item One</cbc:Name>
      <cac:SellersItemIdentification><cbc:ID>ITEM-X</cbc:ID></cac:SellersItemIdentification>
    </cac:Item>
    <cac:Price><cbc:PriceAmount currencyID="EUR">12.5</cbc:PriceAmount></cac:Price>
  </cac:InvoiceLine>
</Invoice>"#;

    #[test]
    fn parses_ubl_invoice() {
        let invoices = XmlParser.parse("inv.xml", UBL.as_bytes()).unwrap();
        assert_eq!(invoices.len(), 1);

        let inv = &invoices[0];
        assert_eq!(inv.doc_type, DocType::Purchase);
        assert_eq!(inv.external_document_no, "INV-XML-1");
        assert_eq!(inv.partner_no, "V-SUP-1");
        assert_eq!(inv.document_date, "2026-07-10");
        assert_eq!(inv.currency_code, "EUR");
        assert_eq!(inv.lines.len(), 1);
        assert_eq!(inv.lines[0].no, "ITEM-X");
        assert_eq!(inv.lines[0].description, "Item One");
        assert_eq!(inv.lines[0].quantity, 3.0);
        assert_eq!(inv.lines[0].unit_price, 12.5);
    }
}
