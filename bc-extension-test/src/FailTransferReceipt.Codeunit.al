// Bound manually by tests to make the transfer receipt fail after the shipment
// posted, which is the half-posted state a rerun must recover from.
codeunit 79009 "BIF Fail Transfer Receipt"
{
    EventSubscriberInstance = Manual;

    var
        ReceiptFailsErr: Label 'Simulated receipt failure.', Locked = true;

    [EventSubscriber(ObjectType::Codeunit, Codeunit::"TransferOrder-Post Receipt", 'OnBeforeTransferOrderPostReceipt', '', false, false)]
    local procedure FailReceipt(var TransferHeader: Record "Transfer Header"; var CommitIsSuppressed: Boolean; PreviewMode: Boolean; var ItemJnlPostLine: Codeunit "Item Jnl.-Post Line")
    begin
        Error(ReceiptFailsErr);
    end;
}
