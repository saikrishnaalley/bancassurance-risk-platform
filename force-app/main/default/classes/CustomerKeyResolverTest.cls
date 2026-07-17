@isTest
private class CustomerKeyResolverTest {

    // NOTE: queryBridgeRows() (the actual Data Cloud query) cannot be exercised here --
    // Data Cloud external objects can't be seeded with synthetic data in a standard @isTest
    // context, and there is no local mocking framework for them equivalent to Test.setMock
    // for HTTP callouts. That method is deliberately kept thin (see CustomerKeyResolver.cls)
    // so it contributes minimally to the class's coverage gap. Everything below tests the
    // real resolution logic (buildRawKeyMap) directly with plain in-memory data, which is
    // where the actual business logic -- and the actual risk of bugs -- lives.

    @isTest
    static void testBuildRawKeyMap_NullList_ReturnsEmptyMap() {
        Test.startTest();
        Map<String, String> result = CustomerKeyResolver.buildRawKeyMap(null);
        Test.stopTest();

        System.assertEquals(0, result.size());
    }

    @isTest
    static void testBuildRawKeyMap_EmptyList_ReturnsEmptyMap() {
        Test.startTest();
        Map<String, String> result = CustomerKeyResolver.buildRawKeyMap(new List<CustomerKeyResolver.BridgeRow>());
        Test.stopTest();

        System.assertEquals(0, result.size());
    }

    @isTest
    static void testBuildRawKeyMap_SingleRow_ResolvesCorrectly() {
        List<CustomerKeyResolver.BridgeRow> rows = new List<CustomerKeyResolver.BridgeRow>{
            new CustomerKeyResolver.BridgeRow('UNIFIED-1', 'RAW-KEY-1')
        };

        Test.startTest();
        Map<String, String> result = CustomerKeyResolver.buildRawKeyMap(rows);
        Test.stopTest();

        System.assertEquals(1, result.size());
        System.assertEquals('RAW-KEY-1', result.get('UNIFIED-1'));
    }

    @isTest
    static void testBuildRawKeyMap_MultipleRowsSameUnifiedId_FirstNonBlankWins() {
        // Simulates the real overlap-population scenario: one unified profile with two
        // bridge rows (banking-sourced and insurance-sourced), both carrying the same
        // raw Customer_Key by design.
        List<CustomerKeyResolver.BridgeRow> rows = new List<CustomerKeyResolver.BridgeRow>{
            new CustomerKeyResolver.BridgeRow('UNIFIED-2', 'RAW-KEY-2'),
            new CustomerKeyResolver.BridgeRow('UNIFIED-2', 'RAW-KEY-2')
        };

        Test.startTest();
        Map<String, String> result = CustomerKeyResolver.buildRawKeyMap(rows);
        Test.stopTest();

        System.assertEquals(1, result.size(), 'Duplicate bridge rows for the same unified id should not create extra map entries');
        System.assertEquals('RAW-KEY-2', result.get('UNIFIED-2'));
    }

    @isTest
    static void testBuildRawKeyMap_BlankOrNullFields_AreSkipped() {
        List<CustomerKeyResolver.BridgeRow> rows = new List<CustomerKeyResolver.BridgeRow>{
            new CustomerKeyResolver.BridgeRow(null, 'RAW-KEY-3'),
            new CustomerKeyResolver.BridgeRow('UNIFIED-4', null),
            new CustomerKeyResolver.BridgeRow('', 'RAW-KEY-5'),
            new CustomerKeyResolver.BridgeRow('UNIFIED-6', 'RAW-KEY-6')
        };

        Test.startTest();
        Map<String, String> result = CustomerKeyResolver.buildRawKeyMap(rows);
        Test.stopTest();

        System.assertEquals(1, result.size(), 'Only the one row with both a valid unifiedId and sourceId should resolve');
        System.assertEquals('RAW-KEY-6', result.get('UNIFIED-6'));
    }

    @isTest
    static void testBuildRawKeyMap_BulkAtTwoHundredRows_AllResolveCorrectly() {
        List<CustomerKeyResolver.BridgeRow> rows = new List<CustomerKeyResolver.BridgeRow>();
        for (Integer i = 0; i < 200; i++) {
            rows.add(new CustomerKeyResolver.BridgeRow('UNIFIED-BULK-' + i, 'RAW-BULK-' + i));
        }

        Test.startTest();
        Map<String, String> result = CustomerKeyResolver.buildRawKeyMap(rows);
        Test.stopTest();

        System.assertEquals(200, result.size());
        System.assertEquals('RAW-BULK-0', result.get('UNIFIED-BULK-0'));
        System.assertEquals('RAW-BULK-199', result.get('UNIFIED-BULK-199'));
    }

    @isTest
    static void testResolveRawCustomerKeys_EmptySet_ReturnsEmptyMap_WithoutQuerying() {
        // Exercises the instance method's early-return guard, which avoids calling
        // queryBridgeRows at all for empty input.
        Test.startTest();
        Map<String, String> result = new CustomerKeyResolver().resolveRawCustomerKeys(new Set<String>());
        Test.stopTest();

        System.assertEquals(0, result.size());
    }

    @isTest
    static void testResolveKey_BlankInput_ReturnsNull_WithoutQuerying() {
        Test.startTest();
        String result = CustomerKeyResolver.resolveKey('');
        String resultNull = CustomerKeyResolver.resolveKey(null);
        Test.stopTest();

        System.assertEquals(null, result);
        System.assertEquals(null, resultNull);
    }
}
