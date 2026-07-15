// Posts assembly orders via the standard Assembly-Post codeunit.
codeunit 50008 "BIF Assembly Poster" implements "BIF IDocument Poster"
{
    procedure PostBatch(BatchCode: Code[20]; var Posted: Integer; var Failed: Integer)
    var
        AssemblyHeader: Record "Assembly Header";
        AssemblyPost: Codeunit "Assembly-Post";
        PostLog: Codeunit "BIF Post Log";
        DocNos: List of [Code[20]];
        DocNo: Code[20];
    begin
        AssemblyHeader.SetRange("Document Type", AssemblyHeader."Document Type"::Order);
        AssemblyHeader.SetRange("BIF Batch Code", BatchCode);
        if AssemblyHeader.FindSet() then
            repeat
                DocNos.Add(AssemblyHeader."No.");
            until AssemblyHeader.Next() = 0;

        foreach DocNo in DocNos do
            if AssemblyHeader.Get(AssemblyHeader."Document Type"::Order, DocNo) then
                if TryPost(AssemblyHeader, AssemblyPost) then begin
                    Posted += 1;
                    PostLog.Log(BatchCode, AssemblyHeader."BIF Source Doc No.", true, '');
                end else begin
                    Failed += 1;
                    PostLog.Log(BatchCode, AssemblyHeader."BIF Source Doc No.", false, CopyStr(GetLastErrorText(), 1, 250));
                end;
    end;

    [TryFunction]
    local procedure TryPost(var AssemblyHeader: Record "Assembly Header"; var AssemblyPost: Codeunit "Assembly-Post")
    begin
        Clear(AssemblyPost);
        AssemblyPost.Run(AssemblyHeader);
    end;
}
