// Read-only API exposing per-document posting outcomes. The orchestrator polls
// this (filtered by batchCode) to update staging status per invoice.
page 50001 "BIF Post Result"
{
    PageType = API;
    APIPublisher = 'bif';
    APIGroup = 'invoiceForge';
    APIVersion = 'v1.0';
    EntityName = 'postResult';
    EntitySetName = 'postResults';
    SourceTable = "BIF Post Result";
    Editable = false;
    DelayedInsert = false;
    ODataKeyFields = SystemId;
    Extensible = false;

    layout
    {
        area(Content)
        {
            field(id; Rec.SystemId) { }
            field(batchCode; Rec."Batch Code") { }
            field(sourceDocumentNo; Rec."Source Document No.") { }
            field(postedDocumentNo; Rec."Posted Document No.") { }
            field(success; Rec.Success) { }
            field(errorMessage; Rec."Error Message") { }
            field(createdAt; Rec."Created At") { }
        }
    }
}
