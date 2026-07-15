// Posts purchase orders (receive + invoice) via the standard Purch.-Post codeunit.
codeunit 50006 "BIF Purch Order Poster" implements "BIF IDocument Poster"
{
    procedure PostBatch(BatchCode: Code[20]; var Posted: Integer; var Failed: Integer)
    var
        PurchHeader: Record "Purchase Header";
        PurchPost: Codeunit "Purch.-Post";
        PostLog: Codeunit "BIF Post Log";
        DocNos: List of [Code[20]];
        DocNo: Code[20];
    begin
        PurchHeader.SetRange("Document Type", PurchHeader."Document Type"::Order);
        PurchHeader.SetRange("BIF Batch Code", BatchCode);
        if PurchHeader.FindSet() then
            repeat
                DocNos.Add(PurchHeader."No.");
            until PurchHeader.Next() = 0;

        foreach DocNo in DocNos do
            if PurchHeader.Get(PurchHeader."Document Type"::Order, DocNo) then
                if TryPost(PurchHeader, PurchPost) then begin
                    Posted += 1;
                    PostLog.Log(BatchCode, PurchHeader."BIF Source Doc No.", true, '');
                end else begin
                    Failed += 1;
                    PostLog.Log(BatchCode, PurchHeader."BIF Source Doc No.", false, CopyStr(GetLastErrorText(), 1, 250));
                end;
    end;

    [TryFunction]
    local procedure TryPost(var PurchHeader: Record "Purchase Header"; var PurchPost: Codeunit "Purch.-Post")
    begin
        Clear(PurchPost);
        PurchHeader.Receive := true;
        PurchHeader.Invoice := true;
        PurchPost.Run(PurchHeader);
    end;
}
