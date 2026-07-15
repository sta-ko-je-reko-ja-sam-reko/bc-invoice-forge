//! Format detection + pluggable parser registry.
//!
//! The "file-type agent": sniff an input, pick a parser, get canonical invoices
//! back. New formats are added by implementing [`Parser`] and registering it.

use crate::canonical::Invoice;
use crate::Result;

pub mod csv;
pub mod edi;
pub mod json;
pub mod pdf;
pub mod xml;

/// Recognized source formats. Extend as new parsers are added.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum SourceFormat {
    Csv,
    /// UBL or UN/CEFACT CII invoice XML.
    Xml,
    Json,
    /// Factur-X / ZUGFeRD PDF (embedded invoice XML).
    Pdf,
    /// EDIFACT INVOIC or X12 810.
    Edi,
}

/// A parser turns raw bytes of one recognized format into canonical invoices.
pub trait Parser: Send + Sync {
    fn format(&self) -> SourceFormat;
    /// Parse the full contents of one file into zero or more invoices.
    fn parse(&self, file_name: &str, bytes: &[u8]) -> Result<Vec<Invoice>>;
}

/// Detect a file's format from its name and/or content signature.
///
/// Extension first, then a content sniff so mislabeled files are still routed
/// (PDF magic bytes, XML prolog, JSON opening token).
pub fn detect_format(file_name: &str, bytes: &[u8]) -> Option<SourceFormat> {
    let lower = file_name.to_lowercase();
    if lower.ends_with(".csv") {
        return Some(SourceFormat::Csv);
    } else if lower.ends_with(".xml") {
        return Some(SourceFormat::Xml);
    } else if lower.ends_with(".json") {
        return Some(SourceFormat::Json);
    } else if lower.ends_with(".pdf") {
        return Some(SourceFormat::Pdf);
    } else if lower.ends_with(".edi") || lower.ends_with(".edifact") {
        return Some(SourceFormat::Edi);
    }

    // Content sniff for unknown/missing extensions.
    let head = &bytes[..bytes.len().min(16)];
    if head.starts_with(b"%PDF") {
        Some(SourceFormat::Pdf)
    } else if head.starts_with(b"UNA") || head.starts_with(b"UNB") || head.starts_with(b"ISA") {
        Some(SourceFormat::Edi)
    } else if head.starts_with(b"<?xml") || head.starts_with(b"<") {
        Some(SourceFormat::Xml)
    } else if head.strip_prefix(&[0xEF, 0xBB, 0xBF]).unwrap_or(head).starts_with(b"{")
        || head.starts_with(b"[")
    {
        Some(SourceFormat::Json)
    } else {
        None
    }
}

/// Holds the available parsers and dispatches by detected format.
pub struct ParserRegistry {
    parsers: Vec<Box<dyn Parser>>,
}

impl ParserRegistry {
    /// Build the registry with the default set of parsers.
    pub fn with_defaults() -> Self {
        Self {
            parsers: vec![
                Box::new(csv::CsvParser),
                Box::new(xml::XmlParser),
                Box::new(json::JsonParser),
                Box::new(pdf::PdfParser),
                Box::new(edi::EdiParser),
            ],
        }
    }

    pub fn register(&mut self, parser: Box<dyn Parser>) {
        self.parsers.push(parser);
    }

    /// Detect the format of `bytes`/`file_name` and parse with the matching parser.
    pub fn parse_file(&self, file_name: &str, bytes: &[u8]) -> Result<Vec<Invoice>> {
        let format = detect_format(file_name, bytes)
            .ok_or_else(|| crate::IngestError::UnknownFormat(file_name.to_string()))?;

        let parser = self
            .parsers
            .iter()
            .find(|p| p.format() == format)
            .ok_or_else(|| crate::IngestError::UnknownFormat(file_name.to_string()))?;

        parser.parse(file_name, bytes)
    }
}

impl Default for ParserRegistry {
    fn default() -> Self {
        Self::with_defaults()
    }
}
