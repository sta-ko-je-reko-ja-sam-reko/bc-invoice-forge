// Posts purchase invoices via the standard Purch.-Post codeunit.
codeunit 50004 "BIF Purchase Poster" implements "BIF IDocument Poster"
{
    procedure PostBatch(BatchCode: Code[20]; var Posted: Integer; var Failed: Integer)
    var
        PurchHeader: Record "Purchase Header";
        PurchPost: Codeunit "Purch.-Post";
        PostLog: Codeunit "BIF Post Log";
        DocNos: List of [Code[20]];
        DocNo: Code[20];
    begin
        PurchHeader.SetRange("Document Type", PurchHeader."Document Type"::Invoice);
        PurchHeader.SetRange("BIF Batch Code", BatchCode);
        if PurchHeader.FindSet() then
            repeat
                DocNos.Add(PurchHeader."No.");
            until PurchHeader.Next() = 0;

        foreach DocNo in DocNos do
            if PurchHeader.Get(PurchHeader."Document Type"::Invoice, DocNo) then
                if TryPost(PurchHeader, PurchPost) then begin
                    Posted += 1;
                    PostLog.Log(BatchCode, PurchHeader."Vendor Invoice No.", true, '');
                end else begin
                    Failed += 1;
                    PostLog.Log(BatchCode, PurchHeader."Vendor Invoice No.", false, CopyStr(GetLastErrorText(), 1, 250));
                end;
    end;

    [TryFunction]
    local procedure TryPost(var PurchHeader: Record "Purchase Header"; var PurchPost: Codeunit "Purch.-Post")
    begin
        Clear(PurchPost);
        PurchPost.Run(PurchHeader);
    end;
}
