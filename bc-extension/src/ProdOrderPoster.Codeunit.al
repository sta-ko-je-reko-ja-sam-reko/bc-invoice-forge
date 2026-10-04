// Posts/finishes production orders.
//
// ⚠️ Production "posting" is process- and setup-specific: real flows post
// consumption + output journals before finishing. This finishes released orders
// as a starting point — ADAPT to your output-posting process. Whatever the
// standard posting path, your Quality app's subscribers fire and create Quality
// Orders. Confirm the `Prod. Order Status Management` signature for your version.
//
// ChangeProdOrderStatus is a procedure, so this codeunit runs itself per order
// (OnRun, TableNo = Production Order) for per-document rollback (see BIF Sales Poster).
codeunit 75007 "BIF Prod Order Poster" implements "BIF IDocument Poster"
{
    TableNo = "Production Order";

    trigger OnRun()
    var
        StatusMgt: Codeunit "Prod. Order Status Management";
    begin
        // TODO: post consumption/output first if your process requires it.
        StatusMgt.ChangeProdOrderStatus(Rec, Rec.Status::Finished, WorkDate(), false);
    end;

    // The finished production order keeps the released order's number.
    procedure PostBatch(BatchCode: Code[20]; var Posted: Integer; var Failed: Integer)
    var
        ProdOrder: Record "Production Order";
        PostLog: Codeunit "BIF Post Log";
        DocNos: List of [Code[20]];
        DocNo: Code[20];
        SourceDocNo: Code[35];
    begin
        ProdOrder.SetRange(Status, ProdOrder.Status::Released);
        ProdOrder.SetRange("BIF Batch Code", BatchCode);
        if ProdOrder.FindSet() then
            repeat
                DocNos.Add(ProdOrder."No.");
            until ProdOrder.Next() = 0;

        foreach DocNo in DocNos do
            if ProdOrder.Get(ProdOrder.Status::Released, DocNo) then begin
                SourceDocNo := ProdOrder."BIF Source Doc No.";
                Commit();
                if Codeunit.Run(Codeunit::"BIF Prod Order Poster", ProdOrder) then begin
                    Posted += 1;
                    PostLog.Log(BatchCode, SourceDocNo, DocNo, true, '');
                end else begin
                    Failed += 1;
                    PostLog.Log(BatchCode, SourceDocNo, '', false, GetLastErrorText());
                end;
            end;
    end;
}
