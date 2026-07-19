import { LightningElement, wire } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getOpenRiskCases from '@salesforce/apex/RiskCaseQueueController.getOpenRiskCases';
import resolveRiskCase from '@salesforce/apex/RiskCaseQueueController.resolveRiskCase';

const RESOLVE_OPTIONS = [
    { label: 'Under Investigation', value: 'Under Investigation' },
    { label: 'Needs More Info', value: 'Needs More Info' },
    { label: 'Confirmed Fraud', value: 'Confirmed Fraud' },
    { label: 'False Positive', value: 'False Positive' }
];

export default class RiskCaseQueue extends LightningElement {
    wiredResult;
    cases = [];
    isLoading = true;
    resolveOptions = RESOLVE_OPTIONS;

    @wire(getOpenRiskCases)
    wiredCases(result) {
        this.wiredResult = result;
        this.isLoading = false;
        if (result.data) {
            this.cases = result.data.map((c) => ({
                ...c,
                severityClass: this.getSeverityClass(c.riskScore),
                displayName: c.householdName || c.customerKey,
                flaggedDateDisplay: c.flaggedDate
            }));
        } else if (result.error) {
            this.cases = [];
            this.showToast('Error loading risk cases', this.reduceError(result.error), 'error');
        }
    }

    get hasCases() {
        return this.cases && this.cases.length > 0;
    }

    get caseCountLabel() {
        const count = this.cases ? this.cases.length : 0;
        return count === 1 ? '1 open case' : `${count} open cases`;
    }

    getSeverityClass(score) {
        if (score >= 4) {
            return 'severity-badge severity-high';
        } else if (score >= 2) {
            return 'severity-badge severity-medium';
        }
        return 'severity-badge severity-low';
    }

    async handleResolve(event) {
        const caseId = event.currentTarget.dataset.id;
        const newStatus = event.detail.value;

        try {
            await resolveRiskCase({ riskCaseId: caseId, newStatus });
            this.showToast('Case updated', `Status set to ${newStatus}`, 'success');
            await refreshApex(this.wiredResult);
        } catch (error) {
            this.showToast('Could not update case', this.reduceError(error), 'error');
        }
    }

    reduceError(error) {
        if (error && error.body && error.body.message) {
            return error.body.message;
        }
        if (error && error.message) {
            return error.message;
        }
        return 'An unknown error occurred.';
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}
