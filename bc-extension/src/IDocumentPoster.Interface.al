// Extensibility seam for server-side posting. Each document kind implements this
// and is wired to the "BIF Doc Type" enum, so adding a kind = add an enum value
// + a poster codeunit; the batch-post dispatcher needs no changes.
//
// Posting always goes through STANDARD BC posting codeunits, so any subscriber
// (e.g. the Merit Solutions Quality app's OnAfterPost events) fires normally and
// creates Quality Orders automatically.
interface "BIF IDocument Poster"
{
    /// Post every document of this kind carrying `BatchCode`. Increments
    /// `Posted`/`Failed`; logs each per-document outcome to BIF Post Result.
    procedure PostBatch(BatchCode: Code[20]; var Posted: Integer; var Failed: Integer);
}
