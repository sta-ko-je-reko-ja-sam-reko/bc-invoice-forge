//! EDI invoice parser — EDIFACT INVOIC and X12 810.
//!
//! EDI is delimiter-based. EDIFACT: segments (`'`), elements (`+`), components
//! (`:`), release `?`; an optional `UNA` string overrides the delimiters. X12:
//! separators come from the fixed 106-char `ISA` header (element sep at byte 3,
//! component sep at byte 104, segment terminator at byte 105).
//!
//! Maps the common invoice segments to the canonical model — EDIFACT
//! BGM/DTM/CUX/NAD/LIN/IMD/QTY/PRI and X12 BIG/CUR/N1/IT1/PID. EDI is highly
//! partner-specific, so treat this as a solid baseline that may need tuning to a
//! trading partner's profile. A received invoice maps to a **purchase** invoice.

use crate::canonical::{DocType, Document, DocumentLine, Invoice};
use crate::parsers::{Parser, SourceFormat};
use crate::{IngestError, Result};

pub struct EdiParser;

struct Delims {
    comp: char,
    elem: char,
    release: char,
    seg: char,
}

impl Default for Delims {
    fn default() -> Self {
        Delims { comp: ':', elem: '+', release: '?', seg: '\'' }
    }
}

impl Parser for EdiParser {
    fn format(&self) -> SourceFormat {
        SourceFormat::Edi
    }

    fn parse(&self, file_name: &str, bytes: &[u8]) -> Result<Vec<Invoice>> {
        Ok(parse_edi(file_name, bytes)?.into_iter().collect())
    }
}

/// Dispatch by dialect: X12 (starts with `ISA`) vs EDIFACT.
fn parse_edi(file_name: &str, bytes: &[u8]) -> Result<Option<Invoice>> {
    let stripped = bytes.strip_prefix(&[0xEF, 0xBB, 0xBF]).unwrap_or(bytes);
    let text = String::from_utf8_lossy(stripped);
    if text.trim_start().starts_with("ISA") {
        parse_x12_810(file_name, text.trim_start())
    } else {
        parse_edifact_invoic(file_name, bytes)
    }
}

/// Segment = elements; element = components. `segs[i][0][0]` is the segment tag.
type Segments = Vec<Vec<Vec<String>>>;

fn tokenize(input: &str, d: &Delims) -> Segments {
    let mut segments: Segments = Vec::new();
    let mut elements: Vec<Vec<String>> = Vec::new();
    let mut components: Vec<String> = Vec::new();
    let mut cur = String::new();
    let mut released = false;

    for ch in input.chars() {
        if released {
            cur.push(ch);
            released = false;
        } else if ch == d.release {
            released = true;
        } else if ch == d.comp {
            components.push(std::mem::take(&mut cur));
        } else if ch == d.elem {
            components.push(std::mem::take(&mut cur));
            elements.push(std::mem::take(&mut components));
        } else if ch == d.seg {
            components.push(std::mem::take(&mut cur));
            elements.push(std::mem::take(&mut components));
            segments.push(std::mem::take(&mut elements));
        } else if ch == '\n' || ch == '\r' {
            // Ignore line breaks between segments.
        } else {
            cur.push(ch);
        }
    }
    segments
}

/// Component accessor: `at(seg, element_idx, component_idx)`.
fn at<'a>(seg: &'a [Vec<String>], e: usize, c: usize) -> Option<&'a str> {
    seg.get(e)?.get(c).map(|s| s.as_str())
}

fn tag(seg: &[Vec<String>]) -> &str {
    at(seg, 0, 0).unwrap_or("")
}

/// Reformat an EDIFACT date to ISO when the format qualifier is 102 (CCYYMMDD).
fn iso_date(raw: &str, fmt: Option<&str>) -> String {
    if fmt == Some("102") && raw.len() == 8 && raw.chars().all(|c| c.is_ascii_digit()) {
        format!("{}-{}-{}", &raw[0..4], &raw[4..6], &raw[6..8])
    } else {
        raw.to_string()
    }
}

