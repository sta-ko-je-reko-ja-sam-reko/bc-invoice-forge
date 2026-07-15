# Architecture — bc-invoice-forge

This document explains **how** the system moves 100k+ invoices into Business Central SaaS and posts them, and **why** it is built this way. Read the README first for the high-level picture.

---

## 1. Design principles

1. **Posting stays inside BC.** Posting runs BC business logic (Sales-Post CU 80, Purch-Post CU 90, Service-Post). It cannot be replicated externally without corrupting data, and on SaaS there is no DB access. So the external side never posts — it *triggers* posting.
2. **Minimize HTTP round-trips.** The SaaS ceiling is API throttling (HTTP 429). 100k individual posting calls will be throttled and slow. Instead: bulk-import drafts, then trigger a **server-side AL loop** that posts many documents per call.
3. **Do heavy CPU work outside BC.** Parsing, format detection, validation, and dedup of 100k files is where Rust shines. BC only ever sees clean, canonical, validated data.
4. **Everything is resumable and idempotent.** A crash, a 429 storm, or a bad batch must never double-post and must be safe to rerun.
5. **Fail per-document, not per-batch.** One malformed invoice must not roll back thousands of good ones.

## 2. Components

### 2.1 Rust ingestion service (`ingestion/`)

Turns messy source files into clean, validated, staged invoices.

- **Format detection.** A "file-type agent" sniffs each input (extension + content signature + optional schema probe) and routes it to a parser. Parsers are registered in a **registry** so new formats (EDI variants, PEPPOL/UBL, custom CSV) are pluggable.
- **Parsers** (`src/parsers/`): `csv.rs`, `xml.rs`, `edi.rs`, `peppol.rs`, `json.rs`, ... each emits the canonical model.
- **Canonical invoice model** (`src/canonical/`): one internal representation covering **sales, purchase, and service** invoices, with a `doc_type` discriminator. Downstream code never cares about the source format.
- **Validation & dedup:** schema/business rules (dates, amounts, currency, mandatory fields, master-data references), plus dedup via a deterministic **idempotency key** (see §5).
- **Staging** (`src/staging/`): writes each invoice + its status into Postgres.

### 2.2 Postgres staging database

The source of truth for progress and idempotency. It is **not** an accounting store — it holds pending work and audit trail.

Core tables (indicative):

| Table | Purpose |
|---|---|
| `invoice` | canonical invoice header + `doc_type` + `status` + `idempotency_key` + `bc_document_no` |
| `invoice_line` | canonical lines |
| `batch` | a chunk of invoices submitted together; tracks BC-side job status |
| `event_log` | append-only status transitions + errors for audit/replay |

Status state machine (`invoice.status`):

```
parsed -> validated -> imported -> posting -> posted
                          |            |
                          +--> failed <+     (with reason; safe to retry)
```

### 2.3 Rust orchestrator (`orchestrator/`)

Drives BC over its API with controlled concurrency.

- **Auth:** OAuth2 **client credentials** (Azure AD App Registration) against the BC environment; caches + refreshes tokens.
- **Import:** groups `validated` invoices into chunks and pushes them via **OData `$batch`** to BC API pages, moving them to `imported`.
- **Post trigger:** calls the AL `BatchPost` action per chunk (by filter or a batch id), moving invoices to `posting`.
- **Concurrency & backpressure:** a bounded worker pool; on `429`/`5xx` it applies exponential backoff + jitter and honors `Retry-After`.
- **Reconciliation:** polls BC for posting results, updates `posted`/`failed`, and re-queues retryable failures.

### 2.4 BC AL extension (`bc-extension/`)

The only code that runs inside BC.

- **API pages** for ingesting draft invoices: standard `salesInvoices` / `purchaseInvoices` where possible, and a **custom API page for service invoices**.
- **`BatchPost` codeunit:** accepts a filter or batch id, loops over the matching unposted documents **inside BC**, posts each with isolated error handling (`if Codeunit.Run() then ... else log`), and records per-document outcome. This is the key throughput lever — the loop runs server-side, so one API call posts thousands.
- **Background execution:** `BatchPost` runs in a **background session** / **job queue entry** so the triggering HTTP call returns fast and BC processes asynchronously.
- **Result surface:** a status/result API the orchestrator polls (posted document numbers, error reasons per source key).

## 3. End-to-end flow

```
1. Files land        ──► ingestion detects type, parses, validates, dedups
2. Staged            ──► Postgres: status = validated, idempotency_key set
3. Bulk import       ──► orchestrator: OData $batch ──► BC API pages ──► drafts
                         status = imported, bc_document_no captured
4. Trigger post      ──► orchestrator calls BatchPost(batch_id)
                         BC job queue posts the chunk server-side
                         status = posting
5. Reconcile         ──► orchestrator polls result API
                         status = posted | failed(reason)
6. Retry             ──► failed + retryable ──► back to step 3/4
```

## 4. Throughput strategy

The goal is to make BC do bulk work and to keep the API pipe busy without tripping throttling.

- **Chunk size** is a tuning knob: large enough that per-call overhead is amortized, small enough for failure isolation and to fit BC operation limits. Start ~100–500 docs/chunk and measure.
- **Parallel chunks** up to the point where 429s appear; the worker pool self-throttles from there.
- **Server-side loop** means posting cost dominates, not HTTP — exactly what we want.
- **Benchmark early** against a real sandbox; the numbers below are placeholders to be replaced with measured values.

| Metric | Target (to be measured) |
|---|---|
| Import throughput | TBD invoices/min |
| Posting throughput | TBD invoices/min |
| Sustained without 429 | TBD concurrent chunks |

## 5. Idempotency & correctness

- **Idempotency key** = deterministic hash of stable source fields (e.g. `doc_type` + external document no + vendor/customer + date + total). Stored on `invoice` and carried to BC as an external reference.
- **Import** checks the key before creating a draft; a rerun that finds an existing `bc_document_no` skips creation.
- **Posting** is guarded by document status in BC (already-posted documents are skipped) *and* by staging status.
- **Per-document isolation** in `BatchPost` (`Codeunit.Run` in its own transaction) so a single failure logs and continues.

## 6. Throttling & limits (SaaS)

BC online enforces per-environment API limits and returns **HTTP 429** with `Retry-After`. Treat exact numbers as environment-specific and **measure them** rather than hard-coding.

Handling:
- Honor `Retry-After`; exponential backoff + jitter otherwise.
- Cap concurrency; degrade gracefully under sustained 429.
- Prefer fewer, larger operations (`$batch`, server-side loop) over many small ones.
- Keep long-running posting in **background sessions / job queue**, not synchronous HTTP.

> ⚠️ Verify current limits against Microsoft's BC documentation for your environment before sizing. Do not assume a fixed number.

## 7. Security

- Secrets (OAuth2 client secret / certificate, Postgres creds) via environment/secret store — never committed.
- Least-privilege BC permission set for the integration user.
- Audit trail in `event_log` for every state transition.

## 8. Open questions / to validate

- Exact standard-API coverage for **service invoices** — custom API page vs. any usable standard entity.
- Real **429 thresholds** and per-operation limits for the target environment.
- Whether to trigger `BatchPost` per chunk (fine-grained retry) or via one job over a filter (fewer calls).
- Master-data prerequisites (customers/vendors/items/dimensions) — assume present, or reconcile/create first?
