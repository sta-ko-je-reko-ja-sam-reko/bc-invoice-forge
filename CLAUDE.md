# CLAUDE.md — project memory (committed, travels with git)

This file is auto-loaded by Claude Code. It is the durable memory for
**bc-invoice-forge** so work continues identically on any machine after a
`git pull`. Keep it high-signal; put deep detail in [docs/project-state.md](docs/project-state.md).

## What this is

A high-throughput engine to import 100k+ **documents** into **Microsoft
Dynamics 365 Business Central (SaaS)** and post them server-side. A **Rust**
service (ingestion + orchestrator) does the fast/parallel work; an **AL**
extension does the posting inside BC. Started life as invoices only, now a
generic multi-document engine (invoices + orders).

## The non-negotiable constraints (why it's built this way)

- **Posting must happen inside BC** through standard posting codeunits — never
  replicated externally. On SaaS there is **no DB access**; everything is API.
- **Throughput lever = fewer HTTP round-trips**: Rust stages in bulk, then a
  custom AL codeunit loops and posts many docs per call in a background session.
- **Standard posting is deliberate**: it makes the user's published **Merit
  Solutions Quality app** create Quality Orders automatically via its posting
  event subscribers. This tool has **zero** Quality-specific code and no
  dependency on that app (separate companion).

## Architecture (one line each)

- `ingestion/` (Rust lib) — parse (CSV/JSON/UBL/CII/Factur-X PDF/EDIFACT/X12) →
  validate → dedup → stage in Postgres. Format-agnostic `Document` model.
- `orchestrator/` (Rust bin) — OAuth2 to BC, resolve master data, adaptive-
  concurrent import, per-chunk server-side posting, reconcile, error store.
- `bc-extension/` (AL) — interface-dispatched posters (one per doc kind), custom
  API pages, batch-post job + result tables. Object range **50000–50099**.
- Postgres = staging + error store + reference data + mappings (NOT accounting).

Full flow, file map, and object inventory: [docs/project-state.md](docs/project-state.md).
Design rationale: [docs/architecture.md](docs/architecture.md).

## Key decisions already made (do not re-litigate)

- **Errors live in Postgres, never in BC.** `document_error` holds every error
  (header + line, `source` = validation | bc). Invalid docs are marked `invalid`
  and never sent to BC. BC-side failures roll back per-document and are captured.
- **Hybrid validation**: sync BC reference data (`ref_entity`) → validate
  externally (cheap) → BC per-document try-post as the safety net.
- **Posting-group errors** are intentionally left to the BC safety net (can't
  validate externally without replicating BC setup logic).
- **Idempotency key** = length-prefixed blake3 of (doc_type + partner + external
  doc no). Reruns dedup; `orchestrator reprocess` retries only invalid/failed.
- **Doc-type registry**: `DocType` methods (`tag`/`from_tag`/`party_kind`/
  `is_order`/`enum_name`) drive dispatch — no scattered matches. Adding a kind =
  enum variant + parser mapping + AL poster + enum value.

## Current status (IMPORTANT)

- **Nothing has been compiled or run.** No Rust/AL toolchain was available while
  building. Treat all code as written-but-unverified.
- The gate before trusting it is [docs/verification.md](docs/verification.md):
  `cargo build`/`cargo test` → publish AL → smoke-test one invoice → validate
  mappings against real files → load-test/tune.
- Every roadmap item in [README.md](README.md) is checked, **including** the
  extension phases (generic model, error store, reference sync, AL posters,
  error UX, order import).

## Known caveats / TODOs (verify against a sandbox)

- **External-crate API drift** on first compile: `lopdf` (PDF embedded-XML
  traversal) and `quick-xml` method names may need version alignment.
- **AL version-sensitive**: `Service-Post.PostWithLines`, and production
  posting (`Prod. Order Status Management.ChangeStatusOnProdOrder` + the missing
  `Refresh Production Order` step).
- **Order creation is templated** (purchase/production/assembly/transfer): field
  sets, transfer location setup, and production refresh need sandbox confirmation.
- **Legacy table name**: the staging tables are still `invoice` / `invoice_line`
  though they hold all document kinds — cosmetic; rename is a future cleanup.
- **AL permission set** for the integration user is not yet authored.

## Conventions

- Rust: `Document`/`DocumentLine` are the real types; `Invoice`/`InvoiceLine`
  are back-compat aliases. sqlx uses runtime queries (no compile-time DB needed).
- AL objects are `BIF`-prefixed, range 50000–50099. Posting always via standard
  codeunits. New doc kind → implement `interface "BIF IDocument Poster"`.
- Config is env-driven (see `.env.example`). Tuning knobs: `IMPORT_CONCURRENCY`
  (ceiling; adaptive limiter backs off on 429), `IMPORT_CHUNK_SIZE`,
  `MAX_CONCURRENT_CHUNKS`. Feature flags: `REQUIRE_PARTY_MAPPING`,
  `REQUIRE_ITEM_MAPPING`, `VALIDATE_REFERENCES`.

## Useful commands

```
cargo build --workspace && cargo test --workspace     # first compile + tests
docker compose up -d                                   # Postgres
cargo run -p ingestion --example ingest -- samples\invoices.csv
cargo run -p orchestrator -- sync-refs                 # populate ref_entity from BC
cargo run -p orchestrator                              # import + post
cargo run -p orchestrator -- reprocess                 # retry invalid/failed only
cargo run -p ingestion --example export_errors -- errors.csv
cargo run -p ingestion --release --example bench_ingest -- 100000
```
