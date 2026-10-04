// End to end: tagged sales invoices -> batch-post job -> standard Sales-Post, with
// per-document error capture and reruns that never post a document twice.
codeunit 79004 "BIF Sales Post Integration"
{
    Subtype = Test;
    TestPermissions = Disabled;

    var
        Assert: Codeunit "Library Assert";
        TestLibrary: Codeunit "BIF Test Library";

    [Test]
    procedure BatchPostsEverySalesInvoiceOfTheBatch()
    var
        Job: Record "BIF Batch Post Job";
        SalesHeader: array[3] of Record "Sales Header";
        BatchCode: Code[20];
        i: Integer;
    begin
        // [GIVEN] three sales invoices imported under one batch code
        BatchCode := TestLibrary.NewBatchCode();
        for i := 1 to ArrayLen(SalesHeader) do
            TestLibrary.CreateSalesInvoice(SalesHeader[i], BatchCode);

        // [WHEN] the batch-post job runs
        TestLibrary.RunJob(Job, Job."Doc Type"::Sales, BatchCode);

        // [THEN] all three are posted through Sales-Post and logged by external document number
        TestLibrary.AssertJobCompleted(Job, 3, 0);
        Assert.AreEqual(3, TestLibrary.CountResults(BatchCode), 'One result per invoice');
        for i := 1 to ArrayLen(SalesHeader) do begin
            TestLibrary.AssertResult(BatchCode, SalesHeader[i]."External Document No.", true);
            AssertPostedOnce(SalesHeader[i]);
        end;
    end;

    [Test]
    procedure FailingInvoiceIsCapturedAndTheRestStillPost()
    var
        Job: Record "BIF Batch Post Job";
        GoodHeader: array[2] of Record "Sales Header";
        BadHeader: Record "Sales Header";
        CustLedgerEntry: Record "Cust. Ledger Entry";
        BatchCode: Code[20];
    begin
        // [GIVEN] two postable invoices and one for a blocked customer, in one batch
        BatchCode := TestLibrary.NewBatchCode();
        TestLibrary.CreateSalesInvoice(GoodHeader[1], BatchCode);
        TestLibrary.CreateSalesInvoice(BadHeader, BatchCode);
        TestLibrary.CreateSalesInvoice(GoodHeader[2], BatchCode);
        TestLibrary.SetCustomerBlocked(BadHeader."Sell-to Customer No.", true);

        // [WHEN] the batch-post job runs
        TestLibrary.RunJob(Job, Job."Doc Type"::Sales, BatchCode);

        // [THEN] the failure is counted and logged with the BC error, the others post
        TestLibrary.AssertJobCompleted(Job, 2, 1);
        TestLibrary.AssertResult(BatchCode, BadHeader."External Document No.", false);
        TestLibrary.AssertResult(BatchCode, GoodHeader[1]."External Document No.", true);
        TestLibrary.AssertResult(BatchCode, GoodHeader[2]."External Document No.", true);

        // [THEN] the failed invoice is rolled back completely: still open, nothing posted
        TestLibrary.AssertExists(BadHeader, 'The failed invoice stays unposted');
        CustLedgerEntry.SetRange("Customer No.", BadHeader."Sell-to Customer No.");
        Assert.RecordIsEmpty(CustLedgerEntry);
    end;

    [Test]
    procedure RerunPostsOnlyWhatFailedBefore()
    var
        Job: Record "BIF Batch Post Job";
        GoodHeader: Record "Sales Header";
        BadHeader: Record "Sales Header";
        BatchCode: Code[20];
    begin
        // [GIVEN] a batch where one invoice failed on the first run
        BatchCode := TestLibrary.NewBatchCode();
        TestLibrary.CreateSalesInvoice(GoodHeader, BatchCode);
        TestLibrary.CreateSalesInvoice(BadHeader, BatchCode);
        TestLibrary.SetCustomerBlocked(BadHeader."Sell-to Customer No.", true);
        TestLibrary.RunJob(Job, Job."Doc Type"::Sales, BatchCode);
        TestLibrary.AssertJobCompleted(Job, 1, 1);

        // [GIVEN] the cause is fixed
        TestLibrary.SetCustomerBlocked(BadHeader."Sell-to Customer No.", false);

        // [WHEN] the orchestrator reprocesses the batch with a new job
        TestLibrary.RunJob(Job, Job."Doc Type"::Sales, BatchCode);

        // [THEN] only the previously failed invoice is posted; the first one is not posted again
        TestLibrary.AssertJobCompleted(Job, 1, 0);
        AssertPostedOnce(GoodHeader);
        AssertPostedOnce(BadHeader);
    end;

    [Test]
    procedure SecondRunOfAPostedBatchPostsNothing()
    var
        Job: Record "BIF Batch Post Job";
        SalesHeader: Record "Sales Header";
        BatchCode: Code[20];
    begin
        // [GIVEN] a fully posted batch
        BatchCode := TestLibrary.NewBatchCode();
        TestLibrary.CreateSalesInvoice(SalesHeader, BatchCode);
        TestLibrary.RunJob(Job, Job."Doc Type"::Sales, BatchCode);
        TestLibrary.AssertJobCompleted(Job, 1, 0);

        // [WHEN] the same batch is triggered again (for example a retried HTTP call)
        TestLibrary.RunJob(Job, Job."Doc Type"::Sales, BatchCode);

        // [THEN] nothing is posted twice and no new result is logged
        TestLibrary.AssertJobCompleted(Job, 0, 0);
        AssertPostedOnce(SalesHeader);
        Assert.AreEqual(1, TestLibrary.CountResults(BatchCode), 'Results of the batch');
    end;

    local procedure AssertPostedOnce(SalesHeader: Record "Sales Header")
    var
        SalesInvoiceHeader: Record "Sales Invoice Header";
    begin
        SalesInvoiceHeader.SetRange("Pre-Assigned No.", SalesHeader."No.");
        Assert.RecordCount(SalesInvoiceHeader, 1);
        SalesInvoiceHeader.FindFirst();
        Assert.AreEqual(SalesHeader."External Document No.", SalesInvoiceHeader."External Document No.", 'External Document No. of the posted invoice');
    end;
}
