@isTest
private class RiskCaseResolutionActionTest {

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
    static void testResolveRiskCase_ByRiskCaseId_HappyPath_UpdatesStatus() {
        Risk_Case__c rc = new Risk_Case__c(Customer_Key__c = 'CUST-0001', Status__c = 'New', Risk_Score__c = 3, Flagged_Date__c = System.now());
        insert rc;

        RiskCaseResolutionAction.ResolutionRequest req = new RiskCaseResolutionAction.ResolutionRequest();
        req.riskCaseId = rc.Id;
        req.newStatus = 'Confirmed Fraud';

        System.runAs(getRunAsUser()) {
            Test.startTest();
            List<RiskCaseResolutionAction.ResolutionResult> results = RiskCaseResolutionAction.resolveRiskCase(
                new List<RiskCaseResolutionAction.ResolutionRequest>{ req }
            );
            Test.stopTest();

            System.assertEquals(true, results[0].success);
            System.assertEquals(rc.Id, results[0].riskCaseId);

            Risk_Case__c updated = [SELECT Status__c FROM Risk_Case__c WHERE Id = :rc.Id];
            System.assertEquals('Confirmed Fraud', updated.Status__c);
        }
    }

    @isTest
    static void testResolveRiskCase_ByCustomerKey_HappyPath_UpdatesStatus() {
        Risk_Case__c rc = new Risk_Case__c(Customer_Key__c = 'CUST-0002', Status__c = 'New', Risk_Score__c = 1, Flagged_Date__c = System.now());
        insert rc;

        RiskCaseResolutionAction.ResolutionRequest req = new RiskCaseResolutionAction.ResolutionRequest();
        req.customerKey = 'CUST-0002';
        req.newStatus = 'False Positive';

        System.runAs(getRunAsUser()) {
            Test.startTest();
            List<RiskCaseResolutionAction.ResolutionResult> results = RiskCaseResolutionAction.resolveRiskCase(
                new List<RiskCaseResolutionAction.ResolutionRequest>{ req }
            );
            Test.stopTest();

            System.assertEquals(true, results[0].success, 'Lookup by Customer Key alone should succeed');
            Risk_Case__c updated = [SELECT Status__c FROM Risk_Case__c WHERE Id = :rc.Id];
            System.assertEquals('False Positive', updated.Status__c);
        }
    }

    @isTest
    static void testResolveRiskCase_InvalidStatus_FailsWithoutUpdatingRecord() {
        Risk_Case__c rc = new Risk_Case__c(Customer_Key__c = 'CUST-0003', Status__c = 'New', Risk_Score__c = 1, Flagged_Date__c = System.now());
        insert rc;

        RiskCaseResolutionAction.ResolutionRequest req = new RiskCaseResolutionAction.ResolutionRequest();
        req.riskCaseId = rc.Id;
        req.newStatus = 'Not A Real Status';

        System.runAs(getRunAsUser()) {
            Test.startTest();
            List<RiskCaseResolutionAction.ResolutionResult> results = RiskCaseResolutionAction.resolveRiskCase(
                new List<RiskCaseResolutionAction.ResolutionRequest>{ req }
            );
            Test.stopTest();

            System.assertEquals(false, results[0].success);
            System.assert(results[0].message.contains('Invalid status'));

            Risk_Case__c unchanged = [SELECT Status__c FROM Risk_Case__c WHERE Id = :rc.Id];
            System.assertEquals('New', unchanged.Status__c, 'Status should remain unchanged after a rejected update');
        }
    }

    @isTest
    static void testResolveRiskCase_NoMatchingCase_FailsGracefully() {
        RiskCaseResolutionAction.ResolutionRequest req = new RiskCaseResolutionAction.ResolutionRequest();
        req.customerKey = 'CUST-DOES-NOT-EXIST';
        req.newStatus = 'Confirmed Fraud';

        System.runAs(getRunAsUser()) {
            Test.startTest();
            List<RiskCaseResolutionAction.ResolutionResult> results = RiskCaseResolutionAction.resolveRiskCase(
                new List<RiskCaseResolutionAction.ResolutionRequest>{ req }
            );
            Test.stopTest();

            System.assertEquals(false, results[0].success);
            System.assert(results[0].message.contains('No matching Risk Case found'));
        }
    }

    @isTest
    static void testResolveRiskCase_EmptyOrNullRequestList_ReturnsEmptyResults() {
        System.runAs(getRunAsUser()) {
            Test.startTest();
            List<RiskCaseResolutionAction.ResolutionResult> emptyResults = RiskCaseResolutionAction.resolveRiskCase(
                new List<RiskCaseResolutionAction.ResolutionRequest>()
            );
            List<RiskCaseResolutionAction.ResolutionResult> nullResults = RiskCaseResolutionAction.resolveRiskCase(null);
            Test.stopTest();

            System.assertEquals(0, emptyResults.size());
            System.assertEquals(0, nullResults.size());
        }
    }

    @isTest
    static void testResolveRiskCase_MixedValidAndInvalidRequests_HandlesIndependently() {
        Risk_Case__c validCase = new Risk_Case__c(Customer_Key__c = 'CUST-0005', Status__c = 'New', Risk_Score__c = 1, Flagged_Date__c = System.now());
        insert validCase;

        RiskCaseResolutionAction.ResolutionRequest goodReq = new RiskCaseResolutionAction.ResolutionRequest();
        goodReq.riskCaseId = validCase.Id;
        goodReq.newStatus = 'Needs More Info';

        RiskCaseResolutionAction.ResolutionRequest badReq = new RiskCaseResolutionAction.ResolutionRequest();
        badReq.customerKey = 'DOES-NOT-EXIST';
        badReq.newStatus = 'New';

        System.runAs(getRunAsUser()) {
            Test.startTest();
            List<RiskCaseResolutionAction.ResolutionResult> results = RiskCaseResolutionAction.resolveRiskCase(
                new List<RiskCaseResolutionAction.ResolutionRequest>{ goodReq, badReq }
            );
            Test.stopTest();

            System.assertEquals(2, results.size());
            System.assertEquals(true, results[0].success);
            System.assertEquals(false, results[1].success);
        }
    }

    @isTest
    static void testResolveRiskCase_BulkAtFiftyRequests() {
        List<Risk_Case__c> cases = new List<Risk_Case__c>();
        for (Integer i = 0; i < 50; i++) {
            cases.add(new Risk_Case__c(Customer_Key__c = 'BULK-' + i, Status__c = 'New', Risk_Score__c = 1, Flagged_Date__c = System.now()));
        }
        insert cases;

        List<RiskCaseResolutionAction.ResolutionRequest> requests = new List<RiskCaseResolutionAction.ResolutionRequest>();
        for (Risk_Case__c rc : cases) {
            RiskCaseResolutionAction.ResolutionRequest req = new RiskCaseResolutionAction.ResolutionRequest();
            req.riskCaseId = rc.Id;
            req.newStatus = 'Under Investigation';
            requests.add(req);
        }

        System.runAs(getRunAsUser()) {
            Test.startTest();
            List<RiskCaseResolutionAction.ResolutionResult> results = RiskCaseResolutionAction.resolveRiskCase(requests);
            Test.stopTest();

            System.assertEquals(50, results.size());
            for (RiskCaseResolutionAction.ResolutionResult r : results) {
                System.assertEquals(true, r.success);
            }
            System.assertEquals(50, [SELECT COUNT() FROM Risk_Case__c WHERE Status__c = 'Under Investigation' AND Customer_Key__c LIKE 'BULK-%']);
        }
    }
}
