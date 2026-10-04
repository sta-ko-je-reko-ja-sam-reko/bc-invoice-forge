// Guards the keys that keep batch posting fast at 100k+ documents: every poster
// filters its documents by batch code, the orchestrator reads results by batch, and
// the session monitor reads jobs by status.
codeunit 79010 "BIF Schema Tests"
{
    Subtype = Test;
    TestPermissions = Disabled;

    var
        Assert: Codeunit "Library Assert";
        NoKeyErr: Label 'Table %1 has no key that starts with field %2.', Comment = '%1 = table caption, %2 = field caption', Locked = true;

    [Test]
    procedure BatchCodeIsKeyedOnEveryTaggedDocumentTable()
    var
        SalesHeader: Record "Sales Header";
        PurchaseHeader: Record "Purchase Header";
        ServiceHeader: Record "Service Header";
        ProductionOrder: Record "Production Order";
        AssemblyHeader: Record "Assembly Header";
        TransferHeader: Record "Transfer Header";
    begin
        // [THEN] each document table the posters read has a key on BIF Batch Code
        AssertKeyStartsWith(Database::"Sales Header", SalesHeader.FieldNo("BIF Batch Code"));
        AssertKeyStartsWith(Database::"Purchase Header", PurchaseHeader.FieldNo("BIF Batch Code"));
        AssertKeyStartsWith(Database::"Service Header", ServiceHeader.FieldNo("BIF Batch Code"));
        AssertKeyStartsWith(Database::"Production Order", ProductionOrder.FieldNo("BIF Batch Code"));
        AssertKeyStartsWith(Database::"Assembly Header", AssemblyHeader.FieldNo("BIF Batch Code"));
        AssertKeyStartsWith(Database::"Transfer Header", TransferHeader.FieldNo("BIF Batch Code"));
    end;

    [Test]
    procedure PostResultIsKeyedByBatchAndSourceDocument()
    var
        PostResult: Record "BIF Post Result";
    begin
        // [THEN] results can be read per batch and per source document without a scan
        AssertKeyStartsWith(Database::"BIF Post Result", PostResult.FieldNo("Batch Code"));
        AssertKeyStartsWith(Database::"BIF Post Result", PostResult.FieldNo("Source Document No."));
    end;

    [Test]
    procedure BatchPostJobIsKeyedByStatusAndBatch()
    var
        Job: Record "BIF Batch Post Job";
    begin
        // [THEN] the session monitor (Status) and per-batch reads (Batch Code) use a key
        AssertKeyStartsWith(Database::"BIF Batch Post Job", Job.FieldNo(Status));
        AssertKeyStartsWith(Database::"BIF Batch Post Job", Job.FieldNo("Batch Code"));
    end;

    local procedure AssertKeyStartsWith(TableId: Integer; FieldId: Integer)
    var
        RecRef: RecordRef;
        KeyRef: KeyRef;
        Index: Integer;
    begin
        RecRef.Open(TableId);
        for Index := 1 to RecRef.KeyCount() do begin
            KeyRef := RecRef.KeyIndex(Index);
            if KeyRef.Active() then
                if KeyRef.FieldIndex(1).Number() = FieldId then
                    exit;
        end;
        Assert.Fail(StrSubstNo(NoKeyErr, RecRef.Caption(), RecRef.Field(FieldId).Caption()));
    end;
}
