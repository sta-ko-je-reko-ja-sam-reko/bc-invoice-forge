//! Generate a large synthetic invoice CSV for load testing.
//!
//! Usage: cargo run -p ingestion --release --example generate -- <count> <out.csv>
//! Example: cargo run -p ingestion --release --example generate -- 100000 big.csv
//!
//! Deterministic (no randomness): doc types cycle sales/purchase/service,
//! parties and items cycle over a small pool, each invoice has 1-3 lines.

use std::io::Write;

fn main() -> anyhow::Result<()> {
    let mut args = std::env::args().skip(1);
    let count: usize = args
        .next()
        .and_then(|s| s.parse().ok())
        .ok_or_else(|| anyhow::anyhow!("usage: generate <count> <out.csv>"))?;
    let out = args.next().unwrap_or_else(|| "generated.csv".to_string());

    let file = std::fs::File::create(&out)?;
    let mut w = std::io::BufWriter::new(file);

    writeln!(
        w,
        "doc_type,external_document_no,partner_no,document_date,currency_code,item_no,description,quantity,unit_price"
    )?;

    let doc_types = ["sales", "purchase", "service"];
    let items = ["ITEM-A", "ITEM-B", "ITEM-C", "ITEM-D", "RES-1"];

    for i in 0..count {
        let dt = doc_types[i % doc_types.len()];
        let (prefix, partner) = match dt {
            "purchase" => ("PINV", format!("V{:05}", 20000 + (i % 500))),
            "service" => ("SINV", format!("C{:05}", 10000 + (i % 500))),
            _ => ("INV", format!("C{:05}", 10000 + (i % 500))),
        };
        let ext = format!("{prefix}-{i:08}");
        let n_lines = 1 + (i % 3); // 1..=3
        for l in 0..n_lines {
            let item = items[(i + l) % items.len()];
            let qty = 1 + ((i + l) % 10);
            let price = 5.0 + ((i + l) % 50) as f64 * 0.5;
            writeln!(
                w,
                "{dt},{ext},{partner},2026-07-11,EUR,{item},Line {l},{qty},{price:.2}"
            )?;
        }
    }

    w.flush()?;
    println!("wrote {count} invoices to {out}");
    Ok(())
}
