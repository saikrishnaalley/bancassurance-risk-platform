/**
 * Backend for the riskCustomerProfile LWC (Phase 6). Given a Risk_Case__c, returns the
 * linked Household's Financial_Account__c and Insurance_Policy__c records side by side,
 * so an analyst can see banking and insurance data without switching systems.
 *
 * NOTE on chronology: Insurance_Policy__c.Claim_Date__c is a real, data-derived date
 * (from the source dataset's Month/Year/WeekOfMonth fields -- see AccountBackfillService)
 * and policies ARE sorted chronologically. Financial_Account__c has no usable date field
 * in the current data model (the source dataset's Time field is seconds-elapsed-since-
 * first-transaction, not a real calendar timestamp), so accounts are NOT chronologically
 * ordered. This asymmetry is documented honestly here and surfaced in the UI.
 */
public with sharing class RiskCustomerProfileController {

    /** Flattened, LWC-friendly view of one Financial_Account__c. */
    public class AccountRecord {
        @AuraEnabled public Id id;
        @AuraEnabled public String accountNumber;
        @AuraEnabled public String accountType;
        @AuraEnabled public Decimal balance;
    }

    /** Flattened, LWC-friendly view of one Insurance_Policy__c. */
    public class PolicyRecord {
        @AuraEnabled public Id id;
        @AuraEnabled public String policyNumber;
        @AuraEnabled public String policyType;
        @AuraEnabled public String vehicleCategory;
        @AuraEnabled public Boolean fraudFlag;
        @AuraEnabled public Date claimDate;
    }

    /** Combined result: the customer's accounts and policies, plus context fields. */
    public class CustomerProfile {
        @AuraEnabled public String householdName;
        @AuraEnabled public String customerKey;
        @AuraEnabled public List<AccountRecord> accounts = new List<AccountRecord>();
        @AuraEnabled public List<PolicyRecord> policies = new List<PolicyRecord>();
    }

    /**
     * Returns the unified customer profile for the Household linked to the given Risk_Case__c.
     * @param riskCaseId Id of the Risk_Case__c to look up
     * @return CustomerProfile with accounts and policies, or an empty profile if not linked
     */
    @AuraEnabled(cacheable=true)
    public static CustomerProfile getCustomerProfile(Id riskCaseId) {
        CustomerProfile profile = new CustomerProfile();
        if (riskCaseId == null) {
            return profile;
        }

        List<Risk_Case__c> matches = [
            SELECT Customer_Key__c, Household__c, Household__r.Name
            FROM Risk_Case__c
            WHERE Id = :riskCaseId
            WITH SECURITY_ENFORCED
            LIMIT 1
        ];
        if (matches.isEmpty() || matches[0].Household__c == null) {
            return profile;
        }

        Risk_Case__c riskCase = matches[0];
        profile.customerKey = riskCase.Customer_Key__c;
        profile.householdName = riskCase.Household__r.Name;

        for (Financial_Account__c acct : [
            SELECT Id, Account_Number__c, Account_Type__c, Balance__c
            FROM Financial_Account__c
            WHERE Household__c = :riskCase.Household__c
            WITH SECURITY_ENFORCED
        ]) {
            AccountRecord rec = new AccountRecord();
            rec.id = acct.Id;
            rec.accountNumber = acct.Account_Number__c;
            rec.accountType = acct.Account_Type__c;
            rec.balance = acct.Balance__c;
            profile.accounts.add(rec);
        }

        for (Insurance_Policy__c pol : [
            SELECT Id, Policy_Number__c, Policy_Type__c, Vehicle_Category__c, Fraud_Flag__c, Claim_Date__c
            FROM Insurance_Policy__c
            WHERE Household__c = :riskCase.Household__c
            WITH SECURITY_ENFORCED
            ORDER BY Claim_Date__c DESC NULLS LAST
        ]) {
            PolicyRecord rec = new PolicyRecord();
            rec.id = pol.Id;
            rec.policyNumber = pol.Policy_Number__c;
            rec.policyType = pol.Policy_Type__c;
            rec.vehicleCategory = pol.Vehicle_Category__c;
            rec.fraudFlag = pol.Fraud_Flag__c;
            rec.claimDate = pol.Claim_Date__c;
            profile.policies.add(rec);
        }

        return profile;
    }
}
