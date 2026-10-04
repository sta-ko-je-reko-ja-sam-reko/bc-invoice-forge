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

    keys
    {
        // Every poster filters its documents by batch code. Keys in a table extension
        // can only hold the extension's own fields, so the document type / status
        // filter is applied on top of this key.
        key(BIFBatchCode; "BIF Batch Code") { }
    }
}
