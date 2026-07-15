//! Benchmark the ingestion pipeline (parse -> validate -> dedup -> stage) on
//! synthetic CSV, in memory (no DB, no BC). Measures the external-side
//! throughput the Rust service can sustain.
//!
//! Usage: cargo run -p ingestion --release --example bench_ingest -- [count]
//! Default count: 100000.

use std::time::Instant;

use ingestion::staging::InMemoryStaging;
use ingestion::{ingest_file, ParserRegistry, Status};

fn generate_csv(count: usize) -> Vec<u8> {
    let mut s = String::with_capacity(count * 80);
    s.push_str("doc_type,external_document_no,partner_no,document_date,currency_code,item_no,description,quantity,unit_price\n");
    let doc_types = ["sales", "purchase", "service"];
    let items = ["ITEM-A", "ITEM-B", "ITEM-C", "ITEM-D", "RES-1"];
    for i in 0..count {
        let dt = doc_types[i % doc_types.len()];
        let partner = format!("C{:05}", 10000 + (i % 500));
        let ext = format!("INV-{i:08}");
        let n_lines = 1 + (i % 3);
        for l in 0..n_lines {
            let item = items[(i + l) % items.len()];
            let qty = 1 + ((i + l) % 10);
            let price = 5.0 + ((i + l) % 50) as f64 * 0.5;
            s.push_str(&format!(
                "{dt},{ext},{partner},2026-07-11,EUR,{item},Line {l},{qty},{price:.2}\n"
            ));
        }
    }
    s.into_bytes()
}

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    let count: usize = std::env::args()
        .nth(1)
        .and_then(|s| s.parse().ok())
        .unwrap_or(100_000);

    let gen_start = Instant::now();
    let bytes = generate_csv(count);
    let gen_dt = gen_start.elapsed();
    println!(
        "generated {count} invoices ({} MB) in {:.2}s",
        bytes.len() / 1_048_576,
        gen_dt.as_secs_f64()
    );

    let registry = ParserRegistry::with_defaults();
    let mut staging = InMemoryStaging::default();

    let start = Instant::now();
    let report = ingest_file(&registry, &mut staging, "bench.csv", &bytes).await?;
    let dt = start.elapsed().as_secs_f64();

    let rate = report.parsed as f64 / dt;
    println!("{report:#?}");
    println!(
        "ingested {} invoices in {:.3}s  =>  {:.0} invoices/sec",
        report.parsed, dt, rate
    );
    println!("staged (validated): {}", staging.count(Status::Validated).await?);
    Ok(())
}
