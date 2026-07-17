public with sharing class AccountBackfillService {

    public class BackfillResult {
        public Integer householdsCreated = 0;
        public Integer financialAccountsCreated = 0;
        public Integer insurancePoliciesCreated = 0;
        public List<String> skippedRawKeys = new List<String>();
    }

    /**
     * Populates real Financial_Account__c and Insurance_Policy__c records from the actual
     * ingested Banking_Transaction__dlm / Insurance_Claim__dlm data, for the given set of
     * Unified Individual Ids (e.g. from Bancassurance_Risk_Score__cio.unified_individual_id__c).
     *
     * Field-mapping notes, documented honestly rather than silently invented:
     * - Banking_Transaction__dlm is transaction-level (Kaggle Credit Card Fraud dataset), not
     *   account-level -- it has no native Account Type, Account Number, or Balance concept.
     *   Account_Type__c defaults to 'Checking' (a documented assumption, not real source data).
     *   Account_Number__c is synthesized from the raw Customer_Key.
     *   Balance__c is approximated as the SUM of that customer's transaction Amount__c values
     *   -- a stand-in for a true balance, not a real one.
     * - Insurance_Policy__c fields map directly and honestly to real source fields:
     *   Policy_Number__c, Policy_Type__c, Vehicle_Category__c, Fraud_Flag__c all come straight
     *   from Insurance_Claim__dlm with no invented values.
     *
     * Idempotent: skips creating a Financial_Account__c / Insurance_Policy__c if one already
     * exists for that raw Customer_Key, and reuses the existing linked Household__c rather
     * than creating a duplicate.
     */
    public static BackfillResult backfillForUnifiedIndividualIds(Set<String> unifiedIndividualIds) {
        BackfillResult result = new BackfillResult();
        if (unifiedIndividualIds == null || unifiedIndividualIds.isEmpty()) {
            return result;
        }

        Map<String, String> rawKeyByUnifiedId = CustomerKeyResolver.resolveKeys(unifiedIndividualIds);
        Set<String> rawKeys = new Set<String>();
        for (String unifiedId : unifiedIndividualIds) {
            String rawKey = rawKeyByUnifiedId.get(unifiedId);
            if (String.isNotBlank(rawKey)) {
                rawKeys.add(rawKey);
            } else {
                result.skippedRawKeys.add(unifiedId + ' (could not resolve raw Customer_Key)');
            }
        }
        if (rawKeys.isEmpty()) {
            return result;
        }

        // Find which raw keys already have real records, to stay idempotent on re-run.
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

        // Aggregate banking transaction amounts per raw key (transaction-level -> account-level approximation).
        Map<String, Decimal> totalAmountByRawKey = new Map<String, Decimal>();
        Map<String, Integer> transactionCountByRawKey = new Map<String, Integer>();
        for (Banking_Transaction__dlm txn : [
            SELECT Customer_Key__c, Amount__c
            FROM Banking_Transaction__dlm
            WHERE Customer_Key__c IN :rawKeys
        ]) {
            Decimal running = totalAmountByRawKey.containsKey(txn.Customer_Key__c)
                ? totalAmountByRawKey.get(txn.Customer_Key__c)
                : 0;
            totalAmountByRawKey.put(txn.Customer_Key__c, running + (txn.Amount__c != null ? txn.Amount__c : 0));

            Integer count = transactionCountByRawKey.containsKey(txn.Customer_Key__c)
                ? transactionCountByRawKey.get(txn.Customer_Key__c)
                : 0;
            transactionCountByRawKey.put(txn.Customer_Key__c, count + 1);
        }

        // Take the first insurance claim found per raw key for policy-level fields.
        Map<String, Insurance_Claim__dlm> claimByRawKey = new Map<String, Insurance_Claim__dlm>();
        for (Insurance_Claim__dlm claim : [
            SELECT Customer_Key__c, Policy_Number__c, PolicyType__c, VehicleCategory__c, FraudFound_P__c
            FROM Insurance_Claim__dlm
            WHERE Customer_Key__c IN :rawKeys
        ]) {
            if (!claimByRawKey.containsKey(claim.Customer_Key__c)) {
                claimByRawKey.put(claim.Customer_Key__c, claim);
            }
        }

        // Create Households for any raw key that doesn't already have one linked.
        Map<String, Household__c> newHouseholdByRawKey = new Map<String, Household__c>();
        for (String rawKey : rawKeys) {
            if (!existingHouseholdByRawKey.containsKey(rawKey)) {
                newHouseholdByRawKey.put(rawKey, new Household__c(
                    Name = 'Household ' + rawKey.left(8).toUpperCase()
                ));
            }
        }
        if (!newHouseholdByRawKey.isEmpty()) {
            insert newHouseholdByRawKey.values();
            result.householdsCreated = newHouseholdByRawKey.size();
        }

        List<Financial_Account__c> accountsToInsert = new List<Financial_Account__c>();
        List<Insurance_Policy__c> policiesToInsert = new List<Insurance_Policy__c>();

        for (String rawKey : rawKeys) {
            Id householdId = existingHouseholdByRawKey.containsKey(rawKey)
                ? existingHouseholdByRawKey.get(rawKey)
                : newHouseholdByRawKey.get(rawKey).Id;

            if (totalAmountByRawKey.containsKey(rawKey) && !existingHouseholdByRawKey.containsKey(rawKey)) {
                accountsToInsert.add(new Financial_Account__c(
                    Household__c = householdId,
                    Customer_Key__c = rawKey,
                    Account_Number__c = 'ACCT-' + rawKey.left(8).toUpperCase(),
                    Account_Type__c = 'Checking',
                    Balance__c = totalAmountByRawKey.get(rawKey)
                ));
            }

            if (claimByRawKey.containsKey(rawKey) && !existingHouseholdByRawKey.containsKey(rawKey)) {
                Insurance_Claim__dlm claim = claimByRawKey.get(rawKey);
                Boolean fraudFlag = isTruthy(claim.FraudFound_P__c);
                policiesToInsert.add(new Insurance_Policy__c(
                    Household__c = householdId,
                    Customer_Key__c = rawKey,
                    Policy_Number__c = claim.Policy_Number__c != null ? String.valueOf(claim.Policy_Number__c) : null,
                    Policy_Type__c = claim.PolicyType__c,
                    Vehicle_Category__c = claim.VehicleCategory__c,
                    Fraud_Flag__c = fraudFlag
                ));
            }
        }

        if (!accountsToInsert.isEmpty()) {
            insert accountsToInsert;
            result.financialAccountsCreated = accountsToInsert.size();
        }
        if (!policiesToInsert.isEmpty()) {
            insert policiesToInsert;
            result.insurancePoliciesCreated = policiesToInsert.size();
        }

        return result;
    }

    private static Boolean isTruthy(Decimal value) {
        return value != null && value == 1;
    }
}
