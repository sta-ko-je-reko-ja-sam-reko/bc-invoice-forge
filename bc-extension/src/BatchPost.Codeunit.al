// Generic batch-post dispatcher. Resolves the job's document kind to its poster
// via the "BIF IDocument Poster" interface and delegates. Kind-specific posting
// logic lives in the per-kind poster codeunits, not here.
//
// Posting goes through standard BC posting codeunits, so subscribers (e.g. the
// Merit Solutions Quality app) fire and create Quality Orders automatically.
codeunit 50000 "BIF Batch Post"
{
    /// Entry point invoked by the background-session runner.
    procedure RunJob(var Job: Record "BIF Batch Post Job")
    var
        Poster: Interface "BIF IDocument Poster";
        Posted: Integer;
        Failed: Integer;
    begin
        Job.Status := Job.Status::Running;
        Job.Modify(true);
        Commit();

        Poster := Job."Doc Type"; // enum -> interface implementation
        Poster.PostBatch(Job."Batch Code", Posted, Failed);

        Job."Posted Count" := Posted;
        Job."Failed Count" := Failed;
        Job.Status := Job.Status::Completed;
        Job.Modify(true);
    end;
}
