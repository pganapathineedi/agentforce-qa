// ============================================================
// Creates the 7 QA rules — v2
// FIX: labels <= 40 chars, and each rule deployed individually
// so one failure can't roll back the rest.
// ============================================================

// Reusable builder
Map<String, Map<String,Object>> ruleDefs = new Map<String, Map<String,Object>>();

ruleDefs.put('QFR_RN_Cost_Present', new Map<String,Object>{
    'label' => 'QFR - RN Labour Cost Present',
    'Applies_To_Object__c'=>'Form_Line_Item__c','Applies_To_RecordType__c'=>'Labour_Cost_Hours',
    'Rule_Type__c'=>'Field_Required','Applies_To_Line_Key__c'=>'RN_LABOUR_COST',
    'Severity__c'=>'High','Gap_Message__c'=>'Registered Nurse labour cost is required.','Active__c'=>true
});
ruleDefs.put('QFR_RN_Hours_Present', new Map<String,Object>{
    'label' => 'QFR - RN Hours Present',
    'Applies_To_Object__c'=>'Form_Line_Item__c','Applies_To_RecordType__c'=>'Labour_Cost_Hours',
    'Rule_Type__c'=>'Field_Required','Applies_To_Line_Key__c'=>'RN_HOURS',
    'Severity__c'=>'High','Gap_Message__c'=>'Registered Nurse worked hours are required.','Active__c'=>true
});
ruleDefs.put('QFR_Bed_Days_Present', new Map<String,Object>{
    'label' => 'QFR - Occupied Bed Days Present',
    'Applies_To_Object__c'=>'Form_Line_Item__c','Applies_To_RecordType__c'=>'Labour_Cost_Hours',
    'Rule_Type__c'=>'Field_Required','Applies_To_Line_Key__c'=>'OCCUPIED_BED_DAYS',
    'Severity__c'=>'Critical','Gap_Message__c'=>'Occupied bed days are required.','Active__c'=>true
});
ruleDefs.put('QFR_RN_Rate_Reconcile', new Map<String,Object>{
    'label' => 'QFR - RN Rate Reconciliation',
    'Applies_To_Object__c'=>'Form_Line_Item__c','Applies_To_RecordType__c'=>'Labour_Cost_Hours',
    'Rule_Type__c'=>'Reconciliation','Reconciliation_Expression__c'=>'RN_LABOUR_COST / RN_HOURS = RN_IMPLIED_RATE',
    'Tolerance_Percent__c'=>5,'Severity__c'=>'Medium',
    'Gap_Message__c'=>'Reported RN implied rate does not match cost divided by hours.','Active__c'=>true
});
ruleDefs.put('QFR_Total_Hours_Reconcile', new Map<String,Object>{
    'label' => 'QFR - Total Hours Reconciliation',
    'Applies_To_Object__c'=>'Form_Line_Item__c','Applies_To_RecordType__c'=>'Labour_Cost_Hours',
    'Rule_Type__c'=>'Reconciliation','Reconciliation_Expression__c'=>'RN_HOURS + EN_HOURS + PCW_HOURS = TOTAL_HOURS',
    'Tolerance_Percent__c'=>1,'Severity__c'=>'High',
    'Gap_Message__c'=>'Worker-type hours do not sum to declared total hours.','Active__c'=>true
});
ruleDefs.put('QFR_RN_Rate_Plausibility', new Map<String,Object>{
    'label' => 'QFR - RN Hourly Rate Plausibility',
    'Applies_To_Object__c'=>'Form_Line_Item__c','Applies_To_RecordType__c'=>'Labour_Cost_Hours',
    'Rule_Type__c'=>'Plausibility','Plausibility_Metric__c'=>'RN_LABOUR_COST / RN_HOURS',
    'Expected_Range_Low__c'=>38,'Expected_Range_High__c'=>75,
    'Sector_Benchmark__c'=>'RN award minimum approx $38/hr; above $75/hr unusual for aged care.',
    'Compare_To_Prior__c'=>true,'Prior_Variance_Threshold__c'=>15,'Severity__c'=>'Medium',
    'Gap_Message__c'=>'RN implied hourly rate is outside the expected award range.','Active__c'=>true
});
ruleDefs.put('QFR_Cost_Per_Bed_Day', new Map<String,Object>{
    'label' => 'QFR - Cost Per Bed Day',
    'Applies_To_Object__c'=>'Form_Line_Item__c','Applies_To_RecordType__c'=>'Labour_Cost_Hours',
    'Rule_Type__c'=>'Plausibility','Plausibility_Metric__c'=>'TOTAL_LABOUR_COST / OCCUPIED_BED_DAYS',
    'Expected_Range_Low__c'=>80,'Expected_Range_High__c'=>250,
    'Sector_Benchmark__c'=>'Typical daily labour cost per bed day approx $80-$250.',
    'Severity__c'=>'Medium',
    'Gap_Message__c'=>'Labour cost per occupied bed day is outside the expected range.','Active__c'=>true
});

// Deploy each rule in its OWN container so one failure cannot block others
Integer queued = 0;
for (String devName : ruleDefs.keySet()) {
    Map<String,Object> def = ruleDefs.get(devName);
    Metadata.CustomMetadata cmd = new Metadata.CustomMetadata();
    cmd.fullName = 'Completeness_Rule.' + devName;
    cmd.label = (String) def.get('label');
    // Safety: enforce 40-char limit
    if (cmd.label.length() > 40) cmd.label = cmd.label.substring(0,40);

    for (String f : def.keySet()) {
        if (f == 'label') continue;
        Metadata.CustomMetadataValue v = new Metadata.CustomMetadataValue();
        v.field = f;
        v.value = def.get(f);
        cmd.values.add(v);
    }
    Metadata.DeployContainer container = new Metadata.DeployContainer();
    container.addMetadata(cmd);
    Metadata.Operations.enqueueDeployment(container, null);
    queued++;
}
System.debug('Queued ' + queued + ' individual rule deployments.');
