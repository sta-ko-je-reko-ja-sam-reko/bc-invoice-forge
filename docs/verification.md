# Verification & Sandbox Checklist

The code was written without a local Rust/AL toolchain, so **nothing has been
compiled or run**. This doc is the gate to close before trusting the pipeline.
It also collects every "verify against a real environment" caveat flagged during
development, so they're all in one place.

Work top to bottom: **compile → unit tests → publish AL → smoke test one invoice
→ validate mappings → load test → tune**.

---

## 1. Rust: compile & unit tests

```powershell
cd C:\Users\marko.trnavac\Documents\bc-invoice-forge
cargo build --workspace
cargo test  --workspace
```

Expected unit tests (no DB/BC needed): CSV grouping, JSON single/array, idempotency
hash (stable/no-collision/doc-type), UBL XML, EDIFACT INVOIC, X12 810.

**Likely first-compile fixes** (external-crate API drift — versions may differ):
- **`lopdf`** ([ingestion/src/parsers/pdf.rs](../ingestion/src/parsers/pdf.rs)) — the embedded-file traversal
  (`catalog` → `Names` → `EmbeddedFiles` → filespec → `EF/F` stream) is the most
  API-sensitive code. Method names (`as_dict`, `as_array`, `as_stream`,
  `decompressed_content`, `get_object`) may need aligning to the resolved lopdf
  version.
- **`quick-xml`** ([xml.rs](../ingestion/src/parsers/xml.rs)) — `read_event_into`, `BytesText::unescape`,
  `QName::local_name` are stable across 0.31–0.37 but confirm against the locked version.
- **`sqlx` 0.8** — feature set is `runtime-tokio, tls-rustls, postgres, migrate`.
  Queries use the runtime API (not the compile-time-checked macros), so **no live
  DB is needed to build**.

## 2. Postgres staging

```powershell
docker compose up -d
$env:DATABASE_URL="postgres://forge:forge@localhost:5432/forge"
cargo run -p ingestion --example ingest -- samples\invoices.csv
```

- Migrations `0001_init` / `0002_party_map` / `0003_item_map` run automatically.
- Try each format: `samples\invoices.csv`, `samples\invoices.json`,
  `samples\ubl-invoice.xml`, `samples\invoice.edi`. Confirm parsed/staged counts.
- Re-run the same file → `staged: 0, duplicates: N` (idempotency works).

## 3. Master-data mapping

```powershell
cargo run -p ingestion --example load_party_map -- samples\party-map.csv
cargo run -p ingestion --example load_item_map  -- samples\item-map.csv
```

Decide the enforcement mode via env before the orchestrator runs:
- `REQUIRE_PARTY_MAPPING` / `REQUIRE_ITEM_MAPPING` = `false` (default): unmapped
  ids pass through unchanged (fine when sources already use BC numbers).
- `true`: unmapped party/item **fails** the invoice instead of shipping a bad id.

## 4. AL extension — publish to a sandbox

Open [bc-extension/](../bc-extension/) in VS Code (AL extension), point `launch.json` at a
BC **sandbox**, and publish (F5). Then verify:

- [ ] Objects compile against your BC version (range **50000–50099**).
- [ ] **Number series** exist for sales/purchase/**service** invoices.
- [ ] **`Service-Post` signature** — [BatchPost.Codeunit.al](../bc-extension/src/BatchPost.Codeunit.al) calls
      `ServicePost.PostWithLines(header, line, Ship, Consume, Invoice)`. This API
      is **version-sensitive**; confirm/adjust for your BC version. (Sales-Post /
      Purch-Post are standard.)
- [ ] **Background sessions** — the API `run` action uses `StartSession`; confirm
      the integration user may start sessions in your environment.
- [ ] **Permissions** — a least-privilege permission set covering the custom
      tables/pages + posting. (Not yet authored — TODO.)
- [ ] **Custom-field PATCH** — the orchestrator PATCHes `BIF Batch Code` via the
      `salesInvoiceTags` / `purchaseInvoiceTags` API pages; confirm the user can
      write it. (Service sets the batch code inline at create.)

## 5. Smoke test — one invoice end-to-end

Fill `.env` from [.env.example](../.env.example) (BC OAuth2 app registration + `DATABASE_URL`),
stage a single sales invoice, then:

```powershell
cargo run -p orchestrator
```

Trace the full lifecycle in the `invoice` table:
`validated → imported → posting → posted`. Confirm a posted sales invoice
appears in BC and the `BIF Post Result` rows are written.

**Field-name confidence by format** (validate the low-confidence ones with real files):
- **CSV / JSON / UBL** — unit-tested, high confidence.
- **UN/CEFACT CII** (Factur-X XML) — **not** unit-tested; verify seller-party and
  line paths against a real Factur-X invoice; profiles vary.
- **PDF** — verify the `lopdf` embedded-XML extraction against a real
  Factur-X/ZUGFeRD PDF. Plain/scanned PDFs are intentionally unsupported (clear error).
- **EDIFACT / X12** — unit-tested for the standard layout, but EDI is
  **partner-specific**: confirm which DTM/PRI/qualifier codes carry the real
  values for your trading partner.

Also confirm the **BC purchase API** field names on your version:
`vendorInvoiceNumber`, `vendorNumber`, line `directUnitCost`.

## 6. Load test & tuning

- Stage 100k+ invoices; run the orchestrator and watch the per-chunk logs
  (`chunk imported`, `job poll`, `reconciliation complete`).
- **Measure real 429 thresholds** for your environment — do **not** assume a
  fixed number. Watch the adaptive limiter's `throttle: decrease/increase` debug
  logs (`RUST_LOG=debug`).
- Tune the knobs from observed behavior:
  - `IMPORT_CONCURRENCY` — concurrency **ceiling** (limiter backs off below it).
  - `IMPORT_CHUNK_SIZE` — rows per fetch/import chunk.
  - `MAX_CONCURRENT_CHUNKS` — how many chunks may post at once (import↔post overlap).

## 7. Known TODOs (design-level, not blockers)

- `Service-Post` invocation confirmation (§4).
- AL permission set.
- Purchase/Service **posting result** reconciliation is shared by batch code; if
  two doc types share an external document number in one run they could
  mis-map — unlikely, but note it.
- Item/party mapping does **not** auto-create missing BC master data; it only
  resolves existing records.
- Reconciliation polls **inline** per run; a fully decoupled reconcile worker is
  a future enhancement.
- X12: only the 810 (invoice) is mapped; other transaction sets are out of scope.
