-- Staging schema for bc-invoice-forge.
-- Not an accounting store: holds pending work + audit trail only.

CREATE TABLE IF NOT EXISTS invoice (
    idempotency_key      TEXT PRIMARY KEY,
    doc_type             TEXT NOT NULL,          -- sales | purchase | service
    external_document_no TEXT NOT NULL,
    partner_no           TEXT NOT NULL,          -- customer or vendor no
    document_date        TEXT NOT NULL,          -- ISO date from source
    currency_code        TEXT NOT NULL,
    status               TEXT NOT NULL,          -- see lifecycle state machine
    bc_document_no       TEXT,                   -- filled after import
    created_at           TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at           TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_invoice_status ON invoice (status);

CREATE TABLE IF NOT EXISTS invoice_line (
    id              BIGSERIAL PRIMARY KEY,
    idempotency_key TEXT NOT NULL REFERENCES invoice (idempotency_key) ON DELETE CASCADE,
    no              TEXT NOT NULL,               -- item / gl / resource no
    description     TEXT NOT NULL,
    quantity        DOUBLE PRECISION NOT NULL,
    unit_price      DOUBLE PRECISION NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_invoice_line_key ON invoice_line (idempotency_key);

-- Append-only audit of every status transition.
CREATE TABLE IF NOT EXISTS event_log (
    id              BIGSERIAL PRIMARY KEY,
    idempotency_key TEXT NOT NULL,
    status          TEXT NOT NULL,
    reason          TEXT,
    at              TIMESTAMPTZ NOT NULL DEFAULT now()
);
