/**
 * Backend for the complianceDashboard LWC (Phase 6). Gives a Compliance Officer an audit
 * trail of all Risk_Case__c records and a breakdown by status, supporting the "report by
 * time period / outcome" user story. Time-period filtering uses Flagged_Date__c, the only
 * date field on Risk_Case__c; there is no product-line dimension on the object today, so
 * that specific breakdown from the original user story isn't available without a schema
 * change -- documented honestly here rather than faked. (Every Risk_Case__c is inherently
 * cross-product by design -- each of the four locked-in risk rules requires both a banking
 * AND an insurance signal to fire -- so a single-value "product line" field would carry no
 * real reporting signal even if added.)
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
     * Returns the full, unfiltered audit trail (most recent first) and a status breakdown.
     * Retained for backward compatibility; delegates to the date-range overload with nulls.
     * @return DashboardData with up to 200 audit rows and a full status breakdown
     */
    @AuraEnabled(cacheable=true)
    public static DashboardData getDashboardData() {
        return getDashboardDataForRange(null, null);
    }

    /**
     * Returns the audit trail and status breakdown, optionally filtered to a Flagged_Date__c
     * range. Either bound may be null to leave that side of the range open.
     * @param startDate Inclusive lower bound on Flagged_Date__c's date portion, or null for no lower bound
     * @param endDate Inclusive upper bound on Flagged_Date__c's date portion, or null for no upper bound
     * @return DashboardData with up to 200 matching audit rows and a status breakdown of just those rows
     */
    @AuraEnabled(cacheable=true)
    public static DashboardData getDashboardDataForRange(Date startDate, Date endDate) {
        Datetime rangeStart = startDate != null ? Datetime.newInstance(startDate, Time.newInstance(0, 0, 0, 0)) : null;
        Datetime rangeEnd = endDate != null ? Datetime.newInstance(endDate, Time.newInstance(23, 59, 59, 999)) : null;

        List<Risk_Case__c> allCases;
        if (rangeStart != null && rangeEnd != null) {
            allCases = [
                SELECT Id, Customer_Key__c, Household__r.Name, Risk_Score__c, Status__c, Flagged_Date__c, Risk_Reason_Summary__c
                FROM Risk_Case__c
                WHERE Flagged_Date__c >= :rangeStart AND Flagged_Date__c <= :rangeEnd
                WITH SECURITY_ENFORCED
                ORDER BY Flagged_Date__c DESC
                LIMIT 200
            ];
        } else if (rangeStart != null) {
            allCases = [
                SELECT Id, Customer_Key__c, Household__r.Name, Risk_Score__c, Status__c, Flagged_Date__c, Risk_Reason_Summary__c
                FROM Risk_Case__c
                WHERE Flagged_Date__c >= :rangeStart
                WITH SECURITY_ENFORCED
                ORDER BY Flagged_Date__c DESC
                LIMIT 200
            ];
        } else if (rangeEnd != null) {
            allCases = [
                SELECT Id, Customer_Key__c, Household__r.Name, Risk_Score__c, Status__c, Flagged_Date__c, Risk_Reason_Summary__c
                FROM Risk_Case__c
                WHERE Flagged_Date__c <= :rangeEnd
                WITH SECURITY_ENFORCED
                ORDER BY Flagged_Date__c DESC
                LIMIT 200
            ];
        } else {
            allCases = [
                SELECT Id, Customer_Key__c, Household__r.Name, Risk_Score__c, Status__c, Flagged_Date__c, Risk_Reason_Summary__c
                FROM Risk_Case__c
                WITH SECURITY_ENFORCED
                ORDER BY Flagged_Date__c DESC
                LIMIT 200
            ];
        }

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
