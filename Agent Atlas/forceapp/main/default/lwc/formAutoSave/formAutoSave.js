import { LightningElement, api } from 'lwc';

export default class FormAutoSave
    extends LightningElement {

    @api saveIntervalSeconds = 30;

    @api throttleLimitSeconds = 10;

    _timerInstance;

    _lastSavedTime = 0;

    _boundBlurHandler;

    connectedCallback() {

        this.startTimer();

        // CREATE STABLE BOUND REFERENCE

        this._boundBlurHandler =
            this.handleWindowBlur.bind(this);

        // TRIGGER AUTO-SAVE WHEN
        // USER LEAVES TAB OR WINDOW

        window.addEventListener(
            'blur',
            this._boundBlurHandler
        );

    }

    disconnectedCallback() {

        this.stopTimer();

        // CLEANUP EVENT LISTENER

        window.removeEventListener(
            'blur',
            this._boundBlurHandler
        );

    }

    startTimer() {

        this.stopTimer();

        this._timerInstance =
            setInterval(() => {

                this.evaluateAndTriggerSave(
                    'Timer Interval Execution'
                );

            }, this.saveIntervalSeconds * 1000);

    }

    stopTimer() {

        if (this._timerInstance) {

            clearInterval(
                this._timerInstance
            );

        }

    }

    handleWindowBlur() {

        this.evaluateAndTriggerSave(
            'Window Blur Event'
        );

    }

    @api
    forceTriggerSave(reason) {

        this.evaluateAndTriggerSave(

            reason ||
            'Manual Programmatic Override'

        );

    }

    evaluateAndTriggerSave(triggerType) {

        const currentTime = Date.now();

        const differenceInSeconds =

            (currentTime -
                this._lastSavedTime) / 1000;

        // THROTTLE SAFEGUARD

        if (
            differenceInSeconds <
            this.throttleLimitSeconds
        ) {

            console.log(

                `Auto-save throttled. Only ${differenceInSeconds.toFixed(1)}s elapsed of required ${this.throttleLimitSeconds}s.`

            );

            return;

        }

        this._lastSavedTime =
            currentTime;

        // NOTIFY PARENT TO SAVE

        this.dispatchEvent(
            new CustomEvent(
                'autosaverequest',

                {

                    detail: {
                        trigger: triggerType
                    }

                }
            )
        );

    }

}