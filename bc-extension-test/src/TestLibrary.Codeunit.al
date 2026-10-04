// Shared helpers for the BC Invoice Forge tests: batch codes, jobs, result checks and
// documents tagged the way the orchestrator tags them at import time.
codeunit 79000 "BIF Test Library"
{
    var
        Assert: Codeunit "Library Assert";
        LibraryAssembly: Codeunit "Library - Assembly";
        LibraryInventory: Codeunit "Library - Inventory";
        LibraryManufacturing: Codeunit "Library - Manufacturing";
        LibraryPurchase: Codeunit "Library - Purchase";
        LibraryRandom: Codeunit "Library - Random";
        LibrarySales: Codeunit "Library - Sales";
        LibraryService: Codeunit "Library - Service";
        LibraryWarehouse: Codeunit "Library - Warehouse";
        ServiceSetupDone: Boolean;
        SuccessOfDocTxt: Label 'Success of %1', Comment = '%1 = source document number', Locked = true;

    /// <summary>A batch code no other test uses, so tests never see each other's documents or results.</summary>
    /// <returns>A unique batch code.</returns>
    procedure NewBatchCode(): Code[20]
    begin
        exit(CopyStr(UpperCase(DelChr(Format(CreateGuid()), '=', '{}-')), 1, 20));
    end;

    /// <summary>A unique source (external) document number, the orchestrator's correlation key.</summary>
    /// <returns>A unique source document number.</returns>
    procedure NewSourceDocNo(): Code[35]
    begin
        exit(CopyStr('SRC' + UpperCase(DelChr(Format(CreateGuid()), '=', '{}-')), 1, 35));
    end;

    /// <summary>Inserts a batch-post job the way the batchPostJobs API does.</summary>
    /// <param name="Job">The inserted job.</param>
    /// <param name="DocType">The document kind the job posts.</param>
    /// <param name="BatchCode">The batch code of the documents to post.</param>
    procedure CreateJob(var Job: Record "BIF Batch Post Job"; DocType: Enum "BIF Doc Type"; BatchCode: Code[20])
    begin
        Job.Init();
        Job."Batch Code" := BatchCode;
        Job."Doc Type" := DocType;
        Job.Insert(true);
    end;

    /// <summary>Creates a job and runs it in the current session, then re-reads it.</summary>
    /// <param name="Job">The job after the run.</param>
    /// <param name="DocType">The document kind the job posts.</param>
    /// <param name="BatchCode">The batch code of the documents to post.</param>
    procedure RunJob(var Job: Record "BIF Batch Post Job"; DocType: Enum "BIF Doc Type"; BatchCode: Code[20])
    var
        BatchPost: Codeunit "BIF Batch Post";
    begin
        CreateJob(Job, DocType, BatchCode);
        BatchPost.RunJob(Job);
        Job.Get(Job."Entry No.");
    end;

    /// <summary>Checks a finished job's status and counters.</summary>
    /// <param name="Job">The job.</param>
    /// <param name="ExpectedPosted">Expected number of posted documents.</param>
    /// <param name="ExpectedFailed">Expected number of failed documents.</param>
    procedure AssertJobCompleted(Job: Record "BIF Batch Post Job"; ExpectedPosted: Integer; ExpectedFailed: Integer)
    begin
        Assert.AreEqual(Job.Status::Completed, Job.Status, 'Job status');
        Assert.AreEqual(ExpectedPosted, Job."Posted Count", 'Posted Count');
        Assert.AreEqual(ExpectedFailed, Job."Failed Count", 'Failed Count');
    end;

    /// <summary>Number of result rows logged for a batch.</summary>
    /// <param name="BatchCode">The batch code.</param>
    /// <returns>The number of rows.</returns>
    procedure CountResults(BatchCode: Code[20]): Integer
    var
        PostResult: Record "BIF Post Result";
    begin
        PostResult.SetRange("Batch Code", BatchCode);
        exit(PostResult.Count());
    end;

    /// <summary>Checks that exactly one result row exists for a source document and returns its error message.</summary>
    /// <param name="BatchCode">The batch code.</param>
    /// <param name="SourceDocNo">The source document number.</param>
    /// <param name="ExpectedSuccess">Whether the document is expected to have posted.</param>
    /// <returns>The logged error message.</returns>
    procedure AssertResult(BatchCode: Code[20]; SourceDocNo: Code[35]; ExpectedSuccess: Boolean): Text
    var
        PostResult: Record "BIF Post Result";
    begin
        PostResult.SetRange("Batch Code", BatchCode);
        PostResult.SetRange("Source Document No.", SourceDocNo);
        Assert.RecordCount(PostResult, 1);
        PostResult.FindFirst();
        Assert.AreEqual(ExpectedSuccess, PostResult.Success, StrSubstNo(SuccessOfDocTxt, SourceDocNo));
        if ExpectedSuccess then begin
            Assert.AreEqual('', PostResult."Error Message", 'A posted document has no error message');
            Assert.AreNotEqual('', PostResult."Posted Document No.", 'A posted document reports its posted document no.');
        end else begin
            Assert.AreNotEqual('', PostResult."Error Message", 'A failed document carries the BC error');
            Assert.AreEqual('', PostResult."Posted Document No.", 'A failed document has no posted document no.');
        end;
        exit(PostResult."Error Message");
    end;

    /// <summary>Checks the posted document number logged for a source document.</summary>
    /// <param name="BatchCode">The batch code.</param>
    /// <param name="SourceDocNo">The source document number.</param>
    /// <param name="ExpectedPostedDocNo">The expected posted document number.</param>
    procedure AssertPostedDocNo(BatchCode: Code[20]; SourceDocNo: Code[35]; ExpectedPostedDocNo: Code[20])
    var
        PostResult: Record "BIF Post Result";
    begin
        PostResult.SetRange("Batch Code", BatchCode);
        PostResult.SetRange("Source Document No.", SourceDocNo);
        PostResult.SetRange(Success, true);
        PostResult.FindLast();
        Assert.AreEqual(ExpectedPostedDocNo, PostResult."Posted Document No.", 'Posted Document No.');
    end;

    /// <summary>Turns Ext. Doc. No. Mandatory on or off in Purchases &amp; Payables Setup.</summary>
    /// <param name="Mandatory">The new setting.</param>
    procedure SetPurchExtDocNoMandatory(Mandatory: Boolean)
    var
        PurchasesPayablesSetup: Record "Purchases & Payables Setup";
    begin
        PurchasesPayablesSetup.Get();
        PurchasesPayablesSetup."Ext. Doc. No. Mandatory" := Mandatory;
        PurchasesPayablesSetup.Modify();
    end;

    /// <summary>Asserts that a record still exists in the database (for example a document that must stay unposted).</summary>
    /// <param name="RecordVariant">The record.</param>
    /// <param name="Message">The assertion message.</param>
    procedure AssertExists(RecordVariant: Variant; Message: Text)
    var
        RecRef: RecordRef;
    begin
        RecRef.GetTable(RecordVariant);
        RecRef.SetRecFilter();
        Assert.IsFalse(RecRef.IsEmpty(), Message);
    end;

    /// <summary>Asserts that a record no longer exists in the database (for example a posted, deleted document).</summary>
    /// <param name="RecordVariant">The record.</param>
    /// <param name="Message">The assertion message.</param>
    procedure AssertNotExists(RecordVariant: Variant; Message: Text)
    var
        RecRef: RecordRef;
    begin
        RecRef.GetTable(RecordVariant);
        RecRef.SetRecFilter();
        Assert.IsTrue(RecRef.IsEmpty(), Message);
    end;

    /// <summary>Creates a postable sales invoice tagged with a batch code and a unique external document number.</summary>
    /// <param name="SalesHeader">The created invoice.</param>
    /// <param name="BatchCode">The batch code.</param>
    procedure CreateSalesInvoice(var SalesHeader: Record "Sales Header"; BatchCode: Code[20])
    begin
        CreateSalesDocument(SalesHeader, SalesHeader."Document Type"::Invoice, BatchCode);
    end;

    /// <summary>Creates a postable sales document of any type tagged with a batch code.</summary>
    /// <param name="SalesHeader">The created document.</param>
    /// <param name="DocumentType">The sales document type.</param>
    /// <param name="BatchCode">The batch code.</param>
    procedure CreateSalesDocument(var SalesHeader: Record "Sales Header"; DocumentType: Enum "Sales Document Type"; BatchCode: Code[20])
    var
        SalesLine: Record "Sales Line";
    begin
        LibrarySales.CreateSalesHeader(SalesHeader, DocumentType, LibrarySales.CreateCustomerNo());
        LibrarySales.CreateSalesLine(SalesLine, SalesHeader, SalesLine.Type::Item, LibraryInventory.CreateItemNo(), LibraryRandom.RandInt(10));
        SalesLine.Validate("Unit Price", LibraryRandom.RandDecInRange(1, 100, 2));
        SalesLine.Modify(true);
        SalesHeader.Validate("External Document No.", NewSourceDocNo());
        SalesHeader."BIF Batch Code" := BatchCode;
        SalesHeader.Modify(true);
    end;

    /// <summary>Creates a postable purchase invoice tagged with a batch code (Vendor Invoice No. is unique).</summary>
    /// <param name="PurchaseHeader">The created invoice.</param>
    /// <param name="BatchCode">The batch code.</param>
    /// <param name="VendorNo">The vendor; a new one when blank.</param>
    procedure CreatePurchaseInvoice(var PurchaseHeader: Record "Purchase Header"; BatchCode: Code[20]; VendorNo: Code[20])
    begin
        CreatePurchaseDocument(PurchaseHeader, PurchaseHeader."Document Type"::Invoice, BatchCode, VendorNo);
    end;

    /// <summary>Creates a postable purchase order tagged with a batch code and a source document number.</summary>
    /// <param name="PurchaseHeader">The created order.</param>
    /// <param name="BatchCode">The batch code.</param>
    procedure CreatePurchaseOrder(var PurchaseHeader: Record "Purchase Header"; BatchCode: Code[20])
    begin
        CreatePurchaseDocument(PurchaseHeader, PurchaseHeader."Document Type"::Order, BatchCode, '');
    end;

    local procedure CreatePurchaseDocument(var PurchaseHeader: Record "Purchase Header"; DocumentType: Enum "Purchase Document Type"; BatchCode: Code[20]; VendorNo: Code[20])
    var
        PurchaseLine: Record "Purchase Line";
    begin
        if VendorNo = '' then
            VendorNo := LibraryPurchase.CreateVendorNo();
        LibraryPurchase.CreatePurchHeader(PurchaseHeader, DocumentType, VendorNo);
        LibraryPurchase.CreatePurchaseLine(PurchaseLine, PurchaseHeader, PurchaseLine.Type::Item, LibraryInventory.CreateItemNo(), LibraryRandom.RandInt(10));
        PurchaseLine.Validate("Direct Unit Cost", LibraryRandom.RandDecInRange(1, 100, 2));
        PurchaseLine.Modify(true);
        PurchaseHeader."BIF Batch Code" := BatchCode;
        PurchaseHeader."BIF Source Doc No." := NewSourceDocNo();
        PurchaseHeader.Modify(true);
    end;

    /// <summary>Sets up the service number series once per session.</summary>
    procedure InitializeService()
    begin
        if ServiceSetupDone then
            exit;
        LibraryService.SetupServiceMgtNoSeries();
        ServiceSetupDone := true;
    end;

    /// <summary>Creates a service invoice header tagged with a batch code and a source document number, without lines.</summary>
    /// <param name="ServiceHeader">The created invoice.</param>
    /// <param name="BatchCode">The batch code.</param>
    procedure CreateServiceInvoiceHeader(var ServiceHeader: Record "Service Header"; BatchCode: Code[20])
    begin
        InitializeService();
        LibraryService.CreateServiceHeader(ServiceHeader, ServiceHeader."Document Type"::Invoice, LibrarySales.CreateCustomerNo());
        ServiceHeader."BIF Batch Code" := BatchCode;
        ServiceHeader."BIF Source Doc No." := NewSourceDocNo();
        ServiceHeader.Modify(true);
    end;

    /// <summary>Creates a postable service invoice (one item line) tagged with a batch code.</summary>
    /// <param name="ServiceHeader">The created invoice.</param>
    /// <param name="BatchCode">The batch code.</param>
    procedure CreateServiceInvoice(var ServiceHeader: Record "Service Header"; BatchCode: Code[20])
    var
        ServiceLine: Record "Service Line";
    begin
        CreateServiceInvoiceHeader(ServiceHeader, BatchCode);
        LibraryService.CreateServiceLineWithQuantity(ServiceLine, ServiceHeader, ServiceLine.Type::Item, LibraryInventory.CreateItemNo(), LibraryRandom.RandInt(10));
        ServiceLine.Validate("Unit Price", LibraryRandom.RandDecInRange(1, 100, 2));
        ServiceLine.Modify(true);
    end;

    /// <summary>Creates an item with stock at a location.</summary>
    /// <param name="Item">The created item.</param>
    /// <param name="LocationCode">The location that gets the stock.</param>
    /// <param name="Quantity">The quantity put on stock.</param>
    procedure CreateItemWithStock(var Item: Record Item; LocationCode: Code[10]; Quantity: Decimal)
    begin
        LibraryInventory.CreateItem(Item);
        LibraryInventory.PostPositiveAdjustment(Item, LocationCode, '', '', Quantity, WorkDate(), LibraryRandom.RandDecInRange(1, 100, 2));
    end;

    /// <summary>Creates transfer locations and a transfer order header tagged with a batch code, without lines.</summary>
    /// <param name="TransferHeader">The created transfer order.</param>
    /// <param name="BatchCode">The batch code.</param>
    procedure CreateTransferOrderHeader(var TransferHeader: Record "Transfer Header"; BatchCode: Code[20])
    var
        FromLocation: Record Location;
        ToLocation: Record Location;
        InTransitLocation: Record Location;
    begin
        LibraryWarehouse.CreateTransferLocations(FromLocation, ToLocation, InTransitLocation);
        LibraryWarehouse.CreateTransferHeader(TransferHeader, FromLocation.Code, ToLocation.Code, InTransitLocation.Code);
        TransferHeader."BIF Batch Code" := BatchCode;
        TransferHeader."BIF Source Doc No." := NewSourceDocNo();
        TransferHeader.Modify(true);
    end;

    /// <summary>Creates a postable transfer order (one line, item on stock at the from-location) tagged with a batch code.</summary>
    /// <param name="TransferHeader">The created transfer order.</param>
    /// <param name="BatchCode">The batch code.</param>
    procedure CreateTransferOrder(var TransferHeader: Record "Transfer Header"; BatchCode: Code[20])
    var
        TransferLine: Record "Transfer Line";
    begin
        CreateTransferOrder(TransferHeader, TransferLine, BatchCode, LibraryRandom.RandInt(5));
    end;

    /// <summary>Creates a postable transfer order with one line of a given quantity, tagged with a batch code.</summary>
    /// <param name="TransferHeader">The created transfer order.</param>
    /// <param name="TransferLine">The created line.</param>
    /// <param name="BatchCode">The batch code.</param>
    /// <param name="Quantity">The line quantity (the from-location gets 10 more on stock).</param>
    procedure CreateTransferOrder(var TransferHeader: Record "Transfer Header"; var TransferLine: Record "Transfer Line"; BatchCode: Code[20]; Quantity: Decimal)
    var
        Item: Record Item;
    begin
        CreateTransferOrderHeader(TransferHeader, BatchCode);
        CreateItemWithStock(Item, TransferHeader."Transfer-from Code", Quantity + 10);
        LibraryWarehouse.CreateTransferLine(TransferHeader, TransferLine, Item."No.", Quantity);
    end;

    /// <summary>Creates an assembly order (one component on stock) tagged with a batch code.</summary>
    /// <param name="AssemblyHeader">The created assembly order.</param>
    /// <param name="BatchCode">The batch code.</param>
    procedure CreateAssemblyOrder(var AssemblyHeader: Record "Assembly Header"; BatchCode: Code[20])
    var
        ParentItem: Record Item;
        ComponentItem: Record Item;
        AssemblyLine: Record "Assembly Line";
    begin
        LibraryInventory.CreateItem(ParentItem);
        CreateItemWithStock(ComponentItem, '', 100);
        LibraryAssembly.CreateAssemblyHeader(AssemblyHeader, WorkDate(), ParentItem."No.", '', 1, '');
        LibraryAssembly.CreateAssemblyLine(AssemblyHeader, AssemblyLine, AssemblyLine.Type::Item, ComponentItem."No.", ComponentItem."Base Unit of Measure", 2, 2, '');
        AssemblyHeader.Get(AssemblyHeader."Document Type", AssemblyHeader."No.");
        AssemblyHeader."BIF Batch Code" := BatchCode;
        AssemblyHeader."BIF Source Doc No." := NewSourceDocNo();
        AssemblyHeader.Modify(true);
    end;

    /// <summary>Creates a released production order (not refreshed, so without lines) tagged with a batch code.</summary>
    /// <param name="ProductionOrder">The created production order.</param>
    /// <param name="BatchCode">The batch code.</param>
    procedure CreateReleasedProdOrder(var ProductionOrder: Record "Production Order"; BatchCode: Code[20])
    begin
        LibraryManufacturing.CreateProductionOrder(
            ProductionOrder, ProductionOrder.Status::Released, ProductionOrder."Source Type"::Item, LibraryInventory.CreateItemNo(), LibraryRandom.RandInt(10));
        ProductionOrder."BIF Batch Code" := BatchCode;
        ProductionOrder."BIF Source Doc No." := NewSourceDocNo();
        ProductionOrder.Modify(true);
    end;

    /// <summary>Blocks or unblocks a customer for all transactions.</summary>
    /// <param name="CustomerNo">The customer.</param>
    /// <param name="Block">True to block, false to unblock.</param>
    procedure SetCustomerBlocked(CustomerNo: Code[20]; Block: Boolean)
    var
        Customer: Record Customer;
    begin
        Customer.Get(CustomerNo);
        if Block then
            Customer.Blocked := Customer.Blocked::All
        else
            Customer.Blocked := Customer.Blocked::" ";
        Customer.Modify(true);
    end;

    /// <summary>Blocks or unblocks a vendor for all transactions.</summary>
    /// <param name="VendorNo">The vendor.</param>
    /// <param name="Block">True to block, false to unblock.</param>
    procedure SetVendorBlocked(VendorNo: Code[20]; Block: Boolean)
    var
        Vendor: Record Vendor;
    begin
        Vendor.Get(VendorNo);
        if Block then
            Vendor.Blocked := Vendor.Blocked::All
        else
            Vendor.Blocked := Vendor.Blocked::" ";
        Vendor.Modify(true);
    end;
}
