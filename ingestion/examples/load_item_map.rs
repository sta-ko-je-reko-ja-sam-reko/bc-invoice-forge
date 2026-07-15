//! Seed the item_map table from a CSV of `source_id,bc_no`.
//!
//! Usage: cargo run -p ingestion --example load_item_map -- path/to/item-map.csv
//! Requires DATABASE_URL.

use ingestion::staging::PostgresStaging;
use serde::Deserialize;

#[derive(Debug, Deserialize)]
struct Row {
    source_id: String,
    bc_no: String,
}

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    let path = std::env::args()
        .nth(1)
        .ok_or_else(|| anyhow::anyhow!("usage: load_item_map <file.csv>"))?;
    let url = std::env::var("DATABASE_URL")
        .map_err(|_| anyhow::anyhow!("missing env var DATABASE_URL"))?;

    let pg = PostgresStaging::connect(&url).await?;
    pg.migrate().await?;

    let bytes = std::fs::read(&path)?;
    let mut reader = csv::ReaderBuilder::new()
        .has_headers(true)
        .trim(csv::Trim::All)
        .from_reader(bytes.as_slice());

    let mut n = 0usize;
    for result in reader.deserialize::<Row>() {
        let row = result?;
        pg.upsert_item_map(&row.source_id, &row.bc_no).await?;
        n += 1;
    }

    println!("loaded {n} item mappings");
    Ok(())
}
