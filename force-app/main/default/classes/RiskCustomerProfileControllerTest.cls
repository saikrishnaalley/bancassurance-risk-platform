@isTest
private class RiskCustomerProfileControllerTest {

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
    static void testGetCustomerProfile_HappyPath_ReturnsAccountsAndPolicies() {
        Household__c household = new Household__c(Name = 'Household CUST-000123');
        insert household;

        Risk_Case__c riskCase = new Risk_Case__c(
            Customer_Key__c = 'CUST-000123',
            Household__c = household.Id,
            Status__c = 'New',
            Risk_Score__c = 1,
            Flagged_Date__c = System.now()
        );
        insert riskCase;

        insert new Financial_Account__c(
            Household__c = household.Id,
            Customer_Key__c = 'CUST-000123',
            Account_Number__c = 'ACCT-CUST-000123',
            Account_Type__c = 'Checking',
            Balance__c = 4321.50
        );
        insert new Insurance_Policy__c(
            Household__c = household.Id,
            Customer_Key__c = 'CUST-000123',
            Policy_Number__c = '5551',
            Policy_Type__c = 'Auto',
            Vehicle_Category__c = 'Sedan',
            Fraud_Flag__c = false,
            Claim_Date__c = Date.newInstance(2026, 4, 1)
        );

        System.runAs(getRunAsUser()) {
            Test.startTest();
            RiskCustomerProfileController.CustomerProfile profile =
                RiskCustomerProfileController.getCustomerProfile(riskCase.Id);
            Test.stopTest();

            System.assertEquals('Household CUST-000123', profile.householdName);
            System.assertEquals('CUST-000123', profile.customerKey);
            System.assertEquals(1, profile.accounts.size());
            System.assertEquals('ACCT-CUST-000123', profile.accounts[0].accountNumber);
            System.assertEquals(4321.50, profile.accounts[0].balance);
            System.assertEquals(1, profile.policies.size());
            System.assertEquals('5551', profile.policies[0].policyNumber);
            System.assertEquals(false, profile.policies[0].fraudFlag);
            System.assertEquals(Date.newInstance(2026, 4, 1), profile.policies[0].claimDate);
        }
    }

    @isTest
    static void testGetCustomerProfile_NoLinkedHousehold_ReturnsEmptyProfile() {
        Risk_Case__c riskCase = new Risk_Case__c(
            Customer_Key__c = 'CUST-999999',
            Status__c = 'New',
            Risk_Score__c = 1,
            Flagged_Date__c = System.now()
        );
        insert riskCase;

        System.runAs(getRunAsUser()) {
            Test.startTest();
            RiskCustomerProfileController.CustomerProfile profile =
                RiskCustomerProfileController.getCustomerProfile(riskCase.Id);
            Test.stopTest();

            System.assertEquals(null, profile.householdName);
            System.assertEquals(0, profile.accounts.size());
            System.assertEquals(0, profile.policies.size());
        }
    }

    @isTest
    static void testGetCustomerProfile_NullId_ReturnsEmptyProfileWithoutError() {
        System.runAs(getRunAsUser()) {
            Test.startTest();
            RiskCustomerProfileController.CustomerProfile profile =
                RiskCustomerProfileController.getCustomerProfile(null);
            Test.stopTest();

            System.assertEquals(0, profile.accounts.size());
            System.assertEquals(0, profile.policies.size());
        }
    }

    @isTest
    static void testGetCustomerProfile_NonExistentId_ReturnsEmptyProfileWithoutError() {
        Risk_Case__c riskCase = new Risk_Case__c(
            Customer_Key__c = 'CUST-000456',
            Status__c = 'New',
            Risk_Score__c = 1,
            Flagged_Date__c = System.now()
        );
        insert riskCase;
        Id deletedId = riskCase.Id;
        delete riskCase;

        System.runAs(getRunAsUser()) {
            Test.startTest();
            RiskCustomerProfileController.CustomerProfile profile =
                RiskCustomerProfileController.getCustomerProfile(deletedId);
            Test.stopTest();

            System.assertEquals(null, profile.householdName);
            System.assertEquals(0, profile.accounts.size());
        }
    }

