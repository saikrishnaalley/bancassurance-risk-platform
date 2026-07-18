/**
 * Populates real Financial_Account__c and Insurance_Policy__c records from the actual
 * ingested Banking_Transaction__dlm / Insurance_Claim__dlm data, keyed by the real raw
 * Customer_Key (resolved from a Data Cloud Unified Individual Id via CustomerKeyResolver).
 * See the Build Guide for full field-mapping notes and documented approximations.
 */
public with sharing class AccountBackfillService {

    /**
     * Injectable seam, matching the pattern in RiskCaseService: production uses the real
     * CustomerKeyResolver; tests substitute a stub so the orchestrator method below can be
     * exercised end-to-end without needing to seed Data Cloud external objects.
     */
    @TestVisible
    private static ICustomerKeyResolver keyResolver = new CustomerKeyResolver();

    /** Summary of what a backfill run created, and which inputs could not be resolved. */
    public class BackfillResult {
        public Integer householdsCreated = 0;
        public Integer financialAccountsCreated = 0;
        public Integer insurancePoliciesCreated = 0;
        public List<String> skippedRawKeys = new List<String>();
    }

    /**
     * Plain data wrapper. Decouples the testable build logic below from the
     * Insurance_Claim__dlm external object type.
     */
    public class ClaimData {
        public String policyNumber;
        public String policyType;
        public String vehicleCategory;
        public Boolean fraudFlag;
    }

    /**
     * Plain data wrapper for what gets inserted, returned by the pure builder methods
     * so they can be unit tested without performing any DML themselves.
     */
    public class BuildOutput {
        public List<Household__c> householdsToInsert = new List<Household__c>();
        public List<Financial_Account__c> accountsToInsert = new List<Financial_Account__c>();
        public List<Insurance_Policy__c> policiesToInsert = new List<Insurance_Policy__c>();
    }

    /**
     * Populates real Financial_Account__c and Insurance_Policy__c records from the actual
     * ingested Banking_Transaction__dlm / Insurance_Claim__dlm data. See the Build Guide for
     * full field-mapping notes and documented approximations (Account_Type__c, Balance__c).
     * Idempotent: skips any raw Customer_Key that already has a linked Household__c.
     * @param unifiedIndividualIds Set of Data Cloud Unified Individual Ids to backfill
     * @return Summary of records created and any inputs that could not be resolved
     */
    public static BackfillResult backfillForUnifiedIndividualIds(Set<String> unifiedIndividualIds) {
        BackfillResult result = new BackfillResult();
        if (unifiedIndividualIds == null || unifiedIndividualIds.isEmpty()) {
            return result;
        }

        Map<String, String> rawKeyByUnifiedId = keyResolver.resolveRawCustomerKeys(unifiedIndividualIds);
        Set<String> rawKeys = extractResolvedRawKeys(unifiedIndividualIds, rawKeyByUnifiedId, result);
        if (rawKeys.isEmpty()) {
            return result;
        }

        // Fetches Financial_Account__c / Insurance_Policy__c -- our OWN custom objects,
        // not external, so this query (and this method) is normal and fully testable.
        Map<String, Id> existingHouseholdByRawKey = fetchExistingHouseholds(rawKeys);

        // UNTESTABLE by design (Data Cloud external objects) -- kept thin.
        Map<String, Decimal> totalAmountByRawKey = fetchTransactionTotals(rawKeys);
        Map<String, ClaimData> claimByRawKey = fetchClaimData(rawKeys);

        // TESTABLE pure logic: build the Households first (no DML yet).
        List<Household__c> householdsToInsert = buildHouseholdsToInsert(rawKeys, existingHouseholdByRawKey);
        if (!householdsToInsert.isEmpty()) {
            insert householdsToInsert;
            result.householdsCreated = householdsToInsert.size();
        }

        Map<String, Id> householdIdByRawKey = mergeHouseholdIds(rawKeys, existingHouseholdByRawKey, householdsToInsert);

        // TESTABLE pure logic: build the Financial_Account__c / Insurance_Policy__c records.
        BuildOutput accountsAndPolicies = buildAccountsAndPolicies(
            rawKeys, householdIdByRawKey, existingHouseholdByRawKey, totalAmountByRawKey, claimByRawKey
        );

        if (!accountsAndPolicies.accountsToInsert.isEmpty()) {
            insert accountsAndPolicies.accountsToInsert;
            result.financialAccountsCreated = accountsAndPolicies.accountsToInsert.size();
        }
        if (!accountsAndPolicies.policiesToInsert.isEmpty()) {
            insert accountsAndPolicies.policiesToInsert;
            result.insurancePoliciesCreated = accountsAndPolicies.policiesToInsert.size();
        }

        return result;
    }

    /**
     * TESTABLE: pure logic, no query or DML. Separates resolved raw keys from ids that
     * could not be resolved (recorded on the result for visibility).
     * @param unifiedIndividualIds Original input ids
     * @param rawKeyByUnifiedId Resolution map produced by keyResolver
     * @param result BackfillResult to record any skipped/unresolved ids onto
     * @return Set of successfully-resolved raw Customer_Keys
     */
    @TestVisible
    static Set<String> extractResolvedRawKeys(
        Set<String> unifiedIndividualIds, Map<String, String> rawKeyByUnifiedId, BackfillResult result
    ) {
        Set<String> rawKeys = new Set<String>();
        for (String unifiedId : unifiedIndividualIds) {
            String rawKey = rawKeyByUnifiedId.get(unifiedId);
            if (String.isNotBlank(rawKey)) {
                rawKeys.add(rawKey);
            } else {
                result.skippedRawKeys.add(unifiedId + ' (could not resolve raw Customer_Key)');
            }
        }
        return rawKeys;
    }

    /**
     * TESTABLE: queries our own custom objects (Financial_Account__c, Insurance_Policy__c),
     * fully seedable in @isTest, unlike the Data Cloud fetch methods below.
     * @param rawKeys Raw Customer_Keys to check for an existing linked Household__c
     * @return Map of raw Customer_Key to existing Household__c Id
     */
    @TestVisible
    static Map<String, Id> fetchExistingHouseholds(Set<String> rawKeys) {
        Map<String, Id> existingHouseholdByRawKey = new Map<String, Id>();
        for (Financial_Account__c acct : [
            SELECT Customer_Key__c, Household__c
            FROM Financial_Account__c
            WHERE Customer_Key__c IN :rawKeys
        ]) {
            existingHouseholdByRawKey.put(acct.Customer_Key__c, acct.Household__c);
        }
        for (Insurance_Policy__c pol : [
            SELECT Customer_Key__c, Household__c
            FROM Insurance_Policy__c
            WHERE Customer_Key__c IN :rawKeys
        ]) {
            if (!existingHouseholdByRawKey.containsKey(pol.Customer_Key__c)) {
                existingHouseholdByRawKey.put(pol.Customer_Key__c, pol.Household__c);
            }
        }
        return existingHouseholdByRawKey;
    }

    /**
     * UNTESTABLE by design (Data Cloud external object). Kept thin: query + aggregate only.
     * Balance__c is approximated as the SUM of transaction Amount__c values -- a stand-in
     * for a true balance, since the source dataset is transaction-level, not account-level.
     * @param rawKeys Raw Customer_Keys to total banking transaction amounts for
     * @return Map of raw Customer_Key to summed transaction Amount__c
     */
    private static Map<String, Decimal> fetchTransactionTotals(Set<String> rawKeys) {
        Map<String, Decimal> totalAmountByRawKey = new Map<String, Decimal>();
        for (Banking_Transaction__dlm txn : [
            SELECT Customer_Key__c, Amount__c
            FROM Banking_Transaction__dlm
            WHERE Customer_Key__c IN :rawKeys
        ]) {
            Decimal running = totalAmountByRawKey.containsKey(txn.Customer_Key__c)
                ? totalAmountByRawKey.get(txn.Customer_Key__c)
                : 0;
            totalAmountByRawKey.put(txn.Customer_Key__c, running + (txn.Amount__c != null ? txn.Amount__c : 0));
        }
        return totalAmountByRawKey;
    }

    /**
     * UNTESTABLE by design (Data Cloud external object). Kept thin: query + type conversion
     * to the plain ClaimData wrapper only -- no business logic lives here.
     * @param rawKeys Raw Customer_Keys to fetch the first matching insurance claim for
     * @return Map of raw Customer_Key to ClaimData
     */
    private static Map<String, ClaimData> fetchClaimData(Set<String> rawKeys) {
        Map<String, ClaimData> claimByRawKey = new Map<String, ClaimData>();
        for (Insurance_Claim__dlm claim : [
            SELECT Customer_Key__c, Policy_Number__c, PolicyType__c, VehicleCategory__c, FraudFound_P__c
            FROM Insurance_Claim__dlm
            WHERE Customer_Key__c IN :rawKeys
        ]) {
            if (!claimByRawKey.containsKey(claim.Customer_Key__c)) {
                ClaimData data = new ClaimData();
                data.policyNumber = claim.Policy_Number__c != null ? String.valueOf(claim.Policy_Number__c) : null;
                // Insurance_Policy__c.Policy_Type__c is a coarse Auto/Home/Life picklist, but
                // the source DMO's PolicyType__c is a compound "VehicleCategory - CoverageType"
                // string (e.g. "Sedan - Collision", from the original vehicle-insurance-only
                // Kaggle dataset schema) that was never going to fit that picklist directly.
                // Since this entire dataset is vehicle insurance, 'Auto' is the honest, correct
                // mapping -- the vehicle category detail itself is preserved separately below.
                data.policyType = 'Auto';
                data.vehicleCategory = claim.VehicleCategory__c;
                data.fraudFlag = claim.FraudFound_P__c != null && claim.FraudFound_P__c == 1;
                claimByRawKey.put(claim.Customer_Key__c, data);
            }
        }
        return claimByRawKey;
    }

    /**
     * TESTABLE: pure logic, no query or DML.
     * @param rawKeys All raw Customer_Keys being processed
     * @param existingHouseholdByRawKey Raw keys that already have a linked Household__c
     * @return Household__c records to insert for keys that don't have one yet
     */
    @TestVisible
    static List<Household__c> buildHouseholdsToInsert(Set<String> rawKeys, Map<String, Id> existingHouseholdByRawKey) {
        List<Household__c> toInsert = new List<Household__c>();
        for (String rawKey : rawKeys) {
            if (!existingHouseholdByRawKey.containsKey(rawKey)) {
                toInsert.add(new Household__c(Name = 'Household ' + rawKey.toUpperCase()));
            }
        }
        return toInsert;
    }

    /**
     * TESTABLE: pure logic. Matches newly-inserted Households back to their raw key by
     * relying on list order matching buildHouseholdsToInsert's iteration order -- both
     * iterate the same "needs a new household" subset of rawKeys in the same pass.
     * @param rawKeys All raw Customer_Keys being processed
     * @param existingHouseholdByRawKey Raw keys that already had a linked Household__c
     * @param insertedHouseholds Newly-inserted Household__c records, same order as buildHouseholdsToInsert produced
     * @return Map of raw Customer_Key to Household__c Id, combining existing and newly-inserted
     */
    @TestVisible
    static Map<String, Id> mergeHouseholdIds(
        Set<String> rawKeys, Map<String, Id> existingHouseholdByRawKey, List<Household__c> insertedHouseholds
    ) {
        Map<String, Id> householdIdByRawKey = new Map<String, Id>(existingHouseholdByRawKey);
        Integer i = 0;
        for (String rawKey : rawKeys) {
            if (!existingHouseholdByRawKey.containsKey(rawKey)) {
                householdIdByRawKey.put(rawKey, insertedHouseholds[i].Id);
                i++;
            }
        }
        return householdIdByRawKey;
    }

    /**
     * TESTABLE: pure logic, no query or DML.
     * @param rawKeys All raw Customer_Keys being processed
     * @param householdIdByRawKey Household__c Id for each raw key (existing or newly-inserted)
     * @param existingHouseholdByRawKey Raw keys already backfilled -- skipped, to stay idempotent
     * @param totalAmountByRawKey Summed banking transaction amounts per raw key
     * @param claimByRawKey Insurance claim data per raw key
     * @return Financial_Account__c and Insurance_Policy__c records ready to insert
     */
    @TestVisible
    static BuildOutput buildAccountsAndPolicies(
        Set<String> rawKeys,
        Map<String, Id> householdIdByRawKey,
        Map<String, Id> existingHouseholdByRawKey,
        Map<String, Decimal> totalAmountByRawKey,
        Map<String, ClaimData> claimByRawKey
    ) {
        BuildOutput output = new BuildOutput();

        for (String rawKey : rawKeys) {
            if (existingHouseholdByRawKey.containsKey(rawKey)) {
                continue; // already backfilled for this customer -- stay idempotent.
            }
            Id householdId = householdIdByRawKey.get(rawKey);

            if (totalAmountByRawKey.containsKey(rawKey)) {
                output.accountsToInsert.add(new Financial_Account__c(
                    Household__c = householdId,
                    Customer_Key__c = rawKey,
                    Account_Number__c = 'ACCT-' + rawKey.toUpperCase(),
                    Account_Type__c = 'Checking',
                    Balance__c = totalAmountByRawKey.get(rawKey)
                ));
            }

            if (claimByRawKey.containsKey(rawKey)) {
                ClaimData data = claimByRawKey.get(rawKey);
                output.policiesToInsert.add(new Insurance_Policy__c(
                    Household__c = householdId,
                    Customer_Key__c = rawKey,
                    Policy_Number__c = data.policyNumber,
                    Policy_Type__c = data.policyType,
                    Vehicle_Category__c = data.vehicleCategory,
                    Fraud_Flag__c = data.fraudFlag
                ));
            }
        }

        return output;
    }
}
