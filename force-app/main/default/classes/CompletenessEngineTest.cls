/**
 * CompletenessEngineTest
 * ----------------------
 * Unit tests for the completeness engine and invocable action.
 * Note: tests use the Case standard object. Because the engine reads rules
 * from Custom Metadata (which exist in the org), these tests validate the
 * engine plumbing end-to-end against whatever rules are deployed.
 */
@isTest
private class CompletenessEngineTest {

    @isTest
    static void testCheckReturnsResultForCase() {
        // Create a minimal Case
        Case c = new Case(Subject = 'Test Case', Status = 'New');
        insert c;

        Test.startTest();
        CompletenessEngine.CompletenessResult result =
            CompletenessEngine.check(c.Id, 'Submitted');
        Test.stopTest();

        // The engine must always return a non-null result with the right record Id
        System.assertNotEquals(null, result, 'Result should never be null');
        System.assertEquals(c.Id, result.recordId, 'Result should reference the checked record');
        System.assertNotEquals(null, result.gaps, 'Gaps list should be initialised');
    }

    @isTest
    static void testInvocableActionRuns() {
        Case c = new Case(Subject = 'Invocable Test', Status = 'New');
        insert c;

        CompletenessCheckAction.Request req = new CompletenessCheckAction.Request();
        req.recordId = c.Id;
        req.triggerStatus = 'Submitted';

        Test.startTest();
        List<CompletenessCheckAction.Response> responses =
            CompletenessCheckAction.run(new List<CompletenessCheckAction.Request>{ req });
        Test.stopTest();

        System.assertEquals(1, responses.size(), 'One response per request');
        System.assertNotEquals(null, responses[0].summary, 'Summary should be populated');
        System.assertNotEquals(null, responses[0].gapsJson, 'Gaps JSON should be populated');
    }

    @isTest
    static void testCompleteResultSummary() {
        // A result with no gaps should report as complete
        Case c = new Case(Subject = 'Complete Test', Status = 'New');
        insert c;

        CompletenessEngine.CompletenessResult result =
            new CompletenessEngine.CompletenessResult(c.Id);
        System.assertEquals(true, result.isComplete, 'New result starts complete');
        System.assertEquals(0, result.gapCount, 'New result has zero gaps');

        // Add a gap and confirm state flips
        result.addGap(new CompletenessEngine.CompletenessGap(
            'Test Rule', 'Critical', 'Missing thing', 'Flag_Only', 'Ref'));
        System.assertEquals(false, result.isComplete, 'Result with a gap is incomplete');
        System.assertEquals(1, result.gapCount, 'Gap count should be 1');
    }
}
