// Custom import API for service invoice headers (no standard automation entity
// exists). The orchestrator POSTs a header here; Document Type defaults to
// Invoice and the No. is assigned from the service number series on insert.
page 50004 "BIF Service Invoice"
{
    PageType = API;
    APIPublisher = 'bif';
    APIGroup = 'invoiceForge';
    APIVersion = 'v1.0';
    EntityName = 'serviceInvoice';
    EntitySetName = 'serviceInvoices';
    SourceTable = "Service Header";
    ODataKeyFields = SystemId;
    DelayedInsert = true;
    Extensible = false;

    layout
    {
        area(Content)
        {
            field(id; Rec.SystemId) { Editable = false; }
            field(number; Rec."No.") { Editable = false; }
            field(customerNumber; Rec."Customer No.") { }
            field(documentDate; Rec."Document Date") { }
            field(currencyCode; Rec."Currency Code") { }
            field(externalDocumentNo; Rec."BIF Source Doc No.") { }
            field(batchCode; Rec."BIF Batch Code") { }
        }
    }

    trigger OnNewRecord(BelowxRec: Boolean)
    begin
        Rec."Document Type" := Rec."Document Type"::Invoice;
    end;
}
