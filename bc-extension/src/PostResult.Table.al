// Per-document outcome of a batch-post run. The orchestrator reads this back
// (via the result API page) to update staging status per invoice.
table 50001 "BIF Post Result"
{
    DataClassification = CustomerContent;
    Caption = 'BIF Post Result';

    fields
    {
        field(1; "Entry No."; Integer)
        {
            Caption = 'Entry No.';
            AutoIncrement = true;
        }
        field(2; "Batch Code"; Code[20]) { Caption = 'Batch Code'; }
        field(3; "Source Document No."; Code[35])
        {
            Caption = 'Source Document No.';
            // External document number = the orchestrator's correlation key.
        }
        field(4; "Posted Document No."; Code[20]) { Caption = 'Posted Document No.'; }
        field(5; Success; Boolean) { Caption = 'Success'; }
        field(6; "Error Message"; Text[250]) { Caption = 'Error Message'; }
        field(7; "Created At"; DateTime) { Caption = 'Created At'; Editable = false; }
    }

    keys
    {
        key(PK; "Entry No.") { Clustered = true; }
        key(Batch; "Batch Code") { }
    }

    trigger OnInsert()
    begin
        "Created At" := CurrentDateTime();
    end;
}
