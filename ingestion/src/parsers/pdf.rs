//! PDF invoice parser (Factur-X / ZUGFeRD / XRechnung).
//!
//! Modern e-invoice PDFs are PDF/A-3 with a structured invoice XML embedded as
//! an attachment (`factur-x.xml`, `zugferd-invoice.xml`, `xrechnung.xml`). We
//! extract that XML and hand it to the shared UBL/CII parser.
//!
//! Plain scanned or purely-visual PDFs carry no structured data — those need an
//! OCR/template pipeline, which is out of scope here. Such a file yields a clear
//! "no embedded invoice XML" error rather than a wrong guess.

use lopdf::{Document, Object};

use crate::canonical::Invoice;
use crate::parsers::{Parser, SourceFormat};
use crate::{IngestError, Result};

pub struct PdfParser;

impl Parser for PdfParser {
    fn format(&self) -> SourceFormat {
        SourceFormat::Pdf
    }

    fn parse(&self, file_name: &str, bytes: &[u8]) -> Result<Vec<Invoice>> {
        let xml = extract_embedded_xml(bytes).map_err(|e| IngestError::Parse {
            file: file_name.to_string(),
            source: e,
        })?;

        Ok(super::xml::parse_invoice_xml(file_name, &xml)?
            .into_iter()
            .collect())
    }
}

/// Resolve an object through one level of indirection (reference -> object).
fn resolve<'a>(doc: &'a Document, obj: &'a Object) -> &'a Object {
    match obj {
        Object::Reference(id) => doc.get_object(*id).unwrap_or(obj),
        _ => obj,
    }
}

/// Find and decompress the invoice XML embedded in a Factur-X/ZUGFeRD PDF.
fn extract_embedded_xml(bytes: &[u8]) -> anyhow::Result<Vec<u8>> {
    let doc = Document::load_mem(bytes)?;

    let catalog = doc.catalog()?;
    let names = resolve(&doc, catalog.get(b"Names")?)
        .as_dict()
        .map_err(|_| anyhow::anyhow!("PDF catalog has no Names dictionary"))?;
    let embedded = resolve(&doc, names.get(b"EmbeddedFiles")?)
        .as_dict()
        .map_err(|_| anyhow::anyhow!("PDF has no EmbeddedFiles"))?;
    let pairs = resolve(&doc, embedded.get(b"Names")?)
        .as_array()
        .map_err(|_| anyhow::anyhow!("EmbeddedFiles name tree is not a flat Names array"))?;

    // The Names array is [name0, filespec0, name1, filespec1, ...].
    let mut fallback: Option<Vec<u8>> = None;
    for pair in pairs.chunks(2) {
        let [name_obj, spec_obj] = pair else { continue };

        let name = match name_obj {
            Object::String(b, _) => String::from_utf8_lossy(b).to_lowercase(),
            _ => String::new(),
        };

        let Ok(content) = embedded_stream_content(&doc, spec_obj) else {
            continue;
        };

        if name.ends_with(".xml") {
            return Ok(content);
        }
        // Some producers name the attachment oddly; keep the first as fallback.
        fallback.get_or_insert(content);
    }

    fallback.ok_or_else(|| {
        anyhow::anyhow!("no embedded invoice XML (Factur-X/ZUGFeRD) found in PDF")
    })
}

/// Given a filespec object, pull and decompress its embedded file stream.
fn embedded_stream_content(doc: &Document, spec_obj: &Object) -> anyhow::Result<Vec<u8>> {
    let spec = resolve(doc, spec_obj)
        .as_dict()
        .map_err(|_| anyhow::anyhow!("filespec is not a dictionary"))?;
    let ef = resolve(doc, spec.get(b"EF")?)
        .as_dict()
        .map_err(|_| anyhow::anyhow!("filespec has no EF"))?;

    // Prefer F, fall back to UF.
    let stream_obj = ef
        .get(b"F")
        .or_else(|_| ef.get(b"UF"))
        .map_err(|_| anyhow::anyhow!("EF has no F/UF stream"))?;
    let stream = resolve(doc, stream_obj)
        .as_stream()
        .map_err(|_| anyhow::anyhow!("embedded file is not a stream"))?;

    // decompressed_content() returns the raw bytes when the stream has no
    // filter, so it covers both compressed and uncompressed attachments.
    stream
        .decompressed_content()
        .map_err(|e| anyhow::anyhow!("failed to decode embedded stream: {e}"))
}
