// ONE-TIME DATA FIX -- run this once via Execute Anonymous.
//
// IMPORTANT: Data Cloud external object queries (CustomerKeyResolver) are backed by a
// callout under the hood and cannot run while there is uncommitted DML pending in the
// same transaction. So resolve the raw keys ONCE, at the very top, before any DML
// happens anywhere else in this script -- do not call CustomerKeyResolver again later.
//
// What it does:
// 1. Resolves each customer's Unified Individual Id to the real raw Customer_Key (ONCE)
// 2. Backfills real Financial_Account__c / Insurance_Policy__c / Household__c records
// 3. Corrects the existing Risk_Case__c.Customer_Key__c from the Unified Individual Id
//    to the resolved raw Customer_Key, and links Household__c now that it exists

Set<String> flaggedUnifiedIds = new Set<String>{
    'e685df6c9db06df7cd22c17049f9596f',
    'e551e0d641a159f53e761e48b48d35a0',
    '21c99128cc03fcd4d46cabd10ef124ea',
    'f47ff036c17a4ee33c5a0b138ab7efaa',
    '17cf53f75cdbd05237cccecc4f9a23be'
};

// Resolve ONCE, before any DML happens anywhere in this script.
Map<String, String> rawKeyByUnifiedId = CustomerKeyResolver.resolveKeys(flaggedUnifiedIds);
System.debug('Resolved raw keys: ' + rawKeyByUnifiedId);

// Step 1 & 2: backfill real account data. (This performs DML internally.)
AccountBackfillService.BackfillResult backfillResult =
    AccountBackfillService.backfillForUnifiedIndividualIds(flaggedUnifiedIds);

System.debug('Households created: ' + backfillResult.householdsCreated);
System.debug('Financial Accounts created: ' + backfillResult.financialAccountsCreated);
System.debug('Insurance Policies created: ' + backfillResult.insurancePoliciesCreated);
System.debug('Skipped (could not resolve): ' + backfillResult.skippedRawKeys);

// Step 3: correct the existing Risk_Case__c records, reusing the SAME rawKeyByUnifiedId
// map resolved at the top -- no second Data Cloud query needed (and none would work now
// anyway, since DML has already happened above).
List<Risk_Case__c> casesToFix = [
    SELECT Id, Customer_Key__c, Household__c
    FROM Risk_Case__c
    WHERE Customer_Key__c IN :flaggedUnifiedIds
];

// Look up the Household__c that the backfill just created/linked for each raw key.
Set<String> resolvedRawKeys = new Set<String>(rawKeyByUnifiedId.values());
Map<String, Id> householdByRawKey = new Map<String, Id>();
for (Financial_Account__c acct : [
    SELECT Customer_Key__c, Household__c
    FROM Financial_Account__c
    WHERE Customer_Key__c IN :resolvedRawKeys
]) {
    householdByRawKey.put(acct.Customer_Key__c, acct.Household__c);
}

List<Risk_Case__c> toUpdate = new List<Risk_Case__c>();
for (Risk_Case__c rc : casesToFix) {
    String rawKey = rawKeyByUnifiedId.get(rc.Customer_Key__c);
    if (String.isBlank(rawKey)) {
        System.debug(LoggingLevel.WARN, 'Could not resolve raw key for Risk_Case__c ' + rc.Id + ' (was: ' + rc.Customer_Key__c + ')');
        continue;
    }
    rc.Customer_Key__c = rawKey;
    if (householdByRawKey.containsKey(rawKey)) {
        rc.Household__c = householdByRawKey.get(rawKey);
    }
    toUpdate.add(rc);
}

if (!toUpdate.isEmpty()) {
    update toUpdate;
    System.debug('Corrected ' + toUpdate.size() + ' Risk_Case__c records to use the raw Customer_Key.');
}
