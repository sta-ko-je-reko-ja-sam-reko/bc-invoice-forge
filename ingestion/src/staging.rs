//! Staging: persist canonical invoices + their lifecycle status.
//!
//! The `Staging` trait is the persistence boundary. Two implementations:
//! - [`InMemoryStaging`] for tests/dev (no DB).
//! - [`PostgresStaging`] for real runs (sqlx / Postgres).
//!
//! Queries use the runtime `sqlx::query` API (not the compile-time-checked
//! macros) so the crate builds without a live database.

use async_trait::async_trait;
use sqlx::Row;

use crate::canonical::{DocType, Invoice, InvoiceLine};
use crate::errors::DocError;

/// Lifecycle status of a staged invoice. Mirrors the state machine in docs.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Status {
    Parsed,
    Validated,
    /// Failed external validation (bad fields or unknown reference data);
    /// never sent to BC. Errors are in `document_error`.
    Invalid,
    Imported,
    Posting,
    Posted,
    /// Failed during BC import/post; error(s) in `document_error`.
    Failed,
}

impl Status {
    pub fn as_str(&self) -> &'static str {
        match self {
            Status::Parsed => "parsed",
            Status::Validated => "validated",
            Status::Invalid => "invalid",
            Status::Imported => "imported",
            Status::Posting => "posting",
            Status::Posted => "posted",
            Status::Failed => "failed",
        }
    }
}

fn doc_type_from_str(s: &str) -> anyhow::Result<DocType> {
    DocType::from_tag(s).ok_or_else(|| anyhow::anyhow!("unknown doc_type in db: {s}"))
}

/// Persistence boundary for staged invoices.
#[async_trait]
pub trait Staging {
    /// Insert by idempotency key; returns true if newly inserted, false if it
    /// already existed (a safe no-op — the basis for idempotent reruns).
    async fn upsert(&mut self, invoice: &Invoice, status: Status) -> anyhow::Result<bool>;

    /// Move an existing invoice to a new status.
    async fn set_status(&mut self, idempotency_key: &str, status: Status) -> anyhow::Result<()>;

    /// Count invoices currently in a given status.
    async fn count(&self, status: Status) -> anyhow::Result<usize>;
}

// ---------------------------------------------------------------------------
// In-memory implementation (dev/test)
// ---------------------------------------------------------------------------

/// Dev/test staging that keeps everything in memory.
#[derive(Default)]
pub struct InMemoryStaging {
    rows: std::collections::HashMap<String, (Invoice, Status)>,
}

#[async_trait]
impl Staging for InMemoryStaging {
    async fn upsert(&mut self, invoice: &Invoice, status: Status) -> anyhow::Result<bool> {
        let key = invoice.idempotency_key.clone();
        if self.rows.contains_key(&key) {
            return Ok(false);
        }
        self.rows.insert(key, (invoice.clone(), status));
        Ok(true)
    }

    async fn set_status(&mut self, idempotency_key: &str, status: Status) -> anyhow::Result<()> {
        if let Some(row) = self.rows.get_mut(idempotency_key) {
            row.1 = status;
        }
        Ok(())
    }

    async fn count(&self, status: Status) -> anyhow::Result<usize> {
        Ok(self.rows.values().filter(|(_, s)| *s == status).count())
    }
}

// ---------------------------------------------------------------------------
// Postgres implementation
// ---------------------------------------------------------------------------

/// Postgres-backed staging store.
pub struct PostgresStaging {
    pool: sqlx::PgPool,
}

impl PostgresStaging {
    /// Connect to Postgres and build a pool.
    pub async fn connect(database_url: &str) -> anyhow::Result<Self> {
        let pool = sqlx::postgres::PgPoolOptions::new()
            .max_connections(10)
            .connect(database_url)
            .await?;
        Ok(Self { pool })
    }

    /// Run the embedded migrations (creates the staging schema).
    pub async fn migrate(&self) -> anyhow::Result<()> {
        sqlx::migrate!("./migrations").run(&self.pool).await?;
        Ok(())
    }

    pub fn pool(&self) -> &sqlx::PgPool {
        &self.pool
    }

