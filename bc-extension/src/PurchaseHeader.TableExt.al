// Adds the batch marker to purchase invoices so a job can filter exactly the
// documents that belong to it. The orchestrator sets this at import time.
tableextension 50001 "BIF Purch Header Ext" extends "Purchase Header"
{
    fields
    {
        field(50000; "BIF Batch Code"; Code[20])
        {
            Caption = 'Batch Code';
            DataClassification = CustomerContent;
        }
        field(50001; "BIF Source Doc No."; Code[35])
        {
            Caption = 'Source Document No.';
            DataClassification = CustomerContent;
        }
    }
}
