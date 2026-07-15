// Batch marker + source correlation for production orders.
tableextension 50003 "BIF Prod Order Ext" extends "Production Order"
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
