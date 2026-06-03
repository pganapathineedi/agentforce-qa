/**
 * CompletenessRuleProvider
 * -------------------------
 * Plugin interface for complex completeness rules that cannot be expressed
 * declaratively in Completeness_Rule__mdt.
 *
 * A customer's developer implements this interface in their own Apex class,
 * then references the class name in the Apex_Handler__c field of a
 * Completeness_Rule__mdt record (with Rule_Type__c = Custom_Apex).
 *
 * The core engine never changes. All custom domain logic lives in
 * implementations of this interface — the "escape hatch" that keeps the
 * product infinitely extensible.
 */
public interface CompletenessRuleProvider {
    /**
     * Evaluate a single record against this custom rule.
     * @param record   The SObject being checked (e.g. a Case)
     * @param rule      The Completeness_Rule__mdt record driving this check
     * @return          A CompletenessGap if the requirement is NOT met,
     *                  or null if the requirement IS satisfied.
     */
    CompletenessEngine.CompletenessGap evaluate(SObject record, Completeness_Rule__mdt rule);
}
