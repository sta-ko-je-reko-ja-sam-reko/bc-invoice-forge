// Detects batch-post jobs whose background session is gone. A job is Running while
// its session posts; if that session crashes (or the server restarts) nothing ever
// moves the job on, so the orchestrator would poll it forever. A Running job whose
// session is no longer in the Active Session table is marked Failed with a message
// and can be run again.
codeunit 75010 "BIF Job Session Monitor"
{
    var
        SessionGoneErr: Label 'The session that ran this job (session %1) ended before the job finished. Run the job again to post the remaining documents.', Comment = '%1 = session id';
        AlreadyRunningErr: Label 'Batch-post job %1 is already running in session %2.', Comment = '%1 = entry no., %2 = session id';

    /// Marks every Running job whose session has ended as Failed.
    procedure MarkStaleJobsFailed()
    var
        Job: Record "BIF Batch Post Job";
        StaleJob: Record "BIF Batch Post Job";
    begin
        Job.SetRange(Status, Job.Status::Running);
        if Job.FindSet() then
            repeat
                if not IsSessionAlive(Job) then begin
                    StaleJob.Get(Job."Entry No.");
                    MarkFailed(StaleJob);
                end;
            until Job.Next() = 0;
    end;

    /// True when the job's session still exists on its server instance.
    procedure IsSessionAlive(Job: Record "BIF Batch Post Job"): Boolean
    var
        ActiveSession: Record "Active Session";
    begin
        ActiveSession.SetRange("Server Instance ID", Job."Server Instance Id");
        ActiveSession.SetRange("Session ID", Job."Session Id");
        exit(not ActiveSession.IsEmpty());
    end;

    /// Called before a job is started: refuses a job that is really running and
    /// fails a job whose session is gone, so it can be started again.
    procedure CheckCanStart(var Job: Record "BIF Batch Post Job")
    begin
        if Job.Status <> Job.Status::Running then
            exit;
        if IsSessionAlive(Job) then
            Error(AlreadyRunningErr, Job."Entry No.", Job."Session Id");
        MarkFailed(Job);
    end;

    /// Puts a job that is not running back to Pending with cleared counters, so the
    /// same row can be run again.
    procedure ResetJob(var Job: Record "BIF Batch Post Job")
    begin
        CheckCanStart(Job);
        Job.Status := Job.Status::Pending;
        Job."Posted Count" := 0;
        Job."Failed Count" := 0;
        Job."Session Id" := 0;
        Job."Server Instance Id" := 0;
        Job."Started At" := 0DT;
        Job."Finished At" := 0DT;
        Job."Error Message" := '';
        Job.Modify(true);
    end;

    local procedure MarkFailed(var Job: Record "BIF Batch Post Job")
    begin
        Job.Status := Job.Status::Failed;
        Job."Finished At" := CurrentDateTime();
        Job."Error Message" := CopyStr(StrSubstNo(SessionGoneErr, Job."Session Id"), 1, MaxStrLen(Job."Error Message"));
        Job.Modify(true);
    end;
}
