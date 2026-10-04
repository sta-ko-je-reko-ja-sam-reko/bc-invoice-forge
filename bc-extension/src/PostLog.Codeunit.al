// Shared per-document result logging, used by every poster.
codeunit 75002 "BIF Post Log"
{
    /// Writes one result row. `PostedDocNo` is the number of the posted document the
    /// orchestrator can show (posted invoice, receipt, finished order); blank on failure.
    procedure Log(BatchCode: Code[20]; SourceDocNo: Code[35]; PostedDocNo: Code[20]; Success: Boolean; ErrorMsg: Text)
    var
        Result: Record "BIF Post Result";
    begin
        Result.Init();
        Result."Batch Code" := BatchCode;
        Result."Source Document No." := SourceDocNo;
        Result."Posted Document No." := PostedDocNo;
        Result.Success := Success;
        Result."Error Message" := CopyStr(ErrorMsg, 1, MaxStrLen(Result."Error Message"));
        Result.Insert(true);
    end;
}
