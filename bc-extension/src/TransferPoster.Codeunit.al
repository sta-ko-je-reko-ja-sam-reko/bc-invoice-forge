// Posts transfer orders: ship, then receive, via the standard transfer posting
// codeunits. Each step runs in its own Codeunit.Run (see BIF Sales Poster for why).
//
// Both standard codeunits commit, so a run can end with the shipment posted and the
// receipt failed. A rerun must not ship again: the shipment step only runs when a
// line still has a quantity to ship. So:
//   - nothing shipped yet      -> ship everything, then receive it;
//   - fully shipped            -> receive only;
//   - partially shipped        -> ship the remaining quantity to ship, then receive
//                                 everything that is in transit.
codeunit 75009 "BIF Transfer Poster" implements "BIF IDocument Poster"
{
    procedure PostBatch(BatchCode: Code[20]; var Posted: Integer; var Failed: Integer)
    var
        TransferHeader: Record "Transfer Header";
        PostLog: Codeunit "BIF Post Log";
        DocNos: List of [Code[20]];
        DocNo: Code[20];
        SourceDocNo: Code[35];
    begin
        TransferHeader.SetRange("BIF Batch Code", BatchCode);
        if TransferHeader.FindSet() then
            repeat
                DocNos.Add(TransferHeader."No.");
            until TransferHeader.Next() = 0;

        foreach DocNo in DocNos do
            if TransferHeader.Get(DocNo) then begin
                SourceDocNo := TransferHeader."BIF Source Doc No.";
                if ShipAndReceive(TransferHeader) then begin
                    Posted += 1;
                    PostLog.Log(BatchCode, SourceDocNo, GetPostedReceiptNo(DocNo), true, '');
                end else begin
                    Failed += 1;
                    PostLog.Log(BatchCode, SourceDocNo, '', false, GetLastErrorText());
                end;
            end;
    end;

    local procedure ShipAndReceive(var TransferHeader: Record "Transfer Header"): Boolean
    begin
        if HasQtyToShip(TransferHeader."No.") then begin
            Commit();
            if not Codeunit.Run(Codeunit::"TransferOrder-Post Shipment", TransferHeader) then
                exit(false);
            // Re-read; posting the shipment updates the header.
            TransferHeader.Get(TransferHeader."No.");
        end;
        Commit();
        exit(Codeunit.Run(Codeunit::"TransferOrder-Post Receipt", TransferHeader));
    end;

    local procedure HasQtyToShip(TransferOrderNo: Code[20]): Boolean
    var
        TransferLine: Record "Transfer Line";
    begin
        TransferLine.SetRange("Document No.", TransferOrderNo);
        TransferLine.SetRange("Derived From Line No.", 0);
        TransferLine.SetFilter("Qty. to Ship", '>0');
        exit(not TransferLine.IsEmpty());
    end;

    local procedure GetPostedReceiptNo(TransferOrderNo: Code[20]): Code[20]
    var
        TransferReceiptHeader: Record "Transfer Receipt Header";
    begin
        TransferReceiptHeader.SetRange("Transfer Order No.", TransferOrderNo);
        if TransferReceiptHeader.FindLast() then
            exit(TransferReceiptHeader."No.");
    end;
}
