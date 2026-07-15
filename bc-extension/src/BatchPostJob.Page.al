// API page the orchestrator calls to create and trigger a batch-post job.
//
// Flow: POST a row to batchPostJobs, then invoke the bound `run` action:
//   POST .../batchPostJobs({id})/Microsoft.NAV.run
// `run` starts a background session and returns immediately; the orchestrator
// polls Status / Posted Count / Failed Count for reconciliation.
page 50000 "BIF Batch Post Job"
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
        }
    }

    [ServiceEnabled]
    procedure run(var ActionContext: WebServiceActionContext)
    var
        SessionId: Integer;
    begin
        Rec.Status := Rec.Status::Pending;
        Rec.Modify(true);
        Commit(); // ensure the row is visible to the new session

        StartSession(SessionId, Codeunit::"BIF Batch Post Runner", CompanyName(), Rec);

        ActionContext.SetObjectType(ObjectType::Page);
        ActionContext.SetObjectId(Page::"BIF Batch Post Job");
        ActionContext.AddEntityKey(Rec.FieldNo(SystemId), Rec.SystemId);
        ActionContext.SetResultCode(WebServiceActionResultCode::Updated);
    end;
}
