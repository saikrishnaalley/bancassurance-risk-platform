/**
 * Invocable Apex action for the Agentforce agent (Phase 6). Gathers the real, grounded
 * facts about why a Risk_Case__c was flagged -- the four locked-in rule thresholds, the
 * customer's actual banking/insurance data -- so the agent's prompt template generates a
 * genuine, data-grounded explanation instead of an unconstrained/hallucinated one.
 *
 * This does NOT generate the natural-language summary itself -- that's the job of the
 * agent's own reasoning/prompt instructions, which take this action's output as grounding
 * facts. This action's job is purely to fetch and structure real facts.
 *
 * Accepts EITHER a Risk Case Id OR a Customer Key -- analysts naturally think and ask in
 * terms of a customer ("summarize the risk for CUST-001168"), not the internal Salesforce
 * record Id, so both lookup paths are supported.
 */
public with sharing class RiskCaseSummaryAction {

    private static final Set<String> CLOSED_STATUSES = new Set<String>{ 'Confirmed Fraud', 'False Positive' };

    public class RiskCaseSummaryRequest {
        @InvocableVariable(label='Risk Case Id')
        public String riskCaseId;

        @InvocableVariable(label='Customer Key')
        public String customerKey;
    }

    public class RiskCaseSummaryContext {
        @InvocableVariable(label='Found')
        public Boolean found = false;

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
     * Gathers real, grounded context for one or more Risk_Case__c records, looked up by
     * either Risk Case Id or Customer Key, for the Agentforce agent to summarize.
     * @param requests One request per case to summarize; each needs riskCaseId OR customerKey
     * @return One context per request, in the same order; found = false and blank fields
     *         where no match exists
     */
    @InvocableMethod(
        label='Get Risk Case Summary Context'
        description='Gathers real Risk_Case__c, Financial_Account__c, and Insurance_Policy__c facts (by Risk Case Id or Customer Key) for the Agentforce agent to summarize -- grounds the AI explanation in real data rather than letting it guess.'
        category='Risk'
    )
    public static List<RiskCaseSummaryContext> getSummaryContext(List<RiskCaseSummaryRequest> requests) {
        List<RiskCaseSummaryContext> results = new List<RiskCaseSummaryContext>();
        if (requests == null || requests.isEmpty()) {
            return results;
        }

        // Resolve each request's direct Risk Case Id (if given and valid).
        Set<Id> directIds = new Set<Id>();
        Set<String> customerKeysToLookUp = new Set<String>();
        for (RiskCaseSummaryRequest req : requests) {
            if (String.isNotBlank(req.riskCaseId)) {
                try {
                    directIds.add(Id.valueOf(req.riskCaseId));
                } catch (System.StringException e) {
                    System.debug(LoggingLevel.WARN, 'RiskCaseSummaryAction: not a valid Risk Case Id, will try Customer Key instead: ' + req.riskCaseId);
                }
            }
            if (String.isNotBlank(req.customerKey)) {
                customerKeysToLookUp.add(req.customerKey);
            }
        }

        Map<Id, Risk_Case__c> caseById = new Map<Id, Risk_Case__c>();
        Map<String, Id> openCaseIdByCustomerKey = new Map<String, Id>();

        if (!directIds.isEmpty()) {
            caseById.putAll(new Map<Id, Risk_Case__c>([
                SELECT Id, Customer_Key__c, Household__c, Household__r.Name, Risk_Score__c,
                       Status__c, Risk_Reason_Summary__c
                FROM Risk_Case__c
                WHERE Id IN :directIds
                WITH SECURITY_ENFORCED
            ]));
        }

        if (!customerKeysToLookUp.isEmpty()) {
            // Prefer an OPEN case per customer, most recently flagged, matching the same
            // dedup convention RiskCaseService already uses elsewhere in this project.
            for (Risk_Case__c rc : [
                SELECT Id, Customer_Key__c, Household__c, Household__r.Name, Risk_Score__c,
                       Status__c, Risk_Reason_Summary__c, Flagged_Date__c
                FROM Risk_Case__c
                WHERE Customer_Key__c IN :customerKeysToLookUp
                WITH SECURITY_ENFORCED
                ORDER BY Flagged_Date__c DESC
            ]) {
                if (!openCaseIdByCustomerKey.containsKey(rc.Customer_Key__c)
                    && !CLOSED_STATUSES.contains(rc.Status__c)) {
                    openCaseIdByCustomerKey.put(rc.Customer_Key__c, rc.Id);
                    caseById.put(rc.Id, rc);
                }
            }
            // Fall back to the most recent case (even if closed) for any customer key with
            // no open case, so a lookup by customer still returns something useful.
            for (Risk_Case__c rc : [
                SELECT Id, Customer_Key__c, Household__c, Household__r.Name, Risk_Score__c,
                       Status__c, Risk_Reason_Summary__c, Flagged_Date__c
                FROM Risk_Case__c
                WHERE Customer_Key__c IN :customerKeysToLookUp
                WITH SECURITY_ENFORCED
                ORDER BY Flagged_Date__c DESC
            ]) {
                if (!openCaseIdByCustomerKey.containsKey(rc.Customer_Key__c)) {
                    openCaseIdByCustomerKey.put(rc.Customer_Key__c, rc.Id);
                    caseById.put(rc.Id, rc);
                }
            }
        }

        Set<String> customerKeysForAccountsAndPolicies = new Set<String>();
        for (Risk_Case__c rc : caseById.values()) {
            if (String.isNotBlank(rc.Customer_Key__c)) {
                customerKeysForAccountsAndPolicies.add(rc.Customer_Key__c);
            }
        }

        Map<String, Financial_Account__c> accountByCustomerKey = new Map<String, Financial_Account__c>();
        Map<String, Insurance_Policy__c> policyByCustomerKey = new Map<String, Insurance_Policy__c>();
        if (!customerKeysForAccountsAndPolicies.isEmpty()) {
            for (Financial_Account__c acct : [
                SELECT Customer_Key__c, Account_Type__c, Balance__c
                FROM Financial_Account__c
                WHERE Customer_Key__c IN :customerKeysForAccountsAndPolicies
                WITH SECURITY_ENFORCED
            ]) {
                if (!accountByCustomerKey.containsKey(acct.Customer_Key__c)) {
                    accountByCustomerKey.put(acct.Customer_Key__c, acct);
                }
            }

            for (Insurance_Policy__c pol : [
                SELECT Customer_Key__c, Policy_Type__c, Vehicle_Category__c, Fraud_Flag__c, Claim_Date__c
                FROM Insurance_Policy__c
                WHERE Customer_Key__c IN :customerKeysForAccountsAndPolicies
                WITH SECURITY_ENFORCED
                ORDER BY Claim_Date__c DESC NULLS LAST
            ]) {
                if (!policyByCustomerKey.containsKey(pol.Customer_Key__c)) {
                    policyByCustomerKey.put(pol.Customer_Key__c, pol);
                }
            }
        }

        for (RiskCaseSummaryRequest req : requests) {
            RiskCaseSummaryContext context = new RiskCaseSummaryContext();

            Id resolvedId = null;
            if (String.isNotBlank(req.riskCaseId)) {
                try {
                    Id maybeId = Id.valueOf(req.riskCaseId);
                    if (caseById.containsKey(maybeId)) {
                        resolvedId = maybeId;
                    }
                } catch (System.StringException e) {
                    // not a valid Id -- fall through to Customer Key lookup below
                }
            }
            if (resolvedId == null && String.isNotBlank(req.customerKey)) {
                resolvedId = openCaseIdByCustomerKey.get(req.customerKey);
            }

            Risk_Case__c rc = resolvedId != null ? caseById.get(resolvedId) : null;

            if (rc != null) {
                context.found = true;
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