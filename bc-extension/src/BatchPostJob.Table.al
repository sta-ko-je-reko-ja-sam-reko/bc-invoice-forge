// One batch-post job. The orchestrator inserts a row (via the API page),
// triggers it, then polls Status / Posted Count / Failed Count.
table 50000 "BIF Batch Post Job"
{
    DataClassification = CustomerContent;
    Caption = 'BIF Batch Post Job';

    fields
    {
        field(1; "Entry No."; Integer)
        {
            Caption = 'Entry No.';
            AutoIncrement = true;
        }
        field(2; "Batch Code"; Code[20])
        {
            Caption = 'Batch Code';
            // Marks which unposted documents belong to this job
            // (see the "BIF Batch Code" field on the document headers).
        }
        field(3; "Doc Type"; Enum "BIF Doc Type")
        {
            Caption = 'Doc Type';
        }
        field(4; Status; Enum "BIF Job Status")
        {
            Caption = 'Status';
        }
        field(5; "Posted Count"; Integer)
        {
            Caption = 'Posted Count';
            Editable = false;
        }
        field(6; "Failed Count"; Integer)
        {
            Caption = 'Failed Count';
            Editable = false;
        }
        field(7; "Created At"; DateTime)
        {
            Caption = 'Created At';
            Editable = false;
        }
    }

    keys
    {
        key(PK; "Entry No.") { Clustered = true; }
    }

    trigger OnInsert()
    begin
        "Created At" := CurrentDateTime();
        if Status = Status::Pending then;
    end;
}
