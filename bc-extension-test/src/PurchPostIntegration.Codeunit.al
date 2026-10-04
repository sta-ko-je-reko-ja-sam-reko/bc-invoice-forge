// End to end for purchases: invoices posted with Purch.-Post and logged by vendor
// invoice number, BC's duplicate vendor invoice check as the safety net, and purchase
// orders received and invoiced in one go.
codeunit 79005 "BIF Purch Post Integration"
{
    Subtype = Test;
    TestPermissions = Disabled;

    var
        Assert: Codeunit "Library Assert";
        TestLibrary: Codeunit "BIF Test Library";

    [Test]
    procedure PurchaseInvoicesPostAndLogVendorInvoiceNo()
    var
        Job: Record "BIF Batch Post Job";
        PurchaseHeader: array[2] of Record "Purchase Header";
        PurchInvHeader: Record "Purch. Inv. Header";
        BatchCode: Code[20];
        i: Integer;
    begin
        // [GIVEN] two purchase invoices in one batch
        BatchCode := TestLibrary.NewBatchCode();
        for i := 1 to ArrayLen(PurchaseHeader) do
            TestLibrary.CreatePurchaseInvoice(PurchaseHeader[i], BatchCode, '');

        // [WHEN] the purchase job runs
        TestLibrary.RunJob(Job, Job."Doc Type"::Purchase, BatchCode);

        // [THEN] both are posted and their results are keyed by Vendor Invoice No.
        TestLibrary.AssertJobCompleted(Job, 2, 0);
        for i := 1 to ArrayLen(PurchaseHeader) do begin
            TestLibrary.AssertResult(BatchCode, PurchaseHeader[i]."Vendor Invoice No.", true);
            PurchInvHeader.SetRange("Pre-Assigned No.", PurchaseHeader[i]."No.");
            Assert.RecordCount(PurchInvHeader, 1);
            PurchInvHeader.FindFirst();
            TestLibrary.AssertPostedDocNo(BatchCode, PurchaseHeader[i]."Vendor Invoice No.", PurchInvHeader."No.");
        end;
    end;

    [Test]
    procedure DuplicateVendorInvoiceNoIsRejectedByBC()
    var
        Job: Record "BIF Batch Post Job";
        FirstHeader: Record "Purchase Header";
        DuplicateHeader: Record "Purchase Header";
        PostResult: Record "BIF Post Result";
        BatchCode: Code[20];
    begin
        // [GIVEN] two invoices of the same vendor carrying the same vendor invoice number
        BatchCode := TestLibrary.NewBatchCode();
        TestLibrary.CreatePurchaseInvoice(FirstHeader, BatchCode, '');
        TestLibrary.CreatePurchaseInvoice(DuplicateHeader, BatchCode, FirstHeader."Buy-from Vendor No.");
        DuplicateHeader.Validate("Vendor Invoice No.", FirstHeader."Vendor Invoice No.");
        DuplicateHeader.Modify(true);

        // [WHEN] the purchase job runs
        TestLibrary.RunJob(Job, Job."Doc Type"::Purchase, BatchCode);

        // [THEN] one posts, the duplicate fails in BC and is logged as a failure for the same key
        TestLibrary.AssertJobCompleted(Job, 1, 1);
        PostResult.SetRange("Batch Code", BatchCode);
        PostResult.SetRange("Source Document No.", FirstHeader."Vendor Invoice No.");
        Assert.RecordCount(PostResult, 2);
        PostResult.SetRange(Success, false);
        Assert.RecordCount(PostResult, 1);
        PostResult.FindFirst();
        Assert.AreNotEqual('', PostResult."Error Message", 'The duplicate carries the BC error');
    end;

    [Test]
    procedure PurchaseOrderIsReceivedAndInvoiced()
    var
        Job: Record "BIF Batch Post Job";
        PurchaseHeader: Record "Purchase Header";
        PurchRcptHeader: Record "Purch. Rcpt. Header";
        PurchInvHeader: Record "Purch. Inv. Header";
        BatchCode: Code[20];
    begin
        // [GIVEN] a purchase order in a batch
        BatchCode := TestLibrary.NewBatchCode();
        TestLibrary.CreatePurchaseOrder(PurchaseHeader, BatchCode);

        // [WHEN] the purchase order job runs
        TestLibrary.RunJob(Job, Job."Doc Type"::PurchaseOrder, BatchCode);

        // [THEN] the order is received and invoiced, and logged by its source document number
        TestLibrary.AssertJobCompleted(Job, 1, 0);
        TestLibrary.AssertResult(BatchCode, PurchaseHeader."BIF Source Doc No.", true);
        PurchRcptHeader.SetRange("Order No.", PurchaseHeader."No.");
        Assert.RecordCount(PurchRcptHeader, 1);
        PurchInvHeader.SetRange("Order No.", PurchaseHeader."No.");
        Assert.RecordCount(PurchInvHeader, 1);
        PurchInvHeader.FindFirst();
        TestLibrary.AssertPostedDocNo(BatchCode, PurchaseHeader."BIF Source Doc No.", PurchInvHeader."No.");
        TestLibrary.AssertNotExists(PurchaseHeader, 'A fully received and invoiced order is deleted');
    end;

    [Test]
    procedure FailedPurchaseOrderStaysOpenWithoutReceipt()
    var
        Job: Record "BIF Batch Post Job";
        PurchaseHeader: Record "Purchase Header";
        PurchRcptHeader: Record "Purch. Rcpt. Header";
        BatchCode: Code[20];
    begin
        // [GIVEN] a purchase order of a blocked vendor
        BatchCode := TestLibrary.NewBatchCode();
        TestLibrary.CreatePurchaseOrder(PurchaseHeader, BatchCode);
        TestLibrary.SetVendorBlocked(PurchaseHeader."Buy-from Vendor No.", true);

        // [WHEN] the purchase order job runs
        TestLibrary.RunJob(Job, Job."Doc Type"::PurchaseOrder, BatchCode);

        // [THEN] it fails as a whole: no receipt is left behind
        TestLibrary.AssertJobCompleted(Job, 0, 1);
        TestLibrary.AssertResult(BatchCode, PurchaseHeader."BIF Source Doc No.", false);
        TestLibrary.AssertExists(PurchaseHeader, 'The order stays open');
        PurchRcptHeader.SetRange("Order No.", PurchaseHeader."No.");
        Assert.RecordIsEmpty(PurchRcptHeader);
    end;
}
