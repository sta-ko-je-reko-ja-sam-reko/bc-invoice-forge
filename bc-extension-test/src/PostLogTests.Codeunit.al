// Unit tests of BIF Post Log: the per-document result rows the orchestrator reconciles from.
codeunit 79001 "BIF Post Log Tests"
{
    Subtype = Test;
    TestPermissions = Disabled;

    var
        Assert: Codeunit "Library Assert";
        TestLibrary: Codeunit "BIF Test Library";
        PostLog: Codeunit "BIF Post Log";

    [Test]
    procedure SuccessIsLoggedWithoutErrorMessage()
    var
        PostResult: Record "BIF Post Result";
        BatchCode: Code[20];
        SourceDocNo: Code[35];
    begin
        // [GIVEN] a batch and a source document
        BatchCode := TestLibrary.NewBatchCode();
        SourceDocNo := TestLibrary.NewSourceDocNo();

        // [WHEN] a successful post is logged
        PostLog.Log(BatchCode, SourceDocNo, '', true, '');

        // [THEN] one result row carries the batch, the source document and success
        PostResult.SetRange("Batch Code", BatchCode);
        Assert.RecordCount(PostResult, 1);
        PostResult.FindFirst();
        Assert.AreEqual(SourceDocNo, PostResult."Source Document No.", 'Source Document No.');
        Assert.IsTrue(PostResult.Success, 'Success');
        Assert.AreEqual('', PostResult."Error Message", 'Error Message');
        Assert.AreNotEqual(0DT, PostResult."Created At", 'Created At is stamped on insert');
    end;

    [Test]
    procedure FailureIsLoggedWithErrorMessage()
    var
        BatchCode: Code[20];
        SourceDocNo: Code[35];
    begin
        // [GIVEN] a batch and a source document
        BatchCode := TestLibrary.NewBatchCode();
        SourceDocNo := TestLibrary.NewSourceDocNo();

        // [WHEN] a failed post is logged with the BC error
        PostLog.Log(BatchCode, SourceDocNo, '', false, 'Customer is blocked.');

        // [THEN] the row is a failure and keeps the error text
        Assert.AreEqual('Customer is blocked.', TestLibrary.AssertResult(BatchCode, SourceDocNo, false), 'Error Message');
    end;

    [Test]
    procedure PostedDocumentNoIsLogged()
    var
        BatchCode: Code[20];
        SourceDocNo: Code[35];
    begin
        // [GIVEN] a batch and a source document
        BatchCode := TestLibrary.NewBatchCode();
        SourceDocNo := TestLibrary.NewSourceDocNo();

        // [WHEN] a successful post is logged with the posted document number
        PostLog.Log(BatchCode, SourceDocNo, 'PSI-0001', true, '');

        // [THEN] the result carries it for the postResults API
        TestLibrary.AssertPostedDocNo(BatchCode, SourceDocNo, 'PSI-0001');
    end;

    [Test]
    procedure LongErrorMessageIsTruncatedToFieldLength()
    var
        PostResult: Record "BIF Post Result";
        BatchCode: Code[20];
        LongError: Text;
    begin
        // [GIVEN] an error text longer than the Error Message field
        BatchCode := TestLibrary.NewBatchCode();
        LongError := PadStr('', 400, 'x') + 'tail';

        // [WHEN] it is logged
        PostLog.Log(BatchCode, TestLibrary.NewSourceDocNo(), '', false, LongError);

        // [THEN] the row keeps the first 250 characters instead of failing the insert
        PostResult.SetRange("Batch Code", BatchCode);
        PostResult.FindFirst();
        Assert.AreEqual(MaxStrLen(PostResult."Error Message"), StrLen(PostResult."Error Message"), 'Error Message length');
        Assert.AreEqual(CopyStr(LongError, 1, MaxStrLen(PostResult."Error Message")), PostResult."Error Message", 'Error Message');
    end;

    [Test]
    procedure EveryCallAddsItsOwnRow()
    var
        PostResult: Record "BIF Post Result";
        BatchCode: Code[20];
        SourceDocNo: Code[35];
    begin
        // [GIVEN] a source document that fails once and posts on a rerun
        BatchCode := TestLibrary.NewBatchCode();
        SourceDocNo := TestLibrary.NewSourceDocNo();

        // [WHEN] both outcomes are logged under the same batch
        PostLog.Log(BatchCode, SourceDocNo, '', false, 'First attempt failed.');
        PostLog.Log(BatchCode, SourceDocNo, '', true, '');

        // [THEN] the log is append-only: two rows with their own entry numbers
        PostResult.SetRange("Batch Code", BatchCode);
        PostResult.SetRange("Source Document No.", SourceDocNo);
        Assert.RecordCount(PostResult, 2);
        PostResult.SetRange(Success, true);
        Assert.RecordCount(PostResult, 1);
    end;

    [Test]
    procedure ResultsAreScopedByBatchCode()
    var
        BatchCode: Code[20];
        OtherBatchCode: Code[20];
    begin
        // [GIVEN] two batches
        BatchCode := TestLibrary.NewBatchCode();
        OtherBatchCode := TestLibrary.NewBatchCode();

        // [WHEN] results are logged to both
        PostLog.Log(BatchCode, TestLibrary.NewSourceDocNo(), '', true, '');
        PostLog.Log(BatchCode, TestLibrary.NewSourceDocNo(), '', true, '');
        PostLog.Log(OtherBatchCode, TestLibrary.NewSourceDocNo(), '', true, '');

        // [THEN] each batch only sees its own rows (the postResults API is polled per batch code)
        Assert.AreEqual(2, TestLibrary.CountResults(BatchCode), 'Rows of the first batch');
        Assert.AreEqual(1, TestLibrary.CountResults(OtherBatchCode), 'Rows of the second batch');
    end;
}
