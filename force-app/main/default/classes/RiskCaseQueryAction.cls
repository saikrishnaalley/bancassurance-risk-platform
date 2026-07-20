/**
 * Invocable Apex action for the Agentforce agent (Phase 6). Lets an analyst ask
 * queue-style questions in natural language ("what cases need my attention",
 * "show me the highest risk cases") instead of only summarizing one case at a time.
 * Read-only -- no confirmation needed in Agent Builder.
 */
public with sharing class RiskCaseQueryAction {

    private static final Set<String> OPEN_STATUSES = new Set<String>{ 'New', 'Under Investigation', 'Needs More Info' };

    public class RiskCaseQueryRequest {
        @InvocableVariable(label='Maximum Results')
        public Integer maxResults;

        @InvocableVariable(label='Minimum Risk Score')
        public Decimal minRiskScore;
    }

    /** Flattened, agent-friendly view of one open Risk_Case__c. */
    public class RiskCaseSummary {
        @InvocableVariable(label='Risk Case Id')
        public String riskCaseId;

        @InvocableVariable(label='Customer Key')
        public String customerKey;

        @InvocableVariable(label='Household Name')
        public String householdName;

        @InvocableVariable(label='Risk Score')
        public Decimal riskScore;

        @InvocableVariable(label='Status')
        public String status;

        @InvocableVariable(label='Reason Summary')
        public String reasonSummary;
    }

    public class RiskCaseQueryResult {
        @InvocableVariable(label='Total Open Cases')
        public Integer totalOpenCases;

        @InvocableVariable(label='Cases')
        public List<RiskCaseSummary> cases = new List<RiskCaseSummary>();
    }

    /**
     * Returns open Risk_Case__c records, highest risk first, optionally capped and/or
     * filtered to a minimum score. Mirrors the same open-case definition and ordering
     * used by RiskCaseQueueController's LWC-facing queue, so the agent's answer matches
     * what an analyst would see in the Risk Case Queue.
     * @param requests One request; only the first is used (single-query action)
     * @return Total open case count and up to maxResults (default 5) matching cases
     */
    @InvocableMethod(
        label='Query Open Risk Cases'
        description='Answers queue-style questions like "what cases need my attention" or "show me the highest risk cases" by returning real open Risk_Case__c records, highest risk first.'
        category='Risk'
    )
    public static List<RiskCaseQueryResult> queryOpenCases(List<RiskCaseQueryRequest> requests) {
        List<RiskCaseQueryResult> results = new List<RiskCaseQueryResult>();

        RiskCaseQueryRequest req = (requests != null && !requests.isEmpty()) ? requests[0] : new RiskCaseQueryRequest();
        Integer limitSize = (req.maxResults != null && req.maxResults > 0) ? req.maxResults : 5;
        limitSize = Math.min(limitSize, 50);
        Decimal minScore = req.minRiskScore;

        List<Risk_Case__c> matches;
        if (minScore != null) {
            matches = [
                SELECT Id, Customer_Key__c, Household__r.Name, Risk_Score__c, Status__c, Risk_Reason_Summary__c
                FROM Risk_Case__c
                WHERE Status__c IN :OPEN_STATUSES AND Risk_Score__c >= :minScore
                WITH SECURITY_ENFORCED
                ORDER BY Risk_Score__c DESC, Flagged_Date__c ASC
                LIMIT :limitSize
            ];
        } else {
            matches = [
                SELECT Id, Customer_Key__c, Household__r.Name, Risk_Score__c, Status__c, Risk_Reason_Summary__c
                FROM Risk_Case__c
                WHERE Status__c IN :OPEN_STATUSES
                WITH SECURITY_ENFORCED
                ORDER BY Risk_Score__c DESC, Flagged_Date__c ASC
                LIMIT :limitSize
            ];
        }

        Integer totalOpen = countOpenCases(minScore);

        RiskCaseQueryResult result = buildResult(matches, totalOpen);
        results.add(result);
        return results;
    }

    /**
     * TESTABLE: pure logic, builds the result payload from already-fetched records.
     * @param matches Risk_Case__c records already queried
     * @param totalOpenCases Total count of open cases matching the filter (may exceed matches.size() if capped)
     * @return RiskCaseQueryResult with the flattened case list and total count
     */
    @TestVisible
    static RiskCaseQueryResult buildResult(List<Risk_Case__c> matches, Integer totalOpenCases) {
        RiskCaseQueryResult result = new RiskCaseQueryResult();
        result.totalOpenCases = totalOpenCases;

        if (matches == null) {
            return result;
        }

        for (Risk_Case__c rc : matches) {
            RiskCaseSummary summary = new RiskCaseSummary();
            summary.riskCaseId = rc.Id;
            summary.customerKey = rc.Customer_Key__c;
            summary.householdName = rc.Household__r != null ? rc.Household__r.Name : null;
            summary.riskScore = rc.Risk_Score__c;
            summary.status = rc.Status__c;
            summary.reasonSummary = rc.Risk_Reason_Summary__c;
            result.cases.add(summary);
        }

        return result;
    }

    private static Integer countOpenCases(Decimal minScore) {
        if (minScore != null) {
            return [
                SELECT COUNT()
                FROM Risk_Case__c
                WHERE Status__c IN :OPEN_STATUSES AND Risk_Score__c >= :minScore
                WITH SECURITY_ENFORCED
            ];
        }
        return [
            SELECT COUNT()
            FROM Risk_Case__c
            WHERE Status__c IN :OPEN_STATUSES
            WITH SECURITY_ENFORCED
        ];
    }
}
