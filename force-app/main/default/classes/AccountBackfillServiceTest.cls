@isTest
private class AccountBackfillServiceTest {

    // Same limitation as CustomerKeyResolverTest: this service queries Data Cloud external
    // objects (Banking_Transaction__dlm, Insurance_Claim__dlm, UnifiedLinkssotIndividualRisk__dlm)
    // directly, which cannot be seeded with synthetic data in a standard @isTest context and
    // have no local mocking framework. Only the boundary/input-handling logic is unit-testable
    // here. The actual backfill behavior against real data must be verified via Execute
    // Anonymous in the org -- see the Build Guide's verification steps for the exact script
    // and expected results.

    @isTest
    static void testBackfill_NullInput_ReturnsEmptyResultWithoutError() {
        Test.startTest();
        AccountBackfillService.BackfillResult result = AccountBackfillService.backfillForUnifiedIndividualIds(null);
        Test.stopTest();

        System.assertEquals(0, result.householdsCreated);
        System.assertEquals(0, result.financialAccountsCreated);
        System.assertEquals(0, result.insurancePoliciesCreated);
        System.assertEquals(0, result.skippedRawKeys.size());
    }

    @isTest
    static void testBackfill_EmptySet_ReturnsEmptyResultWithoutError() {
        Test.startTest();
        AccountBackfillService.BackfillResult result = AccountBackfillService.backfillForUnifiedIndividualIds(new Set<String>());
        Test.stopTest();

        System.assertEquals(0, result.householdsCreated);
        System.assertEquals(0, result.financialAccountsCreated);
        System.assertEquals(0, result.insurancePoliciesCreated);
    }
}
