import { LightningElement, api, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getCustomerProfile from '@salesforce/apex/RiskCustomerProfileController.getCustomerProfile';

export default class RiskCustomerProfile extends LightningElement {
    @api recordId; // Risk_Case__c Id, auto-provided by the Lightning Record Page
    profile;
    isLoading = true;

    @wire(getCustomerProfile, { riskCaseId: '$recordId' })
    wiredProfile({ data, error }) {
        this.isLoading = false;
        if (data) {
            this.profile = data;
        } else if (error) {
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Could not load customer profile',
                    message: this.reduceError(error),
                    variant: 'error'
                })
            );
        }
    }

    get hasHousehold() {
        return !!(this.profile && this.profile.householdName);
    }

    get hasAccounts() {
        return this.hasHousehold && this.profile.accounts && this.profile.accounts.length > 0;
    }

    get hasPolicies() {
        return this.hasHousehold && this.profile.policies && this.profile.policies.length > 0;
    }

    get householdName() {
        return this.profile ? this.profile.householdName : '';
    }

    reduceError(error) {
        if (error && error.body && error.body.message) {
            return error.body.message;
        }
        return 'An unknown error occurred.';
    }
}
