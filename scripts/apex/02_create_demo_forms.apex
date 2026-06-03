// ============================================================
// Creates TWO labour-cost forms with line items:
//   FORM A = "good"  — all valid, should return PASS
//   FORM B = "flawed"— deliberate errors, should return FAIL
// Then runs the QA engine on both and prints the verdicts.
// ============================================================

// Get the Labour Cost & Hours record type for Form__c
Id rtId = Schema.SObjectType.Form__c.getRecordTypeInfosByDeveloperName()
            .get('Labour_Cost_Hours').getRecordTypeId();

// ---------- FORM A: GOOD ----------
Form__c formA = new Form__c(
    Form_Type__c = 'Labour Cost and Hours',
    Form_Status__c = 'Submitted',
    RecordTypeId = rtId
);
insert formA;

List<Form_Line_Item__c> linesA = new List<Form_Line_Item__c>{
    // RN: cost 100000 / hours 2500 = $40/hr (within 38-75) GOOD
    new Form_Line_Item__c(Form__c=formA.Id, Line_Key__c='RN_LABOUR_COST', Line_Type__c='Currency', Value_Currency__c=100000, Prior_Value_Number__c=98000),
    new Form_Line_Item__c(Form__c=formA.Id, Line_Key__c='RN_HOURS', Line_Type__c='Number', Value_Number__c=2500, Prior_Value_Number__c=2480),
    new Form_Line_Item__c(Form__c=formA.Id, Line_Key__c='RN_IMPLIED_RATE', Line_Type__c='Number', Value_Number__c=40),
    new Form_Line_Item__c(Form__c=formA.Id, Line_Key__c='EN_HOURS', Line_Type__c='Number', Value_Number__c=1800),
    new Form_Line_Item__c(Form__c=formA.Id, Line_Key__c='PCW_HOURS', Line_Type__c='Number', Value_Number__c=5700),
    new Form_Line_Item__c(Form__c=formA.Id, Line_Key__c='TOTAL_HOURS', Line_Type__c='Number', Value_Number__c=10000),
    new Form_Line_Item__c(Form__c=formA.Id, Line_Key__c='TOTAL_LABOUR_COST', Line_Type__c='Currency', Value_Currency__c=450000),
    new Form_Line_Item__c(Form__c=formA.Id, Line_Key__c='OCCUPIED_BED_DAYS', Line_Type__c='Number', Value_Number__c=3000)
    // 450000/3000 = $150/bed-day (within 80-250) GOOD
};
insert linesA;

// ---------- FORM B: FLAWED ----------
Form__c formB = new Form__c(
    Form_Type__c = 'Labour Cost and Hours',
    Form_Status__c = 'Submitted',
    RecordTypeId = rtId
);
insert formB;

List<Form_Line_Item__c> linesB = new List<Form_Line_Item__c>{
    // RN: cost 80000 / hours 2500 = $32/hr (BELOW $38 award floor) -> plausibility FLAG
    new Form_Line_Item__c(Form__c=formB.Id, Line_Key__c='RN_LABOUR_COST', Line_Type__c='Currency', Value_Currency__c=80000, Prior_Value_Number__c=98000),
    new Form_Line_Item__c(Form__c=formB.Id, Line_Key__c='RN_HOURS', Line_Type__c='Number', Value_Number__c=2500, Prior_Value_Number__c=2480),
    new Form_Line_Item__c(Form__c=formB.Id, Line_Key__c='RN_IMPLIED_RATE', Line_Type__c='Number', Value_Number__c=40), // says 40 but actual is 32 -> reconciliation FAIL
    new Form_Line_Item__c(Form__c=formB.Id, Line_Key__c='EN_HOURS', Line_Type__c='Number', Value_Number__c=1800),
    new Form_Line_Item__c(Form__c=formB.Id, Line_Key__c='PCW_HOURS', Line_Type__c='Number', Value_Number__c=5700),
    new Form_Line_Item__c(Form__c=formB.Id, Line_Key__c='TOTAL_HOURS', Line_Type__c='Number', Value_Number__c=12000) // 2500+1800+5700=10000, not 12000 -> reconciliation FAIL
    // NOTE: OCCUPIED_BED_DAYS deliberately MISSING -> completeness Critical -> FAIL
};
insert linesB;

// ---------- Run the engine on both ----------
QAEngine.QAResult resA = QAEngine.assessForm(formA.Id);
QAEngine.QAResult resB = QAEngine.assessForm(formB.Id);

System.debug('================ FORM A (GOOD) ================');
System.debug('Form A Id: ' + formA.Id);
System.debug('VERDICT: ' + resA.verdict);
System.debug('Findings: ' + resA.findings.size() + ' | Plausibility facts: ' + resA.plausibilityFacts.size());
for (QAEngine.QAFinding f : resA.findings) System.debug('  FINDING [' + f.severity + '/' + f.checkType + '] ' + f.message);
for (QAEngine.PlausibilityFact pf : resA.plausibilityFacts) System.debug('  PLAUS: ' + pf.metricName + ' = ' + pf.computedValue + ' | outsideRange=' + pf.outsideRange + ' | priorSwing=' + pf.priorSwingExceeded);

System.debug('================ FORM B (FLAWED) ================');
System.debug('Form B Id: ' + formB.Id);
System.debug('VERDICT: ' + resB.verdict);
System.debug('Findings: ' + resB.findings.size() + ' | Plausibility facts: ' + resB.plausibilityFacts.size());
for (QAEngine.QAFinding f : resB.findings) System.debug('  FINDING [' + f.severity + '/' + f.checkType + '] ' + f.message + ' | ' + f.detail);
for (QAEngine.PlausibilityFact pf : resB.plausibilityFacts) System.debug('  PLAUS: ' + pf.metricName + ' = ' + pf.computedValue + ' | outsideRange=' + pf.outsideRange + ' | priorSwing=' + pf.priorSwingExceeded);

System.debug('================ DEMO IDS ================');
System.debug('GOOD FORM ID:   ' + formA.Id);
System.debug('FLAWED FORM ID: ' + formB.Id);
