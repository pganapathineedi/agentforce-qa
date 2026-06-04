/**
 * CaseQACheckAction
 * -----------------
 * Invocable wrapper around QAEngine.assessCase so the Agentforce agent (and
 * Flows) can assess a whole QFR submission (a Case with multiple forms) and
 * receive one overall verdict plus a per-form breakdown.
 *
 * Consistent with QACheckAction: the engine composes the finished summary text;
 * the agent presents it.
 */
public with sharing class CaseQACheckAction {

    public class Request {
        @InvocableVariable(label='Case Id' required=true)
        public Id caseId;
    }

    public class Response {
        @InvocableVariable(label='Overall Verdict')
        public String overallVerdict;

        @InvocableVariable(label='Submission Summary')
        public String submissionSummary;

        @InvocableVariable(label='Forms Assessed')
        public Integer formsAssessed;
    }

    @InvocableMethod(
        label='Run Submission QA Assessment'
        description='Assesses all forms on a QFR submission (Case) and returns one overall verdict plus a per-form breakdown.'
        category='QA Agent'
    )
    public static List<Response> run(List<Request> requests) {
        List<Response> responses = new List<Response>();

        for (Request req : requests) {
            QAEngine.CaseQAResult result = QAEngine.assessCase(req.caseId);

            Response resp = new Response();
            resp.overallVerdict = result.overallVerdict;
            resp.formsAssessed = result.formsAssessed;
            resp.submissionSummary = buildSummary(result);
            responses.add(resp);
        }
        return responses;
    }

    /**
     * Composes the finished submission summary as reviewer notes.
     */
    private static String buildSummary(QAEngine.CaseQAResult result) {
        if (result.formsAssessed == 0) {
            return 'No forms found on this submission to assess.';
        }

        String headline = 'This submission has an overall verdict of '
            + result.overallVerdict + ', based on ' + result.formsAssessed
            + ' form' + (result.formsAssessed == 1 ? '' : 's') + ' assessed ('
            + result.formsPassed + ' passed, ' + result.formsFlagged
            + ' flagged, ' + result.formsFailed + ' failed).';

        List<String> lines = new List<String>();
        for (QAEngine.FormSummary fs : result.formSummaries) {
            String detail = fs.formType + ': ' + fs.verdict;
            if (fs.findingCount > 0) {
                detail += ' (' + fs.findingCount + ' finding'
                    + (fs.findingCount == 1 ? '' : 's');
                if (fs.plausibilityFlagCount > 0) {
                    detail += ', ' + fs.plausibilityFlagCount + ' plausibility flag'
                        + (fs.plausibilityFlagCount == 1 ? '' : 's');
                }
                detail += ')';
            } else if (fs.plausibilityFlagCount > 0) {
                detail += ' (' + fs.plausibilityFlagCount + ' plausibility flag'
                    + (fs.plausibilityFlagCount == 1 ? '' : 's') + ')';
            }
            lines.add(detail);
        }

        String guidance;
        if (result.overallVerdict == 'Fail') {
            guidance = 'The submission cannot be accepted until the failing forms are corrected.';
        } else if (result.overallVerdict == 'Flag') {
            guidance = 'The submission has no hard failures but some figures warrant review before acceptance.';
        } else {
            guidance = 'All forms passed; the submission is ready for acceptance.';
        }

        return headline + '\n\n' + String.join(lines, '\n') + '\n\n' + guidance;
    }
}
