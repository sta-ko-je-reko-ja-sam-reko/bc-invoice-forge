-- Maps a source line-item code (from CSV/JSON/UBL/CII) to the BC item number.
-- Seed this out-of-band (see the `load_item_map` example).

CREATE TABLE IF NOT EXISTS item_map (
    source_id TEXT PRIMARY KEY,  -- normalized (trim + lowercase) source item code
    bc_no     TEXT NOT NULL      -- BC item number
);