fn parse_edifact_invoic(file_name: &str, bytes: &[u8]) -> Result<Option<Invoice>> {
    let bytes = bytes.strip_prefix(&[0xEF, 0xBB, 0xBF]).unwrap_or(bytes);
    let text = String::from_utf8_lossy(bytes);
    let text = text.trim_start();

    // Parse the optional UNA service string (fixed 9 chars, ASCII) for delimiters.
    let mut d = Delims::default();
    let body: &str = if text.starts_with("UNA") && text.len() >= 9 {
        let s: Vec<char> = text.chars().take(9).collect();
        d = Delims {
            comp: s[3],
            elem: s[4],
            release: s[6],
            seg: s[8],
        };
        text.get(9..).unwrap_or("")
    } else {
        text
    };

    let segments = tokenize(body, &d);

    let mut ib_external = String::new();
    let mut ib_partner = String::new();
    let mut ib_date = String::new();
    let mut ib_currency = String::new();
    let mut lines: Vec<DocumentLine> = Vec::new();
    let mut cur: Option<LineBuilder> = None;
    let mut saw_invoice = false;

    for seg in &segments {
        match tag(seg) {
            "BGM" => {
                saw_invoice = true;
                if let Some(no) = at(seg, 2, 0) {
                    ib_external = no.to_string();
                }
            }
            "DTM" => {
                // DTM+<qualifier>:<value>:<format>
                if matches!(at(seg, 1, 0), Some("137") | Some("3")) {
                    let raw = at(seg, 1, 1).unwrap_or("");
                    ib_date = iso_date(raw, at(seg, 1, 2));
                }
            }
            "CUX" => {
                if ib_currency.is_empty() {
                    if let Some(cur_code) = at(seg, 1, 1) {
                        ib_currency = cur_code.to_string();
                    }
                }
            }
            "NAD" => {
                // Supplier party is the vendor for a received invoice.
                if at(seg, 1, 0) == Some("SU") {
                    if let Some(id) = at(seg, 2, 0) {
                        ib_partner = id.to_string();
                    }
                }
            }
            "LIN" => {
                if let Some(l) = cur.take() {
                    lines.push(l.into());
                }
                let mut lb = LineBuilder::default();
                if let Some(item) = at(seg, 3, 0) {
                    lb.no = item.to_string();
                }
                cur = Some(lb);
            }
            "IMD" => {
                if let Some(lb) = cur.as_mut() {
                    // Description is the last non-empty component of element 3.
                    if let Some(desc) = seg.get(3).and_then(|c| c.iter().rev().find(|s| !s.is_empty())) {
                        lb.description = desc.clone();
                    }
                }
            }
            "QTY" => {
                if let Some(lb) = cur.as_mut() {
                    if let Some(q) = at(seg, 1, 1) {
                        lb.quantity = q.parse().unwrap_or(0.0);
                    }
                }
            }
            "PRI" => {
                if let Some(lb) = cur.as_mut() {
                    if let Some(p) = at(seg, 1, 1) {
                        lb.price = p.parse().unwrap_or(0.0);
                    }
                }
            }
            _ => {}
        }
    }

    if let Some(l) = cur.take() {
        lines.push(l.into());
    }

    if !saw_invoice {
        return Err(IngestError::Parse {
            file: file_name.to_string(),
            source: anyhow::anyhow!("no BGM segment; not a recognizable EDIFACT INVOIC"),
        });
    }

    Ok(Some(Document::new(
        DocType::Purchase,
        ib_external,
        ib_partner,
        ib_date,
        ib_currency,
        lines,
    )))
}

/// Split an X12 interchange into segments/elements/components (no release char).
fn tokenize_x12(input: &str, elem: char, seg: char, sub: char) -> Segments {
    let mut segments: Segments = Vec::new();
    for raw in input.split(seg) {
        let s = raw.trim_matches(|c: char| c == '\n' || c == '\r' || c == ' ');
        if s.is_empty() {
            continue;
        }
        let elements = s
            .split(elem)
            .map(|e| e.split(sub).map(|c| c.to_string()).collect::<Vec<_>>())
            .collect::<Vec<_>>();
        segments.push(elements);
    }
    segments
}

fn parse_x12_810(file_name: &str, text: &str) -> Result<Option<Invoice>> {
    // Separators come from fixed positions in the 106-char ISA header.
    let b = text.as_bytes();
    if b.len() < 106 {
        return Err(IngestError::Validation("X12 ISA header too short".into()));
    }
    let elem = b[3] as char;
    let sub = b[104] as char;
    let seg = b[105] as char;

    let segments = tokenize_x12(text, elem, seg, sub);

    let mut ib_external = String::new();
    let mut ib_partner = String::new();
    let mut ib_date = String::new();
    let mut ib_currency = String::new();
    let mut lines: Vec<DocumentLine> = Vec::new();
    let mut cur: Option<LineBuilder> = None;
    let mut saw_invoice = false;

    for s in &segments {
        match tag(s) {
            "BIG" => {
                saw_invoice = true;
                ib_date = iso_date(at(s, 1, 0).unwrap_or(""), Some("102"));
                if let Some(no) = at(s, 2, 0) {
                    ib_external = no.to_string();
                }
            }
            "CUR" => {
                if ib_currency.is_empty() {
                    if let Some(c) = at(s, 2, 0) {
                        ib_currency = c.to_string();
                    }
                }
            }
            "N1" => {
                // VN = vendor (supplier of a received invoice).
                if at(s, 1, 0) == Some("VN") {
                    ib_partner = at(s, 4, 0)
                        .filter(|v| !v.is_empty())
                        .or_else(|| at(s, 2, 0))
                        .unwrap_or("")
                        .to_string();
                }
            }
            "IT1" => {
                if let Some(l) = cur.take() {
                    lines.push(l.into());
                }
                let mut lb = LineBuilder::default();
                if let Some(q) = at(s, 2, 0) {
                    lb.quantity = q.parse().unwrap_or(0.0);
                }
                if let Some(p) = at(s, 4, 0) {
                    lb.price = p.parse().unwrap_or(0.0);
                }
                if let Some(item) = at(s, 7, 0) {
                    lb.no = item.to_string();
                }
                cur = Some(lb);
            }
            "PID" => {
                if let Some(lb) = cur.as_mut() {
                    if let Some(desc) = at(s, 5, 0) {
                        if !desc.is_empty() {
                            lb.description = desc.to_string();
                        }
                    }
                }
            }
            _ => {}
        }
    }

    if let Some(l) = cur.take() {
        lines.push(l.into());
    }

    if !saw_invoice {
        return Err(IngestError::Parse {
            file: file_name.to_string(),
            source: anyhow::anyhow!("no BIG segment; not a recognizable X12 810"),
        });
    }

    Ok(Some(Document::new(
        DocType::Purchase,
        ib_external,
        ib_partner,
        ib_date,
        ib_currency,
        lines,
    )))
}

