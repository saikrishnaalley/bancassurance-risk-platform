public with sharing class RiskCaseQueueController {

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
