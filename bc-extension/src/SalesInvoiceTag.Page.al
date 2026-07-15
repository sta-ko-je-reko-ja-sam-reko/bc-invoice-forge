// Small custom API that lets the orchestrator stamp the batch code onto an
// already-imported sales invoice (the standard salesInvoices API doesn't expose
// the custom "BIF Batch Code" field). PATCH by systemId after import.
page 50002 "BIF Sales Invoice Tag"
{
    PageType = API;
    APIPublisher = 'bif';
    APIGroup = 'invoiceForge';
    APIVersion = 'v1.0';
    EntityName = 'salesInvoiceTag';
    EntitySetName = 'salesInvoiceTags';
    SourceTable = "Sales Header";
    ODataKeyFields = SystemId;
    DelayedInsert = false;
    Extensible = false;

    layout
    {
        area(Content)
        {
            field(id; Rec.SystemId) { Editable = false; }
            field(number; Rec."No.") { Editable = false; }
            field(batchCode; Rec."BIF Batch Code") { }
        }
    }

    trigger OnOpenPage()
    begin
        Rec.SetRange("Document Type", Rec."Document Type"::Invoice);
    end;
}
