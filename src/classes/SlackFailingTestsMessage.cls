public with sharing class SlackFailingTestsMessage {

    public List<Attachments> attachments {get;set;}

    public class Attachments {
        public String fallback {get;set;}
        public String color {get;set;}
        public String pretext {get;set;}
        public List<Fields> fields {get;set;}
        public String footer {get;set;}
    }

    public class Fields {
        public String title {get;set;}
        public String value {get;set;}
    }

    public String generateJSONPayload (List<ApexTestResult> failedTests) {
        List<Fields> fields = new List<Fields>();

        Integer passingTestsCount = 0;
        Integer failedTestsCount = 0;
        Integer totaltestsCount = 0;

        for (ApexTestResult failingTest : failedTests) {
            totaltestsCount += 1;
            if (failingTest.Outcome == 'Pass') {
                passingTestsCount += 1;
                continue;
            }
            Fields f = new Fields();
            f.title = failingTest.StackTrace;
            f.value = failingTest.Message;
            failedTestsCount += 1;
            fields.add(f);
        }

        Attachments messageBody = new Attachments();
        Organization orgInfo = [SELECT Name, InstanceName FROM Organization LIMIT 1];
        Decimal passingPercentage = passingTestsCount * 100.0/totaltestsCount;
        messageBody.fallback = String.format('{0} tests ran, {1} passing ({3}), {2} failed on {4} ({5}).', new List<String>{
            totaltestsCount+''
            ,passingTestsCount+''
            ,failedTestsCount+''
            ,passingPercentage.setScale(2)+'%'
            ,orgInfo.Name
            ,orgInfo.InstanceName
        });
        messageBody.pretext = messageBody.fallback;
        messageBody.color = fields.size() > 0 ? '#f44336' : '#4caf50';
        String passingText = String.format('All tests passing on {0} ({1})! ✅', new List<String>{
            orgInfo.Name,
            orgInfo.InstanceName
        });
        if (fields.size() == 0) {
            messageBody.fallback = passingText;
            messageBody.pretext = passingText;
        }
        messageBody.fields = fields;
        messageBody.footer = 'via Salesforce and Slack API';

        this.attachments = new List<Attachments>{messageBody};

        return JSON.serialize(this);
    }
}
