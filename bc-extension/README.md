# bc-extension — AL app

The only code that runs **inside** Business Central. It exposes API pages the
orchestrator calls and posts large sets of documents server-side. Posting always
goes through **standard** BC posting codeunits, so subscribers (e.g. the Merit
Solutions Quality app) fire and create Quality Orders automatically.

## Architecture

Posting is extensible via an interface. `BIF Batch Post` resolves a job's
document kind to a poster and delegates — adding a kind means adding an enum
value + a poster codeunit, nothing else.

```
BIF Batch Post (dispatcher)
   └─ Job."Doc Type" : enum "BIF Doc Type"  ──implements──▶  interface "BIF IDocument Poster"
                                                                  ├─ BIF Sales Poster        (Sales-Post)
                                                                  ├─ BIF Purchase Poster     (Purch.-Post, invoice)
                                                                  ├─ BIF Service Poster      (Service-Post)
                                                                  ├─ BIF Purch Order Poster  (Purch.-Post, receive+invoice)
                                                                  ├─ BIF Prod Order Poster   (finish — ADAPT)
                                                                  ├─ BIF Assembly Poster     (Assembly-Post)
                                                                  └─ BIF Transfer Poster     (ship + receive)
```

Each poster collects its documents (filtered by `BIF Batch Code`), posts each in
an isolated `[TryFunction]`, and logs the outcome via `BIF Post Log` →
`BIF Post Result`.

## Object inventory (range 50000–50099)

- **Interface**: `BIF IDocument Poster`
- **Enum**: `BIF Doc Type` (implements the interface), `BIF Job Status`
- **Codeunits**: `BIF Batch Post`, `BIF Batch Post Runner`, `BIF Post Log`, and 7 posters (50003–50009)
- **Tables**: `BIF Batch Post Job`, `BIF Post Result`
- **Pages (API)**: `batchPostJobs` (+ `run` action), `postResults`, `salesInvoiceTags`, `purchaseInvoiceTags`, `serviceInvoices`(+lines), and order-creation APIs `purchaseOrders`(+lines), `assemblyOrders`, `productionOrders`, `transferOrders`(+lines)
- **Table extensions** (`BIF Batch Code` + `BIF Source Doc No.`): Sales/Purchase/Service headers, Production Order, Assembly Header, Transfer Header

## To verify against a sandbox

- **Order creation field sets** (purchase/production/assembly/transfer order API
  pages) are **templated** — confirm field names + required setup per BC version.
- **Production**: the creation page inserts a released order but does **not**
  run `Refresh Production Order` (needed to create lines/components), and the
  poster **finishes** the order as a placeholder — adapt to your output-posting
  flow. `Prod. Order Status Management.ChangeStatusOnProdOrder` is version-specific.
- **Transfer**: needs from/to/in-transit location setup; those codes ride in the
  document's `header_fields` (populated by a source-specific parser).
- **`Service-Post.PostWithLines`** signature — confirm for your BC version.
- **Permission set** for the integration user.

## Dev

Open this folder in VS Code with the AL extension, set `launch.json` to your BC
sandbox, then `AL: Publish` (F5). Requires the objects to compile against your
target BC version (see `app.json`).
