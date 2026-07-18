import { LightningElement, wire } from 'lwc';
import getDashboardData from '@salesforce/apex/ComplianceDashboardController.getDashboardData';

export default class ComplianceDashboard extends LightningElement {
    dashboardData;
    isLoading = true;
    error;

    @wire(getDashboardData)
    wiredData({ data, error }) {
        this.isLoading = false;
        if (data) {
            this.dashboardData = data;
        } else if (error) {
            this.error = this.reduceError(error);
        }
    }

    get hasData() {
        return this.dashboardData && this.dashboardData.totalCases > 0;
    }

    get totalCases() {
        return this.dashboardData ? this.dashboardData.totalCases : 0;
    }

    get statusBreakdownWithPercent() {
        if (!this.dashboardData || !this.dashboardData.statusBreakdown) {
            return [];
        }
        const total = this.dashboardData.totalCases || 1;
        return this.dashboardData.statusBreakdown.map((row) => ({
            ...row,
            percent: Math.round((row.count / total) * 100),
            barStyle: `width: ${Math.round((row.count / total) * 100)}%`
        }));
    }

    get auditTrail() {
        return this.dashboardData ? this.dashboardData.auditTrail : [];
    }

    reduceError(error) {
        if (error && error.body && error.body.message) {
            return error.body.message;
        }
        return 'An unknown error occurred.';
    }
}
