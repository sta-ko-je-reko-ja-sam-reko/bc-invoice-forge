// Custom import API for transfer order lines (linked by document number).
page 50011 "BIF Transfer Order Line"
{
    PageType = API;
    APIPublisher = 'bif';
    APIGroup = 'invoiceForge';
    APIVersion = 'v1.0';
    EntityName = 'transferOrderLine';
    EntitySetName = 'transferOrderLines';
    SourceTable = "Transfer Line";
    ODataKeyFields = SystemId;
    DelayedInsert = true;
    Extensible = false;

    layout
    {
        area(Content)
        {
            field(id; Rec.SystemId) { Editable = false; }
            field(documentNo; Rec."Document No.") { }
            field(itemNo; Rec."Item No.") { }
            field(quantity; Rec.Quantity) { }
        }
    }

    trigger OnInsertRecord(BelowxRec: Boolean): Boolean
    var
        TransferLine: Record "Transfer Line";
    begin
        if Rec."Line No." = 0 then begin
            TransferLine.SetRange("Document No.", Rec."Document No.");
            if TransferLine.FindLast() then
                Rec."Line No." := TransferLine."Line No." + 10000
            else
                Rec."Line No." := 10000;
        end;
    end;
}
