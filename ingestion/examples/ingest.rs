//! Run the ingestion pipeline against a file and print the report.
//!
//! Usage: cargo run -p ingestion --example ingest -- path/to/invoices.csv
//!
//! Uses Postgres when DATABASE_URL is set (and runs migrations first),
//! otherwise falls back to in-memory staging.

use ingestion::staging::{InMemoryStaging, PostgresStaging};
use ingestion::{ingest_file, ParserRegistry, Staging, Status};

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    let path = std::env::args()
        .nth(1)
        .ok_or_else(|| anyhow::anyhow!("usage: ingest <file>"))?;

    let bytes = std::fs::read(&path)?;
    let registry = ParserRegistry::with_defaults();

    let mut staging: Box<dyn Staging> = match std::env::var("DATABASE_URL") {
        Ok(url) => {
            let pg = PostgresStaging::connect(&url).await?;
            pg.migrate().await?;
            println!("staging: postgres");
            Box::new(pg)
        }
        Err(_) => {
            println!("staging: in-memory (set DATABASE_URL for postgres)");
            Box::new(InMemoryStaging::default())
        }
    };

    let report = ingest_file(&registry, staging.as_mut(), &path, &bytes).await?;

    println!("{report:#?}");
    println!("validated: {}", staging.count(Status::Validated).await?);
    println!("failed:    {}", staging.count(Status::Failed).await?);
    Ok(())
}
