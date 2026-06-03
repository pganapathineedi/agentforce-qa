// ============================================================
// Verification script — run after deploying + creating data.
// Confirms rules exist and runs the QA engine on the demo forms.
// Run via: Developer Console > Debug > Open Execute Anonymous Window
//          (tick "Open Log", then filter to "Debug Only")
// ============================================================

// 1. List all QA rules the engine can see
Integer ruleCount = 0;
for (Completeness_Rule__mdt r : Completeness_Rule__mdt.getAll().values()) {
    if (r.Applies_To_Object__c == 'Form_Line_Item__c') {
        System.debug('QA RULE: ' + r.MasterLabel + ' | ' + r.Rule_Type__c);
        ruleCount++;
    }
}
System.debug('TOTAL QA RULES: ' + ruleCount);

// 2. Assess the two most recent forms (good + flawed)
List<Form__c> forms = [SELECT Id, Form_Type__c FROM Form__c ORDER BY CreatedDate DESC LIMIT 2];
for (Form__c f : forms) {
    QAEngine.QAResult r = QAEngine.assessForm(f.Id);
    System.debug('FORM ' + f.Id + ' -> VERDICT: ' + r.verdict
        + ' | findings: ' + r.findings.size()
        + ' | plausibility facts: ' + r.plausibilityFacts.size());
}
