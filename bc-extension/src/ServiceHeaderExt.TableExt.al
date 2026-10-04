// Service invoices have no standard automation API, so we import them through
// custom API pages. This adds the batch marker plus a place to carry the
// external document number (Service Header has no External Document No. field).
tableextension 75002 "BIF Service Header Ext" extends "Service Header"
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
