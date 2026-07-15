// Batch marker + source correlation for transfer orders.
tableextension 50005 "BIF Transfer Header Ext" extends "Transfer Header"
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
