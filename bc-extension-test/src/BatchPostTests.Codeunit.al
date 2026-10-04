// Tests of the batch-post job and its dispatcher: job defaults, enum-to-poster resolution
// for every document kind, the background runner entry point, and the batch/kind filter
// that decides which documents a job may touch.
codeunit 79002 "BIF Batch Post Tests"
{
    Subtype = Test;
    TestPermissions = Disabled;

    var
        Assert: Codeunit "Library Assert";
        TestLibrary: Codeunit "BIF Test Library";

    [Test]
    procedure NewJobIsPendingAndStampsCreatedAt()
    var
        Job: Record "BIF Batch Post Job";
    begin
        // [WHEN] a job is inserted as the batchPostJobs API does
        TestLibrary.CreateJob(Job, Job."Doc Type"::Sales, TestLibrary.NewBatchCode());

        // [THEN] it waits as Pending with no counts and a creation time
        Assert.AreEqual(Job.Status::Pending, Job.Status, 'Status');
        Assert.AreEqual(0, Job."Posted Count", 'Posted Count');
        Assert.AreEqual(0, Job."Failed Count", 'Failed Count');
        Assert.AreNotEqual(0DT, Job."Created At", 'Created At');
        Assert.AreNotEqual(0, Job."Entry No.", 'Entry No. is assigned');
    end;

    [Test]
    procedure EveryDocTypeResolvesToAPoster()
    var
        Job: Record "BIF Batch Post Job";
        DocType: Enum "BIF Doc Type";
        Ordinal: Integer;
        BatchCode: Code[20];
    begin
        // [GIVEN] a batch without documents
        BatchCode := TestLibrary.NewBatchCode();

        // [WHEN] a job runs for every document kind of the enum
        foreach Ordinal in Enum::"BIF Doc Type".Ordinals() do begin
            DocType := Enum::"BIF Doc Type".FromInteger(Ordinal);
            TestLibrary.RunJob(Job, DocType, BatchCode);

            // [THEN] each kind dispatches to its poster and completes with nothing posted
            TestLibrary.AssertJobCompleted(Job, 0, 0);
        end;
        Assert.AreEqual(0, TestLibrary.CountResults(BatchCode), 'An empty batch logs no results');
    end;

    [Test]
    procedure RunnerCodeunitRunsTheJob()
    var
        Job: Record "BIF Batch Post Job";
        SalesHeader: Record "Sales Header";
        BatchCode: Code[20];
    begin
        // [GIVEN] a pending sales job with one invoice
        BatchCode := TestLibrary.NewBatchCode();
        TestLibrary.CreateSalesInvoice(SalesHeader, BatchCode);
        TestLibrary.CreateJob(Job, Job."Doc Type"::Sales, BatchCode);

        // [WHEN] the background-session entry point runs it
        Codeunit.Run(Codeunit::"BIF Batch Post Runner", Job);

        // [THEN] the job is completed and the invoice is posted
        Job.Get(Job."Entry No.");
        TestLibrary.AssertJobCompleted(Job, 1, 0);
        TestLibrary.AssertResult(BatchCode, SalesHeader."External Document No.", true);
    end;

    [Test]
    procedure JobOnlyPostsDocumentsOfItsKind()
    var
        Job: Record "BIF Batch Post Job";
        SalesHeader: Record "Sales Header";
        BatchCode: Code[20];
    begin
        // [GIVEN] a sales invoice in a batch
        BatchCode := TestLibrary.NewBatchCode();
        TestLibrary.CreateSalesInvoice(SalesHeader, BatchCode);

        // [WHEN] a purchase job runs for the same batch code
        TestLibrary.RunJob(Job, Job."Doc Type"::Purchase, BatchCode);

        // [THEN] the sales invoice is left alone
        TestLibrary.AssertJobCompleted(Job, 0, 0);
        TestLibrary.AssertExists(SalesHeader, 'The sales invoice is still unposted');
    end;

    [Test]
    procedure JobOnlyPostsDocumentsOfItsBatch()
    var
        Job: Record "BIF Batch Post Job";
        SalesHeader: Record "Sales Header";
        OtherSalesHeader: Record "Sales Header";
        BatchCode: Code[20];
    begin
        // [GIVEN] one sales invoice in the job's batch and one in another batch
        BatchCode := TestLibrary.NewBatchCode();
        TestLibrary.CreateSalesInvoice(SalesHeader, BatchCode);
        TestLibrary.CreateSalesInvoice(OtherSalesHeader, TestLibrary.NewBatchCode());

        // [WHEN] the job runs
        TestLibrary.RunJob(Job, Job."Doc Type"::Sales, BatchCode);

        // [THEN] only the invoice of its batch is posted
        TestLibrary.AssertJobCompleted(Job, 1, 0);
        TestLibrary.AssertNotExists(SalesHeader, 'The invoice of the batch is posted');
        TestLibrary.AssertExists(OtherSalesHeader, 'The invoice of the other batch is untouched');
    end;

    [Test]
    procedure JobWithoutBatchCodeFailsAndPostsNothing()
    var
        Job: Record "BIF Batch Post Job";
        SalesHeader: Record "Sales Header";
    begin
        // [GIVEN] a sales invoice without a batch code, like any invoice entered by hand
        TestLibrary.CreateSalesInvoice(SalesHeader, '');

        // [WHEN] a job runs with a blank batch code
        TestLibrary.RunJob(Job, Job."Doc Type"::Sales, '');

        // [THEN] the job fails instead of posting every untagged invoice of the company
        Assert.AreEqual(Job.Status::Failed, Job.Status, 'Status');
        Assert.AreNotEqual('', Job."Error Message", 'The job says why it failed');
        Assert.AreEqual(0, Job."Posted Count", 'Posted Count');
        Assert.AreEqual(0, Job."Failed Count", 'Failed Count');
        TestLibrary.AssertExists(SalesHeader, 'The untagged invoice is untouched');
    end;

    [Test]
    procedure SalesJobSkipsOtherSalesDocumentTypes()
    var
        Job: Record "BIF Batch Post Job";
        SalesHeader: Record "Sales Header";
        BatchCode: Code[20];
    begin
        // [GIVEN] a sales order tagged with the batch code
        BatchCode := TestLibrary.NewBatchCode();
        TestLibrary.CreateSalesDocument(SalesHeader, SalesHeader."Document Type"::Order, BatchCode);

        // [WHEN] a sales (invoice) job runs
        TestLibrary.RunJob(Job, Job."Doc Type"::Sales, BatchCode);

        // [THEN] the order is not posted: the sales poster handles invoices only
        TestLibrary.AssertJobCompleted(Job, 0, 0);
        TestLibrary.AssertExists(SalesHeader, 'The sales order is untouched');
    end;

    [Test]
    procedure PurchaseJobsSplitInvoicesFromOrders()
    var
        Job: Record "BIF Batch Post Job";
        InvoiceHeader: Record "Purchase Header";
        OrderHeader: Record "Purchase Header";
        BatchCode: Code[20];
    begin
        // [GIVEN] a purchase invoice and a purchase order in the same batch
        BatchCode := TestLibrary.NewBatchCode();
        TestLibrary.CreatePurchaseInvoice(InvoiceHeader, BatchCode, '');
        TestLibrary.CreatePurchaseOrder(OrderHeader, BatchCode);

        // [WHEN] a purchase (invoice) job runs
        TestLibrary.RunJob(Job, Job."Doc Type"::Purchase, BatchCode);

        // [THEN] only the invoice is posted
        TestLibrary.AssertJobCompleted(Job, 1, 0);
        TestLibrary.AssertNotExists(InvoiceHeader, 'The invoice is posted');
        TestLibrary.AssertExists(OrderHeader, 'The order waits for a purchase order job');

        // [WHEN] a purchase order job runs
        TestLibrary.RunJob(Job, Job."Doc Type"::PurchaseOrder, BatchCode);

        // [THEN] the order is posted too
        TestLibrary.AssertJobCompleted(Job, 1, 0);
        TestLibrary.AssertNotExists(OrderHeader, 'The order is posted');
    end;
}
