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
its own `if Codeunit.Run(...)` (a failed document rolls back on its own; database
writes inside a `[TryFunction]` are rejected by the server), and logs the outcome
via `BIF Post Log` → `BIF Post Result`, including the posted document number
(posted invoice, posted assembly order, finished production order, transfer
receipt). A job with a blank batch code is marked `Failed` without posting
anything, because a blank filter would match every untagged document in the
company.

A job records the session that runs it. If that session dies, `BIF Job Session
Monitor` marks the job `Failed` (with a message) the next time `batchPostJobs` is
read or a job is started, so it never stays `Running`. A failed job can be run
again (`run`) or put back to `Pending` (`reset`).

Transfer orders are rerun-safe: the shipment is only posted when a line still has
a quantity to ship, so a transfer whose receipt failed after shipping is only
received on the rerun; a partially shipped one ships the rest, then receives.

## Object inventory (range 75000–78999)

- **Interface**: `BIF IDocument Poster`
- **Enum**: `BIF Doc Type` (implements the interface), `BIF Job Status`
- **Codeunits**: `BIF Batch Post`, `BIF Batch Post Runner`, `BIF Post Log`, 7 posters (75003–75009), `BIF Job Session Monitor` (75010)
- **Tables**: `BIF Batch Post Job`, `BIF Post Result`
- **Pages (API)**: `batchPostJobs` (+ `run` and `reset` actions), `postResults`, `salesInvoiceTags`, `purchaseInvoiceTags`, `serviceInvoices`(+lines), and order-creation APIs `purchaseOrders`(+lines), `assemblyOrders`, `productionOrders`, `transferOrders`(+lines)
- **Table extensions** (`BIF Batch Code` + `BIF Source Doc No.`, keyed on `BIF Batch Code`): Sales/Purchase/Service headers, Production Order, Assembly Header, Transfer Header
- **Permission set**: `BIF Invoice Forge` (full access to the extension's own objects; combine with standard permissions to create and post documents)

## To verify against a sandbox

- **Order creation field sets** (purchase/production/assembly/transfer order API
  pages) are **templated** — confirm field names + required setup per BC version.
- **Production**: the creation page inserts a released order but does **not**
  run `Refresh Production Order` (needed to create lines/components), and the
  poster **finishes** the order as a placeholder — adapt to your output-posting
  flow. `Prod. Order Status Management.ChangeProdOrderStatus` is version-specific.
- **Transfer**: needs from/to/in-transit location setup; those codes ride in the
  document's `header_fields` (populated by a source-specific parser).
- **`Service-Post.PostWithLines`** signature — confirm for your BC version.
- **Permission set** for the integration user: `BIF Invoice Forge` covers the
  extension's objects; the standard document and posting permissions still need
  to be chosen per tenant.

## Dev

Open this folder in VS Code with the AL extension, set `launch.json` to your BC
sandbox, then `AL: Publish` (F5). Requires the objects to compile against your
target BC version (see `app.json`).

## Build and test

The test app lives next to this folder in [`../bc-extension-test`](../bc-extension-test)
(it cannot live inside `bc-extension/`, because the compiler builds every `.al`
file under the project folder into the app).

```powershell
# compile app + test app with CodeCop, UICop, AppSourceCop, PerTenantExtensionCop
# against the local BC artifact cache (bar: zero errors, zero warnings)
.\tools\build.ps1
# publish both to a BcContainerHelper container and run every test
# (elevated PowerShell; results in .output\TestResults.xml)
.\tools\test.ps1 -ContainerName bc29loc
```

Test codeunits (range 79000–79999): `BIF Post Log Tests`, `BIF Batch Post Tests`,
`BIF Job Session Tests` (crashed sessions, reset, rerun), `BIF Schema Tests` (keys)
(job defaults, enum → poster dispatch for every kind, batch/kind filtering),
`BIF Job API Tests` and `BIF Import API Tests` (API page behaviour through
`TestPage`), and the `... Integration` codeunits that post real documents per kind
(sales, purchase invoice/order, service, transfer, assembly, production) with
error capture and reruns. Shared helpers are in `BIF Test Library`.
