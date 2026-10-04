// Adds the batch marker to sales invoices so a job can filter exactly the
// documents that belong to it. The orchestrator sets this at import time.
tableextension 75000 "BIF Sales Header Ext" extends "Sales Header"
{
    fields
    {
        field(75000; "BIF Batch Code"; Code[20])
        {
            Caption = 'Batch Code';
            DataClassification = CustomerContent;
        }
    }
}
