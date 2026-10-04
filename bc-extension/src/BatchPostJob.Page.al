// API page the orchestrator calls to create and trigger a batch-post job.
//
// Flow: POST a row to batchPostJobs, then invoke the bound `run` action:
//   POST .../batchPostJobs({id})/Microsoft.NAV.run
// `run` starts a background session and returns immediately; the orchestrator
// polls Status / Posted Count / Failed Count for reconciliation.
//
// Reading the page (or calling `run`) first fails every Running job whose session
// has ended (BIF Job Session Monitor), so a crashed run never stays Running. A
// failed job can be started again with `run`, or put back to Pending with `reset`:
//   POST .../batchPostJobs({id})/Microsoft.NAV.reset
page 75000 "BIF Batch Post Job"
{
    PageType = API;
    APIPublisher = 'bif';
    APIGroup = 'invoiceForge';
    APIVersion = 'v1.0';
    EntityName = 'batchPostJob';
    EntitySetName = 'batchPostJobs';
    SourceTable = "BIF Batch Post Job";
    DelayedInsert = true;
    ODataKeyFields = SystemId;
    Extensible = false;

    layout
    {
        area(Content)
        {
            field(id; Rec.SystemId) { Editable = false; }
            field(entryNo; Rec."Entry No.") { Editable = false; }
            field(batchCode; Rec."Batch Code") { }
            field(docType; Rec."Doc Type") { }
            field(status; Rec.Status) { Editable = false; }
            field(postedCount; Rec."Posted Count") { Editable = false; }
            field(failedCount; Rec."Failed Count") { Editable = false; }
            field(createdAt; Rec."Created At") { Editable = false; }
            field(startedAt; Rec."Started At") { Editable = false; }
            field(finishedAt; Rec."Finished At") { Editable = false; }
            field(errorMessage; Rec."Error Message") { Editable = false; }
        }
    }

    var
        SessionNotStartedErr: Label 'The background session for the job could not be started.';

    trigger OnOpenPage()
    var
        JobSessionMonitor: Codeunit "BIF Job Session Monitor";
    begin
        JobSessionMonitor.MarkStaleJobsFailed();
    end;

    [ServiceEnabled]
    procedure run(var ActionContext: WebServiceActionContext)
    var
        JobSessionMonitor: Codeunit "BIF Job Session Monitor";
        SessionId: Integer;
    begin
        JobSessionMonitor.CheckCanStart(Rec);
        Rec.Status := Rec.Status::Pending;
        Rec."Error Message" := '';
        Rec.Modify(true);
        Commit(); // ensure the row is visible to the new session

        if not StartSession(SessionId, Codeunit::"BIF Batch Post Runner", CompanyName(), Rec) then begin
            Rec.Status := Rec.Status::Failed;
            Rec."Error Message" := SessionNotStartedErr;
            Rec.Modify(true);
        end;

        SetActionResult(ActionContext);
    end;

    /// Puts a job that is not running back to Pending (clears counters and errors).
    [ServiceEnabled]
    procedure reset(var ActionContext: WebServiceActionContext)
    var
        JobSessionMonitor: Codeunit "BIF Job Session Monitor";
    begin
        JobSessionMonitor.ResetJob(Rec);
        SetActionResult(ActionContext);
    end;

    local procedure SetActionResult(var ActionContext: WebServiceActionContext)
    begin
        ActionContext.SetObjectType(ObjectType::Page);
        ActionContext.SetObjectId(Page::"BIF Batch Post Job");
        ActionContext.AddEntityKey(Rec.FieldNo(SystemId), Rec.SystemId);
        ActionContext.SetResultCode(WebServiceActionResultCode::Updated);
    end;
}
