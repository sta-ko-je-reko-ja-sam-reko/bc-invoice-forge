# Benchmarking & Load Testing

Two layers: the **ingestion side** (parse/validate/stage) benchmarks fully
locally; the **BC side** (import/post/reconcile) needs either a real sandbox or a
mock endpoint, because throughput there is gated by BC — not by the Rust code.

## 1. Ingestion throughput (local, no BC, no DB)

```powershell
# Pure parse -> validate -> dedup -> stage, in memory:
cargo run -p ingestion --release --example bench_ingest -- 100000
```

Reports generation time, ingest time, and **invoices/sec**. Always use
`--release`; debug builds are many times slower and not representative.

Scale the count up (1M+) to find where CPU/allocation becomes the limit. This
number is the ceiling the external service can feed BC at — in practice BC's API
throttling is the real bottleneck, so ingestion is rarely the constraint.

## 2. Generate a load file

```powershell
cargo run -p ingestion --release --example generate -- 100000 big.csv
```

Deterministic synthetic invoices across all three doc types. Feed it through the
staging path:

```powershell
$env:DATABASE_URL="postgres://forge:forge@localhost:5432/forge"
cargo run -p ingestion --release --example ingest -- big.csv
```

This measures the **DB-backed** staging path (Postgres round-trips) as opposed to
the in-memory bench above.

## 3. End-to-end (import + post) throughput

This is the number that matters for "100k invoices posted", and it's gated by BC.
Two ways to drive it:

### a. Against a real BC sandbox
Fill `.env`, stage a load file, run `cargo run -p orchestrator --release`, and
watch the per-chunk logs plus the adaptive limiter (`RUST_LOG=debug` shows
`throttle: increase/decrease`). This gives **real** 429 thresholds and posting
rates.

### b. Against a mock endpoint (no tenant)
Point the orchestrator at a local mock so you can exercise and profile the full
concurrency/pipeline/backpressure machinery without a tenant:

```
BC_TOKEN_URL=http://localhost:8080/token
BC_API_BASE_URL=http://localhost:8080/v2.0
```

The mock must answer: `POST /token` (return `{"access_token":"x"}`), the standard
`salesInvoices`/`purchaseInvoices` + `...Lines` creates (return `{"id","number"}`),
the custom `batchPostJobs` create + `Microsoft.NAV.run` action, `postResults`
(return an OData `{"value":[...]}` list), and the `...Tags` PATCH. A mock lets you
measure orchestrator overhead and validate behavior under injected 429s, but it
does **not** represent real BC posting cost. (Mock server not included — a small
`axum`/`hyper` stub is enough.)

## Metrics to capture

| Metric | Where |
|---|---|
| Ingestion invoices/sec | `bench_ingest` |
| Import invoices/sec | orchestrator logs (`chunk imported`, timestamps) |
| Posting invoices/sec | `job poll` + `reconciliation complete` timings |
| Sustained concurrency before 429 | `throttle:` debug logs |
| Failure buckets | `event_log` / `BIF Post Result` |

## Tuning knobs (set from observed behavior)

- `IMPORT_CONCURRENCY` — concurrency **ceiling** (adaptive limiter backs off below it).
- `IMPORT_CHUNK_SIZE` — rows per fetch/import chunk.
- `MAX_CONCURRENT_CHUNKS` — how many chunks may post at once (import↔post overlap depth).

Start conservative, raise `IMPORT_CONCURRENCY` until you see sustained 429s in the
logs, then let the adaptive limiter settle — the stable target it converges to is
your environment's practical ceiling.
