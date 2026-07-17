public with sharing class CustomerKeyResolver implements ICustomerKeyResolver {

    /**
     * Resolves Unified Individual Ids (from Bancassurance_Risk_Score__cio.unified_individual_id__c)
     * back to the real, raw Customer_Key value that exists in the source DMOs
     * (Banking_Transaction__dlm.Customer_Key__c, Insurance_Claim__dlm.Customer_Key__c).
     *
     * This is necessary because Identity Resolution generates its own new identifier for a
     * Unified Individual profile -- that identifier is NOT the same value as the synthetic
     * Customer_Key injected into the source CSVs during preprocessing. The bridge table
     * (Unified Link Individual RISK) maps UnifiedRecordId -> SourceRecordId, and per the
     * Identity Resolution fix documented in the Project Plan, SourceRecordId (Individual.Individual Id)
     * was directly mapped to equal the raw Customer_Key for records ingested through the
     * banking_party_identification.csv / insurance_party_identification.csv streams.
     *
     * If a unified profile maps to multiple source records (expected for the ~500-customer
     * overlap population, since both party identification files intentionally share the same
     * Customer_Key for those customers), all resolved source keys are expected to be identical;
     * the first non-blank value found is used.
     */
    public Map<String, String> resolveRawCustomerKeys(Set<String> unifiedIndividualIds) {
        Map<String, String> rawKeyByUnifiedId = new Map<String, String>();
        if (unifiedIndividualIds == null || unifiedIndividualIds.isEmpty()) {
            return rawKeyByUnifiedId;
        }

        for (UnifiedLinkssotIndividualRisk__dlm bridge : [
            SELECT UnifiedRecordId__c, SourceRecordId__c
            FROM UnifiedLinkssotIndividualRisk__dlm
            WHERE UnifiedRecordId__c IN :unifiedIndividualIds
            AND SourceRecordId__c != null
        ]) {
            if (!rawKeyByUnifiedId.containsKey(bridge.UnifiedRecordId__c)) {
                rawKeyByUnifiedId.put(bridge.UnifiedRecordId__c, bridge.SourceRecordId__c);
            }
        }

        return rawKeyByUnifiedId;
    }

    // Static convenience wrappers for callers (e.g. AccountBackfillService, ad hoc scripts)
    // that don't need the injectable/testable seam RiskCaseService uses.
    public static Map<String, String> resolveKeys(Set<String> unifiedIndividualIds) {
        return new CustomerKeyResolver().resolveRawCustomerKeys(unifiedIndividualIds);
    }

    public static String resolveKey(String unifiedIndividualId) {
        if (String.isBlank(unifiedIndividualId)) {
            return null;
        }
        Map<String, String> resolved = resolveKeys(new Set<String>{ unifiedIndividualId });
        return resolved.get(unifiedIndividualId);
    }
}