#[derive(Default)]
struct LineBuilder {
    no: String,
    description: String,
    quantity: f64,
    price: f64,
}

impl From<LineBuilder> for DocumentLine {
    fn from(l: LineBuilder) -> Self {
        DocumentLine::new(l.no, l.description, l.quantity, l.price)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const INVOIC: &str = "UNA:+.? '\n\
UNB+UNOC:3+SENDER+RECEIVER+260710:1200+1'\n\
UNH+1+INVOIC:D:96A:UN'\n\
BGM+380+PINV-EDI-7001+9'\n\
DTM+137:20260710:102'\n\
NAD+SU+V20000::9'\n\
CUX+2:EUR:4'\n\
LIN+1++ITEM-C:EN'\n\
IMD+F++:::Raw material'\n\
QTY+47:10'\n\
PRI+AAA:3.25'\n\
LIN+2++ITEM-D:EN'\n\
IMD+F++:::Packaging'\n\
QTY+47:100'\n\
PRI+AAA:0.40'\n\
UNT+14+1'\n\
UNZ+1+1'\n";

    #[test]
    fn parses_edifact_invoic() {
        let invoices = EdiParser.parse("inv.edi", INVOIC.as_bytes()).unwrap();
        assert_eq!(invoices.len(), 1);

        let inv = &invoices[0];
        assert_eq!(inv.doc_type, DocType::Purchase);
        assert_eq!(inv.external_document_no, "PINV-EDI-7001");
        assert_eq!(inv.partner_no, "V20000");
        assert_eq!(inv.document_date, "2026-07-10");
        assert_eq!(inv.currency_code, "EUR");
        assert_eq!(inv.lines.len(), 2);
        assert_eq!(inv.lines[0].no, "ITEM-C");
        assert_eq!(inv.lines[0].description, "Raw material");
        assert_eq!(inv.lines[0].quantity, 10.0);
        assert_eq!(inv.lines[1].no, "ITEM-D");
        assert_eq!(inv.lines[1].unit_price, 0.40);
    }

    #[test]
    fn parses_x12_810() {
        // Build an exactly-106-char ISA via width-formatted fields.
        let isa = format!(
            "ISA*00*{:10}*00*{:10}*ZZ*{:15}*ZZ*{:15}*260711*1200*U*00401*000000001*0*P*>~",
            "", "", "SENDER", "RECEIVER"
        );
        assert_eq!(isa.len(), 106, "ISA must be 106 chars for separator detection");

        let msg = format!(
            "{isa}\n\
GS*IN*SENDER*RECEIVER*20260711*1200*1*X*004010~\n\
ST*810*0001~\n\
BIG*20260711*PINV-X12-7001*20260701*PO-123~\n\
CUR*SE*EUR~\n\
N1*VN*Acme Supplies*92*V20000~\n\
IT1*1*10*EA*3.25**VP*ITEM-C~\n\
PID*F****Raw material~\n\
IT1*2*100*EA*0.40**VP*ITEM-D~\n\
PID*F****Packaging~\n\
SE*11*0001~\n"
        );

        let invoices = EdiParser.parse("inv.x12", msg.as_bytes()).unwrap();
        assert_eq!(invoices.len(), 1);

        let inv = &invoices[0];
        assert_eq!(inv.doc_type, DocType::Purchase);
        assert_eq!(inv.external_document_no, "PINV-X12-7001");
        assert_eq!(inv.partner_no, "V20000");
        assert_eq!(inv.document_date, "2026-07-11");
        assert_eq!(inv.currency_code, "EUR");
        assert_eq!(inv.lines.len(), 2);
        assert_eq!(inv.lines[0].no, "ITEM-C");
        assert_eq!(inv.lines[0].description, "Raw material");
        assert_eq!(inv.lines[0].quantity, 10.0);
        assert_eq!(inv.lines[1].no, "ITEM-D");
        assert_eq!(inv.lines[1].unit_price, 0.40);
    }
}
