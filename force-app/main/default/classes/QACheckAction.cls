/**
 * QACheckAction
 * -------------
 * Invocable wrapper around QAEngine so the Agentforce agent (and Flows) can run
 * a QA assessment on a Form and receive:
 *   - a verdict (Pass / Flag / Fail)
 *   - a deterministic findings summary (completeness + reconciliation)
 *   - a plausibility fact-package the agent reasons over in natural language
 *
 * The agent uses the facts to produce the human-readable judgment; the engine
 * never fabricates numbers.
 */
public with sharing class QACheckAction {

    public class Request {
        @InvocableVariable(label='Form Id' required=true)
        public Id formId;
    }

    public class Response {
        @InvocableVariable(label='Verdict')
        public String verdict;

        @InvocableVariable(label='Deterministic Findings Summary')
        public String findingsSummary;

        @InvocableVariable(label='QA Analysis')
        public String plausibilityFacts;

        @InvocableVariable(label='Finding Count')
        public Integer findingCount;
    }

    @InvocableMethod(
        label='Run Form QA Assessment'
        description='Assesses a form and its line items for completeness, reconciliation, and plausibility. Returns a verdict, a findings summary, and plausibility facts for the agent to reason over.'
        category='QA Agent'
    )
    public static List<Response> run(List<Request> requests) {
        List<Response> responses = new List<Response>();

        for (Request req : requests) {
            QAEngine.QAResult result = QAEngine.assessForm(req.formId);

            Response resp = new Response();
            resp.verdict = result.verdict;
            resp.findingCount = result.findings.size();
            resp.findingsSummary = buildFindingsSummary(result);
            resp.plausibilityFacts = buildPlausibilityFacts(result);
            responses.add(resp);
        }
        return responses;
    }

    private static String buildFindingsSummary(QAEngine.QAResult result) {
        if (result.findings.isEmpty()) {
            return 'No completeness or reconciliation issues found.';
        }
        List<String> lines = new List<String>();
        for (QAEngine.QAFinding f : result.findings) {
            String ref = String.isNotBlank(f.regulatoryReference)
                ? ' (' + f.regulatoryReference + ')' : '';
            lines.add('[' + f.severity + ' - ' + f.checkType + '] ' + f.message
                + (String.isNotBlank(f.detail) ? ' | ' + f.detail : '') + ref);
        }
        return String.join(lines, '\n');
    }

    /**
     * Composes the finished plausibility ANALYSIS as reviewer case notes.
     *
     * Design note: the agent in this org reliably DISPLAYS action output but does
     * not perform a second generative pass to interpret it (its system rules treat
     * the function result as the reply). So, per Salesforce's own guidance to build
     * deterministic logic into the action rather than topic instructions, the engine
     * writes the analysis here. The result is consistent and auditable - desirable
     * for a compliance/QA tool.
     */
    private static String buildPlausibilityFacts(QAEngine.QAResult result) {
        if (result.plausibilityFacts.isEmpty()) {
            return 'No plausibility metrics applied to this form.';
        }

        // Only narrate metrics that are actually out of range or swung sharply.
        List<QAEngine.PlausibilityFact> notable = new List<QAEngine.PlausibilityFact>();
        for (QAEngine.PlausibilityFact pf : result.plausibilityFacts) {
            if (pf.outsideRange || pf.priorSwingExceeded) notable.add(pf);
        }
        if (notable.isEmpty()) {
            return 'All plausibility metrics fall within expected ranges; the figures look reasonable.';
        }

        List<String> notes = new List<String>();
        for (QAEngine.PlausibilityFact pf : notable) {
            notes.add(composeNote(pf));
        }
        return String.join(notes, '\n\n');
    }

    /**
     * Turns one plausibility fact into a plain-English reviewer note:
     * what the figure is, why it's a concern, the likely cause, and a recommendation.
     */
    private static String composeNote(QAEngine.PlausibilityFact pf) {
        String metric = friendlyMetric(pf.metricName);
        String val = formatNum(pf.computedValue);

        // 1. What the figure is
        String note = 'The ' + metric + ' is ' + val;

        // 2. Why it's a concern (range)
        if (pf.outsideRange && (pf.expectedLow != null || pf.expectedHigh != null)) {
            if (pf.expectedLow != null && pf.computedValue < pf.expectedLow) {
                note += ', which is below the expected minimum of ' + formatNum(pf.expectedLow);
            } else if (pf.expectedHigh != null && pf.computedValue > pf.expectedHigh) {
                note += ', which is above the expected maximum of ' + formatNum(pf.expectedHigh);
            } else {
                note += ', which is outside the expected range of '
                    + formatNum(pf.expectedLow) + ' to ' + formatNum(pf.expectedHigh);
            }
        }

        // 3. Prior-period movement
        if (pf.priorSwingExceeded && pf.priorValue != null) {
            String dir = (pf.priorVariancePercent != null && pf.priorVariancePercent < 0) ? 'down' : 'up';
            note += ', and is ' + dir + ' ' + formatNum(absVal(pf.priorVariancePercent))
                + '% from last period (' + formatNum(pf.priorValue) + ')';
        }
        note += '.';

        // 4. Benchmark context, if any
        if (String.isNotBlank(pf.sectorBenchmark)) {
            note += ' For context: ' + pf.sectorBenchmark;
            if (!pf.sectorBenchmark.endsWith('.')) note += '.';
        }

        // 5. Likely cause + recommendation (tailored to a rate-style metric)
        Boolean looksLikeRate = pf.metricName != null
            && (pf.metricName.toLowerCase().contains('cost') || pf.metricName.toLowerCase().contains('rate'))
            && pf.metricName.contains('/');
        if (looksLikeRate && pf.outsideRange && pf.expectedLow != null && pf.computedValue < pf.expectedLow) {
            note += ' A value below the expected floor often points to misreported on-costs, '
                + 'agency staff being wrongly included or excluded, or a data-entry error.';
        } else {
            note += ' This is an unusual value that may reflect a reporting or data-entry issue.';
        }
        note += ' Recommend confirming this figure with the provider before accepting the form.';

        return note;
    }

    // ---- small formatting helpers ----
    private static String friendlyMetric(String raw) {
        if (String.isBlank(raw)) return 'computed metric';
        // Make machine keys readable: RN_LABOUR_COST / RN_HOURS -> "RN labour cost per hour"
        if (raw.contains('/')) {
            return 'implied rate (' + raw.replace('_', ' ').toLowerCase() + ')';
        }
        return raw.replace('_', ' ').toLowerCase();
    }

    private static Decimal absVal(Decimal d) {
        if (d == null) return null;
        return d < 0 ? -d : d;
    }

    private static String formatNum(Decimal d) {
        if (d == null) return 'n/a';
        // trim trailing zeros for clean display
        Decimal stripped = d.stripTrailingZeros();
        return String.valueOf(stripped);
    }
}
