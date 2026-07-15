// Posts service invoices via Service-Post. NOTE: the Service-Post API is
// version-sensitive; confirm PostWithLines for your BC version.
codeunit 50005 "BIF Service Poster" implements "BIF IDocument Poster"
{
    procedure PostBatch(BatchCode: Code[20]; var Posted: Integer; var Failed: Integer)
    var
        ServiceHeader: Record "Service Header";
        PostLog: Codeunit "BIF Post Log";
        DocNos: List of [Code[20]];
        DocNo: Code[20];
    begin
        ServiceHeader.SetRange("Document Type", ServiceHeader."Document Type"::Invoice);
        ServiceHeader.SetRange("BIF Batch Code", BatchCode);
        if ServiceHeader.FindSet() then
            repeat
                DocNos.Add(ServiceHeader."No.");
            until ServiceHeader.Next() = 0;

        foreach DocNo in DocNos do
            if ServiceHeader.Get(ServiceHeader."Document Type"::Invoice, DocNo) then
                if TryPost(ServiceHeader) then begin
                    Posted += 1;
                    PostLog.Log(BatchCode, ServiceHeader."BIF Source Doc No.", true, '');
                end else begin
                    Failed += 1;
                    PostLog.Log(BatchCode, ServiceHeader."BIF Source Doc No.", false, CopyStr(GetLastErrorText(), 1, 250));
                end;
    end;

    [TryFunction]
    local procedure TryPost(var ServiceHeader: Record "Service Header")
    var
        ServicePost: Codeunit "Service-Post";
        ServiceLine: Record "Service Line";
    begin
        Clear(ServicePost);
        ServiceLine.Reset();
        ServicePost.PostWithLines(ServiceHeader, ServiceLine, true, false, true);
    end;
}
