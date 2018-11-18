public with sharing class SlackWebhookMessage {

    private String endpoint;
    private String message;

    public SlackWebhookMessage () {}

    public void setEndpoint (String endpoint) {
        this.endpoint = endpoint;
    }

    public void setMessage (String msg) {
        this.message = msg;
    }

    public void send () {
        HttpRequest req = new HttpRequest();
        req.setMethod('POST');
        req.setHeader('Content-Type', 'application/json');
        req.setBody(this.message);
        req.setEndpoint(this.endpoint);
        HttpResponse res = new Http().send(req);
        System.debug(LoggingLevel.INFO, res.getStatus());
        System.debug(LoggingLevel.INFO, res.getStatusCode());
    }
}
