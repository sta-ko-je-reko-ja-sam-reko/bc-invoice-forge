// Generic batch-post dispatcher. Resolves the job's document kind to its poster
// via the "BIF IDocument Poster" interface and delegates. Kind-specific posting
// logic lives in the per-kind poster codeunits, not here.
//
// Posting goes through standard BC posting codeunits, so subscribers (e.g. the
// Merit Solutions Quality app) fire and create Quality Orders automatically.
codeunit 75000 "BIF Batch Post"
{
    var
        BlankBatchCodeErr: Label 'The job has no batch code. A blank batch code would post every untagged document of this kind in the company.';

    /// Entry point invoked by the background-session runner.
    procedure RunJob(var Job: Record "BIF Batch Post Job")
    var
        Poster: Interface "BIF IDocument Poster";
        Posted: Integer;
        Failed: Integer;
    begin
        // A blank batch code would match every untagged document of the kind in the
        // company (all manually entered invoices, for example), so refuse to post.
        if Job."Batch Code" = '' then begin
            Job.Status := Job.Status::Failed;
            Job."Error Message" := BlankBatchCodeErr;
            Job."Finished At" := CurrentDateTime();
            Job.Modify(true);
            exit;
        end;

        // Record the session, so BIF Job Session Monitor can fail the job if this
        // session dies before it finishes.
        Job.Status := Job.Status::Running;
        Job."Session Id" := SessionId();
        Job."Server Instance Id" := ServiceInstanceId();
        Job."Started At" := CurrentDateTime();
        Job."Finished At" := 0DT;
        Job."Error Message" := '';
        Job."Posted Count" := 0;
        Job."Failed Count" := 0;
        Job.Modify(true);
        Commit();

        Poster := Job."Doc Type"; // enum -> interface implementation
        Poster.PostBatch(Job."Batch Code", Posted, Failed);

        Job."Posted Count" := Posted;
        Job."Failed Count" := Failed;
        Job.Status := Job.Status::Completed;
        Job."Finished At" := CurrentDateTime();
        Job.Modify(true);
    end;
}
