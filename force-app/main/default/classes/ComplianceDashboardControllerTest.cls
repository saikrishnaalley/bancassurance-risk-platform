@isTest
private class ComplianceDashboardControllerTest {

    @TestSetup
    static void setupRunAsUser() {
        User u = new User(
            FirstName = 'RunAs',
            LastName = 'TestUser',
            Email = 'runas.testuser@bancassurance.test.invalid',
            Username = 'runas.testuser@bancassurance.test.invalid.' + Crypto.getRandomInteger(),
            Alias = 'runau',
            TimeZoneSidKey = 'America/Los_Angeles',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            ProfileId = UserInfo.getProfileId()
        );
        insert u;
    }

    private static User getRunAsUser() {
        return [SELECT Id FROM User WHERE LastName = 'TestUser' AND FirstName = 'RunAs' LIMIT 1];
    }

    @isTest
    static void testGetDashboardData_HappyPath_ReturnsAuditTrailAndBreakdown() {
        Household__c household = new Household__c(Name = 'Household CUST-000123');
        insert household;

        insert new Risk_Case__c(
            Customer_Key__c = 'CUST-000123', Household__c = household.Id,
            Status__c = 'New', Risk_Score__c = 3, Flagged_Date__c = System.now(),
            Risk_Reason_Summary__c = 'Test summary'
        );

        System.runAs(getRunAsUser()) {
            Test.startTest();
            ComplianceDashboardController.DashboardData data = ComplianceDashboardController.getDashboardData();
            Test.stopTest();

            System.assertEquals(1, data.totalCases);
            System.assertEquals(1, data.auditTrail.size());
            System.assertEquals('Household CUST-000123', data.auditTrail[0].householdName);
            System.assertEquals(1, data.statusBreakdown.size());
            System.assertEquals('New', data.statusBreakdown[0].status);
            System.assertEquals(1, data.statusBreakdown[0].count);
        }
    }

    @isTest
    static void testGetDashboardData_NoCases_ReturnsEmptyDashboard() {
        System.runAs(getRunAsUser()) {
            Test.startTest();
            ComplianceDashboardController.DashboardData data = ComplianceDashboardController.getDashboardData();
            Test.stopTest();

            System.assertEquals(0, data.totalCases);
            System.assertEquals(0, data.auditTrail.size());
            System.assertEquals(0, data.statusBreakdown.size());
        }
    }

    @isTest
    static void testBuildDashboardData_NullList_ReturnsEmptyDashboardWithoutError() {
        Test.startTest();
        ComplianceDashboardController.DashboardData data = ComplianceDashboardController.buildDashboardData(null);
        Test.stopTest();

        System.assertEquals(0, data.totalCases);
    }

    @isTest
    static void testBuildDashboardData_MultipleStatuses_BreaksDownCorrectly() {
        List<Risk_Case__c> cases = new List<Risk_Case__c>{
            new Risk_Case__c(Customer_Key__c = 'C1', Status__c = 'New', Risk_Score__c = 1, Flagged_Date__c = System.now()),
            new Risk_Case__c(Customer_Key__c = 'C2', Status__c = 'New', Risk_Score__c = 1, Flagged_Date__c = System.now()),
            new Risk_Case__c(Customer_Key__c = 'C3', Status__c = 'Confirmed Fraud', Risk_Score__c = 5, Flagged_Date__c = System.now()),
            new Risk_Case__c(Customer_Key__c = 'C4', Status__c = 'False Positive', Risk_Score__c = 1, Flagged_Date__c = System.now())
        };

        Test.startTest();
        ComplianceDashboardController.DashboardData data = ComplianceDashboardController.buildDashboardData(cases);
        Test.stopTest();

        System.assertEquals(4, data.totalCases);
        System.assertEquals(3, data.statusBreakdown.size(), 'Three distinct statuses should each have one breakdown row');

        Map<String, Integer> countByStatus = new Map<String, Integer>();
        for (ComplianceDashboardController.StatusCount sc : data.statusBreakdown) {
            countByStatus.put(sc.status, sc.count);
        }
        System.assertEquals(2, countByStatus.get('New'));
        System.assertEquals(1, countByStatus.get('Confirmed Fraud'));
        System.assertEquals(1, countByStatus.get('False Positive'));
    }

    @isTest
    static void testBuildDashboardData_BulkAtTwoHundredCases() {
        List<Risk_Case__c> cases = new List<Risk_Case__c>();
        List<String> statuses = new List<String>{ 'New', 'Under Investigation', 'Confirmed Fraud', 'False Positive' };
        for (Integer i = 0; i < 200; i++) {
            cases.add(new Risk_Case__c(
                Customer_Key__c = 'BULK-' + i,
                Status__c = statuses[Math.mod(i, 4)],
                Risk_Score__c = Math.mod(i, 5) + 1,
                Flagged_Date__c = System.now()
            ));
        }

        Test.startTest();
        ComplianceDashboardController.DashboardData data = ComplianceDashboardController.buildDashboardData(cases);
        Test.stopTest();

        System.assertEquals(200, data.totalCases);
        System.assertEquals(200, data.auditTrail.size());
        System.assertEquals(4, data.statusBreakdown.size());
        Integer sum = 0;
        for (ComplianceDashboardController.StatusCount sc : data.statusBreakdown) {
            sum += sc.count;
        }
        System.assertEquals(200, sum, 'Status breakdown counts must sum to the total case count');
    }