    /// Fetch up to `limit` invoices (with their lines) in a given status.
    /// Used by the orchestrator to pull `validated` invoices for import.
    pub async fn fetch_by_status(&self, status: Status, limit: i64) -> anyhow::Result<Vec<Invoice>> {
        let rows = sqlx::query(
            "SELECT idempotency_key, doc_type, external_document_no, partner_no, \
                    document_date, currency_code \
             FROM invoice WHERE status = $1 ORDER BY created_at LIMIT $2",
        )
        .bind(status.as_str())
        .bind(limit)
        .fetch_all(&self.pool)
        .await?;

        let mut out = Vec::with_capacity(rows.len());
        for r in rows {
            let key: String = r.try_get("idempotency_key")?;
            let doc_type = doc_type_from_str(r.try_get::<String, _>("doc_type")?.as_str())?;
            let lines = self.fetch_lines(&key).await?;
            out.push(Invoice {
                doc_type,
                external_document_no: r.try_get("external_document_no")?,
                partner_no: r.try_get("partner_no")?,
                document_date: r.try_get("document_date")?,
                currency_code: r.try_get("currency_code")?,
                header_fields: Default::default(),
                lines,
                idempotency_key: key,
            });
        }
        Ok(out)
    }

    async fn fetch_lines(&self, idempotency_key: &str) -> anyhow::Result<Vec<InvoiceLine>> {
        let rows = sqlx::query(
            "SELECT no, description, quantity, unit_price \
             FROM invoice_line WHERE idempotency_key = $1 ORDER BY id",
        )
        .bind(idempotency_key)
        .fetch_all(&self.pool)
        .await?;

        rows.into_iter()
            .map(|r| -> anyhow::Result<InvoiceLine> {
                Ok(InvoiceLine {
                    no: r.try_get("no")?,
                    description: r.try_get("description")?,
                    quantity: r.try_get("quantity")?,
                    unit_price: r.try_get("unit_price")?,
                    line_fields: Default::default(),
                })
            })
            .collect()
    }

    /// Resolve a source party identifier to a BC customer/vendor number.
    /// `kind` is "customer" or "vendor". Returns None if unmapped.
    pub async fn resolve_party(&self, kind: &str, source_id: &str) -> anyhow::Result<Option<String>> {
        let normalized = source_id.trim().to_lowercase();
        let row: Option<(String,)> =
            sqlx::query_as("SELECT bc_no FROM party_map WHERE kind = $1 AND source_id = $2")
                .bind(kind)
                .bind(&normalized)
                .fetch_optional(&self.pool)
                .await?;
        Ok(row.map(|(bc_no,)| bc_no))
    }

    /// Insert or update one party mapping. `source_id` is normalized to match
    /// how `resolve_party` looks it up.
    pub async fn upsert_party_map(&self, kind: &str, source_id: &str, bc_no: &str) -> anyhow::Result<()> {
        let normalized = source_id.trim().to_lowercase();
        sqlx::query(
            "INSERT INTO party_map (kind, source_id, bc_no) VALUES ($1, $2, $3) \
             ON CONFLICT (kind, source_id) DO UPDATE SET bc_no = EXCLUDED.bc_no",
        )
        .bind(kind)
        .bind(&normalized)
        .bind(bc_no)
        .execute(&self.pool)
        .await?;
        Ok(())
    }

    /// Resolve a source line-item code to a BC item number. None if unmapped.
    pub async fn resolve_item(&self, source_id: &str) -> anyhow::Result<Option<String>> {
        let normalized = source_id.trim().to_lowercase();
        let row: Option<(String,)> =
            sqlx::query_as("SELECT bc_no FROM item_map WHERE source_id = $1")
                .bind(&normalized)
                .fetch_optional(&self.pool)
                .await?;
        Ok(row.map(|(bc_no,)| bc_no))
    }

    /// Insert or update one item mapping.
    pub async fn upsert_item_map(&self, source_id: &str, bc_no: &str) -> anyhow::Result<()> {
        let normalized = source_id.trim().to_lowercase();
        sqlx::query(
            "INSERT INTO item_map (source_id, bc_no) VALUES ($1, $2) \
             ON CONFLICT (source_id) DO UPDATE SET bc_no = EXCLUDED.bc_no",
        )
        .bind(&normalized)
        .bind(bc_no)
        .execute(&self.pool)
        .await?;
        Ok(())
    }

    /// Record the BC document number captured after a successful import.
    /// Takes `&self` so many imports can update concurrently over the pool.
    pub async fn set_bc_document_no(
        &self,
        idempotency_key: &str,
        bc_document_no: &str,
    ) -> anyhow::Result<()> {
        sqlx::query(
            "UPDATE invoice SET bc_document_no = $2, updated_at = now() \
             WHERE idempotency_key = $1",
        )
        .bind(idempotency_key)
        .bind(bc_document_no)
        .execute(&self.pool)
        .await?;
        Ok(())
    }

