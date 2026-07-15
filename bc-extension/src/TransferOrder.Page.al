// Custom import API for transfer order headers. Requires from/to/in-transit
// location setup in BC. Templated — confirm for your version.
page 50010 "BIF Transfer Order"
{
    PageType = API;
    APIPublisher = 'bif';
    APIGroup = 'invoiceForge';
    APIVersion = 'v1.0';
    EntityName = 'transferOrder';
    EntitySetName = 'transferOrders';
    SourceTable = "Transfer Header";
    ODataKeyFields = SystemId;
    DelayedInsert = true;
    Extensible = false;

    layout
    {
        area(Content)
        {
            field(id; Rec.SystemId) { Editable = false; }
            field(number; Rec."No.") { Editable = false; }
            field(transferFromCode; Rec."Transfer-from Code") { }
            field(transferToCode; Rec."Transfer-to Code") { }
            field(inTransitCode; Rec."In-Transit Code") { }
            field(postingDate; Rec."Posting Date") { }
            field(externalDocumentNo; Rec."BIF Source Doc No.") { }
            field(batchCode; Rec."BIF Batch Code") { }
        }
    }
}
