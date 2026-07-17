@isTest
private class AccountBackfillServiceTest {

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

    /**
     * Returns a dedicated test user (created in setupRunAsUser via @TestSetup) so test
     * methods can wrap their DML/query logic in System.runAs, per Apex testing best
     * practice for verifying behavior under a specific user context.
     */
    private static User getRunAsUser() {
        return [SELECT Id FROM User WHERE LastName = 'TestUser' AND FirstName = 'RunAs' LIMIT 1];
    }


    // NOTE: fetchTransactionTotals() and fetchClaimData() query Data Cloud external objects
    // (Banking_Transaction__dlm, Insurance_Claim__dlm) and cannot be seeded with synthetic
    // data in a standard @isTest context -- there is no local mocking framework for them.
    // Both are kept deliberately thin in AccountBackfillService.cls for exactly this reason.
    // Everything else below -- the actual business logic -- is tested directly with plain
    // in-memory data, since it was refactored specifically to be testable without needing
    // any external object dependency.

    @isTest
    static void testBackfill_NullInput_ReturnsEmptyResultWithoutError() {
        System.runAs(getRunAsUser()) {
            Test.startTest();
            AccountBackfillService.BackfillResult result = AccountBackfillService.backfillForUnifiedIndividualIds(null);
            Test.stopTest();
        System.assertEquals(0, result.householdsCreated);
        System.assertEquals(0, result.financialAccountsCreated);
        System.assertEquals(0, result.insurancePoliciesCreated);
        }
    }

    @isTest
    static void testBackfill_EmptySet_ReturnsEmptyResultWithoutError() {
        System.runAs(getRunAsUser()) {
            Test.startTest();
            AccountBackfillService.BackfillResult result = AccountBackfillService.backfillForUnifiedIndividualIds(new Set<String>());
            Test.stopTest();
        System.assertEquals(0, result.householdsCreated);
        }
    }

    @isTest
    static void testExtractResolvedRawKeys_ResolvedAndUnresolved_SeparatesCorrectly() {
        Set<String> unifiedIds = new Set<String>{ 'UNI-1', 'UNI-2', 'UNI-3' };
        Map<String, String> rawKeyByUnifiedId = new Map<String, String>{ 'UNI-1' => 'RAW-1', 'UNI-3' => 'RAW-3' };
        AccountBackfillService.BackfillResult result = new AccountBackfillService.BackfillResult();

        System.runAs(getRunAsUser()) {
            Test.startTest();
            Set<String> rawKeys = AccountBackfillService.extractResolvedRawKeys(unifiedIds, rawKeyByUnifiedId, result);
            Test.stopTest();
        System.assertEquals(2, rawKeys.size());
        System.assert(rawKeys.contains('RAW-1'));
        System.assert(rawKeys.contains('RAW-3'));
        System.assertEquals(1, result.skippedRawKeys.size(), 'UNI-2 had no resolved key and should be recorded as skipped');
        }
    }

    @isTest
    static void testFetchExistingHouseholds_FindsFromBothObjectTypes() {
        Household__c h1 = new Household__c(Name = 'H1');
        Household__c h2 = new Household__c(Name = 'H2');
        insert new List<Household__c>{ h1, h2 };

        insert new Financial_Account__c(Customer_Key__c = 'RAW-A', Household__c = h1.Id, Account_Type__c = 'Checking');
        insert new Insurance_Policy__c(Customer_Key__c = 'RAW-B', Household__c = h2.Id);

        System.runAs(getRunAsUser()) {
            Test.startTest();
            Map<String, Id> result = AccountBackfillService.fetchExistingHouseholds(new Set<String>{ 'RAW-A', 'RAW-B', 'RAW-C' });
            Test.stopTest();
        System.assertEquals(2, result.size());
        System.assertEquals(h1.Id, result.get('RAW-A'));
        System.assertEquals(h2.Id, result.get('RAW-B'));
        System.assertEquals(false, result.containsKey('RAW-C'), 'A raw key with no existing records should not appear');
        }
    }

    @isTest
    static void testBuildHouseholdsToInsert_OnlyForKeysWithoutExistingHousehold() {
        Set<String> rawKeys = new Set<String>{ 'RAW-1', 'RAW-2', 'RAW-3' };
        Map<String, Id> existing = new Map<String, Id>{ 'RAW-1' => null };
        // Use a fake but valid-shaped existing entry to represent "already has one";
        // real Id value doesn't matter for this pure-logic test.

        System.runAs(getRunAsUser()) {
            Test.startTest();
            List<Household__c> toInsert = AccountBackfillService.buildHouseholdsToInsert(rawKeys, existing);
            Test.stopTest();
        System.assertEquals(2, toInsert.size(), 'Only RAW-2 and RAW-3 lack an existing household');
        }
    }

    @isTest
    static void testBuildHouseholdsToInsert_NamesUseUppercasedKeyPrefix() {
        Set<String> rawKeys = new Set<String>{ 'abcdefgh12345' };

        System.runAs(getRunAsUser()) {
            Test.startTest();
            List<Household__c> toInsert = AccountBackfillService.buildHouseholdsToInsert(rawKeys, new Map<String, Id>());
            Test.stopTest();
        System.assertEquals(1, toInsert.size());
        System.assertEquals('Household ABCDEFGH', toInsert[0].Name);
        }
    }

