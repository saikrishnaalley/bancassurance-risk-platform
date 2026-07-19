import { LightningElement } from 'lwc';
import getDashboardDataForRange from '@salesforce/apex/ComplianceDashboardController.getDashboardDataForRange';

export default class ComplianceDashboard extends LightningElement {
    dashboardData;
    isLoading = true;
    error;
    startDate;
    endDate;

    connectedCallback() {
        this.loadData();
    }

    async loadData() {
        this.isLoading = true;
        try {
            this.dashboardData = await getDashboardDataForRange({
                startDate: this.startDate || null,
                endDate: this.endDate || null
            });
            this.error = null;
        } catch (error) {
            this.error = this.reduceError(error);
        } finally {
            this.isLoading = false;
        }
    }

    handleStartDateChange(event) {
        this.startDate = event.target.value;
    }

    handleEndDateChange(event) {
        this.endDate = event.target.value;
    }

    handleApplyFilter() {
        this.loadData();
    }

    handleClearFilter() {
        this.startDate = null;
        this.endDate = null;
        this.template.querySelectorAll('lightning-input').forEach((input) => {
            input.value = null;
        });
        this.loadData();
    }

    get isFiltered() {
        return !!(this.startDate || this.endDate);
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