    /// Update an invoice's status + append an audit row. `&self` so it is safe
    /// to call from many concurrent tasks (the pool serializes as needed).
    pub async fn update_status(&self, idempotency_key: &str, status: Status) -> anyhow::Result<()> {
        let mut tx = self.pool.begin().await?;

        sqlx::query("UPDATE invoice SET status = $2, updated_at = now() WHERE idempotency_key = $1")
            .bind(idempotency_key)
            .bind(status.as_str())
            .execute(&mut *tx)
            .await?;

        sqlx::query("INSERT INTO event_log (idempotency_key, status) VALUES ($1, $2)")
            .bind(idempotency_key)
            .bind(status.as_str())
            .execute(&mut *tx)
            .await?;

        tx.commit().await?;
        Ok(())
    }

    /// Count of documents per status (run summary metric).
    pub async fn status_counts(&self) -> anyhow::Result<Vec<(String, i64)>> {
        let rows: Vec<(String, i64)> =
            sqlx::query_as("SELECT status, count(*) FROM invoice GROUP BY status ORDER BY status")
                .fetch_all(&self.pool)
                .await?;
        Ok(rows)
    }

    /// Store all errors for a document (header + line, validation + BC).
    pub async fn record_errors(&self, idempotency_key: &str, errors: &[DocError]) -> anyhow::Result<()> {
        if errors.is_empty() {
            return Ok(());
        }
        let mut tx = self.pool.begin().await?;
        for e in errors {
            sqlx::query(
                "INSERT INTO document_error \
                 (idempotency_key, scope, line_no, field, code, message, source) \
                 VALUES ($1, $2, $3, $4, $5, $6, $7)",
            )
            .bind(idempotency_key)
            .bind(e.scope.as_str())
            .bind(e.line_no)
            .bind(e.field.as_deref())
            .bind(e.code.as_str())
            .bind(e.message.as_str())
            .bind(e.source.as_str())
            .execute(&mut *tx)
            .await?;
        }
        tx.commit().await?;
        Ok(())
    }

    /// Delete a document's stored errors (used before reprocessing it).
    pub async fn clear_errors(&self, idempotency_key: &str) -> anyhow::Result<()> {
        sqlx::query("DELETE FROM document_error WHERE idempotency_key = $1")
            .bind(idempotency_key)
            .execute(&self.pool)
            .await?;
        Ok(())
    }

    /// All stored errors for a document, as (scope, line_no, field, code, message, source).
    pub async fn errors_for(
        &self,
        idempotency_key: &str,
    ) -> anyhow::Result<Vec<(String, Option<i32>, Option<String>, String, String, String)>> {
        let rows: Vec<(String, Option<i32>, Option<String>, String, String, String)> = sqlx::query_as(
            "SELECT scope, line_no, field, code, message, source FROM document_error \
             WHERE idempotency_key = $1 ORDER BY id",
        )
        .bind(idempotency_key)
        .fetch_all(&self.pool)
        .await?;
        Ok(rows)
    }

    /// All errors joined with their document context, for CSV export.
    /// (key, doc_type, external_document_no, status, scope, line_no, field, code, message, source)
    #[allow(clippy::type_complexity)]
    pub async fn export_all_errors(
        &self,
    ) -> anyhow::Result<
        Vec<(
            String,
            String,
            String,
            String,
            String,
            Option<i32>,
            Option<String>,
            String,
            String,
            String,
        )>,
    > {
        let rows = sqlx::query_as(
            "SELECT d.idempotency_key, d.doc_type, d.external_document_no, d.status, \
                    e.scope, e.line_no, e.field, e.code, e.message, e.source \
             FROM document_error e \
             JOIN invoice d ON d.idempotency_key = e.idempotency_key \
             ORDER BY d.idempotency_key, e.id",
        )
        .fetch_all(&self.pool)
        .await?;
        Ok(rows)
    }

    /// Requeue every `invalid`/`failed` document back to `validated` and clear
    /// its errors, so a subsequent run retries only those. Returns the count.
    pub async fn requeue_invalid_and_failed(&self) -> anyhow::Result<u64> {
        let mut tx = self.pool.begin().await?;
        sqlx::query(
            "DELETE FROM document_error WHERE idempotency_key IN \
             (SELECT idempotency_key FROM invoice WHERE status IN ('invalid', 'failed'))",
        )
        .execute(&mut *tx)
        .await?;
        let res = sqlx::query(
            "UPDATE invoice SET status = 'validated', updated_at = now() \
             WHERE status IN ('invalid', 'failed')",
        )
        .execute(&mut *tx)
        .await?;
        tx.commit().await?;
        Ok(res.rows_affected())
    }

