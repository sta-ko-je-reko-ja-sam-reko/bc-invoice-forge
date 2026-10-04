// End to end for the order kinds: transfer orders shipped and received, assembly orders
// posted with Assembly-Post, released production orders finished.
codeunit 79007 "BIF Order Post Integration"
{
    Subtype = Test;
    TestPermissions = Disabled;

    var
        Assert: Codeunit "Library Assert";
        LibraryInventory: Codeunit "Library - Inventory";
        LibraryManufacturing: Codeunit "Library - Manufacturing";
        TestLibrary: Codeunit "BIF Test Library";

    [Test]
    procedure TransferOrderIsShippedAndReceived()
    var
        Job: Record "BIF Batch Post Job";
        TransferHeader: Record "Transfer Header";
        TransferShipmentHeader: Record "Transfer Shipment Header";
        TransferReceiptHeader: Record "Transfer Receipt Header";
        BatchCode: Code[20];
    begin
        // [GIVEN] a transfer order with stock at the from-location
        BatchCode := TestLibrary.NewBatchCode();
        TestLibrary.CreateTransferOrder(TransferHeader, BatchCode);

        // [WHEN] the transfer job runs
        TestLibrary.RunJob(Job, Job."Doc Type"::TransferOrder, BatchCode);

        // [THEN] it is shipped and received in one go
        TestLibrary.AssertJobCompleted(Job, 1, 0);
        TestLibrary.AssertResult(BatchCode, TransferHeader."BIF Source Doc No.", true);
        TransferShipmentHeader.SetRange("Transfer Order No.", TransferHeader."No.");
        Assert.RecordCount(TransferShipmentHeader, 1);
        TransferReceiptHeader.SetRange("Transfer Order No.", TransferHeader."No.");
        Assert.RecordCount(TransferReceiptHeader, 1);
        TransferReceiptHeader.FindFirst();
        TestLibrary.AssertPostedDocNo(BatchCode, TransferHeader."BIF Source Doc No.", TransferReceiptHeader."No.");
        TestLibrary.AssertNotExists(TransferHeader, 'A fully received transfer order is deleted');
    end;

    [Test]
    procedure TransferOrderWithoutLinesFails()
    var
        Job: Record "BIF Batch Post Job";
        TransferHeader: Record "Transfer Header";
        BatchCode: Code[20];
    begin
        // [GIVEN] a transfer order without lines
        BatchCode := TestLibrary.NewBatchCode();
        TestLibrary.CreateTransferOrderHeader(TransferHeader, BatchCode);

        // [WHEN] the transfer job runs
        TestLibrary.RunJob(Job, Job."Doc Type"::TransferOrder, BatchCode);

        // [THEN] the shipment fails and is logged; the order stays
        TestLibrary.AssertJobCompleted(Job, 0, 1);
        TestLibrary.AssertResult(BatchCode, TransferHeader."BIF Source Doc No.", false);
        TestLibrary.AssertExists(TransferHeader, 'The transfer order stays');
    end;

    [Test]
    procedure TransferWithFailedReceiptIsOnlyReceivedOnRerun()
    var
        Job: Record "BIF Batch Post Job";
        TransferHeader: Record "Transfer Header";
        TransferShipmentHeader: Record "Transfer Shipment Header";
        TransferReceiptHeader: Record "Transfer Receipt Header";
        FailTransferReceipt: Codeunit "BIF Fail Transfer Receipt";
        BatchCode: Code[20];
    begin
        // [GIVEN] a transfer order whose receipt fails on the first run
        BatchCode := TestLibrary.NewBatchCode();
        TestLibrary.CreateTransferOrder(TransferHeader, BatchCode);
        BindSubscription(FailTransferReceipt);

        // [WHEN] the transfer job runs
        TestLibrary.RunJob(Job, Job."Doc Type"::TransferOrder, BatchCode);

        // [THEN] the order is reported failed: shipped, not received
        UnbindSubscription(FailTransferReceipt);
        TestLibrary.AssertJobCompleted(Job, 0, 1);
        TestLibrary.AssertResult(BatchCode, TransferHeader."BIF Source Doc No.", false);
        TransferShipmentHeader.SetRange("Transfer Order No.", TransferHeader."No.");
        Assert.RecordCount(TransferShipmentHeader, 1);
        TransferReceiptHeader.SetRange("Transfer Order No.", TransferHeader."No.");
        Assert.RecordIsEmpty(TransferReceiptHeader);

        // [WHEN] the batch is rerun
        TestLibrary.RunJob(Job, Job."Doc Type"::TransferOrder, BatchCode);

        // [THEN] only the receipt is posted; the order is not shipped a second time
        TestLibrary.AssertJobCompleted(Job, 1, 0);
        Assert.RecordCount(TransferShipmentHeader, 1);
        Assert.RecordCount(TransferReceiptHeader, 1);
        TransferReceiptHeader.FindFirst();
        TestLibrary.AssertPostedDocNo(BatchCode, TransferHeader."BIF Source Doc No.", TransferReceiptHeader."No.");
        TestLibrary.AssertNotExists(TransferHeader, 'A fully received transfer order is deleted');
    end;

    [Test]
    procedure FullyShippedTransferIsOnlyReceived()
    var
        Job: Record "BIF Batch Post Job";
        TransferHeader: Record "Transfer Header";
        TransferShipmentHeader: Record "Transfer Shipment Header";
        TransferReceiptHeader: Record "Transfer Receipt Header";
        BatchCode: Code[20];
    begin
        // [GIVEN] a transfer order that was already shipped in full
        BatchCode := TestLibrary.NewBatchCode();
        TestLibrary.CreateTransferOrder(TransferHeader, BatchCode);
        Codeunit.Run(Codeunit::"TransferOrder-Post Shipment", TransferHeader);

        // [WHEN] the transfer job runs
        TestLibrary.RunJob(Job, Job."Doc Type"::TransferOrder, BatchCode);

        // [THEN] it is received without a second shipment
        TestLibrary.AssertJobCompleted(Job, 1, 0);
        TransferShipmentHeader.SetRange("Transfer Order No.", TransferHeader."No.");
        Assert.RecordCount(TransferShipmentHeader, 1);
        TransferReceiptHeader.SetRange("Transfer Order No.", TransferHeader."No.");
        Assert.RecordCount(TransferReceiptHeader, 1);
    end;

    [Test]
    procedure PartiallyShippedTransferShipsRestAndReceives()
    var
        Job: Record "BIF Batch Post Job";
        TransferHeader: Record "Transfer Header";
        TransferLine: Record "Transfer Line";
        TransferShipmentHeader: Record "Transfer Shipment Header";
        TransferReceiptHeader: Record "Transfer Receipt Header";
        BatchCode: Code[20];
    begin
        // [GIVEN] a transfer order of 4 of which 1 was already shipped
        BatchCode := TestLibrary.NewBatchCode();
        TestLibrary.CreateTransferOrder(TransferHeader, TransferLine, BatchCode, 4);
        TransferLine.Validate("Qty. to Ship", 1);
        TransferLine.Modify(true);
        Codeunit.Run(Codeunit::"TransferOrder-Post Shipment", TransferHeader);
        TransferLine.Get(TransferLine."Document No.", TransferLine."Line No.");
        if TransferLine."Qty. to Ship" = 0 then begin
            // keep the scenario independent of whether BC resets Qty. to Ship after a partial shipment
            TransferLine.Validate("Qty. to Ship", TransferLine."Outstanding Quantity");
            TransferLine.Modify(true);
        end;

        // [WHEN] the transfer job runs
        TestLibrary.RunJob(Job, Job."Doc Type"::TransferOrder, BatchCode);

        // [THEN] the remaining 3 are shipped and everything in transit is received
        TestLibrary.AssertJobCompleted(Job, 1, 0);
        TransferShipmentHeader.SetRange("Transfer Order No.", TransferHeader."No.");
        Assert.RecordCount(TransferShipmentHeader, 2);
        TransferReceiptHeader.SetRange("Transfer Order No.", TransferHeader."No.");
        Assert.RecordCount(TransferReceiptHeader, 1);
        TestLibrary.AssertNotExists(TransferHeader, 'A fully shipped and received transfer order is deleted');
    end;

    [Test]
    procedure AssemblyOrderIsPosted()
    var
        Job: Record "BIF Batch Post Job";
        AssemblyHeader: Record "Assembly Header";
        PostedAssemblyHeader: Record "Posted Assembly Header";
        BatchCode: Code[20];
    begin
        // [GIVEN] an assembly order whose component is on stock
        BatchCode := TestLibrary.NewBatchCode();
        TestLibrary.CreateAssemblyOrder(AssemblyHeader, BatchCode);

        // [WHEN] the assembly job runs
        TestLibrary.RunJob(Job, Job."Doc Type"::AssemblyOrder, BatchCode);

        // [THEN] it is posted with Assembly-Post
        TestLibrary.AssertJobCompleted(Job, 1, 0);
        TestLibrary.AssertResult(BatchCode, AssemblyHeader."BIF Source Doc No.", true);
        PostedAssemblyHeader.SetRange("Order No.", AssemblyHeader."No.");
        Assert.RecordCount(PostedAssemblyHeader, 1);
        PostedAssemblyHeader.FindFirst();
        TestLibrary.AssertPostedDocNo(BatchCode, AssemblyHeader."BIF Source Doc No.", PostedAssemblyHeader."No.");
    end;

    [Test]
    procedure AssemblyOrderWithNothingToAssembleFails()
    var
        Job: Record "BIF Batch Post Job";
        AssemblyHeader: Record "Assembly Header";
        PostedAssemblyHeader: Record "Posted Assembly Header";
        BatchCode: Code[20];
    begin
        // [GIVEN] an assembly order with nothing left to assemble
        BatchCode := TestLibrary.NewBatchCode();
        TestLibrary.CreateAssemblyOrder(AssemblyHeader, BatchCode);
        AssemblyHeader.Validate("Quantity to Assemble", 0);
        AssemblyHeader.Modify(true);

        // [WHEN] the assembly job runs
        TestLibrary.RunJob(Job, Job."Doc Type"::AssemblyOrder, BatchCode);

        // [THEN] it fails and is logged; nothing is posted
        TestLibrary.AssertJobCompleted(Job, 0, 1);
        TestLibrary.AssertResult(BatchCode, AssemblyHeader."BIF Source Doc No.", false);
        PostedAssemblyHeader.SetRange("Order No.", AssemblyHeader."No.");
        Assert.RecordIsEmpty(PostedAssemblyHeader);
    end;

    [Test]
    procedure ReleasedProductionOrderIsFinished()
    var
        Job: Record "BIF Batch Post Job";
        ProductionOrder: Record "Production Order";
        FinishedProductionOrder: Record "Production Order";
        BatchCode: Code[20];
    begin
        // [GIVEN] a released production order in a batch
        BatchCode := TestLibrary.NewBatchCode();
        TestLibrary.CreateReleasedProdOrder(ProductionOrder, BatchCode);

        // [WHEN] the production order job runs
        TestLibrary.RunJob(Job, Job."Doc Type"::ProductionOrder, BatchCode);

        // [THEN] the order is finished
        TestLibrary.AssertJobCompleted(Job, 1, 0);
        TestLibrary.AssertResult(BatchCode, ProductionOrder."BIF Source Doc No.", true);
        TestLibrary.AssertPostedDocNo(BatchCode, ProductionOrder."BIF Source Doc No.", ProductionOrder."No.");
        TestLibrary.AssertNotExists(ProductionOrder, 'The released order is gone');
        Assert.IsTrue(FinishedProductionOrder.Get(FinishedProductionOrder.Status::Finished, ProductionOrder."No."), 'The finished order exists');
    end;

    [Test]
    procedure ProductionJobSkipsOrdersThatAreNotReleased()
    var
        Job: Record "BIF Batch Post Job";
        ProductionOrder: Record "Production Order";
        BatchCode: Code[20];
    begin
        // [GIVEN] a firm planned production order in a batch
        BatchCode := TestLibrary.NewBatchCode();
        LibraryManufacturing.CreateProductionOrder(
            ProductionOrder, ProductionOrder.Status::"Firm Planned", ProductionOrder."Source Type"::Item, LibraryInventory.CreateItemNo(), 1);
        ProductionOrder."BIF Batch Code" := BatchCode;
        ProductionOrder.Modify(true);

        // [WHEN] the production order job runs
        TestLibrary.RunJob(Job, Job."Doc Type"::ProductionOrder, BatchCode);

        // [THEN] only released orders are finished
        TestLibrary.AssertJobCompleted(Job, 0, 0);
        TestLibrary.AssertExists(ProductionOrder, 'The firm planned order is untouched');
    end;
}
