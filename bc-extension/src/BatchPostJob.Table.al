// One batch-post job. The orchestrator inserts a row (via the API page),
// triggers it, then polls Status / Posted Count / Failed Count.
table 75000 "BIF Batch Post Job"
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
        field(8; "Session Id"; Integer)
        {
            Caption = 'Session Id';
            Editable = false;
            // Session that runs the job; with the server instance it identifies the
            // Active Session row, so a crashed session can be detected.
        }
        field(9; "Server Instance Id"; Integer)
        {
            Caption = 'Server Instance Id';
            Editable = false;
        }
        field(10; "Started At"; DateTime)
        {
            Caption = 'Started At';
            Editable = false;
        }
        field(11; "Finished At"; DateTime)
        {
            Caption = 'Finished At';
            Editable = false;
        }
        field(12; "Error Message"; Text[250])
        {
            Caption = 'Error Message';
            Editable = false;
            // Why the job itself failed (blank batch code, crashed session, session not
            // started). Per-document errors are in BIF Post Result.
        }
    }

    keys
    {
        key(PK; "Entry No.") { Clustered = true; }
        key(Status; Status) { }
        key(Batch; "Batch Code") { }
    }

    trigger OnInsert()
    begin
        "Created At" := CurrentDateTime();
    end;
}
