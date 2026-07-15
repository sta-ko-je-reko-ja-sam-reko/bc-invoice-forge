// Custom import API for service invoice lines. The orchestrator POSTs each line
// referencing its header by document number; Document Type defaults to Invoice
// and Line No. is auto-assigned.
page 50005 "BIF Service Invoice Line"
{
    PageType = API;
    APIPublisher = 'bif';
    APIGroup = 'invoiceForge';
    APIVersion = 'v1.0';
    EntityName = 'serviceInvoiceLine';
    EntitySetName = 'serviceInvoiceLines';
    SourceTable = "Service Line";
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
            field(unitPrice; Rec."Unit Price") { }
        }
    }

    trigger OnNewRecord(BelowxRec: Boolean)
    begin
        Rec."Document Type" := Rec."Document Type"::Invoice;
    end;

    trigger OnInsertRecord(BelowxRec: Boolean): Boolean
    var
        ServiceLine: Record "Service Line";
    begin
        if Rec."Line No." = 0 then begin
            ServiceLine.SetRange("Document Type", Rec."Document Type");
            ServiceLine.SetRange("Document No.", Rec."Document No.");
            if ServiceLine.FindLast() then
                Rec."Line No." := ServiceLine."Line No." + 10000
            else
                Rec."Line No." := 10000;
        end;
    end;
}