    @isTest
    static void testMergeHouseholdIds_CombinesExistingAndNewlyInserted() {
        Household__c household = new Household__c(Name = 'Existing');
        insert household;

        Set<String> rawKeys = new Set<String>{ 'RAW-EXISTING', 'RAW-NEW' };
        Map<String, Id> existing = new Map<String, Id>{ 'RAW-EXISTING' => household.Id };

        Household__c newHousehold = new Household__c(Name = 'New Household');
        insert newHousehold;
        List<Household__c> inserted = new List<Household__c>{ newHousehold };

        System.runAs(getRunAsUser()) {
            Test.startTest();
            Map<String, Id> merged = AccountBackfillService.mergeHouseholdIds(rawKeys, existing, inserted);
            Test.stopTest();
        System.assertEquals(2, merged.size());
        System.assertEquals(household.Id, merged.get('RAW-EXISTING'));
        System.assertEquals(newHousehold.Id, merged.get('RAW-NEW'));
        }
    }

    @isTest
    static void testBuildAccountsAndPolicies_HappyPath_BuildsBothRecordTypes() {
        Id fakeHouseholdId = createFakeHouseholdId();

        Set<String> rawKeys = new Set<String>{ 'RAW-X' };
        Map<String, Id> householdIdByRawKey = new Map<String, Id>{ 'RAW-X' => fakeHouseholdId };
        Map<String, Id> existingHouseholdByRawKey = new Map<String, Id>();

        Map<String, Decimal> totalAmountByRawKey = new Map<String, Decimal>{ 'RAW-X' => 1234.56 };

        AccountBackfillService.ClaimData claim = new AccountBackfillService.ClaimData();
        claim.policyNumber = '9988';
        claim.policyType = 'Auto';
        claim.vehicleCategory = 'Sport';
        claim.fraudFlag = true;
        Map<String, AccountBackfillService.ClaimData> claimByRawKey =
            new Map<String, AccountBackfillService.ClaimData>{ 'RAW-X' => claim };

        System.runAs(getRunAsUser()) {
            Test.startTest();
            AccountBackfillService.BuildOutput output = AccountBackfillService.buildAccountsAndPolicies(
                rawKeys, householdIdByRawKey, existingHouseholdByRawKey, totalAmountByRawKey, claimByRawKey
            );
            Test.stopTest();
        System.assertEquals(1, output.accountsToInsert.size());
        System.assertEquals('RAW-X', output.accountsToInsert[0].Customer_Key__c);
        System.assertEquals(1234.56, output.accountsToInsert[0].Balance__c);
        System.assertEquals('Checking', output.accountsToInsert[0].Account_Type__c);

        System.assertEquals(1, output.policiesToInsert.size());
        System.assertEquals('9988', output.policiesToInsert[0].Policy_Number__c);
        System.assertEquals('Auto', output.policiesToInsert[0].Policy_Type__c);
        System.assertEquals('Sport', output.policiesToInsert[0].Vehicle_Category__c);
        System.assertEquals(true, output.policiesToInsert[0].Fraud_Flag__c);
        }
    }

    @isTest
    static void testBuildAccountsAndPolicies_SkipsRawKeysThatAlreadyHaveAHousehold() {
        Id fakeHouseholdId = createFakeHouseholdId();

        Set<String> rawKeys = new Set<String>{ 'RAW-Y' };
        Map<String, Id> householdIdByRawKey = new Map<String, Id>{ 'RAW-Y' => fakeHouseholdId };
        Map<String, Id> existingHouseholdByRawKey = new Map<String, Id>{ 'RAW-Y' => fakeHouseholdId };
        Map<String, Decimal> totalAmountByRawKey = new Map<String, Decimal>{ 'RAW-Y' => 500 };
        Map<String, AccountBackfillService.ClaimData> claimByRawKey = new Map<String, AccountBackfillService.ClaimData>();

        System.runAs(getRunAsUser()) {
            Test.startTest();
            AccountBackfillService.BuildOutput output = AccountBackfillService.buildAccountsAndPolicies(
                rawKeys, householdIdByRawKey, existingHouseholdByRawKey, totalAmountByRawKey, claimByRawKey
            );
            Test.stopTest();
        System.assertEquals(0, output.accountsToInsert.size(), 'Already-backfilled customers should be skipped, staying idempotent');
        System.assertEquals(0, output.policiesToInsert.size());
        }
    }

