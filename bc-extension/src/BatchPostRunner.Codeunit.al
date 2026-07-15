// Runs a batch-post job in a background session so the triggering HTTP call
// returns immediately. StartSession invokes OnRun with the job record.
codeunit 50001 "BIF Batch Post Runner"
{
    TableNo = "BIF Batch Post Job";

    trigger OnRun()
    var
        BatchPost: Codeunit "BIF Batch Post";
    begin
        BatchPost.RunJob(Rec);
    end;
}
