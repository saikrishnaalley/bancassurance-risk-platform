/**
 * Backend for the branchAgentRiskIndicator LWC (Phase 6). Gives a frontline branch or
 * call center agent a simplified risk signal for a customer -- no fraud-analyst detail,
 * just "is this customer flagged, and what should I do" -- plus a one-click escalation
 * that raises the linked Risk_Case__c's status for analyst follow-up.
 */
public with sharing class BranchAgentRiskController {

    private static final Set<String> CLOSED_STATUSES = new Set<String>{ 'Confirmed Fraud', 'False Positive' };

    /** Simplified risk summary for the frontline agent view. */
    public class RiskSummary {
        @AuraEnabled public Boolean isFlagged = false;
        @AuraEnabled public Id riskCaseId;
        @AuraEnabled public Decimal riskScore;
        @AuraEnabled public String status;
        @AuraEnabled public String suggestedAction;
    }

    /**
     * Returns a simplified risk summary for the Household linked to the given record.
     * Looks up the most recent OPEN Risk_Case__c for that household, if any.
     * @param householdId Id of the Household__c to check
     * @return RiskSummary; isFlagged is false if there is no open Risk_Case__c
     */
    @AuraEnabled(cacheable=true)
    public static RiskSummary getRiskSummary(Id householdId) {
        RiskSummary summary = new RiskSummary();
        if (householdId == null) {
            return summary;
        }

        List<Risk_Case__c> matches = [
            SELECT Id, Risk_Score__c, Status__c
            FROM Risk_Case__c
            WHERE Household__c = :householdId AND Status__c NOT IN :CLOSED_STATUSES
            WITH SECURITY_ENFORCED
            ORDER BY Flagged_Date__c DESC
            LIMIT 1
        ];
        if (matches.isEmpty()) {
            return summary;
        }

        Risk_Case__c riskCase = matches[0];
        summary.isFlagged = true;
        summary.riskCaseId = riskCase.Id;
        summary.riskScore = riskCase.Risk_Score__c;
        summary.status = riskCase.Status__c;
        summary.suggestedAction = buildSuggestedAction(riskCase.Risk_Score__c);
        return summary;
    }

    /**
     * TESTABLE: pure logic mapping a risk score to plain-language guidance for a
     * frontline agent (no fraud expertise assumed).
     * @param riskScore Composite risk score on the Risk_Case__c
     * @return Suggested next step, in plain language
     */
    @TestVisible
    static String buildSuggestedAction(Decimal riskScore) {
        if (riskScore == null) {
            return 'Proceed normally, and escalate if anything seems unusual.';
        } else if (riskScore >= 4) {
            return 'Verify identity carefully before proceeding. Escalate to the fraud team now.';
        } else if (riskScore >= 2) {
            return 'Proceed with extra identity verification. Consider escalating.';
        }
        return 'Proceed normally, and escalate if anything seems unusual.';
    }

    /**
     * One-click escalation: moves the Risk_Case__c to Under Investigation so it surfaces
     * in the analyst queue as needing attention.
     * @param riskCaseId Id of the Risk_Case__c to escalate
     */
    @AuraEnabled
    public static void escalateToAnalyst(Id riskCaseId) {
        List<Risk_Case__c> matches = [
            SELECT Id, Status__c
            FROM Risk_Case__c
            WHERE Id = :riskCaseId
            WITH SECURITY_ENFORCED
            LIMIT 1
        ];
        if (matches.isEmpty()) {
            throw new AuraHandledException('Risk case not found or not accessible.');
        }

        Risk_Case__c riskCase = matches[0];
        riskCase.Status__c = 'Under Investigation';
        try {
            update riskCase;
        } catch (DmlException e) {
            throw new AuraHandledException('Could not escalate risk case: ' + e.getMessage());
        }
    }
}
