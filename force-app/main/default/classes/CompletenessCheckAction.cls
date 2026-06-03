/**
 * CompletenessCheckAction
 * -----------------------
 * Invocable wrapper around CompletenessEngine.
 *
 * This is the bridge between the declarative world (Agentforce agent actions,
 * Flows) and the engine. Exposing it as @InvocableMethod means:
 *   - The Agentforce agent can call it as a custom Action
 *   - A record-triggered Flow can call it when Status = Submitted
 *   - It returns a human-readable summary the agent can speak back
 */
public with sharing class CompletenessCheckAction {

    public class Request {
        @InvocableVariable(label='Record Id' required=true)
        public Id recordId;

        @InvocableVariable(label='Trigger Status' required=false)
        public String triggerStatus;
    }

    public class Response {
        @InvocableVariable(label='Is Complete')
        public Boolean isComplete;

        @InvocableVariable(label='Gap Count')
        public Integer gapCount;

        @InvocableVariable(label='Summary')
        public String summary;

        @InvocableVariable(label='Gap Details (JSON)')
        public String gapsJson;
    }

    @InvocableMethod(
        label='Check Record Completeness'
        description='Evaluates a record against configured completeness rules and returns a summary of any gaps.'
        category='Completeness Agent'
    )
    public static List<Response> run(List<Request> requests) {
        List<Response> responses = new List<Response>();

        for (Request req : requests) {
            CompletenessEngine.CompletenessResult result =
                CompletenessEngine.check(req.recordId, req.triggerStatus);

            Response resp = new Response();
            resp.isComplete = result.isComplete;
            resp.gapCount = result.gapCount;
            resp.gapsJson = JSON.serialize(result.gaps);
            resp.summary = buildSummary(result);
            responses.add(resp);
        }
        return responses;
    }

    /**
     * Builds a plain-English summary the agent can present to a user.
     */
    private static String buildSummary(CompletenessEngine.CompletenessResult result) {
        if (result.isComplete) {
            return 'This record is complete. All configured requirements are met.';
        }

        // Group by severity for a clear summary
        Integer critical = 0, high = 0, other = 0;
        List<String> lines = new List<String>();
        for (CompletenessEngine.CompletenessGap gap : result.gaps) {
            if (gap.severity == 'Critical') critical++;
            else if (gap.severity == 'High') high++;
            else other++;
            String ref = String.isNotBlank(gap.regulatoryReference)
                ? ' (' + gap.regulatoryReference + ')' : '';
            lines.add('• [' + gap.severity + '] ' + gap.message + ref);
        }

        String header = 'This record has ' + result.gapCount + ' outstanding requirement'
            + (result.gapCount == 1 ? '' : 's') + ' before it can proceed';
        if (critical > 0) {
            header += ', including ' + critical + ' critical item' + (critical == 1 ? '' : 's');
        }
        header += ':';

        return header + '\n' + String.join(lines, '\n');
    }
}
