/**
 * Invocable Apex action for the Agentforce agent (Phase 6). Lets an analyst ask
 * queue-style questions in natural language ("what cases need my attention",
 * "show me the highest risk cases") instead of only summarizing one case at a time.
 * Read-only -- no confirmation needed in Agent Builder.
 *
 * Output is deliberately flattened to plain primitives (a single formatted text summary,
 * not a nested List<CustomClass>). An earlier version returned a List<RiskCaseSummary>
 * (a "list of object" output) which caused the entire action's schema to fail to
 * register in Agent Builder -- even the org's own built-in AnswerQuestionsWithKnowledge
 * action showed the same class of error, suggesting this Agentforce release doesn't
 * reliably handle nested list-of-object Invocable outputs. Flattening to primitives
 * avoids the issue entirely and matches the pattern already proven working elsewhere
 * in this project (RiskCaseSummaryAction, RiskCaseResolutionAction).
 */
public with sharing class RiskCaseQueryAction {

    private static final Set<String> OPEN_STATUSES = new Set<String>{ 'New', 'Under Investigation', 'Needs More Info' };

    public class RiskCaseQueryRequest {
        @InvocableVariable(label='Maximum Results')
        public Integer maxResults;

        @InvocableVariable(label='Minimum Risk Score')
        public Decimal minRiskScore;
    }

    public class RiskCaseQueryResult {
        @InvocableVariable(label='Total Open Cases')
        public Integer totalOpenCases = 0;

        @InvocableVariable(label='Returned Case Count')
        public Integer returnedCaseCount = 0;

        @InvocableVariable(label='Case Summary Text')
        public String caseSummaryText;
    }

    /**
     * Returns open Risk_Case__c records, highest risk first, optionally capped and/or
     * filtered to a minimum score, as a single formatted text summary. Mirrors the same
     * open-case definition and ordering used by RiskCaseQueueController's LWC-facing
     * queue, so the agent's answer matches what an analyst would see in the Risk Case Queue.
     * @param requests One request; only the first is used (single-query action)
     * @return Total open case count, returned count, and a formatted text summary of up
     *         to maxResults (default 5, capped at 50) matching cases
     */
    @InvocableMethod(
        label='Query Open Risk Cases'
        description='Answers queue-style questions like "what cases need my attention" or "show me the highest risk cases" by returning a text summary of real open Risk_Case__c records, highest risk first.'
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
     * TESTABLE: pure logic, builds the flattened result payload (including the formatted
     * text summary) from already-fetched records.
     * @param matches Risk_Case__c records already queried
     * @param totalOpenCases Total count of open cases matching the filter (may exceed matches.size() if capped)
     * @return RiskCaseQueryResult with the formatted summary text and counts
     */
    @TestVisible
    static RiskCaseQueryResult buildResult(List<Risk_Case__c> matches, Integer totalOpenCases) {
        RiskCaseQueryResult result = new RiskCaseQueryResult();
        result.totalOpenCases = totalOpenCases;

        if (matches == null || matches.isEmpty()) {
            result.returnedCaseCount = 0;
            result.caseSummaryText = 'No open risk cases match the given criteria.';
            return result;
        }

        result.returnedCaseCount = matches.size();

        List<String> lines = new List<String>();
        Integer i = 1;
        for (Risk_Case__c rc : matches) {
            String household = rc.Household__r != null ? rc.Household__r.Name : rc.Customer_Key__c;
            lines.add(
                i + '. ' + household
                + ' -- Score: ' + (rc.Risk_Score__c != null ? String.valueOf(rc.Risk_Score__c) : 'N/A')
                + ', Status: ' + rc.Status__c
                + ', Customer Key: ' + rc.Customer_Key__c
            );
            i++;
        }
        result.caseSummaryText = String.join(lines, '\n');

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