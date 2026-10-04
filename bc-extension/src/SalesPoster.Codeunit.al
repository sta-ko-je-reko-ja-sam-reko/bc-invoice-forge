// Posts sales invoices via the standard Sales-Post codeunit.
//
// Each document is posted with `if Codeunit.Run(...)`, not inside a [TryFunction]:
// the server rejects database writes inside a TryFunction (DisableWriteInsideTryFunctions,
// on by default), and Codeunit.Run rolls a failed document back on its own.
// Codeunit.Run with a return value needs a committed transaction, hence the Commit
// before each document (the previous document's result row is written in between).
codeunit 75003 "BIF Sales Poster" implements "BIF IDocument Poster"
{
    procedure PostBatch(BatchCode: Code[20]; var Posted: Integer; var Failed: Integer)
    var
        SalesHeader: Record "Sales Header";
        PostLog: Codeunit "BIF Post Log";
        DocNos: List of [Code[20]];
        DocNo: Code[20];
        SourceDocNo: Code[35];
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
            if SalesHeader.Get(SalesHeader."Document Type"::Invoice, DocNo) then begin
                SourceDocNo := SalesHeader."External Document No.";
                Commit();
                if Codeunit.Run(Codeunit::"Sales-Post", SalesHeader) then begin
                    Posted += 1;
                    PostLog.Log(BatchCode, SourceDocNo, GetPostedInvoiceNo(DocNo), true, '');
                end else begin
                    Failed += 1;
                    PostLog.Log(BatchCode, SourceDocNo, '', false, GetLastErrorText());
                end;
            end;
    end;

    local procedure GetPostedInvoiceNo(PreAssignedNo: Code[20]): Code[20]
    var
        SalesInvoiceHeader: Record "Sales Invoice Header";
    begin
        SalesInvoiceHeader.SetRange("Pre-Assigned No.", PreAssignedNo);
        if SalesInvoiceHeader.FindLast() then
            exit(SalesInvoiceHeader."No.");
    end;
}
