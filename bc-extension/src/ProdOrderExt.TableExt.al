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
}
