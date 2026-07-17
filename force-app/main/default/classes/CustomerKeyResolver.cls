public with sharing class CustomerKeyResolver implements ICustomerKeyResolver {

    // Simple, plain-data wrapper -- decouples the mapping logic below from the
    // Data Cloud external object type, so that logic can be unit tested with
    // ordinary in-memory objects instead of requiring a live query.
    public class BridgeRow {
        public String unifiedId;
        public String sourceId;
        public BridgeRow(String unifiedId, String sourceId) {
            this.unifiedId = unifiedId;
            this.sourceId = sourceId;
        }
    }

    /**
     * Resolves Unified Individual Ids back to the real, raw Customer_Key value that exists
     * in the source DMOs. See buildRawKeyMap below for the actual (testable) resolution logic;
     * this method is a thin, deliberately untestable wrapper around the Data Cloud query itself.
     */
    public Map<String, String> resolveRawCustomerKeys(Set<String> unifiedIndividualIds) {
        if (unifiedIndividualIds == null || unifiedIndividualIds.isEmpty()) {
            return new Map<String, String>();
        }
        return buildRawKeyMap(queryBridgeRows(unifiedIndividualIds));
    }

    // UNTESTABLE by design: queries a Data Cloud external object, which cannot be seeded
    // with synthetic data in a standard @isTest context. Kept intentionally thin (just the
    // query and a type conversion) so the untestable surface area is as small as possible --
    // all the actual resolution logic lives in the testable buildRawKeyMap method below.
    private List<BridgeRow> queryBridgeRows(Set<String> unifiedIndividualIds) {
        List<BridgeRow> rows = new List<BridgeRow>();
        for (UnifiedLinkssotIndividualRisk__dlm bridge : [
            SELECT UnifiedRecordId__c, SourceRecordId__c
            FROM UnifiedLinkssotIndividualRisk__dlm
            WHERE UnifiedRecordId__c IN :unifiedIndividualIds
            AND SourceRecordId__c != null
        ]) {
            rows.add(new BridgeRow(bridge.UnifiedRecordId__c, bridge.SourceRecordId__c));
        }
        return rows;
    }

    /**
     * TESTABLE pure logic: given already-fetched bridge rows (plain data, no external
     * object dependency), builds the Unified Individual Id -> raw Customer_Key map.
     * If a unified profile maps to multiple source records (expected for the overlap
     * population, since both party identification files intentionally share the same
     * Customer_Key for those customers), the first non-blank value found wins.
     */
    @TestVisible
    static Map<String, String> buildRawKeyMap(List<BridgeRow> rows) {
        Map<String, String> rawKeyByUnifiedId = new Map<String, String>();
        if (rows == null) {
            return rawKeyByUnifiedId;
        }
        for (BridgeRow row : rows) {
            if (row == null || String.isBlank(row.unifiedId) || String.isBlank(row.sourceId)) {
                continue;
            }
            if (!rawKeyByUnifiedId.containsKey(row.unifiedId)) {
                rawKeyByUnifiedId.put(row.unifiedId, row.sourceId);
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
