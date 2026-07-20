@isTest
private class RiskCaseQueryActionTest {

    @TestSetup
    static void setupRunAsUser() {
        User u = new User(
            FirstName = 'RunAs',
            LastName = 'TestUser',
            Email = 'runas.testuser@bancassurance.test.invalid',
            Username = 'runas.testuser@bancassurance.test.invalid.' + Crypto.getRandomInteger(),
            Alias = 'runau',
            TimeZoneSidKey = 'America/Los_Angeles',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            ProfileId = UserInfo.getProfileId()
        );
        insert u;
    }

    private static User getRunAsUser() {
        return [SELECT Id FROM User WHERE LastName = 'TestUser' AND FirstName = 'RunAs' LIMIT 1];
    }

    @isTest
    static void testQueryOpenCases_HappyPath_ReturnsOnlyOpenSortedByScoreDesc() {
        insert new Risk_Case__c(Customer_Key__c = 'C1', Status__c = 'New', Risk_Score__c = 1, Flagged_Date__c = System.now());
        insert new Risk_Case__c(Customer_Key__c = 'C2', Status__c = 'Under Investigation', Risk_Score__c = 5, Flagged_Date__c = System.now());
        insert new Risk_Case__c(Customer_Key__c = 'C3', Status__c = 'Confirmed Fraud', Risk_Score__c = 8, Flagged_Date__c = System.now());

        RiskCaseQueryAction.RiskCaseQueryRequest req = new RiskCaseQueryAction.RiskCaseQueryRequest();

        System.runAs(getRunAsUser()) {
            Test.startTest();
            List<RiskCaseQueryAction.RiskCaseQueryResult> results = RiskCaseQueryAction.queryOpenCases(
                new List<RiskCaseQueryAction.RiskCaseQueryRequest>{ req }
            );
            Test.stopTest();

            System.assertEquals(1, results.size());
            RiskCaseQueryAction.RiskCaseQueryResult result = results[0];
            System.assertEquals(2, result.totalOpenCases, 'Only the 2 open-status cases should count, not the closed one');
            System.assertEquals(2, result.cases.size());
            System.assertEquals('C2', result.cases[0].customerKey, 'Highest score among open cases should sort first');
        }
    }

    @isTest
    static void testQueryOpenCases_MaxResultsCapsReturnedList_ButNotTotalCount() {
        for (Integer i = 0; i < 10; i++) {
            insert new Risk_Case__c(Customer_Key__c = 'C' + i, Status__c = 'New', Risk_Score__c = i, Flagged_Date__c = System.now());
        }

        RiskCaseQueryAction.RiskCaseQueryRequest req = new RiskCaseQueryAction.RiskCaseQueryRequest();
        req.maxResults = 3;

        System.runAs(getRunAsUser()) {
            Test.startTest();
            List<RiskCaseQueryAction.RiskCaseQueryResult> results = RiskCaseQueryAction.queryOpenCases(
                new List<RiskCaseQueryAction.RiskCaseQueryRequest>{ req }
            );
            Test.stopTest();

            System.assertEquals(3, results[0].cases.size(), 'Returned list should be capped to maxResults');
            System.assertEquals(10, results[0].totalOpenCases, 'Total count should reflect all open cases, not just the capped page');
        }
    }

    @isTest
    static void testQueryOpenCases_MinRiskScoreFilter_OnlyReturnsMatchingCases() {
        insert new Risk_Case__c(Customer_Key__c = 'LOW', Status__c = 'New', Risk_Score__c = 1, Flagged_Date__c = System.now());
        insert new Risk_Case__c(Customer_Key__c = 'HIGH', Status__c = 'New', Risk_Score__c = 5, Flagged_Date__c = System.now());

        RiskCaseQueryAction.RiskCaseQueryRequest req = new RiskCaseQueryAction.RiskCaseQueryRequest();
        req.minRiskScore = 3;

        System.runAs(getRunAsUser()) {
            Test.startTest();
            List<RiskCaseQueryAction.RiskCaseQueryResult> results = RiskCaseQueryAction.queryOpenCases(
                new List<RiskCaseQueryAction.RiskCaseQueryRequest>{ req }
            );
            Test.stopTest();

            System.assertEquals(1, results[0].totalOpenCases);
            System.assertEquals('HIGH', results[0].cases[0].customerKey);
        }
    }

    @isTest
    static void testQueryOpenCases_NoOpenCases_ReturnsEmptyResultWithZeroCount() {
        insert new Risk_Case__c(Customer_Key__c = 'C1', Status__c = 'Confirmed Fraud', Risk_Score__c = 5, Flagged_Date__c = System.now());

        RiskCaseQueryAction.RiskCaseQueryRequest req = new RiskCaseQueryAction.RiskCaseQueryRequest();

        System.runAs(getRunAsUser()) {
            Test.startTest();
            List<RiskCaseQueryAction.RiskCaseQueryResult> results = RiskCaseQueryAction.queryOpenCases(
                new List<RiskCaseQueryAction.RiskCaseQueryRequest>{ req }
            );
            Test.stopTest();

            System.assertEquals(0, results[0].totalOpenCases);
            System.assertEquals(0, results[0].cases.size());
        }
    }

    @isTest
    static void testQueryOpenCases_EmptyRequestList_UsesDefaults() {
        insert new Risk_Case__c(Customer_Key__c = 'C1', Status__c = 'New', Risk_Score__c = 1, Flagged_Date__c = System.now());

        System.runAs(getRunAsUser()) {
            Test.startTest();
            List<RiskCaseQueryAction.RiskCaseQueryResult> results = RiskCaseQueryAction.queryOpenCases(
                new List<RiskCaseQueryAction.RiskCaseQueryRequest>()
            );
            Test.stopTest();

            System.assertEquals(1, results.size(), 'An empty request list should still produce one result using default parameters');
            System.assertEquals(1, results[0].totalOpenCases);
        }
    }

    @isTest
    static void testQueryOpenCases_MaxResultsCappedAtFifty() {
        List<Risk_Case__c> cases = new List<Risk_Case__c>();
        for (Integer i = 0; i < 60; i++) {
            cases.add(new Risk_Case__c(Customer_Key__c = 'BULK-' + i, Status__c = 'New', Risk_Score__c = Math.mod(i, 5) + 1, Flagged_Date__c = System.now()));
        }
        insert cases;

        RiskCaseQueryAction.RiskCaseQueryRequest req = new RiskCaseQueryAction.RiskCaseQueryRequest();
        req.maxResults = 1000;

        System.runAs(getRunAsUser()) {
            Test.startTest();
            List<RiskCaseQueryAction.RiskCaseQueryResult> results = RiskCaseQueryAction.queryOpenCases(
                new List<RiskCaseQueryAction.RiskCaseQueryRequest>{ req }
            );
            Test.stopTest();

            System.assertEquals(50, results[0].cases.size(), 'Even an oversized maxResults request should be capped at 50');
            System.assertEquals(60, results[0].totalOpenCases);
        }
    }

    @isTest
    static void testBuildResult_NullMatches_ReturnsEmptyCasesListWithoutError() {
        Test.startTest();
        RiskCaseQueryAction.RiskCaseQueryResult result = RiskCaseQueryAction.buildResult(null, 0);
        Test.stopTest();

        System.assertEquals(0, result.cases.size());
        System.assertEquals(0, result.totalOpenCases);
    }
}
