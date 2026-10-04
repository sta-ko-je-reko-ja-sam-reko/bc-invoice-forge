// Tests of the custom import API pages (documents without a usable standard API):
// header defaults set on new records, batch code and source document number taken
// inline, and line numbers assigned on insert. Ends with an import-then-post run.
codeunit 79008 "BIF Import API Tests"
{
    Subtype = Test;
    TestPermissions = Disabled;

    var
        Assert: Codeunit "Library Assert";
        LibraryInventory: Codeunit "Library - Inventory";
        LibraryPurchase: Codeunit "Library - Purchase";
        LibrarySales: Codeunit "Library - Sales";
        TestLibrary: Codeunit "BIF Test Library";

    [Test]
    procedure ServiceInvoiceApiCreatesInvoiceHeader()
    var
        ServiceHeader: Record "Service Header";
        ServiceInvoiceApi: TestPage "BIF Service Invoice";
        CustomerNo: Code[20];
        BatchCode: Code[20];
        SourceDocNo: Code[35];
    begin
        // [GIVEN] a customer, a batch code and a source document number
        TestLibrary.InitializeService();
        CustomerNo := LibrarySales.CreateCustomerNo();
        BatchCode := TestLibrary.NewBatchCode();
        SourceDocNo := TestLibrary.NewSourceDocNo();

        // [WHEN] a service invoice header is posted to the API page
        ServiceInvoiceApi.OpenNew();
        ServiceInvoiceApi.customerNumber.SetValue(CustomerNo);
        ServiceInvoiceApi.externalDocumentNo.SetValue(SourceDocNo);
        ServiceInvoiceApi.batchCode.SetValue(BatchCode);
        ServiceInvoiceApi.Close();

        // [THEN] a service invoice is created with a number from the series and the inline tags
        ServiceHeader.SetRange("BIF Batch Code", BatchCode);
        Assert.RecordCount(ServiceHeader, 1);
        ServiceHeader.FindFirst();
        Assert.AreEqual(ServiceHeader."Document Type"::Invoice, ServiceHeader."Document Type", 'Document Type');
        Assert.AreNotEqual('', ServiceHeader."No.", 'No. is assigned from the number series');
        Assert.AreEqual(CustomerNo, ServiceHeader."Customer No.", 'Customer No.');
        Assert.AreEqual(SourceDocNo, ServiceHeader."BIF Source Doc No.", 'BIF Source Doc No.');
    end;

    [Test]
    procedure ServiceInvoiceLineApiNumbersLines()
    var
        ServiceHeader: Record "Service Header";
        ServiceLine: Record "Service Line";
        ItemNo: Code[20];
    begin
        // [GIVEN] an imported service invoice header without lines
        TestLibrary.CreateServiceInvoiceHeader(ServiceHeader, TestLibrary.NewBatchCode());
        ItemNo := LibraryInventory.CreateItemNo();

        // [WHEN] two lines are posted to the line API page without line numbers
        InsertServiceLineThroughApi(ServiceHeader."No.", ItemNo, 2);
        InsertServiceLineThroughApi(ServiceHeader."No.", ItemNo, 3);

        // [THEN] they become invoice lines 10000 and 20000 of that invoice
        ServiceLine.SetRange("Document Type", ServiceLine."Document Type"::Invoice);
        ServiceLine.SetRange("Document No.", ServiceHeader."No.");
        Assert.RecordCount(ServiceLine, 2);
        ServiceLine.FindFirst();
        Assert.AreEqual(10000, ServiceLine."Line No.", 'First line no.');
        Assert.AreEqual(2, ServiceLine.Quantity, 'First line quantity');
        ServiceLine.FindLast();
        Assert.AreEqual(20000, ServiceLine."Line No.", 'Second line no.');
        Assert.AreEqual(3, ServiceLine.Quantity, 'Second line quantity');
    end;

    [Test]
    procedure PurchaseOrderApiCreatesOrderHeader()
    var
        PurchaseHeader: Record "Purchase Header";
        PurchaseOrderApi: TestPage "BIF Purchase Order";
        VendorNo: Code[20];
        BatchCode: Code[20];
        SourceDocNo: Code[35];
    begin
        // [GIVEN] a vendor, a batch code and a source document number
        VendorNo := LibraryPurchase.CreateVendorNo();
        BatchCode := TestLibrary.NewBatchCode();
        SourceDocNo := TestLibrary.NewSourceDocNo();

        // [WHEN] a purchase order header is posted to the API page
        PurchaseOrderApi.OpenNew();
        PurchaseOrderApi.vendorNumber.SetValue(VendorNo);
        PurchaseOrderApi.externalDocumentNo.SetValue(SourceDocNo);
        PurchaseOrderApi.batchCode.SetValue(BatchCode);
        PurchaseOrderApi.Close();

        // [THEN] a purchase order is created with the inline tags
        PurchaseHeader.SetRange("BIF Batch Code", BatchCode);
        Assert.RecordCount(PurchaseHeader, 1);
        PurchaseHeader.FindFirst();
        Assert.AreEqual(PurchaseHeader."Document Type"::Order, PurchaseHeader."Document Type", 'Document Type');
        Assert.AreNotEqual('', PurchaseHeader."No.", 'No. is assigned from the number series');
        Assert.AreEqual(VendorNo, PurchaseHeader."Buy-from Vendor No.", 'Buy-from Vendor No.');
        Assert.AreEqual(SourceDocNo, PurchaseHeader."BIF Source Doc No.", 'BIF Source Doc No.');
    end;

    [Test]
    procedure PurchaseOrderLineApiNumbersLines()
    var
        PurchaseHeader: Record "Purchase Header";
        PurchaseLine: Record "Purchase Line";
        ItemNo: Code[20];
    begin
        // [GIVEN] a purchase order header without lines
        LibraryPurchase.CreatePurchHeader(PurchaseHeader, PurchaseHeader."Document Type"::Order, LibraryPurchase.CreateVendorNo());
        ItemNo := LibraryInventory.CreateItemNo();

        // [WHEN] two lines are posted to the line API page without line numbers
        InsertPurchaseLineThroughApi(PurchaseHeader."No.", ItemNo, 4, 12.5);
        InsertPurchaseLineThroughApi(PurchaseHeader."No.", ItemNo, 6, 7.25);

        // [THEN] they become order lines 10000 and 20000 with quantity and cost
        PurchaseLine.SetRange("Document Type", PurchaseLine."Document Type"::Order);
        PurchaseLine.SetRange("Document No.", PurchaseHeader."No.");
        Assert.RecordCount(PurchaseLine, 2);
        PurchaseLine.FindFirst();
        Assert.AreEqual(10000, PurchaseLine."Line No.", 'First line no.');
        Assert.AreEqual(4, PurchaseLine.Quantity, 'First line quantity');
        Assert.AreEqual(12.5, PurchaseLine."Direct Unit Cost", 'First line cost');
        PurchaseLine.FindLast();
        Assert.AreEqual(20000, PurchaseLine."Line No.", 'Second line no.');
    end;

    [Test]
    procedure PurchaseOrderLineApiContinuesAfterExistingLines()
    var
        PurchaseHeader: Record "Purchase Header";
        PurchaseLine: Record "Purchase Line";
        LastLineNo: Integer;
    begin
        // [GIVEN] a purchase order that already has a line
        LibraryPurchase.CreatePurchaseOrder(PurchaseHeader);
        PurchaseLine.SetRange("Document Type", PurchaseHeader."Document Type");
        PurchaseLine.SetRange("Document No.", PurchaseHeader."No.");
        PurchaseLine.FindLast();
        LastLineNo := PurchaseLine."Line No.";

        // [WHEN] a line is posted to the line API page
        InsertPurchaseLineThroughApi(PurchaseHeader."No.", LibraryInventory.CreateItemNo(), 1, 1);

        // [THEN] it is numbered after the existing line
        PurchaseLine.FindLast();
        Assert.AreEqual(LastLineNo + 10000, PurchaseLine."Line No.", 'Line no. after the existing line');
    end;

    [Test]
    procedure TransferOrderLineApiNumbersLines()
    var
        TransferHeader: Record "Transfer Header";
        TransferLine: Record "Transfer Line";
        ItemNo: Code[20];
    begin
        // [GIVEN] a transfer order header without lines
        TestLibrary.CreateTransferOrderHeader(TransferHeader, TestLibrary.NewBatchCode());
        ItemNo := LibraryInventory.CreateItemNo();

        // [WHEN] two lines are posted to the line API page without line numbers
        InsertTransferLineThroughApi(TransferHeader."No.", ItemNo, 1);
        InsertTransferLineThroughApi(TransferHeader."No.", ItemNo, 2);

        // [THEN] they become lines 10000 and 20000 of that transfer order
        TransferLine.SetRange("Document No.", TransferHeader."No.");
        Assert.RecordCount(TransferLine, 2);
        TransferLine.FindFirst();
        Assert.AreEqual(10000, TransferLine."Line No.", 'First line no.');
        TransferLine.FindLast();
        Assert.AreEqual(20000, TransferLine."Line No.", 'Second line no.');
        Assert.AreEqual(2, TransferLine.Quantity, 'Second line quantity');
    end;

    [Test]
    procedure PurchaseOrderImportedThroughApiIsPosted()
    var
        Job: Record "BIF Batch Post Job";
        PurchaseHeader: Record "Purchase Header";
        PurchInvHeader: Record "Purch. Inv. Header";
        PurchaseOrderApi: TestPage "BIF Purchase Order";
        BatchCode: Code[20];
        SourceDocNo: Code[35];
    begin
        // [GIVEN] a purchase order imported through the header and line API pages
        BatchCode := TestLibrary.NewBatchCode();
        SourceDocNo := TestLibrary.NewSourceDocNo();
        PurchaseOrderApi.OpenNew();
        PurchaseOrderApi.vendorNumber.SetValue(LibraryPurchase.CreateVendorNo());
        PurchaseOrderApi.externalDocumentNo.SetValue(SourceDocNo);
        PurchaseOrderApi.batchCode.SetValue(BatchCode);
        PurchaseOrderApi.Close();
        PurchaseHeader.SetRange("BIF Batch Code", BatchCode);
        PurchaseHeader.FindFirst();
        // The purchaseOrders API has no vendor invoice number field; invoicing needs one
        // when Purchases & Payables Setup has Ext. Doc. No. Mandatory (the default).
        PurchaseHeader.Validate("Vendor Invoice No.", SourceDocNo);
        PurchaseHeader.Modify(true);
        InsertPurchaseLineThroughApi(PurchaseHeader."No.", LibraryInventory.CreateItemNo(), 2, 10);

        // [WHEN] the purchase order job runs
        TestLibrary.RunJob(Job, Job."Doc Type"::PurchaseOrder, BatchCode);

        // [THEN] the imported order is received and invoiced and logged by its source document number
        TestLibrary.AssertJobCompleted(Job, 1, 0);
        TestLibrary.AssertResult(BatchCode, SourceDocNo, true);
        PurchInvHeader.SetRange("Order No.", PurchaseHeader."No.");
        Assert.RecordCount(PurchInvHeader, 1);
    end;

    local procedure InsertServiceLineThroughApi(DocumentNo: Code[20]; ItemNo: Code[20]; Quantity: Decimal)
    var
        ServiceLine: Record "Service Line";
        ServiceInvoiceLineApi: TestPage "BIF Service Invoice Line";
    begin
        ServiceInvoiceLineApi.OpenNew();
        ServiceInvoiceLineApi.documentNo.SetValue(DocumentNo);
        ServiceInvoiceLineApi.lineType.SetValue(Format(ServiceLine.Type::Item));
        ServiceInvoiceLineApi.number.SetValue(ItemNo);
        ServiceInvoiceLineApi.quantity.SetValue(Quantity);
        ServiceInvoiceLineApi.Close();
    end;

    local procedure InsertPurchaseLineThroughApi(DocumentNo: Code[20]; ItemNo: Code[20]; Quantity: Decimal; DirectUnitCost: Decimal)
    var
        PurchaseLine: Record "Purchase Line";
        PurchaseOrderLineApi: TestPage "BIF Purchase Order Line";
    begin
        PurchaseOrderLineApi.OpenNew();
        PurchaseOrderLineApi.documentNo.SetValue(DocumentNo);
        PurchaseOrderLineApi.lineType.SetValue(Format(PurchaseLine.Type::Item));
        PurchaseOrderLineApi.number.SetValue(ItemNo);
        PurchaseOrderLineApi.quantity.SetValue(Quantity);
        PurchaseOrderLineApi.directUnitCost.SetValue(DirectUnitCost);
        PurchaseOrderLineApi.Close();
    end;

    local procedure InsertTransferLineThroughApi(DocumentNo: Code[20]; ItemNo: Code[20]; Quantity: Decimal)
    var
        TransferOrderLineApi: TestPage "BIF Transfer Order Line";
    begin
        TransferOrderLineApi.OpenNew();
        TransferOrderLineApi.documentNo.SetValue(DocumentNo);
        TransferOrderLineApi.itemNo.SetValue(ItemNo);
        TransferOrderLineApi.quantity.SetValue(Quantity);
        TransferOrderLineApi.Close();
    end;
}
