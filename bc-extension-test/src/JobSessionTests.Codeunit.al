// Tests of crashed-session handling: a job records the session that runs it, a
// Running job whose session is gone is failed (on API read and before a start), a
// job that is really running is protected, and a failed job can be reset and rerun.
codeunit 79011 "BIF Job Session Tests"
{
    Subtype = Test;
    TestPermissions = Disabled;

    var
        Assert: Codeunit "Library Assert";
        TestLibrary: Codeunit "BIF Test Library";
        JobSessionMonitor: Codeunit "BIF Job Session Monitor";

    [Test]
    procedure RunJobRecordsSessionAndTimes()
    var
        Job: Record "BIF Batch Post Job";
    begin
        // [WHEN] a job runs
        TestLibrary.RunJob(Job, Job."Doc Type"::Sales, TestLibrary.NewBatchCode());

        // [THEN] it records the session that ran it and when it started and finished
        TestLibrary.AssertJobCompleted(Job, 0, 0);
        Assert.AreEqual(SessionId(), Job."Session Id", 'Session Id');
        Assert.AreEqual(ServiceInstanceId(), Job."Server Instance Id", 'Server Instance Id');
        Assert.AreNotEqual(0DT, Job."Started At", 'Started At');
        Assert.AreNotEqual(0DT, Job."Finished At", 'Finished At');
        Assert.AreEqual('', Job."Error Message", 'Error Message');
    end;

    [Test]
    procedure RunningJobWithEndedSessionIsMarkedFailed()
    var
        Job: Record "BIF Batch Post Job";
    begin
        // [GIVEN] a job left Running by a session that no longer exists
        CreateRunningJob(Job, TestLibrary.NewBatchCode(), false);

        // [WHEN] stale jobs are checked
        JobSessionMonitor.MarkStaleJobsFailed();

        // [THEN] the job is failed with a message saying why
        Job.Get(Job."Entry No.");
        Assert.AreEqual(Job.Status::Failed, Job.Status, 'Status');
        Assert.AreNotEqual('', Job."Error Message", 'Error Message');
        Assert.AreNotEqual(0DT, Job."Finished At", 'Finished At');
    end;

    [Test]
    procedure RunningJobWithLiveSessionStaysRunning()
    var
        Job: Record "BIF Batch Post Job";
    begin
        // [GIVEN] a job Running in a session that exists (this one)
        CreateRunningJob(Job, TestLibrary.NewBatchCode(), true);

        // [WHEN] stale jobs are checked
        JobSessionMonitor.MarkStaleJobsFailed();

        // [THEN] the job is left alone
        Job.Get(Job."Entry No.");
        Assert.AreEqual(Job.Status::Running, Job.Status, 'Status');
    end;

    [Test]
    procedure ReadingTheJobApiFailsStaleJobs()
    var
        Job: Record "BIF Batch Post Job";
        BatchPostJobApi: TestPage "BIF Batch Post Job";
    begin
        // [GIVEN] a job left Running by a session that no longer exists
        CreateRunningJob(Job, TestLibrary.NewBatchCode(), false);

        // [WHEN] the orchestrator reads the batchPostJobs API
        BatchPostJobApi.OpenView();
        Assert.IsTrue(BatchPostJobApi.GoToRecord(Job), 'The job is listed');

        // [THEN] it sees the job as failed, with the reason
        Assert.AreEqual(Format(Job.Status::Failed), BatchPostJobApi.status.Value(), 'status');
        Assert.AreNotEqual('', BatchPostJobApi.errorMessage.Value(), 'errorMessage');
        BatchPostJobApi.Close();
    end;

    [Test]
    procedure StartingAStaleJobFailsItSoItCanRun()
    var
        Job: Record "BIF Batch Post Job";
    begin
        // [GIVEN] a job left Running by a session that no longer exists
        CreateRunningJob(Job, TestLibrary.NewBatchCode(), false);

        // [WHEN] it is about to be started again
        JobSessionMonitor.CheckCanStart(Job);

        // [THEN] it is no longer Running
        Assert.AreEqual(Job.Status::Failed, Job.Status, 'Status');
    end;

    [Test]
    procedure StartingARunningJobIsRefused()
    var
        Job: Record "BIF Batch Post Job";
    begin
        // [GIVEN] a job that is really running
        CreateRunningJob(Job, TestLibrary.NewBatchCode(), true);

        // [WHEN] it is started a second time
        asserterror JobSessionMonitor.CheckCanStart(Job);

        // [THEN] that is refused, so a batch is never posted by two sessions at once
        Assert.ExpectedError('already running');
    end;

    [Test]
    procedure ResetRefusesARunningJob()
    var
        Job: Record "BIF Batch Post Job";
    begin
        // [GIVEN] a job that is really running
        CreateRunningJob(Job, TestLibrary.NewBatchCode(), true);

        // [WHEN] it is reset
        asserterror JobSessionMonitor.ResetJob(Job);

        // [THEN] that is refused
        Assert.ExpectedError('already running');
    end;

    [Test]
    procedure CrashedJobIsResetAndRerun()
    var
        Job: Record "BIF Batch Post Job";
        SalesHeader: Record "Sales Header";
        BatchPost: Codeunit "BIF Batch Post";
        BatchCode: Code[20];
    begin
        // [GIVEN] a batch with an invoice whose job crashed while Running
        BatchCode := TestLibrary.NewBatchCode();
        TestLibrary.CreateSalesInvoice(SalesHeader, BatchCode);
        CreateRunningJob(Job, BatchCode, false);

        // [WHEN] the job is reset
        JobSessionMonitor.ResetJob(Job);

        // [THEN] it is Pending with cleared counters and errors
        Assert.AreEqual(Job.Status::Pending, Job.Status, 'Status after reset');
        Assert.AreEqual(0, Job."Posted Count", 'Posted Count after reset');
        Assert.AreEqual('', Job."Error Message", 'Error Message after reset');

        // [WHEN] it runs again
        BatchPost.RunJob(Job);

        // [THEN] the invoice is posted
        Job.Get(Job."Entry No.");
        TestLibrary.AssertJobCompleted(Job, 1, 0);
        TestLibrary.AssertResult(BatchCode, SalesHeader."External Document No.", true);
    end;

    local procedure CreateRunningJob(var Job: Record "BIF Batch Post Job"; BatchCode: Code[20]; LiveSession: Boolean)
    begin
        TestLibrary.CreateJob(Job, Job."Doc Type"::Sales, BatchCode);
        Job.Status := Job.Status::Running;
        Job."Server Instance Id" := ServiceInstanceId();
        if LiveSession then
            Job."Session Id" := SessionId()
        else
            Job."Session Id" := GetEndedSessionId();
        Job."Started At" := CurrentDateTime();
        Job.Modify(true);
    end;

    local procedure GetEndedSessionId(): Integer
    var
        ActiveSession: Record "Active Session";
        CandidateId: Integer;
    begin
        // a session id above every active one on this server instance
        ActiveSession.SetRange("Server Instance ID", ServiceInstanceId());
        ActiveSession.SetCurrentKey("Server Instance ID", "Session ID");
        if ActiveSession.FindLast() then
            CandidateId := ActiveSession."Session ID";
        exit(CandidateId + 100000);
    end;
}