    @isTest
    static void testGetDashboardDataForRange_BothBounds_FiltersCorrectly() {
        insert new Risk_Case__c(Customer_Key__c = 'TOO-EARLY', Status__c = 'New', Risk_Score__c = 1, Flagged_Date__c = Datetime.newInstance(2026, 1, 1, 12, 0, 0));
        insert new Risk_Case__c(Customer_Key__c = 'IN-RANGE', Status__c = 'New', Risk_Score__c = 1, Flagged_Date__c = Datetime.newInstance(2026, 3, 15, 12, 0, 0));
        insert new Risk_Case__c(Customer_Key__c = 'TOO-LATE', Status__c = 'New', Risk_Score__c = 1, Flagged_Date__c = Datetime.newInstance(2026, 6, 1, 12, 0, 0));

        System.runAs(getRunAsUser()) {
            Test.startTest();
            ComplianceDashboardController.DashboardData data = ComplianceDashboardController.getDashboardDataForRange(
                Date.newInstance(2026, 2, 1), Date.newInstance(2026, 4, 1)
            );
            Test.stopTest();

            System.assertEquals(1, data.totalCases);
            System.assertEquals('IN-RANGE', data.auditTrail[0].customerKey);
        }
    }

    @isTest
    static void testGetDashboardDataForRange_OnlyStartDate_FiltersFromThatPointForward() {
        insert new Risk_Case__c(Customer_Key__c = 'BEFORE', Status__c = 'New', Risk_Score__c = 1, Flagged_Date__c = Datetime.newInstance(2026, 1, 1, 12, 0, 0));
        insert new Risk_Case__c(Customer_Key__c = 'AFTER', Status__c = 'New', Risk_Score__c = 1, Flagged_Date__c = Datetime.newInstance(2026, 6, 1, 12, 0, 0));

        System.runAs(getRunAsUser()) {
            Test.startTest();
            ComplianceDashboardController.DashboardData data = ComplianceDashboardController.getDashboardDataForRange(
                Date.newInstance(2026, 3, 1), null
            );
            Test.stopTest();

            System.assertEquals(1, data.totalCases);
            System.assertEquals('AFTER', data.auditTrail[0].customerKey);
        }
    }

    @isTest
    static void testGetDashboardDataForRange_OnlyEndDate_FiltersUpToThatPoint() {
        insert new Risk_Case__c(Customer_Key__c = 'BEFORE', Status__c = 'New', Risk_Score__c = 1, Flagged_Date__c = Datetime.newInstance(2026, 1, 1, 12, 0, 0));
        insert new Risk_Case__c(Customer_Key__c = 'AFTER', Status__c = 'New', Risk_Score__c = 1, Flagged_Date__c = Datetime.newInstance(2026, 6, 1, 12, 0, 0));

        System.runAs(getRunAsUser()) {
            Test.startTest();
            ComplianceDashboardController.DashboardData data = ComplianceDashboardController.getDashboardDataForRange(
                null, Date.newInstance(2026, 3, 1)
            );
            Test.stopTest();

            System.assertEquals(1, data.totalCases);
            System.assertEquals('BEFORE', data.auditTrail[0].customerKey);
        }
    }

    @isTest
    static void testGetDashboardDataForRange_NoBounds_ReturnsEverything() {
        insert new Risk_Case__c(Customer_Key__c = 'C1', Status__c = 'New', Risk_Score__c = 1, Flagged_Date__c = Datetime.newInstance(2026, 1, 1, 12, 0, 0));
        insert new Risk_Case__c(Customer_Key__c = 'C2', Status__c = 'New', Risk_Score__c = 1, Flagged_Date__c = Datetime.newInstance(2026, 6, 1, 12, 0, 0));

        System.runAs(getRunAsUser()) {
            Test.startTest();
            ComplianceDashboardController.DashboardData data = ComplianceDashboardController.getDashboardDataForRange(null, null);
            Test.stopTest();

            System.assertEquals(2, data.totalCases, 'No bounds should behave the same as the unfiltered getDashboardData');
        }
    }

    @isTest
    static void testGetDashboardDataForRange_BoundaryDatesAreInclusive() {
        insert new Risk_Case__c(Customer_Key__c = 'ON-START', Status__c = 'New', Risk_Score__c = 1, Flagged_Date__c = Datetime.newInstance(2026, 3, 1, 0, 0, 1));
        insert new Risk_Case__c(Customer_Key__c = 'ON-END', Status__c = 'New', Risk_Score__c = 1, Flagged_Date__c = Datetime.newInstance(2026, 3, 31, 23, 59, 0));

        System.runAs(getRunAsUser()) {
            Test.startTest();
            ComplianceDashboardController.DashboardData data = ComplianceDashboardController.getDashboardDataForRange(
                Date.newInstance(2026, 3, 1), Date.newInstance(2026, 3, 31)
            );
            Test.stopTest();

            System.assertEquals(2, data.totalCases, 'Records falling exactly on the start or end date should be included');
        }
    }

    @isTest
    static void testGetDashboardDataForRange_RangeExcludesEverything_ReturnsEmpty() {
        insert new Risk_Case__c(Customer_Key__c = 'C1', Status__c = 'New', Risk_Score__c = 1, Flagged_Date__c = Datetime.newInstance(2026, 1, 1, 12, 0, 0));

        System.runAs(getRunAsUser()) {
            Test.startTest();
            ComplianceDashboardController.DashboardData data = ComplianceDashboardController.getDashboardDataForRange(
                Date.newInstance(2027, 1, 1), Date.newInstance(2027, 12, 31)
            );
            Test.stopTest();

            System.assertEquals(0, data.totalCases);
            System.assertEquals(0, data.statusBreakdown.size());
        }
    }
}
