@isTest
private class RiskCaseSummaryActionTest {

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
    static void testGetSummaryContext_HappyPath_ReturnsFullContext() {
        Household__c household = new Household__c(Name = 'Household CUST-000123');
        insert household;

        Risk_Case__c riskCase = new Risk_Case__c(
            Customer_Key__c = 'CUST-000123',
            Household__c = household.Id,
            Status__c = 'New',
            Risk_Score__c = 3,
            Flagged_Date__c = System.now(),
            Risk_Reason_Summary__c = 'Flagged by Bancassurance_Risk_Score Calculated Insight (composite score = 3)'
        );
        insert riskCase;

        insert new Financial_Account__c(
            Household__c = household.Id, Customer_Key__c = 'CUST-000123',
            Account_Type__c = 'Checking', Balance__c = 1500.75
        );
        insert new Insurance_Policy__c(
            Household__c = household.Id, Customer_Key__c = 'CUST-000123',
            Policy_Type__c = 'Auto', Vehicle_Category__c = 'Sedan',
            Fraud_Flag__c = true, Claim_Date__c = Date.newInstance(2026, 4, 1)
        );

        RiskCaseSummaryAction.RiskCaseSummaryRequest req = new RiskCaseSummaryAction.RiskCaseSummaryRequest();
        req.riskCaseId = riskCase.Id;

        System.runAs(getRunAsUser()) {
            Test.startTest();
            List<RiskCaseSummaryAction.RiskCaseSummaryContext> results = RiskCaseSummaryAction.getSummaryContext(
                new List<RiskCaseSummaryAction.RiskCaseSummaryRequest>{ req }
            );
            Test.stopTest();

            System.assertEquals(1, results.size());
            RiskCaseSummaryAction.RiskCaseSummaryContext ctx = results[0];
            System.assertEquals('CUST-000123', ctx.customerKey);
            System.assertEquals('Household CUST-000123', ctx.householdName);
            System.assertEquals(3, ctx.riskScore);
            System.assertEquals('New', ctx.status);
            System.assertEquals('Checking', ctx.accountType);
            System.assertEquals(1500.75, ctx.accountBalance);
            System.assertEquals('Auto', ctx.policyType);
            System.assertEquals('Sedan', ctx.vehicleCategory);
            System.assertEquals(true, ctx.insuranceFraudFlag);
            System.assertEquals(Date.newInstance(2026, 4, 1), ctx.claimDate);
        }
    }

    @isTest
    static void testGetSummaryContext_NoLinkedAccountOrPolicy_ReturnsCaseFieldsOnly() {
        Risk_Case__c riskCase = new Risk_Case__c(
            Customer_Key__c = 'CUST-000456',
            Status__c = 'New',
            Risk_Score__c = 1,
            Flagged_Date__c = System.now()
        );
        insert riskCase;

        RiskCaseSummaryAction.RiskCaseSummaryRequest req = new RiskCaseSummaryAction.RiskCaseSummaryRequest();
        req.riskCaseId = riskCase.Id;

        System.runAs(getRunAsUser()) {
            Test.startTest();
            List<RiskCaseSummaryAction.RiskCaseSummaryContext> results = RiskCaseSummaryAction.getSummaryContext(
                new List<RiskCaseSummaryAction.RiskCaseSummaryRequest>{ req }
            );
            Test.stopTest();

            System.assertEquals(1, results.size());
            System.assertEquals('CUST-000456', results[0].customerKey);
            System.assertEquals(null, results[0].householdName);
            System.assertEquals(null, results[0].accountType);
            System.assertEquals(null, results[0].policyType);
        }
    }

    @isTest
    static void testGetSummaryContext_NullOrMissingId_ReturnsBlankContextWithoutError() {
        RiskCaseSummaryAction.RiskCaseSummaryRequest reqWithNullId = new RiskCaseSummaryAction.RiskCaseSummaryRequest();
        reqWithNullId.riskCaseId = null;

        System.runAs(getRunAsUser()) {
            Test.startTest();
            List<RiskCaseSummaryAction.RiskCaseSummaryContext> results = RiskCaseSummaryAction.getSummaryContext(
                new List<RiskCaseSummaryAction.RiskCaseSummaryRequest>{ reqWithNullId }
            );
            Test.stopTest();

            System.assertEquals(1, results.size(), 'A request is still returned, just with blank fields, to preserve request/response order');
            System.assertEquals(null, results[0].customerKey);
        }
    }

