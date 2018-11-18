# SalesforceAutomatedTests

Couple of classes that schedule tests to run at a specified time, and then can email the results to you or post to a Slack channel

# Usage

1. Create the `AutomatedTestingQueue__c` object in your organization with the `AsyncId__c` field (text, 40 chars).
2. Create the remote site setting for slack webhooks (`https://hooks.slack.com`) if you want to use it instead of the email. If you don't want to post messages to slack, skip to step 4.
3. Add your slack webhook URL to the `AutomatedTestingJob.sendTestResultSlack` method.
4. Schedule your tests to run at a specified time (it is recommended to run when people are not working on the code, so at late night or at the morning) using the `AutomatedTestJobQueuer.createDailyJobAt` method.
5. Schedule the platform to monitor for tests results using the `AutomatedTestingJob.createEveryHourScheduledJobs` method.

# About this

This small modification comes after searching a method to run tests and inform a couple of users involved in a single org or project. Salesforce already provided the base classes in this repository in the Force.com Workbook, but then I added the Slack channel things.

