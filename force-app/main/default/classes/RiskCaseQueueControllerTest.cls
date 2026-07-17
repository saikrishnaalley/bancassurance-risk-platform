@isTest
private class RiskCaseQueueControllerTest {

    @isTest
    static void testGetOpenRiskCases_ReturnsOnlyOpenStatuses_OrderedByScoreDesc() {
        insert new Risk_Case__c(Customer_Key__c = 'CUST-A', Risk_Score__c = 1, Status__c = 'New', Flagged_Date__c = System.now());
        insert new Risk_Case__c(Customer_Key__c = 'CUST-B', Risk_Score__c = 5, Status__c = 'Under Investigation', Flagged_Date__c = System.now());
        insert new Risk_Case__c(Customer_Key__c = 'CUST-C', Risk_Score__c = 3, Status__c = 'Needs More Info', Flagged_Date__c = System.now());
        // Closed cases should never appear in the queue.
        insert new Risk_Case__c(Customer_Key__c = 'CUST-D', Risk_Score__c = 8, Status__c = 'Confirmed Fraud', Flagged_Date__c = System.now());
        insert new Risk_Case__c(Customer_Key__c = 'CUST-E', Risk_Score__c = 8, Status__c = 'False Positive', Flagged_Date__c = System.now());

        Test.startTest();
        List<RiskCaseQueueController.RiskCaseRecord> results = RiskCaseQueueController.getOpenRiskCases();
        Test.stopTest();

        System.assertEquals(3, results.size(), 'Only the 3 open-status cases should be returned');
        System.assertEquals('CUST-B', results[0].customerKey, 'Highest score (5) should sort first');
        System.assertEquals('CUST-C', results[1].customerKey, 'Score 3 should sort second');
        System.assertEquals('CUST-A', results[2].customerKey, 'Score 1 should sort last');
    }

    @isTest
    static void testGetOpenRiskCases_IncludesHouseholdNameWhenLinked() {
        Household__c household = new Household__c(Name = 'Test Household');
        insert household;

        insert new Risk_Case__c(
            Customer_Key__c = 'CUST-F',
            Risk_Score__c = 2,
            Status__c = 'New',
            Flagged_Date__c = System.now(),
            Household__c = household.Id
        );

        Test.startTest();
        List<RiskCaseQueueController.RiskCaseRecord> results = RiskCaseQueueController.getOpenRiskCases();
        Test.stopTest();

        System.assertEquals(1, results.size());
        System.assertEquals('Test Household', results[0].householdName);
    }

    @isTest
    static void testGetOpenRiskCases_NoHousehold_HouseholdNameIsNull() {
        insert new Risk_Case__c(Customer_Key__c = 'CUST-G', Risk_Score__c = 1, Status__c = 'New', Flagged_Date__c = System.now());

        Test.startTest();
        List<RiskCaseQueueController.RiskCaseRecord> results = RiskCaseQueueController.getOpenRiskCases();
        Test.stopTest();

        System.assertEquals(1, results.size());
        System.assertEquals(null, results[0].householdName);
    }

    @isTest
    static void testGetOpenRiskCases_NoOpenCases_ReturnsEmptyList() {
        insert new Risk_Case__c(Customer_Key__c = 'CUST-H', Risk_Score__c = 1, Status__c = 'Confirmed Fraud', Flagged_Date__c = System.now());

        Test.startTest();
        List<RiskCaseQueueController.RiskCaseRecord> results = RiskCaseQueueController.getOpenRiskCases();
        Test.stopTest();

        System.assertEquals(0, results.size());
    }

    @isTest
    static void testResolveRiskCase_HappyPath_UpdatesStatus() {
        Risk_Case__c rc = new Risk_Case__c(Customer_Key__c = 'CUST-I', Risk_Score__c = 3, Status__c = 'New', Flagged_Date__c = System.now());
        insert rc;

        Test.startTest();
        RiskCaseQueueController.resolveRiskCase(rc.Id, 'Confirmed Fraud');
        Test.stopTest();

        Risk_Case__c updated = [SELECT Status__c FROM Risk_Case__c WHERE Id = :rc.Id];
        System.assertEquals('Confirmed Fraud', updated.Status__c);
    }

    @isTest
    static void testResolveRiskCase_InvalidStatus_ThrowsException() {
        Risk_Case__c rc = new Risk_Case__c(Customer_Key__c = 'CUST-J', Risk_Score__c = 3, Status__c = 'New', Flagged_Date__c = System.now());
        insert rc;

        Boolean exceptionThrown = false;
        Test.startTest();
        try {
            RiskCaseQueueController.resolveRiskCase(rc.Id, 'Not A Real Status');
        } catch (AuraHandledException e) {
            exceptionThrown = true;
        }
        Test.stopTest();

        System.assertEquals(true, exceptionThrown, 'An invalid status value should throw an AuraHandledException');

        Risk_Case__c unchanged = [SELECT Status__c FROM Risk_Case__c WHERE Id = :rc.Id];
        System.assertEquals('New', unchanged.Status__c, 'Status should remain unchanged after a rejected update');
    }

    @isTest
    static void testResolveRiskCase_NonExistentId_ThrowsException() {
        // Delete a case immediately after creating it to get a well-formed but non-existent Id.
        Risk_Case__c rc = new Risk_Case__c(Customer_Key__c = 'CUST-K', Risk_Score__c = 1, Status__c = 'New', Flagged_Date__c = System.now());
        insert rc;
        Id deletedId = rc.Id;
        delete rc;

        Boolean exceptionThrown = false;
        Test.startTest();
        try {
            RiskCaseQueueController.resolveRiskCase(deletedId, 'False Positive');
        } catch (AuraHandledException e) {
            exceptionThrown = true;
        }
        Test.stopTest();

        System.assertEquals(true, exceptionThrown, 'A non-existent Risk_Case__c Id should throw an AuraHandledException');
    }

    @isTest
    static void testGetOpenRiskCases_BulkAtQueryLimitBoundary() {
        List<Risk_Case__c> bulkCases = new List<Risk_Case__c>();
        for (Integer i = 0; i < 250; i++) {
            bulkCases.add(new Risk_Case__c(
                Customer_Key__c = 'BULK-CUST-' + i,
                Risk_Score__c = Math.mod(i, 6),
                Status__c = 'New',
                Flagged_Date__c = System.now()
            ));
        }
        insert bulkCases;

        Test.startTest();
        List<RiskCaseQueueController.RiskCaseRecord> results = RiskCaseQueueController.getOpenRiskCases();
        Test.stopTest();

        System.assertEquals(200, results.size(), 'Query LIMIT 200 should cap the returned records even when more exist');
        for (Integer i = 0; i < results.size() - 1; i++) {
            System.assert(
                results[i].riskScore >= results[i + 1].riskScore,
                'Results must remain sorted by risk score descending across the full page'
            );
        }
    }
}
