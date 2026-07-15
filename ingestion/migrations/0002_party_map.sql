-- Maps a source party identifier (PEPPOL id, external customer/vendor code,
-- supplier party id from UBL/CII) to the real BC customer/vendor number.
-- Seed this out-of-band (see the `load-party-map` example).

CREATE TABLE IF NOT EXISTS party_map (
    kind      TEXT NOT NULL,   -- 'customer' | 'vendor'
    source_id TEXT NOT NULL,   -- normalized (trim + lowercase) source identifier
    bc_no     TEXT NOT NULL,   -- BC customer/vendor number
    PRIMARY KEY (kind, source_id)
);