    @isTest
    static void testGetCustomerProfile_PoliciesSortedChronologicallyMostRecentFirst() {
        Household__c household = new Household__c(Name = 'Household CUST-000999');
        insert household;

        Risk_Case__c riskCase = new Risk_Case__c(
            Customer_Key__c = 'CUST-000999',
            Household__c = household.Id,
            Status__c = 'New',
            Risk_Score__c = 1,
            Flagged_Date__c = System.now()
        );
        insert riskCase;

        insert new List<Insurance_Policy__c>{
            new Insurance_Policy__c(
                Household__c = household.Id, Customer_Key__c = 'CUST-000999',
                Policy_Number__c = 'OLDEST', Policy_Type__c = 'Auto',
                Claim_Date__c = Date.newInstance(2024, 1, 1)
            ),
            new Insurance_Policy__c(
                Household__c = household.Id, Customer_Key__c = 'CUST-000999',
                Policy_Number__c = 'NEWEST', Policy_Type__c = 'Auto',
                Claim_Date__c = Date.newInstance(2026, 6, 1)
            ),
            new Insurance_Policy__c(
                Household__c = household.Id, Customer_Key__c = 'CUST-000999',
                Policy_Number__c = 'MIDDLE', Policy_Type__c = 'Auto',
                Claim_Date__c = Date.newInstance(2025, 3, 1)
            )
        };

        System.runAs(getRunAsUser()) {
            Test.startTest();
            RiskCustomerProfileController.CustomerProfile profile =
                RiskCustomerProfileController.getCustomerProfile(riskCase.Id);
            Test.stopTest();

            System.assertEquals(3, profile.policies.size());
            System.assertEquals('NEWEST', profile.policies[0].policyNumber, 'Most recent claim date should sort first');
            System.assertEquals('MIDDLE', profile.policies[1].policyNumber);
            System.assertEquals('OLDEST', profile.policies[2].policyNumber, 'Oldest claim date should sort last');
        }
    }

    @isTest
    static void testGetCustomerProfile_MultipleAccountsAndPolicies_ReturnsAll() {
        Household__c household = new Household__c(Name = 'Household CUST-000789');
        insert household;

        Risk_Case__c riskCase = new Risk_Case__c(
            Customer_Key__c = 'CUST-000789',
            Household__c = household.Id,
            Status__c = 'New',
            Risk_Score__c = 2,
            Flagged_Date__c = System.now()
        );
        insert riskCase;

        List<Financial_Account__c> accounts = new List<Financial_Account__c>();
        List<Insurance_Policy__c> policies = new List<Insurance_Policy__c>();
        for (Integer i = 0; i < 5; i++) {
            accounts.add(new Financial_Account__c(
                Household__c = household.Id,
                Customer_Key__c = 'CUST-000789',
                Account_Number__c = 'ACCT-' + i,
                Account_Type__c = 'Checking',
                Balance__c = 100 * i
            ));
            policies.add(new Insurance_Policy__c(
                Household__c = household.Id,
                Customer_Key__c = 'CUST-000789',
                Policy_Number__c = String.valueOf(i),
                Policy_Type__c = 'Auto',
                Vehicle_Category__c = 'Sedan',
                Fraud_Flag__c = Math.mod(i, 2) == 0
            ));
        }
        insert accounts;
        insert policies;

        System.runAs(getRunAsUser()) {
            Test.startTest();
            RiskCustomerProfileController.CustomerProfile profile =
                RiskCustomerProfileController.getCustomerProfile(riskCase.Id);
            Test.stopTest();

            System.assertEquals(5, profile.accounts.size());
            System.assertEquals(5, profile.policies.size());
        }
    }

    @isTest
    static void testGetCustomerProfile_BulkAtFiftyAccountsAndPolicies() {
        Household__c household = new Household__c(Name = 'Household CUST-000555');
        insert household;

        Risk_Case__c riskCase = new Risk_Case__c(
            Customer_Key__c = 'CUST-000555',
            Household__c = household.Id,
            Status__c = 'New',
            Risk_Score__c = 1,
            Flagged_Date__c = System.now()
        );
        insert riskCase;

        List<Financial_Account__c> accounts = new List<Financial_Account__c>();
        List<Insurance_Policy__c> policies = new List<Insurance_Policy__c>();
        for (Integer i = 0; i < 50; i++) {
            accounts.add(new Financial_Account__c(
                Household__c = household.Id,
                Customer_Key__c = 'CUST-000555',
                Account_Number__c = 'ACCT-' + i,
                Account_Type__c = 'Checking',
                Balance__c = 10 * i
            ));
            policies.add(new Insurance_Policy__c(
                Household__c = household.Id,
                Customer_Key__c = 'CUST-000555',
                Policy_Number__c = String.valueOf(i),
                Policy_Type__c = 'Auto',
                Vehicle_Category__c = 'Sedan',
                Fraud_Flag__c = Math.mod(i, 10) == 0,
                Claim_Date__c = Date.newInstance(2026, 1, 1).addDays(i)
            ));
        }
        insert accounts;
        insert policies;

        System.runAs(getRunAsUser()) {
            Test.startTest();
            RiskCustomerProfileController.CustomerProfile profile =
                RiskCustomerProfileController.getCustomerProfile(riskCase.Id);
            Test.stopTest();

            System.assertEquals(50, profile.accounts.size());
            System.assertEquals(50, profile.policies.size());
            for (Integer i = 0; i < profile.policies.size() - 1; i++) {
                System.assert(
                    profile.policies[i].claimDate >= profile.policies[i + 1].claimDate,
                    'Policies must remain sorted by claim date descending across the full result set'
                );
            }
        }
    }
}
