@isTest
private class RiskCaseServiceTest {

    // Stub resolver: since Data Cloud external objects can't be seeded with synthetic data,
    // this stub simulates CustomerKeyResolver's behavior with an identity mapping (each fake
    // "unified id" used in these tests resolves to itself as the "raw key"), except where a
    // test specifically wants to exercise the unresolved/skipped path.
    private class StubResolver implements ICustomerKeyResolver {
        private Set<String> unresolvableIds = new Set<String>();

        public StubResolver() {
        }

        public StubResolver(Set<String> unresolvableIds) {
            this.unresolvableIds = unresolvableIds;
        }

        public Map<String, String> resolveRawCustomerKeys(Set<String> unifiedIndividualIds) {
            Map<String, String> result = new Map<String, String>();
            if (unifiedIndividualIds == null) {
                return result;
            }
            for (String id : unifiedIndividualIds) {
                if (!unresolvableIds.contains(id)) {
                    result.put(id, id);
                }
            }
            return result;
        }
    }

    @isTest
    static void testHappyPath_NewCustomer_CreatesRiskCase() {
        RiskCaseService.keyResolver = new StubResolver();

        RiskCaseService.RiskSignalRequest req = new RiskCaseService.RiskSignalRequest();
        req.customerKey = 'CUST-0001';
        req.riskScore = 3.5;
        req.riskReasonSummary = 'Banking anomaly + suspiciously-timed claim';

        Test.startTest();
        List<RiskCaseService.RiskSignalResult> results = RiskCaseService.createOrUpdateRiskCase(
            new List<RiskCaseService.RiskSignalRequest>{ req }
        );
        Test.stopTest();

        System.assertEquals(1, results.size(), 'Expected exactly one result for one request');
        System.assertEquals(true, results[0].wasCreated, 'A brand-new customer key should create a new case');

        Risk_Case__c saved = [SELECT Customer_Key__c, Risk_Score__c, Status__c, Risk_Reason_Summary__c FROM Risk_Case__c WHERE Id = :results[0].riskCaseId];
        System.assertEquals('CUST-0001', saved.Customer_Key__c);
        System.assertEquals(3.5, saved.Risk_Score__c);
        System.assertEquals('New', saved.Status__c);
        System.assertEquals('Banking anomaly + suspiciously-timed claim', saved.Risk_Reason_Summary__c);
    }

    @isTest
    static void testExistingOpenCase_UpdatesInPlaceInsteadOfDuplicating() {
        RiskCaseService.keyResolver = new StubResolver();

        Risk_Case__c existing = new Risk_Case__c(
            Customer_Key__c = 'CUST-0002',
            Status__c = 'Under Investigation',
            Risk_Score__c = 1,
            Flagged_Date__c = System.now().addDays(-1)
        );
        insert existing;

        RiskCaseService.RiskSignalRequest req = new RiskCaseService.RiskSignalRequest();
        req.customerKey = 'CUST-0002';
        req.riskScore = 5;

        Test.startTest();
        List<RiskCaseService.RiskSignalResult> results = RiskCaseService.createOrUpdateRiskCase(
            new List<RiskCaseService.RiskSignalRequest>{ req }
        );
        Test.stopTest();

        System.assertEquals(false, results[0].wasCreated, 'An open case for the same customer should be updated, not duplicated');
        System.assertEquals(existing.Id, results[0].riskCaseId);

        List<Risk_Case__c> allCasesForCustomer = [SELECT Id, Risk_Score__c FROM Risk_Case__c WHERE Customer_Key__c = 'CUST-0002'];
        System.assertEquals(1, allCasesForCustomer.size(), 'Should still be exactly one case for this customer');
        System.assertEquals(5, allCasesForCustomer[0].Risk_Score__c);
    }

    @isTest
    static void testClosedCaseIsIgnored_NewSignalCreatesFreshCase() {
        RiskCaseService.keyResolver = new StubResolver();

        Risk_Case__c closed = new Risk_Case__c(
            Customer_Key__c = 'CUST-0003',
            Status__c = 'Confirmed Fraud',
            Risk_Score__c = 8,
            Flagged_Date__c = System.now().addDays(-30)
        );
        insert closed;

        RiskCaseService.RiskSignalRequest req = new RiskCaseService.RiskSignalRequest();
        req.customerKey = 'CUST-0003';
        req.riskScore = 2;

        Test.startTest();
        List<RiskCaseService.RiskSignalResult> results = RiskCaseService.createOrUpdateRiskCase(
            new List<RiskCaseService.RiskSignalRequest>{ req }
        );
        Test.stopTest();

        System.assertEquals(true, results[0].wasCreated, 'A closed prior case should not block a new case from being created');

        List<Risk_Case__c> allCasesForCustomer = [SELECT Id, Status__c FROM Risk_Case__c WHERE Customer_Key__c = 'CUST-0003'];
        System.assertEquals(2, allCasesForCustomer.size(), 'The closed case and the new case should both exist');
    }

