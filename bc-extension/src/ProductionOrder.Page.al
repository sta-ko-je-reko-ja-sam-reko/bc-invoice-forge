// Custom import API for production order headers.
// ⚠️ After insert, a real flow must run "Refresh Production Order" to create the
// order's lines/components/routing. That refresh is not done here (it needs a
// bound action or a subscriber) — TODO for Phase 4b hardening. Templated fields.
page 50009 "BIF Production Order"
{
    PageType = API;
    APIPublisher = 'bif';
    APIGroup = 'invoiceForge';
    APIVersion = 'v1.0';
    EntityName = 'productionOrder';
    EntitySetName = 'productionOrders';
    SourceTable = "Production Order";
    ODataKeyFields = SystemId;
    DelayedInsert = true;
    Extensible = false;

    layout
    {
        area(Content)
        {
            field(id; Rec.SystemId) { Editable = false; }
            field(number; Rec."No.") { Editable = false; }
            field(sourceNo; Rec."Source No.") { }
            field(quantity; Rec.Quantity) { }
            field(dueDate; Rec."Due Date") { }
            field(locationCode; Rec."Location Code") { }
            field(externalDocumentNo; Rec."BIF Source Doc No.") { }
            field(batchCode; Rec."BIF Batch Code") { }
        }
    }

    trigger OnNewRecord(BelowxRec: Boolean)
    begin
        Rec.Status := Rec.Status::Released;
        Rec."Source Type" := Rec."Source Type"::Item;
    end;
}
