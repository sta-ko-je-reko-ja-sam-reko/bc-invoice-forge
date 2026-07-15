// Posts/finishes production orders.
//
// ⚠️ Production "posting" is process- and setup-specific: real flows post
// consumption + output journals before finishing. This finishes released orders
// as a starting point — ADAPT to your output-posting process. Whatever the
// standard posting path, your Quality app's subscribers fire and create Quality
// Orders. Confirm the `Prod. Order Status Management` signature for your version.
codeunit 50007 "BIF Prod Order Poster" implements "BIF IDocument Poster"
{
    procedure PostBatch(BatchCode: Code[20]; var Posted: Integer; var Failed: Integer)
    var
        ProdOrder: Record "Production Order";
        PostLog: Codeunit "BIF Post Log";
        DocNos: List of [Code[20]];
        DocNo: Code[20];
    begin
        ProdOrder.SetRange(Status, ProdOrder.Status::Released);
        ProdOrder.SetRange("BIF Batch Code", BatchCode);
        if ProdOrder.FindSet() then
            repeat
                DocNos.Add(ProdOrder."No.");
            until ProdOrder.Next() = 0;

        foreach DocNo in DocNos do
            if ProdOrder.Get(ProdOrder.Status::Released, DocNo) then
                if TryFinish(ProdOrder) then begin
                    Posted += 1;
                    PostLog.Log(BatchCode, ProdOrder."BIF Source Doc No.", true, '');
                end else begin
                    Failed += 1;
                    PostLog.Log(BatchCode, ProdOrder."BIF Source Doc No.", false, CopyStr(GetLastErrorText(), 1, 250));
                end;
    end;

    [TryFunction]
    local procedure TryFinish(var ProdOrder: Record "Production Order")
    var
        StatusMgt: Codeunit "Prod. Order Status Management";
    begin
        // TODO: post consumption/output first if your process requires it.
        StatusMgt.ChangeStatusOnProdOrder(ProdOrder, ProdOrder.Status::Finished, WorkDate(), false);
    end;
}
