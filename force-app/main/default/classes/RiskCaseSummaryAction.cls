/**
 * Invocable Apex action for the Agentforce agent (Phase 6). Gathers the real, grounded
 * facts about why a Risk_Case__c was flagged -- the four locked-in rule thresholds, the
 * customer's actual banking/insurance data -- so the agent's prompt template generates a
 * genuine, data-grounded explanation instead of an unconstrained/hallucinated one.
 *
 * This does NOT generate the natural-language summary itself -- that's the job of the
 * Prompt Template built in Prompt Builder, which takes this action's output as merge
 * fields. This action's job is purely to fetch and structure real facts.
 */
public with sharing class RiskCaseSummaryAction {

    public class RiskCaseSummaryRequest {
        @InvocableVariable(required=true label='Risk Case Id')
        public String riskCaseId;
    }

    public class RiskCaseSummaryContext {
        @InvocableVariable(label='Customer Key')
        public String customerKey;

        @InvocableVariable(label='Household Name')
        public String householdName;

        @InvocableVariable(label='Composite Risk Score')
        public Decimal riskScore;

        @InvocableVariable(label='Current Status')
        public String status;

        @InvocableVariable(label='Existing Reason Summary')
        public String existingReasonSummary;

        @InvocableVariable(label='Banking Account Type')
        public String accountType;

        @InvocableVariable(label='Banking Account Balance')
        public Decimal accountBalance;

        @InvocableVariable(label='Insurance Policy Type')
        public String policyType;

        @InvocableVariable(label='Insurance Vehicle Category')
        public String vehicleCategory;

        @InvocableVariable(label='Insurance Fraud Flag')
        public Boolean insuranceFraudFlag;

        @InvocableVariable(label='Insurance Claim Date')
        public Date claimDate;
    }

    /**
     * Gathers real, grounded context for one or more Risk_Case__c records, for the
     * Agentforce agent's prompt template to summarize.
     * @param requests One request per Risk_Case__c to summarize
     * @return One context per request, in the same order; blank/null fields where no
     *         linked Household or account/policy data exists
     */
    @InvocableMethod(
        label='Get Risk Case Summary Context'
        description='Gathers real Risk_Case__c, Financial_Account__c, and Insurance_Policy__c facts for the Agentforce agent to summarize -- grounds the AI explanation in real data rather than letting it guess.'
        category='Risk'
    )
    public static List<RiskCaseSummaryContext> getSummaryContext(List<RiskCaseSummaryRequest> requests) {
        List<RiskCaseSummaryContext> results = new List<RiskCaseSummaryContext>();
        if (requests == null || requests.isEmpty()) {
            return results;
        }

        Set<Id> riskCaseIds = new Set<Id>();
        Map<String, Id> validIdByRequestString = new Map<String, Id>();
        for (RiskCaseSummaryRequest req : requests) {
            if (String.isNotBlank(req.riskCaseId)) {
                try {
                    Id validId = Id.valueOf(req.riskCaseId);
                    riskCaseIds.add(validId);
                    validIdByRequestString.put(req.riskCaseId, validId);
                } catch (System.StringException e) {
                    System.debug(LoggingLevel.WARN, 'RiskCaseSummaryAction: not a valid Id, skipping: ' + req.riskCaseId);
                }
            }
        }

        // NOTE: intentionally do NOT early-return here even if riskCaseIds is empty --
        // every request in the input list must still produce a (possibly blank) result,
        // in the same order, so callers can correlate requests to results by index.
        Map<Id, Risk_Case__c> caseById = new Map<Id, Risk_Case__c>();
        Map<String, Financial_Account__c> accountByCustomerKey = new Map<String, Financial_Account__c>();
        Map<String, Insurance_Policy__c> policyByCustomerKey = new Map<String, Insurance_Policy__c>();

        if (!riskCaseIds.isEmpty()) {
            caseById = new Map<Id, Risk_Case__c>([
                SELECT Id, Customer_Key__c, Household__c, Household__r.Name, Risk_Score__c,
                       Status__c, Risk_Reason_Summary__c
                FROM Risk_Case__c
                WHERE Id IN :riskCaseIds
                WITH SECURITY_ENFORCED
            ]);

            Set<String> customerKeys = new Set<String>();
            for (Risk_Case__c rc : caseById.values()) {
                if (String.isNotBlank(rc.Customer_Key__c)) {
                    customerKeys.add(rc.Customer_Key__c);
                }
            }

            if (!customerKeys.isEmpty()) {
                for (Financial_Account__c acct : [
                    SELECT Customer_Key__c, Account_Type__c, Balance__c
                    FROM Financial_Account__c
                    WHERE Customer_Key__c IN :customerKeys
                    WITH SECURITY_ENFORCED
                ]) {
                    if (!accountByCustomerKey.containsKey(acct.Customer_Key__c)) {
                        accountByCustomerKey.put(acct.Customer_Key__c, acct);
                    }
                }

                for (Insurance_Policy__c pol : [
                    SELECT Customer_Key__c, Policy_Type__c, Vehicle_Category__c, Fraud_Flag__c, Claim_Date__c
                    FROM Insurance_Policy__c
                    WHERE Customer_Key__c IN :customerKeys
                    WITH SECURITY_ENFORCED
                    ORDER BY Claim_Date__c DESC NULLS LAST
                ]) {
                    if (!policyByCustomerKey.containsKey(pol.Customer_Key__c)) {
                        policyByCustomerKey.put(pol.Customer_Key__c, pol);
                    }
                }
            }
        }

        for (RiskCaseSummaryRequest req : requests) {
            RiskCaseSummaryContext context = new RiskCaseSummaryContext();
            Id validId = String.isNotBlank(req.riskCaseId) ? validIdByRequestString.get(req.riskCaseId) : null;
            Risk_Case__c rc = validId != null ? caseById.get(validId) : null;

            if (rc != null) {
                context.customerKey = rc.Customer_Key__c;
                context.householdName = rc.Household__r != null ? rc.Household__r.Name : null;
                context.riskScore = rc.Risk_Score__c;
                context.status = rc.Status__c;
                context.existingReasonSummary = rc.Risk_Reason_Summary__c;

                Financial_Account__c acct = accountByCustomerKey.get(rc.Customer_Key__c);
                if (acct != null) {
                    context.accountType = acct.Account_Type__c;
                    context.accountBalance = acct.Balance__c;
                }

                Insurance_Policy__c pol = policyByCustomerKey.get(rc.Customer_Key__c);
                if (pol != null) {
                    context.policyType = pol.Policy_Type__c;
                    context.vehicleCategory = pol.Vehicle_Category__c;
                    context.insuranceFraudFlag = pol.Fraud_Flag__c;
                    context.claimDate = pol.Claim_Date__c;
                }
            }

            results.add(context);
        }

        return results;
    }
}