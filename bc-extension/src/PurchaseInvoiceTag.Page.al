// Lets the orchestrator stamp the batch code onto an already-imported purchase
// invoice (the standard purchaseInvoices API doesn't expose the custom field).
// PATCH by systemId after import.
page 50003 "BIF Purch Invoice Tag"
{
    PageType = API;
    APIPublisher = 'bif';
    APIGroup = 'invoiceForge';
    APIVersion = 'v1.0';
    EntityName = 'purchaseInvoiceTag';
    EntitySetName = 'purchaseInvoiceTags';
    SourceTable = "Purchase Header";
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
