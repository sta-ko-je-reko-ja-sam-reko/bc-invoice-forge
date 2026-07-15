# bc-invoice-forge

High-throughput import and posting engine for **Microsoft Dynamics 365 Business Central (SaaS)**. A Rust ingestion service auto-detects, parses, and validates 100k+ sales, purchase, and service invoices, then orchestrates bulk import and **server-side batch posting** through BC's supported APIs and AL logic.

---

## Why this exists

Posting 100k+ invoices in BC is slow when done one document at a time through the UI or naive API calls. This project splits the work so each part runs where it is fastest:

- **Parsing, validation, and staging** happen **outside** BC, in a fast Rust service.
- **Posting** happens **inside** BC — because it must. Posting runs BC's business logic (Sales-Post, Purch-Post, Service-Post: validation, dimensions, G/L, VAT, ledger entries, number series). That logic cannot be bypassed, and on SaaS there is **no database access at all** — everything goes through APIs.

The performance win comes from **minimizing HTTP round-trips**: Rust stages invoices in bulk, then a custom AL *batch-posting* codeunit loops and posts them **server-side**. One HTTP trigger posts thousands of documents instead of making one call per invoice.

## The core constraint (read this first)

> **You cannot post invoices outside of BC.** On SaaS you cannot even read/write the database directly. All import and posting goes through REST/OData API pages and AL code. The throughput ceiling is set by BC's **API throttling** (HTTP 429) and the cost of posting itself — not by the Rust side.

## Responsibility split

| Stage | Runs where | Technology |
|---|---|---|
| Detect file type & parse (CSV/XML/EDI/PEPPOL/JSON) | External | Rust |
| Validate, dedup, canonical model | External | Rust + Postgres staging |
| Bulk import invoices as drafts | BC ingestion is the bottleneck | Rust → OData `$batch` → BC API pages |
| **Post invoices** | **Inside BC** | Custom AL `BatchPost` codeunit (background session), triggered by Rust |
| Progress tracking, retry, backoff | External | Rust orchestrator |

## Architecture (SaaS)

```
 Source files (mixed formats)
        │
        ▼
┌──────────────────────────────┐
│ RUST ingestion + orchestrator│
│  • format detection + parse  │
│  • validate / dedup          │
│  • canonical invoice model   │
│  • Postgres staging + status │
└───────────────┬──────────────┘
                │ OData $batch (chunked bulk insert)
                ▼
┌──────────────────────────────┐
│ BC SaaS                      │
│  • API pages (Sales / Purch /│
│    custom Service)           │
│  • Custom AL "BatchPost"     │
│    codeunit (background job) │
└───────────────┬──────────────┘
                │ status polling / 429 backoff
                ▲
        Rust tracks progress, retries failures
```

Full detail in [docs/architecture.md](docs/architecture.md).

## Repository layout

```
bc-invoice-forge/
├── ingestion/          # Rust: parsers, format detection, validation
│   ├── src/parsers/    #   csv, xml (UBL/CII), json, pdf (Factur-X), edi + registry
│   ├── src/canonical/  #   unified invoice model (sales/purchase/service)
│   └── src/staging/    #   Postgres repo, status state machine
├── orchestrator/       # Rust: BC API client, $batch, concurrency, backoff, retry
├── bc-extension/       # AL app: API pages + BatchPost codeunit + job queue
│   └── src/
├── docs/               # architecture, throttling notes, throughput targets
└── docker-compose.yml  # Postgres + orchestrator for local dev
```

## Document types supported

- **Sales invoices** — posted via Sales-Post (CU 80); standard `salesInvoices` API + `post` bound action.
- **Purchase invoices** — posted via Purch-Post (CU 90); standard `purchaseInvoices` API + `post` bound action.
- **Service invoices** — no standard automation entity, so imported via **custom API pages** (`serviceInvoices` / `serviceInvoiceLines`) and posted via `Service-Post`.

## Invoice lifecycle (staging status)

