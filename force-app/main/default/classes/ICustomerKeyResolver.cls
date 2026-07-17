public interface ICustomerKeyResolver {
    Map<String, String> resolveRawCustomerKeys(Set<String> unifiedIndividualIds);
}
