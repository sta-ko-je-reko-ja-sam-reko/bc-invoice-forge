//! Export every stored document error to CSV for review/reprocessing.
//!
//! Usage: cargo run -p ingestion --example export_errors -- [out.csv]
//! Requires DATABASE_URL. Default output: errors.csv

use std::io::Write;

use ingestion::staging::PostgresStaging;

/// Minimal CSV field escaping: quote if the value contains a comma, quote, or newline.
fn esc(s: &str) -> String {
    if s.contains([',', '"', '\n', '\r']) {
        format!("\"{}\"", s.replace('"', "\"\""))
    } else {
        s.to_string()
    }
}

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    let out = std::env::args().nth(1).unwrap_or_else(|| "errors.csv".to_string());
    let url = std::env::var("DATABASE_URL")
        .map_err(|_| anyhow::anyhow!("missing env var DATABASE_URL"))?;

    let pg = PostgresStaging::connect(&url).await?;
    let rows = pg.export_all_errors().await?;

    let file = std::fs::File::create(&out)?;
    let mut w = std::io::BufWriter::new(file);
    writeln!(
        w,
        "idempotency_key,doc_type,external_document_no,status,scope,line_no,field,code,message,source"
    )?;

    for (key, doc_type, ext, status, scope, line_no, field, code, message, source) in &rows {
        writeln!(
            w,
            "{key},{doc_type},{},{status},{scope},{},{},{},{},{source}",
            esc(ext),
            line_no.as_ref().map(|n| n.to_string()).unwrap_or_default(),
            esc(field.as_deref().unwrap_or("")),
            esc(code),
            esc(message),
        )?;
    }

    w.flush()?;
    println!("exported {} error rows to {out}", rows.len());
    Ok(())
}
