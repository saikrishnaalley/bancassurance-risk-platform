import { LightningElement } from 'lwc';
import {
    subscribe,
    unsubscribe,
    onError,
    isEmpEnabled
} from 'lightning/empApi';

const CHANNEL_NAME = '/data/Risk_Case__ChangeEvent';
const MAX_EVENTS_SHOWN = 25;

export default class RiskSignalFeed extends LightningElement {
    subscription = {};
    events = [];
    isSubscribed = false;
    connectionError;
    nextEventKey = 0;

    connectedCallback() {
        this.registerErrorListener();
        this.handleSubscribe();
    }

    disconnectedCallback() {
        this.handleUnsubscribe();
    }

    async handleSubscribe() {
        try {
            const enabled = await isEmpEnabled();
            if (!enabled) {
                this.connectionError = 'Streaming API (empApi) is not enabled for this session.';
                return;
            }

            const subscription = await subscribe(CHANNEL_NAME, -1, (message) => {
                this.handleIncomingEvent(message);
            });
            this.subscription = subscription;
            this.isSubscribed = true;
            this.connectionError = null;
        } catch (error) {
            this.connectionError = this.reduceError(error);
        }
    }

    handleUnsubscribe() {
        if (this.subscription && this.isSubscribed) {
            unsubscribe(this.subscription, () => {
                this.isSubscribed = false;
            });
        }
    }

    registerErrorListener() {
        onError((error) => {
            this.connectionError = this.reduceError(error);
        });
    }

    handleIncomingEvent(message) {
        const header = message?.data?.payload?.ChangeEventHeader;
        if (!header) {
            return;
        }

        const entry = {
            key: this.nextEventKey++,
            entityName: header.entityName,
            changeType: header.changeType,
            recordIds: (header.recordIds || []).join(', '),
            receivedAt: new Date().toISOString(),
            replayId: message?.data?.event?.replayId
        };

        this.events = [entry, ...this.events].slice(0, MAX_EVENTS_SHOWN);
    }

    get hasEvents() {
        return this.events.length > 0;
    }

    get statusLabel() {
        if (this.connectionError) {
            return 'Connection error';
        }
        return this.isSubscribed ? 'Listening for changes' : 'Connecting...';
    }

    get statusClass() {
        if (this.connectionError) {
            return 'status-error';
        }
        return this.isSubscribed ? 'status-live' : 'status-connecting';
    }

    reduceError(error) {
        if (error && error.message) {
            return error.message;
        }
        if (typeof error === 'string') {
            return error;
        }
        return 'An unknown streaming error occurred.';
    }
}