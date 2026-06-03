/**
 * QAEngineTest
 * ------------
 * Tests the QA engine end-to-end against a Form with line items.
 * Builds a labour-cost form, creates line items, and verifies the engine
 * produces findings, plausibility facts, and a verdict.
 *
 * Note: these tests exercise the engine plumbing. They create their own form
 * and line items; rule evaluation depends on the Completeness_Rule__mdt records
 * deployed in the org.
 */
@isTest
private class QAEngineTest {

    @isTest
    static void testAssessFormReturnsResult() {
        Form__c form = new Form__c(Form_Type__c = 'Labour Cost and Hours', Form_Status__c = 'Submitted');
        insert form;

        // A couple of line items the rules might reference
        List<Form_Line_Item__c> lines = new List<Form_Line_Item__c>{
            new Form_Line_Item__c(Form__c = form.Id, Line_Key__c = 'RN_LABOUR_COST',
                Line_Type__c = 'Currency', Value_Currency__c = 100000),
            new Form_Line_Item__c(Form__c = form.Id, Line_Key__c = 'RN_HOURS',
                Line_Type__c = 'Number', Value_Number__c = 2500)
        };
        insert lines;

        Test.startTest();
        QAEngine.QAResult result = QAEngine.assessForm(form.Id);
        Test.stopTest();

        System.assertNotEquals(null, result, 'Result should never be null');
        System.assertEquals(form.Id, result.formId, 'Result references the form');
        System.assert(
            result.verdict == 'Pass' || result.verdict == 'Flag' || result.verdict == 'Fail',
            'Verdict must be one of Pass/Flag/Fail, got ' + result.verdict);
    }

    @isTest
    static void testInvocableActionRuns() {
        Form__c form = new Form__c(Form_Type__c = 'Labour Cost and Hours', Form_Status__c = 'Submitted');
        insert form;

        QACheckAction.Request req = new QACheckAction.Request();
        req.formId = form.Id;

        Test.startTest();
        List<QACheckAction.Response> responses =
            QACheckAction.run(new List<QACheckAction.Request>{ req });
        Test.stopTest();

        System.assertEquals(1, responses.size(), 'One response per request');
        System.assertNotEquals(null, responses[0].verdict, 'Verdict populated');
        System.assertNotEquals(null, responses[0].findingsSummary, 'Findings summary populated');
        System.assertNotEquals(null, responses[0].plausibilityFacts, 'Plausibility facts populated');
    }

    @isTest
    static void testResultStructures() {
        Form__c form = new Form__c(Form_Type__c = 'Labour Cost and Hours');
        insert form;

        QAEngine.QAResult result = new QAEngine.QAResult(form.Id);
        System.assertEquals('Pass', result.verdict, 'Fresh result defaults to Pass');

        QAEngine.QAFinding finding = new QAEngine.QAFinding(
            'Test Rule', 'Reconciliation', 'High', 'Does not reconcile', 'A=1 B=2', 'Ref');
        result.findings.add(finding);
        System.assertEquals(1, result.findings.size(), 'Finding added');

        QAEngine.PlausibilityFact fact = new QAEngine.PlausibilityFact('Rate Rule', 'RN_COST / RN_HOURS');
        fact.computedValue = 40;
        result.plausibilityFacts.add(fact);
        System.assertEquals(1, result.plausibilityFacts.size(), 'Plausibility fact added');
    }
}
