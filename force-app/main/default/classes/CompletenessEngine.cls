/**
 * CompletenessEngine
 * ------------------
 * The generic, domain-agnostic engine at the heart of the Completeness Check Agent.
 *
 * It knows NOTHING about aged care, telco, or any specific domain. It simply:
 *   1. Loads active Completeness_Rule__mdt records matching a record's object,
 *      record type, and trigger status.
 *   2. Evaluates each rule against the record.
 *   3. Returns a structured list of gaps (what's missing) with severity + message.
 *
 * All domain knowledge lives in the metadata rules — never in this class.
 * This is what makes the product scalable: ship the engine once, configure
 * forever.
 */
public with sharing class CompletenessEngine {

    /**
     * Represents one unmet requirement found on a record.
     * This is what gets returned to the agent / flow / UI.
     */
    public class CompletenessGap {
        @AuraEnabled public String ruleLabel;
        @AuraEnabled public String severity;
        @AuraEnabled public String message;
        @AuraEnabled public String actionIfMissing;
        @AuraEnabled public String regulatoryReference;

        public CompletenessGap(String ruleLabel, String severity, String message,
                               String actionIfMissing, String regulatoryReference) {
            this.ruleLabel = ruleLabel;
            this.severity = severity;
            this.message = message;
            this.actionIfMissing = actionIfMissing;
            this.regulatoryReference = regulatoryReference;
        }
    }

    /**
     * The result of a completeness check on a single record.
     */
    public class CompletenessResult {
        @AuraEnabled public Id recordId;
        @AuraEnabled public Boolean isComplete;
        @AuraEnabled public Integer gapCount;
        @AuraEnabled public List<CompletenessGap> gaps;

        public CompletenessResult(Id recordId) {
            this.recordId = recordId;
            this.gaps = new List<CompletenessGap>();
            this.isComplete = true;
            this.gapCount = 0;
        }

        public void addGap(CompletenessGap gap) {
            this.gaps.add(gap);
            this.isComplete = false;
            this.gapCount = this.gaps.size();
        }
    }

    /**
     * MAIN ENTRY POINT.
     * Evaluate a record against all matching active completeness rules.
     *
     * @param recordId       The record to check
     * @param triggerStatus  The status that triggered the check (e.g. "Submitted").
     *                       Pass null to evaluate all rules regardless of status.
     * @return               A CompletenessResult listing all gaps found.
     */
    public static CompletenessResult check(Id recordId, String triggerStatus) {
        CompletenessResult result = new CompletenessResult(recordId);

        // 1. Determine the object type from the record Id
        String objectApiName = recordId.getSObjectType().getDescribe().getName();

        // 2. Load matching active rules from metadata
        List<Completeness_Rule__mdt> rules = getMatchingRules(objectApiName, triggerStatus);
        if (rules.isEmpty()) {
            return result; // No rules = nothing to check = complete by default
        }

        // 3. Query the record with all fields we might need
        SObject record = queryRecord(recordId, objectApiName, rules);
        if (record == null) {
            return result;
        }

        // 4. Evaluate each rule
        for (Completeness_Rule__mdt rule : rules) {
            // Optional record-type filter
            if (!matchesRecordType(record, rule)) {
                continue;
            }
            // Optional condition gate
            if (!conditionApplies(record, rule)) {
                continue;
            }

            CompletenessGap gap = evaluateRule(record, rule);
            if (gap != null) {
                result.addGap(gap);
            }
        }

        return result;
    }

    /**
     * Load active rules matching the object and (optionally) trigger status.
     * CMDT queries do NOT count against SOQL governor limits — a key advantage.
     */
    private static List<Completeness_Rule__mdt> getMatchingRules(String objectApiName, String triggerStatus) {
        List<Completeness_Rule__mdt> matched = new List<Completeness_Rule__mdt>();
        for (Completeness_Rule__mdt rule : Completeness_Rule__mdt.getAll().values()) {
            if (rule.Active__c != true) continue;
            if (rule.Applies_To_Object__c != objectApiName) continue;
            // If a trigger status is specified on both sides, they must match
            if (triggerStatus != null
                && String.isNotBlank(rule.Trigger_Status__c)
                && rule.Trigger_Status__c != triggerStatus) {
                continue;
            }
            matched.add(rule);
        }
        return matched;
    }

    /**
     * Dynamically query the record, pulling every field referenced by the rules
     * plus RecordType.DeveloperName for filtering.
     */
    private static SObject queryRecord(Id recordId, String objectApiName, List<Completeness_Rule__mdt> rules) {
        Set<String> fields = new Set<String>{ 'Id' };
        Boolean hasRecordType = Schema.getGlobalDescribe()
            .get(objectApiName).getDescribe().fields.getMap().containsKey('recordtypeid');
        if (hasRecordType) {
            fields.add('RecordType.DeveloperName');
        }
        for (Completeness_Rule__mdt rule : rules) {
            if (String.isNotBlank(rule.Target_Field_API__c)) {
                fields.add(rule.Target_Field_API__c);
            }
            // Pull any field referenced in a simple condition (best-effort)
            if (String.isNotBlank(rule.Condition_Logic__c)) {
                for (String token : extractFieldTokens(rule.Condition_Logic__c, objectApiName)) {
                    fields.add(token);
                }
            }
        }
        String soql = 'SELECT ' + String.join(new List<String>(fields), ', ')
                    + ' FROM ' + objectApiName + ' WHERE Id = :recordId LIMIT 1';
        List<SObject> records = Database.query(soql);
        return records.isEmpty() ? null : records[0];
    }

    /**
     * Evaluate a single rule. Routes to the right check based on Rule_Type__c.
     */
    private static CompletenessGap evaluateRule(SObject record, Completeness_Rule__mdt rule) {
        String type = rule.Rule_Type__c;

        if (type == 'Field_Required') {
            Object val = getFieldValue(record, rule.Target_Field_API__c);
            Boolean missing = (val == null) || (val instanceof String && String.isBlank((String) val));
            return missing ? buildGap(rule) : null;
        }
        else if (type == 'Document_Required') {
            // Placeholder: real check would query ContentDocumentLink for the record.
            // Implemented in a dedicated method to keep the engine readable.
            return hasDocument(record.Id, rule.Required_Document_Type__c) ? null : buildGap(rule);
        }
        else if (type == 'Related_Record_Required') {
            // Placeholder for related-record existence checks.
            return buildGap(rule);
        }
        else if (type == 'Custom_Apex') {
            return runCustomApex(record, rule);
        }
        return null;
    }

    /**
     * The plugin escape hatch: instantiate the named Apex class and delegate.
     * This lets customers add complex logic WITHOUT touching the engine.
     */
    private static CompletenessGap runCustomApex(SObject record, Completeness_Rule__mdt rule) {
        if (String.isBlank(rule.Apex_Handler__c)) return null;
        try {
            Type handlerType = Type.forName(rule.Apex_Handler__c);
            if (handlerType == null) return null;
            CompletenessRuleProvider provider =
                (CompletenessRuleProvider) handlerType.newInstance();
            return provider.evaluate(record, rule);
        } catch (Exception e) {
            // Fail safe: a broken plugin should not crash the whole check
            System.debug(LoggingLevel.ERROR, 'Custom Apex rule failed: ' + e.getMessage());
            return null;
        }
    }

    // ---- Helpers ---------------------------------------------------------

    private static CompletenessGap buildGap(Completeness_Rule__mdt rule) {
        String msg = String.isNotBlank(rule.Gap_Message__c)
            ? rule.Gap_Message__c
            : 'Requirement not met: ' + rule.MasterLabel;
        return new CompletenessGap(
            rule.MasterLabel,
            rule.Severity__c,
            msg,
            rule.Action_If_Missing__c,
            rule.Regulatory_Reference__c
        );
    }

    private static Boolean matchesRecordType(SObject record, Completeness_Rule__mdt rule) {
        if (String.isBlank(rule.Applies_To_RecordType__c)) return true;
        try {
            SObject rt = record.getSObject('RecordType');
            if (rt == null) return false;
            return rule.Applies_To_RecordType__c == (String) rt.get('DeveloperName');
        } catch (Exception e) {
            return true; // If record type can't be read, don't block the rule
        }
    }

    /**
     * Very simple condition evaluator supporting: FIELD >= N, FIELD > N,
     * FIELD = VALUE. Kept deliberately minimal — complex logic goes to Custom_Apex.
     */
    private static Boolean conditionApplies(SObject record, Completeness_Rule__mdt rule) {
        String expr = rule.Condition_Logic__c;
        if (String.isBlank(expr)) return true;
        try {
            for (String op : new List<String>{ '>=', '<=', '!=', '>', '<', '=' }) {
                if (expr.contains(op)) {
                    String fieldName = expr.substringBefore(op).trim();
                    String rawVal = expr.substringAfter(op).trim();
                    Object fieldVal = getFieldValue(record, fieldName);
                    return compare(fieldVal, op, rawVal);
                }
            }
        } catch (Exception e) {
            return true; // On parse error, default to applying the rule
        }
        return true;
    }

    private static Boolean compare(Object fieldVal, String op, String rawVal) {
        if (fieldVal == null) return op == '=' && (rawVal == 'null' || rawVal == '');
        // Numeric comparison if both sides parse as numbers
        try {
            Decimal a = Decimal.valueOf(String.valueOf(fieldVal));
            Decimal b = Decimal.valueOf(rawVal);
            if (op == '>=') return a >= b;
            if (op == '<=') return a <= b;
            if (op == '>')  return a > b;
            if (op == '<')  return a < b;
            if (op == '!=') return a != b;
            return a == b;
        } catch (Exception e) {
            // String comparison fallback
            String a = String.valueOf(fieldVal);
            String b = rawVal.replaceAll('^[\'"]|[\'"]$', '');
            if (op == '!=') return a != b;
            return a == b;
        }
    }

    private static Object getFieldValue(SObject record, String fieldPath) {
        if (String.isBlank(fieldPath)) return null;
        try {
            return record.get(fieldPath);
        } catch (Exception e) {
            return null;
        }
    }

    private static Set<String> extractFieldTokens(String condition, String objectApiName) {
        Set<String> tokens = new Set<String>();
        for (String op : new List<String>{ '>=', '<=', '!=', '>', '<', '=' }) {
            if (condition.contains(op)) {
                String fieldName = condition.substringBefore(op).trim();
                Map<String, Schema.SObjectField> fmap =
                    Schema.getGlobalDescribe().get(objectApiName).getDescribe().fields.getMap();
                if (fmap.containsKey(fieldName.toLowerCase())) {
                    tokens.add(fieldName);
                }
                break;
            }
        }
        return tokens;
    }

    private static Boolean hasDocument(Id recordId, String docType) {
        // Checks whether any file is attached to the record.
        // A fuller implementation would match on docType/title.
        List<ContentDocumentLink> links = [
            SELECT Id FROM ContentDocumentLink WHERE LinkedEntityId = :recordId LIMIT 1
        ];
        return !links.isEmpty();
    }
}
