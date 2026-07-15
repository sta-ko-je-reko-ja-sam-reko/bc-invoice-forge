// Posts sales invoices via the standard Sales-Post codeunit.
codeunit 50003 "BIF Sales Poster" implements "BIF IDocument Poster"
{
    procedure PostBatch(BatchCode: Code[20]; var Posted: Integer; var Failed: Integer)
    var
        SalesHeader: Record "Sales Header";
        SalesPost: Codeunit "Sales-Post";
        PostLog: Codeunit "BIF Post Log";
        DocNos: List of [Code[20]];
        DocNo: Code[20];
    begin
        // Collect first: posting deletes the header, so iterating a live filtered
        // set while posting is unsafe.
        SalesHeader.SetRange("Document Type", SalesHeader."Document Type"::Invoice);
        SalesHeader.SetRange("BIF Batch Code", BatchCode);
        if SalesHeader.FindSet() then
            repeat
                DocNos.Add(SalesHeader."No.");
            until SalesHeader.Next() = 0;

        foreach DocNo in DocNos do
            if SalesHeader.Get(SalesHeader."Document Type"::Invoice, DocNo) then
                if TryPost(SalesHeader, SalesPost) then begin
                    Posted += 1;
                    PostLog.Log(BatchCode, SalesHeader."External Document No.", true, '');
                end else begin
                    Failed += 1;
                    PostLog.Log(BatchCode, SalesHeader."External Document No.", false, CopyStr(GetLastErrorText(), 1, 250));
                end;
    end;

    [TryFunction]
    local procedure TryPost(var SalesHeader: Record "Sales Header"; var SalesPost: Codeunit "Sales-Post")
    begin
        Clear(SalesPost);
        SalesPost.Run(SalesHeader);
    end;
}
