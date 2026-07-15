// Posts transfer orders: ship, then receive, via the standard transfer posting
// codeunits. Both run in one TryFunction so a failure rolls the pair back.
codeunit 50009 "BIF Transfer Poster" implements "BIF IDocument Poster"
{
    procedure PostBatch(BatchCode: Code[20]; var Posted: Integer; var Failed: Integer)
    var
        TransferHeader: Record "Transfer Header";
        PostLog: Codeunit "BIF Post Log";
        DocNos: List of [Code[20]];
        DocNo: Code[20];
    begin
        TransferHeader.SetRange("BIF Batch Code", BatchCode);
        if TransferHeader.FindSet() then
            repeat
                DocNos.Add(TransferHeader."No.");
            until TransferHeader.Next() = 0;

        foreach DocNo in DocNos do
            if TransferHeader.Get(DocNo) then
                if TryPost(TransferHeader) then begin
                    Posted += 1;
                    PostLog.Log(BatchCode, TransferHeader."BIF Source Doc No.", true, '');
                end else begin
                    Failed += 1;
                    PostLog.Log(BatchCode, TransferHeader."BIF Source Doc No.", false, CopyStr(GetLastErrorText(), 1, 250));
                end;
    end;

    [TryFunction]
    local procedure TryPost(var TransferHeader: Record "Transfer Header")
    var
        PostShipment: Codeunit "TransferOrder-Post Shipment";
        PostReceipt: Codeunit "TransferOrder-Post Receipt";
    begin
        Clear(PostShipment);
        PostShipment.Run(TransferHeader);
        // Re-read; posting shipment updates the header.
        TransferHeader.Get(TransferHeader."No.");
        Clear(PostReceipt);
        PostReceipt.Run(TransferHeader);
    end;
}
