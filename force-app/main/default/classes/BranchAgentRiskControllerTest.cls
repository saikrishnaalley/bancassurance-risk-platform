@isTest
private class BranchAgentRiskControllerTest {

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
    static void testGetRiskSummary_OpenCaseExists_ReturnsFlaggedSummary() {
        Household__c household = new Household__c(Name = 'Household CUST-000123');
        insert household;
        insert new Risk_Case__c(
            Customer_Key__c = 'CUST-000123', Household__c = household.Id,
            Status__c = 'New', Risk_Score__c = 3, Flagged_Date__c = System.now()
        );

        System.runAs(getRunAsUser()) {
            Test.startTest();
            BranchAgentRiskController.RiskSummary summary = BranchAgentRiskController.getRiskSummary(household.Id);
            Test.stopTest();

            System.assertEquals(true, summary.isFlagged);
            System.assertEquals(3, summary.riskScore);
            System.assertEquals('New', summary.status);
            System.assert(summary.suggestedAction.contains('extra identity verification'));
        }
    }

    @isTest
    static void testGetRiskSummary_NoOpenCase_ReturnsNotFlagged() {
        Household__c household = new Household__c(Name = 'Household CUST-000456');
        insert household;

        System.runAs(getRunAsUser()) {
            Test.startTest();
            BranchAgentRiskController.RiskSummary summary = BranchAgentRiskController.getRiskSummary(household.Id);
            Test.stopTest();

            System.assertEquals(false, summary.isFlagged);
            System.assertEquals(null, summary.riskCaseId);
        }
    }

    @isTest
    static void testGetRiskSummary_OnlyClosedCasesExist_ReturnsNotFlagged() {
        Household__c household = new Household__c(Name = 'Household CUST-000789');
        insert household;
        insert new Risk_Case__c(
            Customer_Key__c = 'CUST-000789', Household__c = household.Id,
            Status__c = 'False Positive', Risk_Score__c = 5, Flagged_Date__c = System.now()
        );

        System.runAs(getRunAsUser()) {
            Test.startTest();
            BranchAgentRiskController.RiskSummary summary = BranchAgentRiskController.getRiskSummary(household.Id);
            Test.stopTest();

            System.assertEquals(false, summary.isFlagged, 'A closed case should not surface as an active flag');
        }
    }

    @isTest
    static void testGetRiskSummary_NullId_ReturnsNotFlaggedWithoutError() {
        System.runAs(getRunAsUser()) {
            Test.startTest();
            BranchAgentRiskController.RiskSummary summary = BranchAgentRiskController.getRiskSummary(null);
            Test.stopTest();

            System.assertEquals(false, summary.isFlagged);
        }
    }

    @isTest
    static void testBuildSuggestedAction_ScoreThresholds() {
        System.assertEquals(
            'Verify identity carefully before proceeding. Escalate to the fraud team now.',
            BranchAgentRiskController.buildSuggestedAction(4)
        );
        System.assertEquals(
            'Verify identity carefully before proceeding. Escalate to the fraud team now.',
            BranchAgentRiskController.buildSuggestedAction(5)
        );
        System.assert(BranchAgentRiskController.buildSuggestedAction(2).contains('extra identity verification'));
        System.assert(BranchAgentRiskController.buildSuggestedAction(3).contains('extra identity verification'));
        System.assertEquals(
            'Proceed normally, and escalate if anything seems unusual.',
            BranchAgentRiskController.buildSuggestedAction(1)
        );
        System.assertEquals(
            'Proceed normally, and escalate if anything seems unusual.',
            BranchAgentRiskController.buildSuggestedAction(null)
        );
    }

    @isTest
    static void testEscalateToAnalyst_HappyPath_UpdatesStatus() {
        Household__c household = new Household__c(Name = 'Household CUST-001111');
        insert household;
        Risk_Case__c riskCase = new Risk_Case__c(
            Customer_Key__c = 'CUST-001111', Household__c = household.Id,
            Status__c = 'New', Risk_Score__c = 1, Flagged_Date__c = System.now()
        );
        insert riskCase;

        System.runAs(getRunAsUser()) {
            Test.startTest();
            BranchAgentRiskController.escalateToAnalyst(riskCase.Id);
            Test.stopTest();

            Risk_Case__c updated = [SELECT Status__c FROM Risk_Case__c WHERE Id = :riskCase.Id];
            System.assertEquals('Under Investigation', updated.Status__c);
        }
    }

    @isTest
    static void testEscalateToAnalyst_NonExistentId_ThrowsException() {
        Risk_Case__c riskCase = new Risk_Case__c(
            Customer_Key__c = 'CUST-002222', Status__c = 'New', Risk_Score__c = 1, Flagged_Date__c = System.now()
        );
        insert riskCase;
        Id deletedId = riskCase.Id;
        delete riskCase;

        Boolean exceptionThrown = false;
        System.runAs(getRunAsUser()) {
            Test.startTest();
            try {
                BranchAgentRiskController.escalateToAnalyst(deletedId);
            } catch (AuraHandledException e) {
                exceptionThrown = true;
            }
            Test.stopTest();
        }
        System.assertEquals(true, exceptionThrown);
    }

    @isTest
    static void testGetRiskSummary_BulkHouseholdsAtFiftyRecords() {
        List<Household__c> households = new List<Household__c>();
        for (Integer i = 0; i < 50; i++) {
            households.add(new Household__c(Name = 'Household BULK-' + i));
        }
        insert households;

        List<Risk_Case__c> cases = new List<Risk_Case__c>();
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

        System.runAs(getRunAsUser()) {
            Test.startTest();
            for (Household__c h : households) {
                BranchAgentRiskController.RiskSummary summary = BranchAgentRiskController.getRiskSummary(h.Id);
                System.assertEquals(true, summary.isFlagged);
            }
            Test.stopTest();
        }
    }
}