    @isTest
    static void testGetSummaryContext_EmptyOrNullRequestList_ReturnsEmptyResults() {
        System.runAs(getRunAsUser()) {
            Test.startTest();
            List<RiskCaseSummaryAction.RiskCaseSummaryContext> emptyResults = RiskCaseSummaryAction.getSummaryContext(
                new List<RiskCaseSummaryAction.RiskCaseSummaryRequest>()
            );
            List<RiskCaseSummaryAction.RiskCaseSummaryContext> nullResults = RiskCaseSummaryAction.getSummaryContext(null);
            Test.stopTest();

            System.assertEquals(0, emptyResults.size());
            System.assertEquals(0, nullResults.size());
        }
    }

    @isTest
    static void testGetSummaryContext_NonExistentId_ReturnsBlankContextWithoutError() {
        Risk_Case__c riskCase = new Risk_Case__c(
            Customer_Key__c = 'CUST-000789', Status__c = 'New', Risk_Score__c = 1, Flagged_Date__c = System.now()
        );
        insert riskCase;
        Id deletedId = riskCase.Id;
        delete riskCase;

        RiskCaseSummaryAction.RiskCaseSummaryRequest req = new RiskCaseSummaryAction.RiskCaseSummaryRequest();
        req.riskCaseId = deletedId;

        System.runAs(getRunAsUser()) {
            Test.startTest();
            List<RiskCaseSummaryAction.RiskCaseSummaryContext> results = RiskCaseSummaryAction.getSummaryContext(
                new List<RiskCaseSummaryAction.RiskCaseSummaryRequest>{ req }
            );
            Test.stopTest();

            System.assertEquals(1, results.size());
            System.assertEquals(null, results[0].customerKey);
        }
    }

    @isTest
    static void testGetSummaryContext_MalformedIdString_SkippedSafelyWithoutError() {
        RiskCaseSummaryAction.RiskCaseSummaryRequest req = new RiskCaseSummaryAction.RiskCaseSummaryRequest();
        req.riskCaseId = 'not-a-real-id';

        System.runAs(getRunAsUser()) {
            Test.startTest();
            List<RiskCaseSummaryAction.RiskCaseSummaryContext> results = RiskCaseSummaryAction.getSummaryContext(
                new List<RiskCaseSummaryAction.RiskCaseSummaryRequest>{ req }
            );
            Test.stopTest();

            System.assertEquals(1, results.size(), 'A malformed Id string should still produce a blank result, not throw');
            System.assertEquals(null, results[0].customerKey);
        }
    }

    @isTest
    static void testGetSummaryContext_BulkAtFiftyRequests() {
        List<Household__c> households = new List<Household__c>();
        for (Integer i = 0; i < 50; i++) {
            households.add(new Household__c(Name = 'Household BULK-' + i));
        }
        insert households;

        List<Risk_Case__c> cases = new List<Risk_Case__c>();
        List<Financial_Account__c> accounts = new List<Financial_Account__c>();
        for (Integer i = 0; i < 50; i++) {
            cases.add(new Risk_Case__c(
                Customer_Key__c = 'BULK-CUST-' + i,
                Household__c = households[i].Id,
                Status__c = 'New',
                Risk_Score__c = Math.mod(i, 5) + 1,
                Flagged_Date__c = System.now()
            ));
        }
        insert cases;

        for (Integer i = 0; i < 50; i++) {
            accounts.add(new Financial_Account__c(
                Household__c = households[i].Id,
                Customer_Key__c = 'BULK-CUST-' + i,
                Account_Type__c = 'Checking',
                Balance__c = 100 * i
            ));
        }
        insert accounts;

        List<RiskCaseSummaryAction.RiskCaseSummaryRequest> requests = new List<RiskCaseSummaryAction.RiskCaseSummaryRequest>();
        for (Risk_Case__c rc : cases) {
            RiskCaseSummaryAction.RiskCaseSummaryRequest req = new RiskCaseSummaryAction.RiskCaseSummaryRequest();
            req.riskCaseId = rc.Id;
            requests.add(req);
        }

        System.runAs(getRunAsUser()) {
            Test.startTest();
            List<RiskCaseSummaryAction.RiskCaseSummaryContext> results = RiskCaseSummaryAction.getSummaryContext(requests);
            Test.stopTest();

            System.assertEquals(50, results.size());
            for (RiskCaseSummaryAction.RiskCaseSummaryContext ctx : results) {
                System.assertNotEquals(null, ctx.customerKey);
                System.assertEquals('Checking', ctx.accountType);
            }
        }
    }
}