// Posts service invoices via Service-Post. NOTE: the Service-Post API is
// version-sensitive; confirm PostWithLines for your BC version.
//
// Service-Post.PostWithLines is a procedure, not a codeunit trigger, so this codeunit
// runs itself per document (OnRun, TableNo = Service Header) to get the same
// per-document rollback as the other posters (see BIF Sales Poster for why).
codeunit 75005 "BIF Service Poster" implements "BIF IDocument Poster"
{
    TableNo = "Service Header";

    trigger OnRun()
    var
        TempServiceLine: Record "Service Line" temporary;
        ServicePost: Codeunit "Service-Post";
        Ship: Boolean;
        Consume: Boolean;
        Invoice: Boolean;
    begin
        // An empty temporary line set posts all lines of the document, as Service-Post (Yes/No) does.
        Ship := true;
        Consume := false;
        Invoice := true;
        ServicePost.PostWithLines(Rec, TempServiceLine, Ship, Consume, Invoice);
    end;

    procedure PostBatch(BatchCode: Code[20]; var Posted: Integer; var Failed: Integer)
    var
        ServiceHeader: Record "Service Header";
        PostLog: Codeunit "BIF Post Log";
        DocNos: List of [Code[20]];
        DocNo: Code[20];
        SourceDocNo: Code[35];
    begin
        ServiceHeader.SetRange("Document Type", ServiceHeader."Document Type"::Invoice);
        ServiceHeader.SetRange("BIF Batch Code", BatchCode);
        if ServiceHeader.FindSet() then
            repeat
                DocNos.Add(ServiceHeader."No.");
            until ServiceHeader.Next() = 0;

        foreach DocNo in DocNos do
            if ServiceHeader.Get(ServiceHeader."Document Type"::Invoice, DocNo) then begin
                SourceDocNo := ServiceHeader."BIF Source Doc No.";
                Commit();
                if Codeunit.Run(Codeunit::"BIF Service Poster", ServiceHeader) then begin
                    Posted += 1;
                    PostLog.Log(BatchCode, SourceDocNo, true, '');
                end else begin
                    Failed += 1;
                    PostLog.Log(BatchCode, SourceDocNo, false, GetLastErrorText());
                end;
            end;
    end;
}
