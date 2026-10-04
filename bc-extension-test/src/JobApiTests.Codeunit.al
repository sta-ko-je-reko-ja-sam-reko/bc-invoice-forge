// Tests of the API pages the orchestrator uses to drive posting: batchPostJobs,
// postResults and the sales/purchase invoice tag pages that stamp the batch code
// onto invoices imported through the standard APIs.
codeunit 79003 "BIF Job API Tests"
{
    Subtype = Test;
    TestPermissions = Disabled;

    var
        Assert: Codeunit "Library Assert";
        TestLibrary: Codeunit "BIF Test Library";

    [Test]
    procedure BatchPostJobApiInsertsPendingJob()
    var
        Job: Record "BIF Batch Post Job";
        BatchPostJobApi: TestPage "BIF Batch Post Job";
        BatchCode: Code[20];
    begin
        // [GIVEN] a batch code
        BatchCode := TestLibrary.NewBatchCode();

        // [WHEN] a job is posted through the API page with batch code and document kind
        BatchPostJobApi.OpenNew();
        BatchPostJobApi.batchCode.SetValue(BatchCode);
        BatchPostJobApi.docType.SetValue(Format(Job."Doc Type"::Purchase));
        BatchPostJobApi.Close();

        // [THEN] a pending purchase job exists for the batch
        Job.SetRange("Batch Code", BatchCode);
        Assert.RecordCount(Job, 1);
        Job.FindFirst();
        Assert.AreEqual(Job."Doc Type"::Purchase, Job."Doc Type", 'Doc Type');
        Assert.AreEqual(Job.Status::Pending, Job.Status, 'Status');
        Assert.AreNotEqual(0DT, Job."Created At", 'Created At');
    end;

    [Test]
    procedure BatchPostJobApiProtectsServerManagedFields()
    var
        BatchPostJobApi: TestPage "BIF Batch Post Job";
    begin
        // [WHEN] the job API page is opened for a new job
        BatchPostJobApi.OpenNew();

        // [THEN] status, counters and timestamps cannot be set by the client
        Assert.IsTrue(BatchPostJobApi.batchCode.Editable(), 'batchCode is writable');
        Assert.IsTrue(BatchPostJobApi.docType.Editable(), 'docType is writable');
        Assert.IsFalse(BatchPostJobApi.status.Editable(), 'status is read-only');
        Assert.IsFalse(BatchPostJobApi.postedCount.Editable(), 'postedCount is read-only');
        Assert.IsFalse(BatchPostJobApi.failedCount.Editable(), 'failedCount is read-only');
        Assert.IsFalse(BatchPostJobApi.createdAt.Editable(), 'createdAt is read-only');
        BatchPostJobApi.Close();
    end;

    [Test]
    procedure PostResultApiExposesResultsReadOnly()
    var
        PostResult: Record "BIF Post Result";
        PostLog: Codeunit "BIF Post Log";
        PostResultApi: TestPage "BIF Post Result";
        BatchCode: Code[20];
        SourceDocNo: Code[35];
    begin
        // [GIVEN] a logged failure
        BatchCode := TestLibrary.NewBatchCode();
        SourceDocNo := TestLibrary.NewSourceDocNo();
        PostLog.Log(BatchCode, SourceDocNo, false, 'Some BC error.');
        PostResult.SetRange("Batch Code", BatchCode);
        PostResult.FindFirst();

        // [WHEN] the result API page is read
        PostResultApi.OpenView();
        Assert.IsTrue(PostResultApi.GoToRecord(PostResult), 'The result is listed');

        // [THEN] it shows the result and cannot be edited
        Assert.AreEqual(BatchCode, PostResultApi.batchCode.Value(), 'batchCode');
        Assert.AreEqual(SourceDocNo, PostResultApi.sourceDocumentNo.Value(), 'sourceDocumentNo');
        Assert.AreEqual('Some BC error.', PostResultApi.errorMessage.Value(), 'errorMessage');
        Assert.IsFalse(PostResultApi.Editable(), 'The postResults API is read-only');
        PostResultApi.Close();
    end;

    [Test]
    procedure SalesInvoiceTagApiStampsBatchCode()
    var
        SalesHeader: Record "Sales Header";
        SalesInvoiceTagApi: TestPage "BIF Sales Invoice Tag";
        BatchCode: Code[20];
    begin
        // [GIVEN] an imported sales invoice without a batch code
        TestLibrary.CreateSalesInvoice(SalesHeader, '');
        BatchCode := TestLibrary.NewBatchCode();

        // [WHEN] the orchestrator patches the batch code through the tag API
        SalesInvoiceTagApi.OpenEdit();
        Assert.IsTrue(SalesInvoiceTagApi.GoToRecord(SalesHeader), 'The invoice is listed');
        SalesInvoiceTagApi.batchCode.SetValue(BatchCode);
        SalesInvoiceTagApi.Close();

        // [THEN] the invoice carries the batch code
        SalesHeader.Get(SalesHeader."Document Type", SalesHeader."No.");
        Assert.AreEqual(BatchCode, SalesHeader."BIF Batch Code", 'BIF Batch Code');
    end;

    [Test]
    procedure SalesInvoiceTagApiListsInvoicesOnly()
    var
        SalesOrder: Record "Sales Header";
        SalesInvoiceTagApi: TestPage "BIF Sales Invoice Tag";
    begin
        // [GIVEN] a sales order
        TestLibrary.CreateSalesDocument(SalesOrder, SalesOrder."Document Type"::Order, '');

        // [WHEN] the tag API page is read
        SalesInvoiceTagApi.OpenView();

        // [THEN] the order is not exposed
        Assert.IsFalse(SalesInvoiceTagApi.GoToRecord(SalesOrder), 'Orders are not listed');
        SalesInvoiceTagApi.Close();
    end;

    [Test]
    procedure SalesInvoiceTagApiCannotCreateDocuments()
    var
        SalesInvoiceTagApi: TestPage "BIF Sales Invoice Tag";
    begin
        // [WHEN] a client tries to insert through the tag API
        asserterror SalesInvoiceTagApi.OpenNew();

        // [THEN] it is refused: the page only patches imported invoices
        Assert.AreNotEqual('', GetLastErrorText(), 'Inserting is not allowed');
    end;

    [Test]
    procedure PurchaseInvoiceTagApiStampsBatchCode()
    var
        PurchaseHeader: Record "Purchase Header";
        PurchInvoiceTagApi: TestPage "BIF Purch Invoice Tag";
        BatchCode: Code[20];
    begin
        // [GIVEN] an imported purchase invoice without a batch code
        TestLibrary.CreatePurchaseInvoice(PurchaseHeader, '', '');
        BatchCode := TestLibrary.NewBatchCode();

        // [WHEN] the orchestrator patches the batch code through the tag API
        PurchInvoiceTagApi.OpenEdit();
        Assert.IsTrue(PurchInvoiceTagApi.GoToRecord(PurchaseHeader), 'The invoice is listed');
        PurchInvoiceTagApi.batchCode.SetValue(BatchCode);
        PurchInvoiceTagApi.Close();

        // [THEN] the invoice carries the batch code
        PurchaseHeader.Get(PurchaseHeader."Document Type", PurchaseHeader."No.");
        Assert.AreEqual(BatchCode, PurchaseHeader."BIF Batch Code", 'BIF Batch Code');
    end;

    [Test]
    procedure PurchaseInvoiceTagApiListsInvoicesOnly()
    var
        PurchaseOrder: Record "Purchase Header";
        PurchInvoiceTagApi: TestPage "BIF Purch Invoice Tag";
    begin
        // [GIVEN] a purchase order
        TestLibrary.CreatePurchaseOrder(PurchaseOrder, '');

        // [WHEN] the tag API page is read
        PurchInvoiceTagApi.OpenView();

        // [THEN] the order is not exposed
        Assert.IsFalse(PurchInvoiceTagApi.GoToRecord(PurchaseOrder), 'Orders are not listed');
        PurchInvoiceTagApi.Close();
    end;

    [Test]
    procedure TaggedInvoiceIsPostedByTheNextJob()
    var
        Job: Record "BIF Batch Post Job";
        SalesHeader: Record "Sales Header";
        SalesInvoiceTagApi: TestPage "BIF Sales Invoice Tag";
        BatchCode: Code[20];
    begin
        // [GIVEN] an invoice imported without a batch code and then tagged through the API
        TestLibrary.CreateSalesInvoice(SalesHeader, '');
        BatchCode := TestLibrary.NewBatchCode();
        SalesInvoiceTagApi.OpenEdit();
        SalesInvoiceTagApi.GoToRecord(SalesHeader);
        SalesInvoiceTagApi.batchCode.SetValue(BatchCode);
        SalesInvoiceTagApi.Close();

        // [WHEN] the batch-post job runs for that batch
        TestLibrary.RunJob(Job, Job."Doc Type"::Sales, BatchCode);

        // [THEN] the tagged invoice is posted
        TestLibrary.AssertJobCompleted(Job, 1, 0);
        TestLibrary.AssertResult(BatchCode, SalesHeader."External Document No.", true);
    end;
}
