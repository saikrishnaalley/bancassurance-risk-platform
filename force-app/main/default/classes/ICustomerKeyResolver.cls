/**
 * Contract for resolving a Data Cloud Unified Individual Id to the real raw Customer_Key.
 * Exists so RiskCaseService (and other callers) can inject a test double, since Data Cloud
 * external objects cannot be seeded with synthetic data in a standard @isTest context.
 */
public interface ICustomerKeyResolver {
    /**
     * @param unifiedIndividualIds Set of Data Cloud Unified Individual Ids to resolve
     * @return Map of Unified Individual Id to raw Customer_Key
     */
    Map<String, String> resolveRawCustomerKeys(Set<String> unifiedIndividualIds);
}
