// Custom import API for purchase order headers. Batch code set inline.
// Field set is templated — confirm against your BC version.
page 50006 "BIF Purchase Order"
{
    PageType = API;
    APIPublisher = 'bif';
    APIGroup = 'invoiceForge';
    APIVersion = 'v1.0';
    EntityName = 'purchaseOrder';
    EntitySetName = 'purchaseOrders';
    SourceTable = "Purchase Header";
    ODataKeyFields = SystemId;
    DelayedInsert = true;
    Extensible = false;

    layout
    {
        area(Content)
        {
            field(id; Rec.SystemId) { Editable = false; }
            field(number; Rec."No.") { Editable = false; }
            field(vendorNumber; Rec."Buy-from Vendor No.") { }
            field(orderDate; Rec."Order Date") { }
            field(currencyCode; Rec."Currency Code") { }
            field(externalDocumentNo; Rec."BIF Source Doc No.") { }
            field(batchCode; Rec."BIF Batch Code") { }
        }
    }

    trigger OnNewRecord(BelowxRec: Boolean)
    begin
        Rec."Document Type" := Rec."Document Type"::Order;
    end;
}