    @isTest
    static void testLinksHouseholdFromMatchingFinancialAccount() {
        RiskCaseService.keyResolver = new StubResolver();

        Household__c household = new Household__c(Name = 'Test Household');
        insert household;

        Financial_Account__c account = new Financial_Account__c(
            Customer_Key__c = 'CUST-0004',
            Household__c = household.Id,
            Account_Type__c = 'Checking'
        );
        insert account;

        RiskCaseService.RiskSignalRequest req = new RiskCaseService.RiskSignalRequest();
        req.customerKey = 'CUST-0004';
        req.riskScore = 4;

        Test.startTest();
        List<RiskCaseService.RiskSignalResult> results = RiskCaseService.createOrUpdateRiskCase(
            new List<RiskCaseService.RiskSignalRequest>{ req }
        );
        Test.stopTest();

        Risk_Case__c saved = [SELECT Household__c FROM Risk_Case__c WHERE Id = :results[0].riskCaseId];
        System.assertEquals(household.Id, saved.Household__c);
    }

    @isTest
    static void testBlankOrNullInputsAreSkippedWithoutError() {
        RiskCaseService.keyResolver = new StubResolver();

        RiskCaseService.RiskSignalRequest blankKey = new RiskCaseService.RiskSignalRequest();
        blankKey.customerKey = '';
        blankKey.riskScore = 5;

        RiskCaseService.RiskSignalRequest nullScore = new RiskCaseService.RiskSignalRequest();
        nullScore.customerKey = 'CUST-0005';
        nullScore.riskScore = null;

        RiskCaseService.RiskSignalRequest valid = new RiskCaseService.RiskSignalRequest();
        valid.customerKey = 'CUST-0006';
        valid.riskScore = 6;

        Test.startTest();
        List<RiskCaseService.RiskSignalResult> results = RiskCaseService.createOrUpdateRiskCase(
            new List<RiskCaseService.RiskSignalRequest>{ blankKey, nullScore, valid }
        );
        Test.stopTest();

        System.assertEquals(1, results.size(), 'Only the valid request should produce a result');
        System.assertEquals(0, [SELECT COUNT() FROM Risk_Case__c WHERE Customer_Key__c = 'CUST-0005']);
        System.assertEquals(1, [SELECT COUNT() FROM Risk_Case__c WHERE Customer_Key__c = 'CUST-0006']);
    }

    @isTest
    static void testBelowThresholdScoreIsSkipped_NoRiskCaseCreated() {
        RiskCaseService.keyResolver = new StubResolver();

        RiskCaseService.RiskSignalRequest belowThreshold = new RiskCaseService.RiskSignalRequest();
        belowThreshold.customerKey = 'CUST-0007';
        belowThreshold.riskScore = 0.5;

        Test.startTest();
        List<RiskCaseService.RiskSignalResult> results = RiskCaseService.createOrUpdateRiskCase(
            new List<RiskCaseService.RiskSignalRequest>{ belowThreshold }
        );
        Test.stopTest();

        System.assertEquals(0, results.size(), 'A below-threshold score should produce no result and no Risk_Case__c');
        System.assertEquals(0, [SELECT COUNT() FROM Risk_Case__c WHERE Customer_Key__c = 'CUST-0007']);
    }

    @isTest
    static void testUnresolvableCustomerKey_IsSkippedWithoutError() {
        // Simulates a Unified Individual Id that the bridge table has no match for
        // (e.g. a data lag, or an id that never made it into Identity Resolution).
        RiskCaseService.keyResolver = new StubResolver(new Set<String>{ 'CUST-UNRESOLVABLE' });

        RiskCaseService.RiskSignalRequest req = new RiskCaseService.RiskSignalRequest();
        req.customerKey = 'CUST-UNRESOLVABLE';
        req.riskScore = 3;

        Test.startTest();
        List<RiskCaseService.RiskSignalResult> results = RiskCaseService.createOrUpdateRiskCase(
            new List<RiskCaseService.RiskSignalRequest>{ req }
        );
        Test.stopTest();

        System.assertEquals(0, results.size(), 'An unresolvable customer key should be skipped, not stored with a blank/wrong key');
        System.assertEquals(0, [SELECT COUNT() FROM Risk_Case__c WHERE Customer_Key__c = 'CUST-UNRESOLVABLE']);
    }

    @isTest
    static void testEmptyOrNullRequestListReturnsEmptyResults() {
        RiskCaseService.keyResolver = new StubResolver();

        Test.startTest();
        List<RiskCaseService.RiskSignalResult> emptyListResults = RiskCaseService.createOrUpdateRiskCase(
            new List<RiskCaseService.RiskSignalRequest>()
        );
        List<RiskCaseService.RiskSignalResult> nullResults = RiskCaseService.createOrUpdateRiskCase(null);
        Test.stopTest();

        System.assertEquals(0, emptyListResults.size());
        System.assertEquals(0, nullResults.size());
    }

    @isTest
    static void testBulkAtGovernorLimitBoundary_TwoHundredUniqueCustomers() {
        RiskCaseService.keyResolver = new StubResolver();

        List<RiskCaseService.RiskSignalRequest> requests = new List<RiskCaseService.RiskSignalRequest>();
        for (Integer i = 0; i < 200; i++) {
            RiskCaseService.RiskSignalRequest req = new RiskCaseService.RiskSignalRequest();
            req.customerKey = 'BULK-CUST-' + i;
            // 1-10, always at or above RISK_SCORE_THRESHOLD so all 200 requests qualify.
            req.riskScore = Math.mod(i, 10) + 1;
            requests.add(req);
        }

        Test.startTest();
        List<RiskCaseService.RiskSignalResult> results = RiskCaseService.createOrUpdateRiskCase(requests);
        Test.stopTest();

        System.assertEquals(200, results.size());
        System.assertEquals(200, [SELECT COUNT() FROM Risk_Case__c WHERE Customer_Key__c LIKE 'BULK-CUST-%']);
    }
}