    @isTest
    static void testBuildAccountsAndPolicies_NoTransactionOrClaimData_BuildsNeither() {
        Id fakeHouseholdId = createFakeHouseholdId();

        Set<String> rawKeys = new Set<String>{ 'RAW-Z' };
        Map<String, Id> householdIdByRawKey = new Map<String, Id>{ 'RAW-Z' => fakeHouseholdId };

        System.runAs(getRunAsUser()) {
            Test.startTest();
            AccountBackfillService.BuildOutput output = AccountBackfillService.buildAccountsAndPolicies(
                rawKeys, householdIdByRawKey, new Map<String, Id>(), new Map<String, Decimal>(), new Map<String, AccountBackfillService.ClaimData>()
            );
            Test.stopTest();
        System.assertEquals(0, output.accountsToInsert.size(), 'No transaction data for this customer means no Financial_Account__c should be built');
        System.assertEquals(0, output.policiesToInsert.size(), 'No claim data for this customer means no Insurance_Policy__c should be built');
        }
    }

    @isTest
    static void testBuildHouseholdsAndAccountsAndPolicies_BulkAtTwoHundredCustomers() {
        Set<String> rawKeys = new Set<String>();
        Map<String, Decimal> totalAmountByRawKey = new Map<String, Decimal>();
        Map<String, AccountBackfillService.ClaimData> claimByRawKey = new Map<String, AccountBackfillService.ClaimData>();

        for (Integer i = 0; i < 200; i++) {
            String rawKey = 'BULK-RAW-' + i;
            rawKeys.add(rawKey);
            totalAmountByRawKey.put(rawKey, 100 + i);

            AccountBackfillService.ClaimData claim = new AccountBackfillService.ClaimData();
            claim.policyNumber = String.valueOf(1000 + i);
            claim.policyType = 'Auto';
            claim.vehicleCategory = 'Sedan';
            claim.fraudFlag = Math.mod(i, 10) == 0;
            claimByRawKey.put(rawKey, claim);
        }

        System.runAs(getRunAsUser()) {
            Test.startTest();
            List<Household__c> householdsToInsert = AccountBackfillService.buildHouseholdsToInsert(rawKeys, new Map<String, Id>());
            insert householdsToInsert;

            Map<String, Id> householdIdByRawKey = AccountBackfillService.mergeHouseholdIds(rawKeys, new Map<String, Id>(), householdsToInsert);

            AccountBackfillService.BuildOutput output = AccountBackfillService.buildAccountsAndPolicies(
                rawKeys, householdIdByRawKey, new Map<String, Id>(), totalAmountByRawKey, claimByRawKey
            );
            insert output.accountsToInsert;
            insert output.policiesToInsert;
            Test.stopTest();
        System.assertEquals(200, householdsToInsert.size());
        System.assertEquals(200, output.accountsToInsert.size());
        System.assertEquals(200, output.policiesToInsert.size());
        System.assertEquals(200, [SELECT COUNT() FROM Financial_Account__c WHERE Customer_Key__c LIKE 'BULK-RAW-%']);
        System.assertEquals(200, [SELECT COUNT() FROM Insurance_Policy__c WHERE Customer_Key__c LIKE 'BULK-RAW-%']);
        System.assertEquals(20, [SELECT COUNT() FROM Insurance_Policy__c WHERE Customer_Key__c LIKE 'BULK-RAW-%' AND Fraud_Flag__c = true], 'Every 10th record was built with fraudFlag = true');
        }
    }

    @isTest
    static void testBackfill_StubResolver_AllUnresolved_SkipsBeforeAnyDataCloudQuery() {
        // Exercises the injectable keyResolver seam end-to-end through the orchestrator,
        // without ever reaching fetchTransactionTotals/fetchClaimData -- those genuinely
        // can't be safely exercised in a test context (Data Cloud external object queries
        // are backed by a callout under the hood, and an unmocked callout in @isTest throws).
        // This test proves the orchestrator correctly records skipped keys and returns early
        // when nothing resolves, using the same stub pattern as RiskCaseServiceTest.
        AccountBackfillService.keyResolver = new StubResolver(new Set<String>{ 'UNI-UNRESOLVABLE-1', 'UNI-UNRESOLVABLE-2' });

        System.runAs(getRunAsUser()) {
            Test.startTest();
            AccountBackfillService.BackfillResult result = AccountBackfillService.backfillForUnifiedIndividualIds(
                new Set<String>{ 'UNI-UNRESOLVABLE-1', 'UNI-UNRESOLVABLE-2' }
            );
            Test.stopTest();
        System.assertEquals(0, result.householdsCreated);
        System.assertEquals(0, result.financialAccountsCreated);
        System.assertEquals(0, result.insurancePoliciesCreated);
        System.assertEquals(2, result.skippedRawKeys.size(), 'Both unresolvable ids should be recorded as skipped');
        }
    }

    private class StubResolver implements ICustomerKeyResolver {
        private Set<String> unresolvableIds;
        StubResolver(Set<String> unresolvableIds) {
            this.unresolvableIds = unresolvableIds;
        }
        public Map<String, String> resolveRawCustomerKeys(Set<String> unifiedIndividualIds) {
            Map<String, String> result = new Map<String, String>();
            for (String id : unifiedIndividualIds) {
                if (!unresolvableIds.contains(id)) {
                    result.put(id, id);
                }
            }
            return result;
        }
    }

    private static Id createFakeHouseholdId() {
        Household__c h = new Household__c(Name = 'Fake For Id Only');
        insert h;
        return h.Id;
    }
}
