import { LightningElement, api, wire } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getRiskSummary from '@salesforce/apex/BranchAgentRiskController.getRiskSummary';
import escalateToAnalyst from '@salesforce/apex/BranchAgentRiskController.escalateToAnalyst';

export default class BranchAgentRiskIndicator extends LightningElement {
    @api recordId; // Household__c Id, auto-provided by the Lightning Record Page
    wiredResult;
    summary;
    isLoading = true;
    isEscalating = false;

    @wire(getRiskSummary, { householdId: '$recordId' })
    wiredSummary(result) {
        this.wiredResult = result;
        this.isLoading = false;
        if (result.data) {
            this.summary = result.data;
        } else if (result.error) {
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Could not load risk status',
                    message: this.reduceError(result.error),
                    variant: 'error'
                })
            );
        }
    }

    get isFlagged() {
        return !!(this.summary && this.summary.isFlagged);
    }

    get statusLabel() {
        return this.isFlagged ? 'Flagged for Review' : 'No Active Flags';
    }

    get indicatorClass() {
        return this.isFlagged ? 'indicator-flagged' : 'indicator-clear';
    }

    get iconName() {
        return this.isFlagged ? 'utility:warning' : 'utility:success';
    }

    get canEscalate() {
        return this.isFlagged && this.summary.status !== 'Under Investigation';
    }

    async handleEscalate() {
        this.isEscalating = true;
        try {
            await escalateToAnalyst({ riskCaseId: this.summary.riskCaseId });
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Escalated',
                    message: 'This case has been sent to the fraud analyst queue.',
                    variant: 'success'
                })
            );
            await refreshApex(this.wiredResult);
        } catch (error) {
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Could not escalate',
                    message: this.reduceError(error),
                    variant: 'error'
                })
            );
        } finally {
            this.isEscalating = false;
        }
    }

    reduceError(error) {
        if (error && error.body && error.body.message) {
            return error.body.message;
        }
        return 'An unknown error occurred.';
    }
}
