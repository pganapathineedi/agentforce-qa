/**
 * QAEngine
 * --------
 * Form-level QA assessment engine for the QFR use case (and any multi-line form).
 *
 * Where CompletenessEngine evaluates ONE record against field rules, QAEngine
 * evaluates a FORM plus all its child Form_Line_Item__c records, running three
 * kinds of check:
 *
 *   Completeness   — required line items present (delegates to the same rule data)
 *   Reconciliation — figures must math out within tolerance (deterministic)
 *   Plausibility   — engine computes a metric + gathers facts; the AGENT reasons
 *
 * Division of labour (the honest, grounded design):
 *   - Deterministic checks (completeness, reconciliation) -> engine decides pass/fail
 *   - Plausibility -> engine supplies FACTS, agent supplies JUDGMENT
 *
 * The engine stays domain-agnostic: all thresholds, expressions, and benchmarks
 * live in Completeness_Rule__mdt. Ship once, configure forever.
 */
public with sharing class QAEngine {

    // ---- Result structures -------------------------------------------------

    /** One deterministic finding (completeness or reconciliation failure). */
    public class QAFinding {
        @AuraEnabled public String ruleLabel;
        @AuraEnabled public String checkType;      // Completeness | Reconciliation
        @AuraEnabled public String severity;       // Critical | High | Medium | Low
        @AuraEnabled public String message;
        @AuraEnabled public String detail;         // figures behind the finding
        @AuraEnabled public String regulatoryReference;

        public QAFinding(String ruleLabel, String checkType, String severity,
                         String message, String detail, String regRef) {
            this.ruleLabel = ruleLabel;
            this.checkType = checkType;
            this.severity = severity;
            this.message = message;
            this.detail = detail;
            this.regulatoryReference = regRef;
        }
    }

    /** A plausibility fact-package: NOT a pass/fail. The agent reasons over this. */
    public class PlausibilityFact {
        @AuraEnabled public String ruleLabel;
        @AuraEnabled public String metricName;
        @AuraEnabled public Decimal computedValue;
        @AuraEnabled public Decimal expectedLow;
        @AuraEnabled public Decimal expectedHigh;
        @AuraEnabled public String sectorBenchmark;
        @AuraEnabled public Decimal priorValue;
        @AuraEnabled public Decimal priorVariancePercent;
        @AuraEnabled public Boolean outsideRange;
        @AuraEnabled public Boolean priorSwingExceeded;
        @AuraEnabled public String regulatoryReference;

        public PlausibilityFact(String ruleLabel, String metricName) {
            this.ruleLabel = ruleLabel;
            this.metricName = metricName;
            this.outsideRange = false;
            this.priorSwingExceeded = false;
        }
    }

    /** The full QA result for one form. */
    public class QAResult {
        @AuraEnabled public Id formId;
        @AuraEnabled public String verdict;                       // Pass | Flag | Fail
        @AuraEnabled public List<QAFinding> findings;
        @AuraEnabled public List<PlausibilityFact> plausibilityFacts;

        public QAResult(Id formId) {
            this.formId = formId;
            this.findings = new List<QAFinding>();
            this.plausibilityFacts = new List<PlausibilityFact>();
            this.verdict = 'Pass';
        }
    }

    // ---- Main entry point --------------------------------------------------

    /**
     * Assess a single Form and its line items.
     * @param formId  the Form__c record to assess
     * @return        a QAResult with findings, plausibility facts, and a verdict
     */
    public static QAResult assessForm(Id formId) {
        QAResult result = new QAResult(formId);

        // 1. Load the form (record type drives which rules apply)
        Form__c form = loadForm(formId);
        if (form == null) return result;

        String recordTypeName = (form.RecordType != null)
            ? form.RecordType.DeveloperName : null;

        // 2. Load all line items for this form, keyed by Line_Key for fast lookup
        Map<String, Form_Line_Item__c> linesByKey = loadLineItems(formId);

        // 3. Load matching active rules for Form_Line_Item__c on this record type
        List<Completeness_Rule__mdt> rules = getRules('Form_Line_Item__c', recordTypeName);

        // 4. Evaluate each rule by type
        for (Completeness_Rule__mdt rule : rules) {
            String type = rule.Rule_Type__c;
            if (type == 'Field_Required') {
                evaluateCompleteness(rule, linesByKey, result);
            } else if (type == 'Reconciliation') {
                evaluateReconciliation(rule, linesByKey, result);
            } else if (type == 'Plausibility') {
                evaluatePlausibility(rule, linesByKey, result);
            }
        }

        // 5. Roll up the verdict
        result.verdict = computeVerdict(result);
        return result;
    }

    // ---- Completeness ------------------------------------------------------

    private static void evaluateCompleteness(Completeness_Rule__mdt rule,
            Map<String, Form_Line_Item__c> linesByKey, QAResult result) {
        String key = rule.Applies_To_Line_Key__c;
        if (String.isBlank(key)) return;

        Form_Line_Item__c line = linesByKey.get(key);
        Boolean missing = (line == null) || lineValueIsEmpty(line);
        if (missing) {
            result.findings.add(new QAFinding(
                rule.MasterLabel, 'Completeness', rule.Severity__c,
                resolveMessage(rule, 'Required line "' + key + '" is missing or empty.'),
                'Expected line key: ' + key,
                rule.Regulatory_Reference__c));
        }
    }

    // ---- Reconciliation ----------------------------------------------------
    /**
     * Expression form: "LEFT_KEY op RIGHT_KEY = RESULT_KEY" style, but we support
     * the common practical pattern: "A + B = C" or "A / B = C" where tokens are
     * line keys. We compute LHS and RHS and compare within tolerance.
     */
    private static void evaluateReconciliation(Completeness_Rule__mdt rule,
            Map<String, Form_Line_Item__c> linesByKey, QAResult result) {
        String expr = rule.Reconciliation_Expression__c;
        if (String.isBlank(expr) || !expr.contains('=')) return;

        String lhsExpr = expr.substringBefore('=').trim();
        String rhsExpr = expr.substringAfter('=').trim();

        Decimal lhs = evalArithmetic(lhsExpr, linesByKey);
        Decimal rhs = evalArithmetic(rhsExpr, linesByKey);
        if (lhs == null || rhs == null) return; // can't evaluate -> skip silently

        Decimal tolerance = (rule.Tolerance_Percent__c != null) ? rule.Tolerance_Percent__c : 0;
        Decimal allowed = (rhs == 0) ? 0 : Math.abs(rhs) * (tolerance / 100);
        Decimal diff = Math.abs(lhs - rhs);

        if (diff > allowed) {
            String detail = 'Left side (' + lhsExpr + ') = ' + lhs
                + ' ; Right side (' + rhsExpr + ') = ' + rhs
                + ' ; difference ' + diff
                + (tolerance > 0 ? ' exceeds ' + tolerance + '% tolerance.' : '.');
            result.findings.add(new QAFinding(
                rule.MasterLabel, 'Reconciliation', rule.Severity__c,
                resolveMessage(rule, 'Figures do not reconcile.'),
                detail, rule.Regulatory_Reference__c));
        }
    }

    // ---- Plausibility (agentic) -------------------------------------------
    /**
     * The engine computes the metric and gathers reference facts. It does NOT
     * decide pass/fail on judgment — it flags whether the value is outside the
     * configured range or swung too far vs prior, and hands the agent everything
     * needed to reason.
     */
    private static void evaluatePlausibility(Completeness_Rule__mdt rule,
            Map<String, Form_Line_Item__c> linesByKey, QAResult result) {
        String metricExpr = rule.Plausibility_Metric__c;
        if (String.isBlank(metricExpr)) return;

        Decimal value = evalArithmetic(metricExpr, linesByKey);
        if (value == null) return;

        PlausibilityFact fact = new PlausibilityFact(rule.MasterLabel, metricExpr);
        fact.computedValue = value;
        fact.expectedLow = rule.Expected_Range_Low__c;
        fact.expectedHigh = rule.Expected_Range_High__c;
        fact.sectorBenchmark = rule.Sector_Benchmark__c;
        fact.regulatoryReference = rule.Regulatory_Reference__c;

        if (rule.Expected_Range_Low__c != null && value < rule.Expected_Range_Low__c) {
            fact.outsideRange = true;
        }
        if (rule.Expected_Range_High__c != null && value > rule.Expected_Range_High__c) {
            fact.outsideRange = true;
        }

        // Quarter-on-quarter comparison using Prior_Value_Number on the line items
        if (rule.Compare_To_Prior__c == true) {
            Decimal priorValue = evalArithmeticPrior(metricExpr, linesByKey);
            if (priorValue != null && priorValue != 0) {
                fact.priorValue = priorValue;
                Decimal variance = ((value - priorValue) / Math.abs(priorValue)) * 100;
                fact.priorVariancePercent = variance.setScale(1);
                if (rule.Prior_Variance_Threshold__c != null
                    && Math.abs(variance) > rule.Prior_Variance_Threshold__c) {
                    fact.priorSwingExceeded = true;
                }
            }
        }

        result.plausibilityFacts.add(fact);
    }

    // ---- Verdict roll-up ---------------------------------------------------
    /**
     * Critical/High deterministic finding -> Fail.
     * Any Medium/Low finding, or any plausibility flag -> Flag.
     * Otherwise -> Pass.
     */
    private static String computeVerdict(QAResult result) {
        Boolean hasFail = false;
        Boolean hasFlag = false;

        for (QAFinding f : result.findings) {
            if (f.severity == 'Critical' || f.severity == 'High') hasFail = true;
            else hasFlag = true;
        }
        for (PlausibilityFact pf : result.plausibilityFacts) {
            if (pf.outsideRange || pf.priorSwingExceeded) hasFlag = true;
        }

        if (hasFail) return 'Fail';
        if (hasFlag) return 'Flag';
        return 'Pass';
    }

    // ---- Helpers -----------------------------------------------------------

    private static Form__c loadForm(Id formId) {
        List<Form__c> forms = [
            SELECT Id, Form_Type__c, Form_Status__c, RecordType.DeveloperName
            FROM Form__c WHERE Id = :formId LIMIT 1
        ];
        return forms.isEmpty() ? null : forms[0];
    }

    private static Map<String, Form_Line_Item__c> loadLineItems(Id formId) {
        Map<String, Form_Line_Item__c> byKey = new Map<String, Form_Line_Item__c>();
        for (Form_Line_Item__c li : [
            SELECT Id, Line_Key__c, Line_Group__c, Line_Type__c,
                   Value_Number__c, Value_Currency__c, Value_Text__c,
                   Value_Boolean__c, Value_Date__c, Prior_Value_Number__c
            FROM Form_Line_Item__c WHERE Form__c = :formId
        ]) {
            if (String.isNotBlank(li.Line_Key__c)) {
                byKey.put(li.Line_Key__c, li);
            }
        }
        return byKey;
    }

    private static List<Completeness_Rule__mdt> getRules(String objectName, String recordTypeName) {
        List<Completeness_Rule__mdt> matched = new List<Completeness_Rule__mdt>();
        for (Completeness_Rule__mdt rule : Completeness_Rule__mdt.getAll().values()) {
            if (rule.Active__c != true) continue;
            if (rule.Applies_To_Object__c != objectName) continue;
            if (String.isNotBlank(rule.Applies_To_RecordType__c)
                && rule.Applies_To_RecordType__c != recordTypeName) continue;
            matched.add(rule);
        }
        return matched;
    }

    /** The numeric value of a line item, based on its type. */
    private static Decimal lineValue(Form_Line_Item__c li) {
        if (li == null) return null;
        if (li.Value_Currency__c != null) return li.Value_Currency__c;
        if (li.Value_Number__c != null) return li.Value_Number__c;
        return null;
    }

    private static Decimal priorLineValue(Form_Line_Item__c li) {
        return (li == null) ? null : li.Prior_Value_Number__c;
    }

    private static Boolean lineValueIsEmpty(Form_Line_Item__c li) {
        return li.Value_Currency__c == null && li.Value_Number__c == null
            && String.isBlank(li.Value_Text__c) && li.Value_Date__c == null
            && li.Value_Boolean__c != true;
    }

    /**
     * Evaluate a simple arithmetic expression where tokens are line keys.
     * Supports + - * / between line-key values. Falls back to a bare key.
     * Deliberately minimal — complex logic belongs in Custom_Apex rules.
     */
    private static Decimal evalArithmetic(String expr, Map<String, Form_Line_Item__c> linesByKey) {
        return evalArithmeticInternal(expr, linesByKey, false);
    }

    private static Decimal evalArithmeticPrior(String expr, Map<String, Form_Line_Item__c> linesByKey) {
        return evalArithmeticInternal(expr, linesByKey, true);
    }

    private static Decimal evalArithmeticInternal(String expr,
            Map<String, Form_Line_Item__c> linesByKey, Boolean usePrior) {
        if (String.isBlank(expr)) return null;
        expr = expr.trim();

        // Handle the four binary operators (single operator, left-to-right).
        for (String op : new List<String>{ '+', '-', '*', '/' }) {
            Integer idx = expr.indexOf(op);
            if (idx > 0) {
                String leftTok = expr.substring(0, idx).trim();
                String rightTok = expr.substring(idx + 1).trim();
                Decimal l = resolveToken(leftTok, linesByKey, usePrior);
                Decimal r = resolveToken(rightTok, linesByKey, usePrior);
                if (l == null || r == null) return null;
                if (op == '+') return l + r;
                if (op == '-') return l - r;
                if (op == '*') return l * r;
                if (op == '/') return (r == 0) ? null : l.divide(r, 4);
            }
        }
        // No operator -> single token
        return resolveToken(expr, linesByKey, usePrior);
    }

    /** A token is either a numeric literal or a line key. */
    private static Decimal resolveToken(String token, Map<String, Form_Line_Item__c> linesByKey, Boolean usePrior) {
        if (String.isBlank(token)) return null;
        token = token.trim();
        // Numeric literal?
        try {
            return Decimal.valueOf(token);
        } catch (Exception e) {
            // Treat as a line key
            Form_Line_Item__c li = linesByKey.get(token);
            return usePrior ? priorLineValue(li) : lineValue(li);
        }
    }

    private static String resolveMessage(Completeness_Rule__mdt rule, String fallback) {
        return String.isNotBlank(rule.Gap_Message__c) ? rule.Gap_Message__c : fallback;
    }
}
