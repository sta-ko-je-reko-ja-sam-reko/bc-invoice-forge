// Document kind a batch-post job targets. Each value maps to its poster via the
// "BIF IDocument Poster" interface, so the dispatcher (BIF Batch Post) is
// generic — adding a kind = add a value here + a poster codeunit.
enum 50000 "BIF Doc Type" implements "BIF IDocument Poster"
{
    Extensible = true;

    value(0; Sales)
    {
        Caption = 'Sales';
        Implementation = "BIF IDocument Poster" = "BIF Sales Poster";
    }
    value(1; Purchase)
    {
        Caption = 'Purchase';
        Implementation = "BIF IDocument Poster" = "BIF Purchase Poster";
    }
    value(2; Service)
    {
        Caption = 'Service';
        Implementation = "BIF IDocument Poster" = "BIF Service Poster";
    }
    value(3; PurchaseOrder)
    {
        Caption = 'Purchase Order';
        Implementation = "BIF IDocument Poster" = "BIF Purch Order Poster";
    }
    value(4; ProductionOrder)
    {
        Caption = 'Production Order';
        Implementation = "BIF IDocument Poster" = "BIF Prod Order Poster";
    }
    value(5; AssemblyOrder)
    {
        Caption = 'Assembly Order';
        Implementation = "BIF IDocument Poster" = "BIF Assembly Poster";
    }
    value(6; TransferOrder)
    {
        Caption = 'Transfer Order';
        Implementation = "BIF IDocument Poster" = "BIF Transfer Poster";
    }
}
