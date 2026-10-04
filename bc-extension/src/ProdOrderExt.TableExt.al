// Batch marker + source correlation for production orders.
tableextension 75003 "BIF Prod Order Ext" extends "Production Order"
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

    keys
    {
        // Every poster filters its documents by batch code. Keys in a table extension
        // can only hold the extension's own fields, so the document type / status
        // filter is applied on top of this key.
        key(BIFBatchCode; "BIF Batch Code") { }
    }
}
