global with sharing class AutomatedTestingJob implements Schedulable {

    global void execute (SchedulableContext SC) {
        doExecute();
    }

    // Have to use a future method so the email will be sent out.
    @Future(Callout=true)
    public static void doExecute () {
        processAsyncResults();
    }

    /**
     *Schedule String Format: Seconds Minutes Hours Day_of_month Month Day_of_week optional_year
     */
    public static void createEveryHourScheduledJobs () {
        AutomatedTestingJob atj = new AutomatedTestingJob();
        string sch = '0 0 * * * ?';
        system.schedule('Process Queued Unit Tests Every Hour',sch,atj);
    }

    public static void processAsyncResults () {
        List<AutomatedTestingQueue__c> queuedTests = [
            SELECT
                Id,
                Name,
                AsyncId__c
            FROM AutomatedTestingQueue__c
            LIMIT 5
        ];

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

                List<AutomatedTestingQueue__c> queuedTestsToDelete = new List<AutomatedTestingQueue__c>();

                for (List<ApexTestResult> jobTestResults : groupedTestResultsByJob.values()) {
                    // sendTestResultEmail(jobTestResults);
                    sendTestResultSlack(jobTestResults);
                }

                for (AutomatedTestingQueue__c queuedTest : queuedTests) {
                    for (Id completedAsyncId : completedAsyncIds) {
                        if (queuedTest.AsyncId__c == completedAsyncId) {
                            queuedTestsToDelete.add(queuedTest);
                            break;
                        }
                    }
                    if (!groupedTestsByJob.containsKey(queuedTest.asyncId__c)) {
                        queuedTestsToDelete.add(queuedTest);
                    }
                }

                delete queuedTestsToDelete;
            }
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
        slackMessage.setEndpoint('https://hooks.slack.com/services/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');
        slackMessage.setMessage(testsJSON.generateJSONPayload(jobTestResults));
        slackMessage.send();
    }

    private static void sendTestResultEmail (List<ApexTestResult> jobTestResults) {
        Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
        String emailAddress = 'renato.luiz@cbcloud.com.br';
        String[] toAddresses = new String[] { emailAddress };

        mail.setToAddresses(toAddresses);

        String emailSubject = 'Dev Unit Test Results ' + String.valueOf(Date.today());

        mail.setSubject(emailSubject);

        String testResultEmailbody = getTestResultHtmlEmailBody(jobTestResults);

        mail.setHtmlBody(testResultEmailbody);

        Messaging.sendEmail(new Messaging.Email[] { mail });
    }

    private static String getTestResultHtmlEmailBody (List<ApexTestResult> jobTestResults) {
        List<ApexTestResult> successTests = new List<ApexTestResult>();
        List<ApexTestResult> failedTests = new List<ApexTestResult>();

        for (ApexTestResult jobTestResult : jobTestResults) {
            if (jobTestResult.Outcome == 'Pass') {
                successTests.add(jobTestResult);
            } else {
                failedTests.add(jobTestResult);
            }
        }

        Integer numTestsRun = successTests.size() + failedTests.size();
        Integer numFailures = failedTests.size();
        Integer successNum = numTestsRun - numFailures;

        if (successNum < 0) {
            successNum = 0;
        }

        String testResultBody = '';

        testResultBody += '<body><div><p>Hi!</p><p>Here are the test results you scheduled the ' +
            'platform to email to you:</p><table><tr><td>Ran</td><td>Passing</td><td>Failing</td>' +
            ' </tr><tr class="test-summary-body">';

        testResultBody += '<td>' + numTestsRun + '</td>';
        testResultBody += '<td>' + successNum + '</td>';
        testResultBody += '<td>' + numFailures + '</td>';

        if (numFailures > 0) {
            for (ApexTestResult testFailure : failedTests) {
                testResultBody += '<tr>';
                testResultBody += '<td><p>' + testFailure.ApexClass.Name +
                    '</p><p>' + testFailure.MethodName + '</p></td>';
                testResultBody += '<td>' + testFailure.Message + '</td>';
                testResultBody += '<td>' + testFailure.StackTrace + '</td>';
                testResultBody += '<td>' + testFailure.ApexLog.DurationMilliseconds +
                    '</td></tr>';
            }
            testResultBody += '</tbody></table>';
        }
        testResultBody += '</div></body>';
        return testResultBody;
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
