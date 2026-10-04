// Posts assembly orders via the standard Assembly-Post codeunit.
// Each document runs in its own Codeunit.Run (see BIF Sales Poster for why).
codeunit 75008 "BIF Assembly Poster" implements "BIF IDocument Poster"
{
    procedure PostBatch(BatchCode: Code[20]; var Posted: Integer; var Failed: Integer)
    var
        AssemblyHeader: Record "Assembly Header";
        PostLog: Codeunit "BIF Post Log";
        DocNos: List of [Code[20]];
        DocNo: Code[20];
        SourceDocNo: Code[35];
    begin
        AssemblyHeader.SetRange("Document Type", AssemblyHeader."Document Type"::Order);
        AssemblyHeader.SetRange("BIF Batch Code", BatchCode);
        if AssemblyHeader.FindSet() then
            repeat
                DocNos.Add(AssemblyHeader."No.");
            until AssemblyHeader.Next() = 0;

        foreach DocNo in DocNos do
            if AssemblyHeader.Get(AssemblyHeader."Document Type"::Order, DocNo) then begin
                SourceDocNo := AssemblyHeader."BIF Source Doc No.";
                Commit();
                if Codeunit.Run(Codeunit::"Assembly-Post", AssemblyHeader) then begin
                    Posted += 1;
                    PostLog.Log(BatchCode, SourceDocNo, GetPostedAssemblyNo(DocNo), true, '');
                end else begin
                    Failed += 1;
                    PostLog.Log(BatchCode, SourceDocNo, '', false, GetLastErrorText());
                end;
            end;
    end;

    local procedure GetPostedAssemblyNo(OrderNo: Code[20]): Code[20]
    var
        PostedAssemblyHeader: Record "Posted Assembly Header";
    begin
        PostedAssemblyHeader.SetRange("Order No.", OrderNo);
        if PostedAssemblyHeader.FindLast() then
            exit(PostedAssemblyHeader."No.");
    end;
}
