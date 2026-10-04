// End to end for service invoices: imported through custom API pages (no standard
// automation API exists), posted with Service-Post.PostWithLines per document.
codeunit 79006 "BIF Service Post Integration"
{
    Subtype = Test;
    TestPermissions = Disabled;

    var
        Assert: Codeunit "Library Assert";
        TestLibrary: Codeunit "BIF Test Library";

    [Test]
    procedure ServiceInvoiceIsPostedAndLoggedBySourceDocNo()
    var
        Job: Record "BIF Batch Post Job";
        ServiceHeader: Record "Service Header";
        ServiceInvoiceHeader: Record "Service Invoice Header";
        BatchCode: Code[20];
    begin
        // [GIVEN] a service invoice with one line in a batch
        BatchCode := TestLibrary.NewBatchCode();
        TestLibrary.CreateServiceInvoice(ServiceHeader, BatchCode);

        // [WHEN] the service job runs
        TestLibrary.RunJob(Job, Job."Doc Type"::Service, BatchCode);

        // [THEN] the invoice is posted and logged by the source document number it was imported with
        TestLibrary.AssertJobCompleted(Job, 1, 0);
        TestLibrary.AssertResult(BatchCode, ServiceHeader."BIF Source Doc No.", true);
        ServiceInvoiceHeader.SetRange("Pre-Assigned No.", ServiceHeader."No.");
        Assert.RecordCount(ServiceInvoiceHeader, 1);
        TestLibrary.AssertNotExists(ServiceHeader, 'The posted service invoice is deleted');
    end;

    [Test]
    procedure ServiceInvoiceWithoutLinesFailsAndOthersPost()
    var
        Job: Record "BIF Batch Post Job";
        EmptyHeader: Record "Service Header";
        GoodHeader: Record "Service Header";
        BatchCode: Code[20];
    begin
        // [GIVEN] a service invoice without lines and a postable one in the same batch
        BatchCode := TestLibrary.NewBatchCode();
        TestLibrary.CreateServiceInvoiceHeader(EmptyHeader, BatchCode);
        TestLibrary.CreateServiceInvoice(GoodHeader, BatchCode);

        // [WHEN] the service job runs
        TestLibrary.RunJob(Job, Job."Doc Type"::Service, BatchCode);

        // [THEN] the empty one fails with the BC error, the other posts
        TestLibrary.AssertJobCompleted(Job, 1, 1);
        TestLibrary.AssertResult(BatchCode, EmptyHeader."BIF Source Doc No.", false);
        TestLibrary.AssertResult(BatchCode, GoodHeader."BIF Source Doc No.", true);
        TestLibrary.AssertExists(EmptyHeader, 'The failed invoice stays open');
    end;
}
