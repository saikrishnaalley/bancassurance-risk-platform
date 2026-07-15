public with sharing class RiskCaseService {
    private static final Set<String> CLOSED_STATUSES = new Set<String>{ 'Confirmed Fraud', 'False Positive' };

    public class RiskSignalRequest {
        @InvocableVariable(required=true label='Customer Key')
        public String customerKey;

        @InvocableVariable(required=true label='Composite Risk Score')
        public Decimal riskScore;

        @InvocableVariable(label='Risk Reason Summary')
        public String riskReasonSummary;
    }

    public class RiskSignalResult {
        @InvocableVariable(label='Risk Case Id')
        public Id riskCaseId;

        @InvocableVariable(label='Was Created')
        public Boolean wasCreated;
    }

    @InvocableMethod(
        label='Create or Update Risk Case'
        description='Upserts an open Risk_Case__c from a Data Cloud composite risk signal and publishes a Risk_Signal_Change__e event.'
        category='Risk'
    )
    public static List<RiskSignalResult> createOrUpdateRiskCase(List<RiskSignalRequest> requests) {
        List<RiskSignalResult> results = new List<RiskSignalResult>();
        if (requests == null || requests.isEmpty()) {
            return results;
        }

        Set<String> customerKeys = new Set<String>();
        for (RiskSignalRequest req : requests) {
            if (String.isNotBlank(req.customerKey)) {
                customerKeys.add(req.customerKey);
            }
        }
        if (customerKeys.isEmpty()) {
            return results;
        }

        Map<String, Risk_Case__c> openCaseByCustomerKey = new Map<String, Risk_Case__c>();
        for (Risk_Case__c existing : [
            SELECT Id, Customer_Key__c, Risk_Score__c, Risk_Reason_Summary__c, Status__c, Flagged_Date__c
            FROM Risk_Case__c
            WHERE Customer_Key__c IN :customerKeys AND Status__c NOT IN :CLOSED_STATUSES
            ORDER BY Flagged_Date__c DESC
        ]) {
            if (!openCaseByCustomerKey.containsKey(existing.Customer_Key__c)) {
                openCaseByCustomerKey.put(existing.Customer_Key__c, existing);
            }
        }

        Map<String, Id> householdByCustomerKey = new Map<String, Id>();
        for (Financial_Account__c acct : [
            SELECT Customer_Key__c, Household__c
            FROM Financial_Account__c
            WHERE Customer_Key__c IN :customerKeys AND Household__c != null
        ]) {
            if (!householdByCustomerKey.containsKey(acct.Customer_Key__c)) {
                householdByCustomerKey.put(acct.Customer_Key__c, acct.Household__c);
            }
        }

        List<Risk_Case__c> toUpsert = new List<Risk_Case__c>();
        List<Boolean> isNewByIndex = new List<Boolean>();

        for (RiskSignalRequest req : requests) {
            if (String.isBlank(req.customerKey) || req.riskScore == null) {
                continue;
            }

            Risk_Case__c riskCase = openCaseByCustomerKey.get(req.customerKey);
            Boolean isNew = riskCase == null;
            if (isNew) {
                riskCase = new Risk_Case__c(
                    Customer_Key__c = req.customerKey,
                    Status__c = 'New',
                    Flagged_Date__c = System.now()
                );
                if (householdByCustomerKey.containsKey(req.customerKey)) {
                    riskCase.Household__c = householdByCustomerKey.get(req.customerKey);
                }
            }

            riskCase.Risk_Score__c = req.riskScore;
            if (String.isNotBlank(req.riskReasonSummary)) {
                riskCase.Risk_Reason_Summary__c = req.riskReasonSummary;
            }

            toUpsert.add(riskCase);
            isNewByIndex.add(isNew);
        }

        if (toUpsert.isEmpty()) {
            return results;
        }

        upsert toUpsert;

        List<Risk_Signal_Change__e> events = new List<Risk_Signal_Change__e>();
        for (Integer i = 0; i < toUpsert.size(); i++) {
            Risk_Case__c saved = toUpsert[i];
            events.add(new Risk_Signal_Change__e(
                Risk_Case_Id__c = saved.Id,
                Customer_Key__c = saved.Customer_Key__c,
                Risk_Score__c = saved.Risk_Score__c,
                Change_Type__c = isNewByIndex[i] ? 'Created' : 'Updated'
            ));

            RiskSignalResult result = new RiskSignalResult();
            result.riskCaseId = saved.Id;
            result.wasCreated = isNewByIndex[i];
            results.add(result);
        }

        EventBus.publish(events);

        return results;
    }
}
