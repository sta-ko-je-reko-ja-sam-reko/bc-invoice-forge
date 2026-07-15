# Project State — bc-invoice-forge

Detailed, committed memory. Read this after [../CLAUDE.md](../CLAUDE.md) to resume
work on any machine. Reflects the state as of the last commit; **nothing has been
compiled or run yet.**

## 1. Purpose & scope

Import 100k+ documents into BC SaaS and post them server-side, fast. Covers
**7 document kinds**:

- Sales invoice, Purchase invoice, Service invoice (fully wired: import + post)
- Purchase order, Production order, Assembly order, Transfer order (import + post
  wired but **templated**; needs sandbox verification)

Posting uses standard BC codeunits so the user's published **Merit Solutions
Quality app** creates Quality Orders automatically (separate companion, no dep).

## 2. End-to-end pipeline

```
parse (CSV/JSON/UBL/CII/Factur-X PDF/EDIFACT/X12)
  → Document model (kind + common fields + header_fields/line_fields bags)
  → dedup (blake3 idempotency key) → stage (Postgres `invoice`/`invoice_line`)
  → resolve party (party_map) + items (item_map)
  → validate: accumulate ALL errors (fields + reference data via ref_entity)
       • invalid → document_error + status `invalid` → NEVER sent to BC
  → adaptive-concurrent import into BC (custom/standard API pages)
  → per-chunk server-side batch post (AL interface dispatch, background session)
       • BC error → rolled back per-doc → document_error (source=bc) + `failed`
       • success → Quality Orders fire via subscribers
  → reconcile postResults → per-invoice status
  → observability: status counts + error-code summary
  → export_errors (CSV) ; reprocess (retry only invalid/failed)
```

## 3. Repository / file map

```
ingestion/                         Rust lib
  migrations/ 0001_init 0002_party_map 0003_item_map 0004_errors_refs
  examples/ ingest · load_party_map · load_item_map · generate · bench_ingest · export_errors
  src/
    lib.rs            ingest_file(), re-exports
    canonical.rs      Document/DocumentLine, DocType (7 kinds) + registry methods
    errors.rs         DocError (header/line/bc)
    validation.rs     validate_fields() accumulates all errors; dedup()
    staging.rs        Staging trait; InMemoryStaging; PostgresStaging (all queries)
    parsers/ mod(detect+registry) · csv · json · xml(UBL+CII) · pdf(Factur-X) · edi(EDIFACT+X12)

orchestrator/                      Rust bin
  src/
    main.rs           drain loop, import_batch, resolve_party/items, sync_references,
                      subcommands: `sync-refs`, `reprocess`
    config.rs         env config (+ token_url override for mock/bench)
    bc_client.rs      OAuth2, create_* (sales/purchase/service + 4 orders),
                      tag_*, batch job create/run, list_reference (paged), get/patch
    post.rs           trigger_batch_post (create job + run)
    reconcile.rs      poll jobs → apply postResults → status/errors
    retry.rs          backoff + is_retryable
    throttle.rs       AdaptiveLimiter (AIMD: halve on 429, +1 per 20 ok)
    validate.rs       validate_document (fields + ref_entity checks)

bc-extension/                      AL (range 50000–50099)
  app.json
  src/
    IDocumentPoster.Interface.al   interface "BIF IDocument Poster"
    DocType.Enum.al                enum implements interface, 7 values → posters
    JobStatus.Enum.al
    BatchPost.Codeunit.al          generic dispatcher (enum→interface)
    BatchPostRunner.Codeunit.al    StartSession background runner
    PostLog.Codeunit.al            shared result logging
    SalesPoster / PurchasePoster / ServicePoster .Codeunit.al
    PurchOrderPoster / ProdOrderPoster / AssemblyPoster / TransferPoster .Codeunit.al
    BatchPostJob.Table.al · PostResult.Table.al
    BatchPostJob.Page.al (+ run action) · PostResult.Page.al
    SalesInvoiceTag.Page.al · PurchaseInvoiceTag.Page.al
    ServiceInvoice.Page.al · ServiceInvoiceLine.Page.al
    PurchaseOrder(.Page/Line) · AssemblyOrder.Page · ProductionOrder.Page · TransferOrder(.Page/Line)
    *.TableExt.al  Sales/Purchase/Service headers, Production Order, Assembly Header, Transfer Header
                   (fields: "BIF Batch Code", "BIF Source Doc No.")

docs/ architecture.md · verification.md · benchmarking.md · project-state.md
samples/ invoices.csv · invoices.json · ubl-invoice.xml · invoice.edi · party-map.csv · item-map.csv
```

## 4. AL object inventory (range 50000–50099; per-type namespaces)

- Interface: `BIF IDocument Poster`
- Enums: 50000 `BIF Doc Type` (implements interface), 50001 `BIF Job Status`
- Tables: 50000 `BIF Batch Post Job`, 50001 `BIF Post Result`
- Codeunits: 50000 Batch Post, 50001 Batch Post Runner, 50002 Post Log,
  50003 Sales Poster, 50004 Purchase Poster, 50005 Service Poster,
  50006 Purch Order Poster, 50007 Prod Order Poster, 50008 Assembly Poster,
  50009 Transfer Poster
- Pages (API): 50000 batchPostJobs, 50001 postResults, 50002 salesInvoiceTags,
  50003 purchaseInvoiceTags, 50004 serviceInvoices, 50005 serviceInvoiceLines,
  50006 purchaseOrders, 50007 purchaseOrderLines, 50008 assemblyOrders,
  50009 productionOrders, 50010 transferOrders, 50011 transferOrderLines
- Table extensions: 50000 Sales Header, 50001 Purchase Header, 50002 Service
  Header, 50003 Production Order, 50004 Assembly Header, 50005 Transfer Header

## 5. Decisions & clarifications from the user

- BC deployment: **SaaS** (API only).
- Document types: sales/purchase/service invoices **+** purchase/production/
  assembly/transfer orders.
- Relationship to published app: **separate companion** (Quality Orders auto-fire
  via posting subscribers; no dependency, no re-submission of their app).
- Validation strategy: **hybrid** (reference sync + external validation + BC
  safety net).
- Error UX: **CSV export + reprocess-only-failed** (chosen as most practical).

## 6. Testing status

- Unit tests exist (written, unrun): parsers (csv/json/xml/edi), idempotency
  hash, doc-type tag roundtrip.
- No integration/e2e run. `bench_ingest` measures ingestion throughput locally.
- BC-side benchmark needs a sandbox or a mock (see benchmarking.md; token URL is
  overridable via `BC_TOKEN_URL`).

## 7. Immediate next actions (resume here)

1. `cargo build --workspace` — fix external-crate API drift (lopdf, quick-xml).
2. `cargo test --workspace`.
3. `docker compose up -d`; run the ingest example against each sample format.
4. Publish `bc-extension/` to a BC sandbox; author a permission set.
5. Smoke-test one sales invoice end-to-end (validated→imported→posting→posted).
6. Verify CII/EDI/PDF field mappings against real files.
7. Verify + adapt order creation/posting per kind (start with Purchase Order).
8. `sync-refs`, enable `VALIDATE_REFERENCES`, load-test, tune throttle knobs.

## 8. Open design threads (not yet done)

- Rename `invoice`/`invoice_line` tables → `document`/`document_line` (cosmetic).
- Production order refresh (create lines/components) after creation.
- Decoupled reconciliation worker (currently inline polling per run).
- Posting-group / dimension pre-validation (currently BC-safety-net only).
- AL permission set + optional BC page that reads the external error store.
