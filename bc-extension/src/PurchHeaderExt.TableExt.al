// Adds the batch marker to purchase invoices so a job can filter exactly the
// documents that belong to it. The orchestrator sets this at import time.
tableextension 75001 "BIF Purch Header Ext" extends "Purchase Header"
{
    fields
    {
        field(75000; "BIF Batch Code"; Code[20])
        {
            Caption = 'Batch Code';
            DataClassification = CustomerContent;
        }
        field(75001; "BIF Source Doc No."; Code[35])
        {
            Caption = 'Source Document No.';
            DataClassification = CustomerContent;
        }
    }
}
