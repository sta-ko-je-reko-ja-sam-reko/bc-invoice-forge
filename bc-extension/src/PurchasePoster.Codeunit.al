// Posts purchase invoices via the standard Purch.-Post codeunit.
// Each document runs in its own Codeunit.Run (see BIF Sales Poster for why).
codeunit 75004 "BIF Purchase Poster" implements "BIF IDocument Poster"
{
    procedure PostBatch(BatchCode: Code[20]; var Posted: Integer; var Failed: Integer)
    var
        PurchHeader: Record "Purchase Header";
        PostLog: Codeunit "BIF Post Log";
        DocNos: List of [Code[20]];
        DocNo: Code[20];
        SourceDocNo: Code[35];
    begin
        PurchHeader.SetRange("Document Type", PurchHeader."Document Type"::Invoice);
        PurchHeader.SetRange("BIF Batch Code", BatchCode);
        if PurchHeader.FindSet() then
            repeat
                DocNos.Add(PurchHeader."No.");
            until PurchHeader.Next() = 0;

        foreach DocNo in DocNos do
            if PurchHeader.Get(PurchHeader."Document Type"::Invoice, DocNo) then begin
                SourceDocNo := PurchHeader."Vendor Invoice No.";
                Commit();
                if Codeunit.Run(Codeunit::"Purch.-Post", PurchHeader) then begin
                    Posted += 1;
                    PostLog.Log(BatchCode, SourceDocNo, true, '');
                end else begin
                    Failed += 1;
                    PostLog.Log(BatchCode, SourceDocNo, false, GetLastErrorText());
                end;
            end;
    end;
}
