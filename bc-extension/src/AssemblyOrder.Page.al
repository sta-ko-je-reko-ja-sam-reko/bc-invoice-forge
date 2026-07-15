// Custom import API for assembly order headers. Setting Item No. + Quantity
// explodes the assembly BOM into lines. Templated — confirm for your version.
page 50008 "BIF Assembly Order"
{
    PageType = API;
    APIPublisher = 'bif';
    APIGroup = 'invoiceForge';
    APIVersion = 'v1.0';
    EntityName = 'assemblyOrder';
    EntitySetName = 'assemblyOrders';
    SourceTable = "Assembly Header";
    ODataKeyFields = SystemId;
    DelayedInsert = true;
    Extensible = false;

    layout
    {
        area(Content)
        {
            field(id; Rec.SystemId) { Editable = false; }
            field(number; Rec."No.") { Editable = false; }
            field(itemNo; Rec."Item No.") { }
            field(quantity; Rec.Quantity) { }
            field(dueDate; Rec."Due Date") { }
            field(locationCode; Rec."Location Code") { }
            field(externalDocumentNo; Rec."BIF Source Doc No.") { }
            field(batchCode; Rec."BIF Batch Code") { }
        }
    }

    trigger OnNewRecord(BelowxRec: Boolean)
    begin
        Rec."Document Type" := Rec."Document Type"::Order;
    end;
}
