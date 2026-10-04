// Full access to the extension's own objects: the batch-post job and result tables,
// the API pages the orchestrator calls and the posting codeunits. Assign it to the
// integration user together with the standard permissions needed to create and post
// the documents themselves.
permissionset 75000 "BIF Invoice Forge"
{
    Assignable = true;
    Caption = 'BIF Invoice Forge';

    Permissions =
        tabledata "BIF Batch Post Job" = RIMD,
        tabledata "BIF Post Result" = RIMD,
        table "BIF Batch Post Job" = X,
        table "BIF Post Result" = X,
        codeunit "BIF Batch Post" = X,
        codeunit "BIF Batch Post Runner" = X,
        codeunit "BIF Post Log" = X,
        codeunit "BIF Sales Poster" = X,
        codeunit "BIF Purchase Poster" = X,
        codeunit "BIF Service Poster" = X,
        codeunit "BIF Purch Order Poster" = X,
        codeunit "BIF Prod Order Poster" = X,
        codeunit "BIF Assembly Poster" = X,
        codeunit "BIF Transfer Poster" = X,
        page "BIF Batch Post Job" = X,
        page "BIF Post Result" = X,
        page "BIF Sales Invoice Tag" = X,
        page "BIF Purch Invoice Tag" = X,
        page "BIF Service Invoice" = X,
        page "BIF Service Invoice Line" = X,
        page "BIF Purchase Order" = X,
        page "BIF Purchase Order Line" = X,
        page "BIF Assembly Order" = X,
        page "BIF Production Order" = X,
        page "BIF Transfer Order" = X,
        page "BIF Transfer Order Line" = X;
}