    /// Top error codes across all documents, most frequent first.
    pub async fn error_summary(&self, limit: i64) -> anyhow::Result<Vec<(String, i64)>> {
        let rows: Vec<(String, i64)> = sqlx::query_as(
            "SELECT code, count(*) AS n FROM document_error GROUP BY code ORDER BY n DESC LIMIT $1",
        )
        .bind(limit)
        .fetch_all(&self.pool)
        .await?;
        Ok(rows)
    }

    /// Upsert a reference entity (customer/vendor/item/posting_group/...).
    pub async fn ref_upsert(&self, kind: &str, no: &str, name: Option<&str>) -> anyhow::Result<()> {
        let normalized = no.trim().to_lowercase();
        sqlx::query(
            "INSERT INTO ref_entity (kind, no, name) VALUES ($1, $2, $3) \
             ON CONFLICT (kind, no) DO UPDATE SET name = EXCLUDED.name",
        )
        .bind(kind)
        .bind(&normalized)
        .bind(name)
        .execute(&self.pool)
        .await?;
        Ok(())
    }

    /// Whether a reference entity exists (normalized lookup).
    pub async fn ref_exists(&self, kind: &str, no: &str) -> anyhow::Result<bool> {
        let normalized = no.trim().to_lowercase();
        let row: Option<(i32,)> =
            sqlx::query_as("SELECT 1 FROM ref_entity WHERE kind = $1 AND no = $2")
                .bind(kind)
                .bind(&normalized)
                .fetch_optional(&self.pool)
                .await?;
        Ok(row.is_some())
    }

    /// Count of reference rows for a kind (0 = not synced yet).
    pub async fn ref_count(&self, kind: &str) -> anyhow::Result<i64> {
        let row: (i64,) = sqlx::query_as("SELECT count(*) FROM ref_entity WHERE kind = $1")
            .bind(kind)
            .fetch_one(&self.pool)
            .await?;
        Ok(row.0)
    }
}

#[async_trait]
impl Staging for PostgresStaging {
    async fn upsert(&mut self, invoice: &Invoice, status: Status) -> anyhow::Result<bool> {
        let mut tx = self.pool.begin().await?;

        let res = sqlx::query(
            "INSERT INTO invoice \
             (idempotency_key, doc_type, external_document_no, partner_no, document_date, currency_code, status) \
             VALUES ($1, $2, $3, $4, $5, $6, $7) \
             ON CONFLICT (idempotency_key) DO NOTHING",
        )
        .bind(invoice.idempotency_key.as_str())
        .bind(invoice.doc_type.tag())
        .bind(invoice.external_document_no.as_str())
        .bind(invoice.partner_no.as_str())
        .bind(invoice.document_date.as_str())
        .bind(invoice.currency_code.as_str())
        .bind(status.as_str())
        .execute(&mut *tx)
        .await?;

        let inserted = res.rows_affected() == 1;

        if inserted {
            for line in &invoice.lines {
                sqlx::query(
                    "INSERT INTO invoice_line \
                     (idempotency_key, no, description, quantity, unit_price) \
                     VALUES ($1, $2, $3, $4, $5)",
                )
                .bind(invoice.idempotency_key.as_str())
                .bind(line.no.as_str())
                .bind(line.description.as_str())
                .bind(line.quantity)
                .bind(line.unit_price)
                .execute(&mut *tx)
                .await?;
            }

            sqlx::query("INSERT INTO event_log (idempotency_key, status) VALUES ($1, $2)")
                .bind(invoice.idempotency_key.as_str())
                .bind(status.as_str())
                .execute(&mut *tx)
                .await?;
        }

        tx.commit().await?;
        Ok(inserted)
    }

    async fn set_status(&mut self, idempotency_key: &str, status: Status) -> anyhow::Result<()> {
        PostgresStaging::update_status(self, idempotency_key, status).await
    }

    async fn count(&self, status: Status) -> anyhow::Result<usize> {
        let row: (i64,) = sqlx::query_as("SELECT count(*) FROM invoice WHERE status = $1")
            .bind(status.as_str())
            .fetch_one(&self.pool)
            .await?;
        Ok(row.0 as usize)
    }
}
