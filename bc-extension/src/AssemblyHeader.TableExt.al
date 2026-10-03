// Batch marker + source correlation for assembly orders.
tableextension 75004 "BIF Assembly Header Ext" extends "Assembly Header"
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
