global with sharing class AutomatedTestJobQueuer implements Schedulable {

    global void execute (SchedulableContext SC) {
        doExecute();
    }

    @Future(Callout=true)
    public static void doExecute () {
        enqueueUnitTests();
    }

    public static void createDailyJobAt (Integer hour) {
        if (hour < 0 || hour > 23) {
            throw new UnsupportedOperationException('Schedule must be done with the 24-hour ' +
                'clock. Values acceptable are between 0 and 23');
        }
        AutomatedTestJobQueuer atj = new AutomatedTestJobQueuer();
        String sch = '0 0 ' + String.valueOf(hour) + ' * * ?';
        System.schedule('Enqueued Unit Tests at ' + String.valueOf(hour) + '.',sch,atj);
    }

    /**
     *Allows us to externally enqueue our unit tests. For example,
     * whenever we check our code into source control, we could
     * run our unit tests.
     */
    webservice static void enqueueUnitTests () {
        enqueueTests();
    }


    // Enqueue all classes beginning with "Test".

    public static void enqueueTests () {
       /* The first thing you need to do is query the classes that contain
        * the unit tests you want executed.

        * In our org, every test class contains the word 'Test', so we query them all
        * here. Optionally, we created a custom setting to control wether we want to run
        * tests for managed packages as well.
        */

        List<ApexClass> testClasses = new List<ApexClass>();
        String classQuery = 'SELECT Id, Name FROM ApexClass WHERE ';
        if (TestSettings__c.getOrgDefaults().IncludeNamespacedTests__c) {
            classQuery += 'Name LIKE \'%Test%\'';
        } else {
            classQuery += 'Name LIKE \'%Test%\' AND NamesapcePrefix = NULL';
        }
        testClasses = (List<ApexClass>) Database.query(classQuery);

        Integer testClassCnt = testClasses != null ? testClasses.size() : 0;

        if (testClassCnt > 0) {
          /*
           * Insertion of the ApexTestQueueItem causes the unit tests to be
           * executed. Since they're asynchronous, the apex async job id
           * needs to be stored somewhere so we can process the test results
           * when the job is complete.
           */
            ApexTestQueueItem[] queueItems = new List<ApexTestQueueItem>();

            for (ApexClass testClass : testClasses) {
                queueItems.add(new ApexTestQueueItem(ApexClassId=testClass.Id));
            }
            insert queueItems;

            // Get the job ID of the first queue item returned.
            ApexTestQueueItem item = [
                SELECT
                    ParentJobId
                FROM ApexTestQueueItem
                WHERE Id = :queueItems[0].Id
                LIMIT 1
            ];

            AutomatedTestingQueue__c atq = new AutomatedTestingQueue__c(
                AsyncId__c = item.parentjobid
            );
            insert atq;
        }
    }
}
