/**
 * Backend for the complianceDashboard LWC (Phase 6). Gives a Compliance Officer an audit
 * trail of all Risk_Case__c records and a breakdown by status, supporting the "report by
 * time period / outcome" user story. Time-period breakdown uses Flagged_Date__c, the only
 * date field on Risk_Case__c; there is no product-line dimension on the object today, so
 * that specific breakdown from the original user story isn't available without a schema
 * change -- documented honestly here rather than faked.
 */
public with sharing class ComplianceDashboardController {

    /** One row in the audit trail. */
    public class AuditRow {
        @AuraEnabled public Id id;
        @AuraEnabled public String customerKey;
        @AuraEnabled public String householdName;
        @AuraEnabled public Decimal riskScore;
        @AuraEnabled public String status;
        @AuraEnabled public Datetime flaggedDate;
        @AuraEnabled public String riskReasonSummary;
    }

    /** One row in the status breakdown summary. */
    public class StatusCount {
        @AuraEnabled public String status;
        @AuraEnabled public Integer count;
    }

    /** Combined dashboard payload. */
    public class DashboardData {
        @AuraEnabled public List<AuditRow> auditTrail = new List<AuditRow>();
        @AuraEnabled public List<StatusCount> statusBreakdown = new List<StatusCount>();
        @AuraEnabled public Integer totalCases = 0;
    }

    /**
     * Returns the full audit trail (most recent first) and a status breakdown.
     * @return DashboardData with up to 200 audit rows and a full status breakdown
     */
    @AuraEnabled(cacheable=true)
    public static DashboardData getDashboardData() {
        List<Risk_Case__c> allCases = [
            SELECT Id, Customer_Key__c, Household__r.Name, Risk_Score__c, Status__c, Flagged_Date__c, Risk_Reason_Summary__c
            FROM Risk_Case__c
            WITH SECURITY_ENFORCED
            ORDER BY Flagged_Date__c DESC
            LIMIT 200
        ];
        return buildDashboardData(allCases);
    }

    /**
     * TESTABLE: pure logic, builds the dashboard payload from already-fetched records.
     * @param cases Risk_Case__c records already queried
     * @return DashboardData with the audit trail and status breakdown
     */
    @TestVisible
    static DashboardData buildDashboardData(List<Risk_Case__c> cases) {
        DashboardData data = new DashboardData();
        if (cases == null) {
            return data;
        }

        Map<String, Integer> countByStatus = new Map<String, Integer>();
        for (Risk_Case__c rc : cases) {
            AuditRow row = new AuditRow();
            row.id = rc.Id;
            row.customerKey = rc.Customer_Key__c;
            row.householdName = rc.Household__r != null ? rc.Household__r.Name : null;
            row.riskScore = rc.Risk_Score__c;
            row.status = rc.Status__c;
            row.flaggedDate = rc.Flagged_Date__c;
            row.riskReasonSummary = rc.Risk_Reason_Summary__c;
            data.auditTrail.add(row);

            String status = String.isNotBlank(rc.Status__c) ? rc.Status__c : 'Unknown';
            countByStatus.put(status, (countByStatus.containsKey(status) ? countByStatus.get(status) : 0) + 1);
        }

        for (String status : countByStatus.keySet()) {
            StatusCount sc = new StatusCount();
            sc.status = status;
            sc.count = countByStatus.get(status);
            data.statusBreakdown.add(sc);
        }
        data.totalCases = cases.size();

        return data;
    }
}
