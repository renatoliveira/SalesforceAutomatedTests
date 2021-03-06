global with sharing class AutomatedTestingJob implements Schedulable {

    global void execute (SchedulableContext SC) {
        doExecute();
    }

    // Have to use a future method so the email will be sent out.
    @Future(Callout=true)
    public static void doExecute () {
        processAsyncResults(true, [
            SELECT
                Id,
                Name,
                AsyncId__c
            FROM AutomatedTestingQueue__c
            WHERE Completed__c = FALSE
            LIMIT 5
        ]);
    }

    /**
     *Schedule String Format: Seconds Minutes Hours Day_of_month Month Day_of_week optional_year
     */
    public static void createEveryHourScheduledJobs () {
        AutomatedTestingJob atj = new AutomatedTestingJob();
        string sch = '0 0 * * * ?';
        system.schedule('Process Queued Unit Tests Every Hour',sch,atj);
    }

    public static void processAsyncResults (Boolean sendResults, List<AutomatedTestingQueue__c> queuedTests) {
        if (queuedTests != null && queuedTests.size() > 0) {
            Set<Id> asyncIds = new Set<Id>();

            for (AutomatedTestingQueue__c queuedJob : queuedTests) {
                 asyncIds.add(queuedJob.AsyncId__c);
            }

            List<ApexTestQueueItem> queuedItems = checkClassStatus(asyncIds);
            Map<Id, List<ApexTestQueueItem>> groupedTestsByJob = new Map<Id, List<ApexTestQueueItem>>();

            for (ApexTestQueueItem atqi : queuedItems) {
                if (groupedTestsByJob.containsKey(atqi.ParentJobId) == true) {
                    List<ApexTestQueueItem> groupedTests = groupedTestsByJob.get(atqi.ParentJobId);
                    groupedTests.add(atqi);
                } else {
                    List<ApexTestQueueItem> groupedTests = new List<ApexTestQueueItem>();
                    groupedTests.add(atqi);
                    groupedTestsByJob.put(atqi.ParentJobId, groupedTests);
                }
            }

            Set<Id> completedAsyncIds = getCompletedAsyncJobsIds(groupedTestsByJob);
            if (completedAsyncIds != null && completedAsyncIds.size() > 0) {
                List<ApexTestResult> testResults = checkMethodStatus(completedAsyncIds);
                Map<Id, List<ApexTestResult>> groupedTestResultsByJob = new Map<Id, List<ApexTestResult>>();

                for (ApexTestResult testResult : testResults) {
                    if (groupedTestResultsByJob.containsKey(testResult.AsyncApexJobId)) {
                        List<ApexTestResult> groupedTestsResults = groupedTestResultsByJob.get(testResult.AsyncApexJobId);
                        groupedTestsResults.add(testResult);
                    }
                    else{
                        List<ApexTestResult> groupedTestsResults = new List<ApexTestResult>();
                        groupedTestsResults.add(testResult);

                        groupedTestResultsByJob.put(testResult.AsyncApexJobId, groupedTestsResults );
                    }
                }

                List<AutomatedTestingQueue__c> queuedTestsToUpdate = new List<AutomatedTestingQueue__c>();

                for (List<ApexTestResult> jobTestResults : groupedTestResultsByJob.values()) {
                    if (sendResults) {
                        sendTestResultSlack(jobTestResults);
                    }
                }

                for (AutomatedTestingQueue__c queuedTest : queuedTests) {
                    for (Id completedAsyncId : completedAsyncIds) {
                        if (queuedTest.AsyncId__c == completedAsyncId) {
                            queuedTestsToUpdate.add(queuedTest);
                            break;
                        }
                    }

                    if (groupedTestResultsByJob.containsKey(queuedTest.AsyncId__c)) {
                        AggregatedTestResult agr = getAggregatedTestResult(groupedTestResultsByJob.get(queuedTest.AsyncId__c));
                        queuedTest.Passing__c = agr.passing;
                        queuedTest.Failing__c = agr.failing;
                        queuedTest.Skipped__c = agr.skipped;
                        queuedTest.Completed__c = true;
                    }

                    if (!groupedTestsByJob.containsKey(queuedTest.AsyncId__c)) {
                        queuedTestsToUpdate.add(queuedTest);
                    }
                }

                update queuedTestsToUpdate;
            }
        }
    }

    private static AggregatedTestResult getAggregatedTestResult (List<ApexTestResult> tests) {
        Integer passing = 0;
        Integer failing = 0;
        Integer skipped = 0;

        for (ApexTestResult t : tests) {
            if (t.Outcome == 'Pass') {
                passing += 1;
            } else if (t.Outcome == 'Skip') {
                skipped += 1;
            } else {
                failing += 1;
            }
        }
        return new AggregatedTestResult(passing, failing, skipped);
    }

    public class AggregatedTestResult {
        private Integer passing;
        private Integer failing;
        private Integer skipped;

        public AggregatedTestResult (Integer passing, Integer failing, Integer skipped) {
            this.passing = passing;
            this.failing = failing;
            this.skipped = skipped;
        }
    }

    public static Set<Id> getCompletedAsyncJobsIds (Map<Id, List<ApexTestQueueItem>> groupedTestsByJob) {
        Set<Id> completedAsyncJobIds = new Set<Id>();

        for (List<ApexTestQueueItem> jobTests : groupedTestsByJob.values()) {
            if (jobTests == null || jobTests.size() == 0) {
                continue;
            }
            Boolean allCompleted = true;

            for (ApexTestQueueItem queuedTest : jobTests) {
                if (queuedTest.Status != 'Completed' &&
                        queuedTest.Status != 'Failed' &&
                        queuedTest.Status != 'Aborted') {
                    allCompleted = false;
                    break;
                }
            }

            if (allCompleted == true) {
                completedAsyncJobIds.add(jobTests[0].ParentJobId);
            }
        }

        return completedAsyncJobIds;
    }

    private static void sendTestResultSlack (List<ApexTestResult> jobTestResults) {
        SlackFailingTestsMessage testsJSON = new SlackFailingTestsMessage();
        SlackWebhookMessage slackMessage = new SlackWebhookMessage();
        slackMessage.setEndpoint('your slack hook here');
        slackMessage.setMessage(testsJSON.generateJSONPayload(jobTestResults));
        slackMessage.send();
    }

    /**
     * Get the status and pass rate for each class
     * whose tests were run by the job.
     * that correspond to the specified job ID.
     */
    public static List<ApexTestQueueItem> checkClassStatus (Set<Id> jobIds) {
        List<ApexTestQueueItem> items = [
            SELECT
                ApexClass.Name,
                Status,
                ExtendedStatus,
                ParentJobId
            FROM ApexTestQueueItem
            WHERE ParentJobId in :jobIds
        ];
        for (ApexTestQueueItem item : items) {
            String extStatus = item.extendedstatus == null ? '' : item.extendedStatus;
        }
        return items;
    }

    // Get the result for each test method that was executed.

    public static List<ApexTestResult> checkMethodStatus (Set<Id> jobIds) {
        return [
            SELECT
                Outcome,
                MethodName,
                Message,
                StackTrace,
                AsyncApexJobId,
                ApexClass.Name,
                ApexClass.Body,
                ApexClass.LengthWithoutComments,
                ApexClass.NamespacePrefix,
                ApexClass.Status,
                ApexLogId,
                ApexLog.DurationMilliseconds,
                ApexLog.Operation,
                ApexLog.Request,
                ApexLog.Status,
                ApexLog.Location,
                ApexLog.Application
            FROM ApexTestResult
            WHERE AsyncApexJobId in :jobIds
        ];
    }
}
