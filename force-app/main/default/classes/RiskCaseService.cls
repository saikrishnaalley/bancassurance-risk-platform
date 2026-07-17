/**
 * Creates or updates Risk_Case__c records from Data Cloud composite risk signals, and
 * publishes a Risk_Signal_Change__e event for each. Invoked by the Data Cloud-Triggered
 * Flow (Bancassurance_Risk_Case_Automation) as an Apex Action, or directly (e.g. Execute
 * Anonymous) for manual/ad hoc testing.
 */
public with sharing class RiskCaseService {
    private static final Set<String> CLOSED_STATUSES = new Set<String>{ 'Confirmed Fraud', 'False Positive' };

    // Matches the locked-in Composite Risk Score threshold from the Bancassurance_Risk_Score
    // Calculated Insight (see Project Plan, Phase 5): a customer needs to have triggered at
    // least one of the four risk-flag rules to warrant a Risk_Case__c.
    private static final Decimal RISK_SCORE_THRESHOLD = 1;

    // Injectable seam: production uses the real CustomerKeyResolver (queries the Data Cloud
    // bridge table). Tests substitute a stub, since Data Cloud external objects can't be
    // seeded with synthetic records in a standard @isTest context.
    @TestVisible
    private static ICustomerKeyResolver keyResolver = new CustomerKeyResolver();

    /**
     * One Data Cloud composite risk signal for a single customer.
     */
    public class RiskSignalRequest {
        // Expected to be the Data Cloud Unified Individual Id (e.g. from
        // Bancassurance_Risk_Score__cio.unified_individual_id__c), NOT the raw source
        // Customer_Key. Resolved to the real raw Customer_Key internally below before
        // anything is stored -- see CustomerKeyResolver for why these differ.
        @InvocableVariable(required=true label='Customer Key')
        public String customerKey;

        @InvocableVariable(required=true label='Composite Risk Score')
        public Decimal riskScore;

        @InvocableVariable(label='Risk Reason Summary')
        public String riskReasonSummary;
    }

    /**
     * Outcome of processing one RiskSignalRequest.
     */
    public class RiskSignalResult {
        @InvocableVariable(label='Risk Case Id')
        public Id riskCaseId;

        @InvocableVariable(label='Was Created')
        public Boolean wasCreated;
    }

    @InvocableMethod(
        label='Create or Update Risk Case'
        description='Resolves the Unified Individual Id to the real raw Customer_Key, then upserts an open Risk_Case__c from a Data Cloud composite risk signal (score >= threshold only) and publishes a Risk_Signal_Change__e event.'
        category='Risk'
    )
    public static List<RiskSignalResult> createOrUpdateRiskCase(List<RiskSignalRequest> requests) {
        List<RiskSignalResult> results = new List<RiskSignalResult>();
        if (requests == null || requests.isEmpty()) {
            return results;
        }

        // Filter to qualifying requests up front. The Data Cloud-Triggered Flow entry
        // conditions cannot filter directly on the Calculated Insight's custom output field
        // (composite_risk_score__c), so this method is the actual threshold enforcement point.
        List<RiskSignalRequest> qualifying = new List<RiskSignalRequest>();
        Set<String> unifiedIds = new Set<String>();
        for (RiskSignalRequest req : requests) {
            if (String.isNotBlank(req.customerKey)
                && req.riskScore != null
                && req.riskScore >= RISK_SCORE_THRESHOLD) {
                qualifying.add(req);
                unifiedIds.add(req.customerKey);
            }
        }
        if (qualifying.isEmpty()) {
            return results;
        }

        // Resolve Unified Individual Id -> real raw Customer_Key before anything else,
        // so Risk_Case__c.Customer_Key__c always matches Financial_Account__c.Customer_Key__c
        // and Insurance_Policy__c.Customer_Key__c (both populated from the raw source data).
        Map<String, String> rawKeyByUnifiedId = keyResolver.resolveRawCustomerKeys(unifiedIds);

        Set<String> customerKeys = new Set<String>();
        for (RiskSignalRequest req : qualifying) {
            String rawKey = rawKeyByUnifiedId.get(req.customerKey);
            if (String.isBlank(rawKey)) {
                System.debug(
                    LoggingLevel.WARN,
                    'RiskCaseService: could not resolve raw Customer_Key for Unified Individual Id '
                    + req.customerKey + '; skipping this request rather than storing an unresolved key.'
                );
                continue;
            }
            customerKeys.add(rawKey);
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

        // NOTE: this class does not currently enforce field-level security (FLS) or object
        // CRUD permissions beyond the sharing rules implied by `with sharing`. For a
        // production deployment, wrap the DML below with Security.stripInaccessible() or
        // annotate the SOQL with WITH SECURITY_ENFORCED.
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

        for (RiskSignalRequest req : qualifying) {
            String rawKey = rawKeyByUnifiedId.get(req.customerKey);
            if (String.isBlank(rawKey)) {
                continue;
            }

            Risk_Case__c riskCase = openCaseByCustomerKey.get(rawKey);
            Boolean isNew = riskCase == null;
            if (isNew) {
                riskCase = new Risk_Case__c(
                    Customer_Key__c = rawKey,
                    Status__c = 'New',
                    Flagged_Date__c = System.now()
                );
                if (householdByCustomerKey.containsKey(rawKey)) {
                    riskCase.Household__c = householdByCustomerKey.get(rawKey);
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

        List<Database.SaveResult> publishResults = EventBus.publish(events);
        for (Database.SaveResult sr : publishResults) {
            if (!sr.isSuccess()) {
                for (Database.Error err : sr.getErrors()) {
                    System.debug(
                        LoggingLevel.ERROR,
                        'Risk_Signal_Change__e publish failed: ' + err.getStatusCode() + ' - ' + err.getMessage()
                    );
                }
            }
        }

        return results;
    }
}
