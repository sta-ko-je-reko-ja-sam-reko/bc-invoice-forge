// Custom import API for purchase order lines (linked by document number).
page 50007 "BIF Purchase Order Line"
{
    PageType = API;
    APIPublisher = 'bif';
    APIGroup = 'invoiceForge';
    APIVersion = 'v1.0';
    EntityName = 'purchaseOrderLine';
    EntitySetName = 'purchaseOrderLines';
    SourceTable = "Purchase Line";
    ODataKeyFields = SystemId;
    DelayedInsert = true;
    Extensible = false;

    layout
    {
        area(Content)
        {
            field(id; Rec.SystemId) { Editable = false; }
            field(documentNo; Rec."Document No.") { }
            field(lineType; Rec.Type) { }
            field(number; Rec."No.") { }
            field(quantity; Rec.Quantity) { }
            field(directUnitCost; Rec."Direct Unit Cost") { }
        }
    }

    trigger OnNewRecord(BelowxRec: Boolean)
    begin
        Rec."Document Type" := Rec."Document Type"::Order;
    end;

    trigger OnInsertRecord(BelowxRec: Boolean): Boolean
    var
        PurchLine: Record "Purchase Line";
    begin
        if Rec."Line No." = 0 then begin
            PurchLine.SetRange("Document Type", Rec."Document Type");
            PurchLine.SetRange("Document No.", Rec."Document No.");
            if PurchLine.FindLast() then
                Rec."Line No." := PurchLine."Line No." + 10000
            else
                Rec."Line No." := 10000;
        end;
    end;
}