```
parsed -> validated -> imported -> posting -> posted
                          |            |
                          +--> failed <+     (with reason; safe to retry)
```

Every invoice carries an **idempotency key** so reruns never double-post.

## Status

🚧 Feature-complete but **not yet compiled/run** (built without a local Rust/AL
toolchain). Before trusting it, work through **[docs/verification.md](docs/verification.md)** —
the compile → publish → smoke-test → load-test gate, plus every "verify against a
real environment" caveat in one place. Roadmap below.

## Roadmap

- [x] Rust ingestion crate: format detection + parser registry + canonical model (CSV)
- [x] Postgres staging schema + status state machine (`sqlx`)
- [x] BC API client: OAuth2 client credentials, `salesInvoices` import, 429-aware retry
- [x] AL extension: batch-post job table + background-session posting + API pages
- [x] Orchestrator: pull validated → import → tag → trigger server-side posting
- [x] Reconciliation loop: poll the job, apply `postResults` to per-invoice staging status
- [x] Purchase import/posting path
- [x] Service import/posting path (custom service-invoice API pages + `Service-Post`)
- [x] Concurrency: bounded-parallel import (`buffer_unordered`) with per-call 429 backoff
- [x] Chunk-drain loop: one run imports the entire validated backlog, chunk by chunk
- [x] Post-per-chunk pipeline: each chunk posts while the next imports (bounded overlap + backpressure)
- [x] Real idempotency key: length-prefixed blake3 hash of the business key
- [x] Parsers: CSV, JSON, UBL + UN/CEFACT CII XML, PDF (Factur-X/ZUGFeRD embedded XML)
- [x] Party mapping: source party id → BC customer/vendor no (`party_map` table + loader)
- [x] Item mapping: source item code → BC item no (`item_map` table + loader)
- [x] EDI parsers: EDIFACT INVOIC + X12 810
- [x] Adaptive throttling: AIMD limiter shrinks concurrency on 429, recovers on success
- [x] Benchmark harness: synthetic data generator + ingestion bench + [benchmarking guide](docs/benchmarking.md)
- [x] Observability: end-of-run status counts + grouped error codes

### Extensibility (generic documents + robust errors)

- [x] **Phase 1 — Error foundation**: external `document_error` store (header/line, validation/BC), `ref_entity` reference table, accumulating field validation, `invalid` status, run error summary. Invalid docs never reach BC.
- [x] **Phase 2 — Generic document model**: `Document`/`DocumentLine` (with `Invoice` aliases), 7 kinds incl. PO/production/assembly/transfer, header/line extra-field bags, registry metadata (`party_kind`/`is_order`/`tag`)
- [x] **Phase 3 — Reference sync**: `orchestrator sync-refs` pulls customers/vendors/items (paged) → `ref_entity`, activating reference validation (posting-group errors stay caught by the BC safety net)
- [x] **Phase 4 — AL generic posters**: `interface "BIF IDocument Poster"` + enum dispatch; posters for all 7 kinds (Sales/Purchase/Service + Purchase/Production/Assembly/Transfer orders) + order-header table extensions. Quality Orders fire automatically via your app's posting subscribers.
- [x] **Phase 5 — Error UX**: `export_errors` (CSV of every error, with document context) + `orchestrator reprocess` (requeue only invalid/failed docs after fixing master data)
- [x] **Phase 4b — Order import wiring**: creation API pages (purchase/production/assembly/transfer orders) + orchestrator create methods + generic per-kind job dispatch. **Templated — needs sandbox verification** (order field sets, production refresh, transfer setup).

## Getting started (dev)

> Prerequisites: Rust (stable), Docker, AL dev tools (VS Code + AL extension), and a BC SaaS sandbox with an App Registration for OAuth2.

```
docker compose up -d        # Postgres for staging
# ingestion / orchestrator crates: see ingestion/README.md (to come)
# bc-extension: publish to a BC sandbox from VS Code
```

## License

TBD.
