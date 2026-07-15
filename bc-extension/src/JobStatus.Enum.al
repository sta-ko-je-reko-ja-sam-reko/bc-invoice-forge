// Lifecycle of a batch-post job, polled by the orchestrator for reconciliation.
enum 50001 "BIF Job Status"
{
    Extensible = true;

    value(0; Pending) { Caption = 'Pending'; }
    value(1; Running) { Caption = 'Running'; }
    value(2; Completed) { Caption = 'Completed'; }
    value(3; Failed) { Caption = 'Failed'; }
}
