/**
 * Backend controller for the riskCaseQueue LWC (Fraud/Risk Analyst persona, Phase 6).
 * Exposes the open Risk_Case__c queue, sorted by risk score, and a resolve action.
 */
public with sharing class RiskCaseQueueController {

    /** Flattened, LWC-friendly view of a Risk_Case__c record. */
    public class RiskCaseRecord {
        @AuraEnabled public Id id;
        @AuraEnabled public String customerKey;
        @AuraEnabled public Decimal riskScore;
        @AuraEnabled public String status;
        @AuraEnabled public String riskReasonSummary;
        @AuraEnabled public Datetime flaggedDate;
        @AuraEnabled public String householdName;
    }

    // Statuses considered "open" / actionable for the analyst queue.
    private static final Set<String> OPEN_STATUSES = new Set<String>{ 'New', 'Under Investigation', 'Needs More Info' };

    /**
     * Returns open Risk_Case__c records for the analyst queue, highest risk first.
     * @return Up to 200 open Risk_Case__c records, flattened for the LWC
     */
    @AuraEnabled(cacheable=true)
    public static List<RiskCaseRecord> getOpenRiskCases() {
        List<RiskCaseRecord> results = new List<RiskCaseRecord>();

        for (Risk_Case__c rc : [
            SELECT Id, Customer_Key__c, Risk_Score__c, Status__c, Risk_Reason_Summary__c,
                   Flagged_Date__c, Household__r.Name
            FROM Risk_Case__c
            WHERE Status__c IN :OPEN_STATUSES
            WITH SECURITY_ENFORCED
            ORDER BY Risk_Score__c DESC, Flagged_Date__c ASC
            LIMIT 200
        ]) {
            RiskCaseRecord rec = new RiskCaseRecord();
            rec.id = rc.Id;
            rec.customerKey = rc.Customer_Key__c;
            rec.riskScore = rc.Risk_Score__c;
            rec.status = rc.Status__c;
            rec.riskReasonSummary = rc.Risk_Reason_Summary__c;
            rec.flaggedDate = rc.Flagged_Date__c;
            rec.householdName = rc.Household__r != null ? rc.Household__r.Name : null;
            results.add(rec);
        }

        return results;
    }

    /**
     * Updates a Risk_Case__c's status from the analyst queue's inline resolve action.
     * @param riskCaseId Id of the Risk_Case__c to update
     * @param newStatus New status value; must be one of the real Status__c picklist values
     */
    @AuraEnabled
    public static void resolveRiskCase(Id riskCaseId, String newStatus) {
        Set<String> validStatuses = new Set<String>{
            'New', 'Under Investigation', 'Needs More Info', 'Confirmed Fraud', 'False Positive'
        };
        if (!validStatuses.contains(newStatus)) {
            throw new AuraHandledException('Invalid status: ' + newStatus);
        }

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

        Risk_Case__c rc = matches[0];
        rc.Status__c = newStatus;

        try {
            update rc;
        } catch (DmlException e) {
            throw new AuraHandledException('Could not update risk case: ' + e.getMessage());
        }
    }
}
