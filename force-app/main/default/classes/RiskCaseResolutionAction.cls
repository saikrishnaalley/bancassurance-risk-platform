/**
 * Invocable Apex action for the Agentforce agent (Phase 6). Lets an analyst resolve a
 * Risk_Case__c directly from conversation ("mark this as a false positive"), satisfying
 * the original Fraud Analyst user story: "I want to resolve a case as Confirmed Fraud /
 * False Positive / Needs More Info, so outcomes are tracked and auditable."
 *
 * WRITE ACTION: unlike RiskCaseSummaryAction and RiskCaseQueryAction (both read-only),
 * this modifies data. In Agent Builder, "Require user confirmation" MUST be enabled on
 * this action so the analyst explicitly approves the change before it's committed --
 * the agent should never silently resolve a case without the human confirming first.
 */
public with sharing class RiskCaseResolutionAction {

    private static final Set<String> VALID_STATUSES = new Set<String>{
        'New', 'Under Investigation', 'Needs More Info', 'Confirmed Fraud', 'False Positive'
    };

    public class ResolutionRequest {
        @InvocableVariable(label='Risk Case Id')
        public String riskCaseId;

        @InvocableVariable(label='Customer Key')
        public String customerKey;

        @InvocableVariable(required=true label='New Status')
        public String newStatus;
    }

    public class ResolutionResult {
        @InvocableVariable(label='Success')
        public Boolean success = false;

        @InvocableVariable(label='Message')
        public String message;

        @InvocableVariable(label='Risk Case Id')
        public String riskCaseId;
    }

    /**
     * Resolves one or more Risk_Case__c records, looked up by Risk Case Id or Customer
     * Key (same dual-lookup pattern as RiskCaseSummaryAction), to a new status.
     * @param requests One request per case to resolve
     * @return One result per request, in the same order, with success/failure and a message
     */
    @InvocableMethod(
        label='Resolve Risk Case'
        description='Updates a Risk_Case__c status (New, Under Investigation, Needs More Info, Confirmed Fraud, or False Positive), looked up by Risk Case Id or Customer Key. This changes real data -- always confirm with the analyst before calling.'
        category='Risk'
    )
    public static List<ResolutionResult> resolveRiskCase(List<ResolutionRequest> requests) {
        List<ResolutionResult> results = new List<ResolutionResult>();
        if (requests == null || requests.isEmpty()) {
            return results;
        }

        Set<Id> directIds = new Set<Id>();
        Set<String> customerKeysToLookUp = new Set<String>();
        for (ResolutionRequest req : requests) {
            if (String.isNotBlank(req.riskCaseId)) {
                try {
                    directIds.add(Id.valueOf(req.riskCaseId));
                } catch (System.StringException e) {
                    // not a valid Id -- Customer Key lookup may still resolve it below
                }
            }
            if (String.isNotBlank(req.customerKey)) {
                customerKeysToLookUp.add(req.customerKey);
            }
        }

        Map<Id, Risk_Case__c> caseById = new Map<Id, Risk_Case__c>();
        if (!directIds.isEmpty()) {
            caseById.putAll(new Map<Id, Risk_Case__c>([
                SELECT Id, Customer_Key__c, Status__c FROM Risk_Case__c WHERE Id IN :directIds WITH SECURITY_ENFORCED
            ]));
        }

        Map<String, Id> mostRecentCaseIdByCustomerKey = new Map<String, Id>();
        if (!customerKeysToLookUp.isEmpty()) {
            for (Risk_Case__c rc : [
                SELECT Id, Customer_Key__c, Status__c
                FROM Risk_Case__c
                WHERE Customer_Key__c IN :customerKeysToLookUp
                WITH SECURITY_ENFORCED
                ORDER BY Flagged_Date__c DESC
            ]) {
                if (!mostRecentCaseIdByCustomerKey.containsKey(rc.Customer_Key__c)) {
                    mostRecentCaseIdByCustomerKey.put(rc.Customer_Key__c, rc.Id);
                    caseById.put(rc.Id, rc);
                }
            }
        }

        List<Risk_Case__c> toUpdate = new List<Risk_Case__c>();
        List<ResolutionResult> pendingResults = new List<ResolutionResult>();

        for (ResolutionRequest req : requests) {
            ResolutionResult result = new ResolutionResult();

            if (!VALID_STATUSES.contains(req.newStatus)) {
                result.success = false;
                result.message = 'Invalid status: ' + req.newStatus + '. Must be one of: ' + String.join(new List<String>(VALID_STATUSES), ', ');
                results.add(result);
                continue;
            }

            Id resolvedId = null;
            if (String.isNotBlank(req.riskCaseId)) {
                try {
                    Id maybeId = Id.valueOf(req.riskCaseId);
                    if (caseById.containsKey(maybeId)) {
                        resolvedId = maybeId;
                    }
                } catch (System.StringException e) {
                    // fall through to Customer Key lookup below
                }
            }
            if (resolvedId == null && String.isNotBlank(req.customerKey)) {
                resolvedId = mostRecentCaseIdByCustomerKey.get(req.customerKey);
            }

            Risk_Case__c rc = resolvedId != null ? caseById.get(resolvedId) : null;
            if (rc == null) {
                result.success = false;
                result.message = 'No matching Risk Case found for the provided Risk Case Id or Customer Key.';
                results.add(result);
                continue;
            }

            rc.Status__c = req.newStatus;
            toUpdate.add(rc);
            result.riskCaseId = rc.Id;
            result.success = true;
            result.message = 'Risk Case updated to ' + req.newStatus + '.';
            pendingResults.add(result);
            results.add(result);
        }

        if (!toUpdate.isEmpty()) {
            try {
                update toUpdate;
            } catch (DmlException e) {
                // Roll every result in this batch back to failure if the DML itself fails,
                // since we can't easily tell which specific record(s) caused it here.
                for (ResolutionResult r : pendingResults) {
                    r.success = false;
                    r.message = 'Could not update Risk Case: ' + e.getMessage();
                }
            }
        }

        return results;
    }
}
