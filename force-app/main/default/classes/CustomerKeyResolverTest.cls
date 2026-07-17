@isTest
private class CustomerKeyResolverTest {

    // IMPORTANT: UnifiedLinkssotIndividualRisk__dlm is a Data Cloud external object, backed by
    // Data Cloud rather than the org's own database. External objects cannot be inserted into
    // or seeded within a standard @isTest context the way regular sObjects can, and there is no
    // local mocking framework for them equivalent to Test.setMock for HTTP callouts. As a result,
    // the actual SOQL query against the bridge table cannot be exercised with synthetic data here.
    // This test class covers the boundary/input-handling logic that IS testable in isolation.
    // The query itself must be verified against real data via Execute Anonymous in the org
    // (see the Build Guide's verification steps) rather than via an automated unit test.

    @isTest
    static void testResolveRawCustomerKeys_NullSet_ReturnsEmptyMap() {
        Test.startTest();
        Map<String, String> result = new CustomerKeyResolver().resolveRawCustomerKeys(null);
        Test.stopTest();

        System.assertEquals(0, result.size(), 'A null input set should return an empty map, not throw');
    }

    @isTest
    static void testResolveRawCustomerKeys_EmptySet_ReturnsEmptyMap() {
        Test.startTest();
        Map<String, String> result = new CustomerKeyResolver().resolveRawCustomerKeys(new Set<String>());
        Test.stopTest();

        System.assertEquals(0, result.size(), 'An empty input set should return an empty map without querying');
    }

    @isTest
    static void testResolveKeys_StaticWrapper_EmptySet_ReturnsEmptyMap() {
        Test.startTest();
        Map<String, String> result = CustomerKeyResolver.resolveKeys(new Set<String>());
        Test.stopTest();

        System.assertEquals(0, result.size(), 'The static resolveKeys wrapper should behave the same as the instance method');
    }

    @isTest
    static void testResolveKey_BlankInput_ReturnsNull() {
        Test.startTest();
        String result = CustomerKeyResolver.resolveKey('');
        String resultNull = CustomerKeyResolver.resolveKey(null);
        Test.stopTest();

        System.assertEquals(null, result, 'A blank string input should resolve to null, not throw or query');
        System.assertEquals(null, resultNull, 'A null input should resolve to null, not throw or query');
    }
}
