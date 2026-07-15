-- Detailed, per-document / per-line error store. This is where ALL errors for
-- ALL documents live — outside Business Central. One document can have many
-- errors (header and/or line, from external validation and/or BC posting).

CREATE TABLE IF NOT EXISTS document_error (
    id              BIGSERIAL PRIMARY KEY,
    idempotency_key TEXT NOT NULL,
    scope           TEXT NOT NULL,        -- 'header' | 'line'
    line_no         INTEGER,              -- NULL for header-scope errors
    field           TEXT,                 -- offending field (nullable)
    code            TEXT NOT NULL,        -- machine code, e.g. UNKNOWN_CUSTOMER
    message         TEXT NOT NULL,        -- human-readable detail
    source          TEXT NOT NULL,        -- 'validation' | 'bc'
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_document_error_key  ON document_error (idempotency_key);
CREATE INDEX IF NOT EXISTS idx_document_error_code ON document_error (code);

-- Reference data synced from BC, used for cheap external validation so that
-- invalid documents (unknown customer/vendor/item/posting group) are caught
-- WITHOUT ever touching BC. A single generic table keyed by (kind, no).
CREATE TABLE IF NOT EXISTS ref_entity (
    kind TEXT NOT NULL,     -- 'customer' | 'vendor' | 'item' | 'posting_group' | ...
    no   TEXT NOT NULL,     -- normalized (trim + lowercase)
    name TEXT,
    PRIMARY KEY (kind, no)
);
