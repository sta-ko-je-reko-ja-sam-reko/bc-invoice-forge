// Shared per-document result logging, used by every poster.
codeunit 50002 "BIF Post Log"
{
    procedure Log(BatchCode: Code[20]; SourceDocNo: Code[35]; Success: Boolean; ErrorMsg: Text)
    var
        Result: Record "BIF Post Result";
    begin
        Result.Init();
        Result."Batch Code" := BatchCode;
        Result."Source Document No." := SourceDocNo;
        Result.Success := Success;
        Result."Error Message" := CopyStr(ErrorMsg, 1, MaxStrLen(Result."Error Message"));
        Result.Insert(true);
    end;
}
