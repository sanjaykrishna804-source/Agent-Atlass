import { LightningElement, api, track }
from 'lwc';

import { ShowToastEvent }
from 'lightning/platformShowToastEvent';

import fillFormWithAI
from '@salesforce/apex/AIFormFillerController.fillFormWithAI';

export default class AiFormFillerButton
    extends LightningElement {

    @api formData;

    @api currentPage;

    @api formConfig;

    @api submissionId;

    @api targetApplicationId;

    @track isProcessing = false;

    @track showResults = false;

    @track filledFieldsCount = 0;

    @track totalFieldsCount = 0;

    @track sourceBreakdown = [];

    @track processingMessage =
        'Sprinkling a little AI on your form...';

    buttonLabel = 'Fill with AI';

    showButton = true;

    showOptions = true;

    fillScope = 'fill-all';

    // LOAD

    connectedCallback() {

        this.totalFieldsCount =
            this.calculateTotalFields();

    }

    // HANDLE AI FILL

    async handleFillClick() {

        // CONFIRMATION

        const confirmed =
            await this.confirmFill();

        if (!confirmed) {

            return;

        }

        this.isProcessing = true;

        this.showButton = false;

        this.showResults = false;

        try {

            this.processingMessage =
                'Sprinkling a little AI on your form...';

            this.notifyAIStatus(
                true,
                this.processingMessage
            );

            const result =
                await fillFormWithAI({
                    targetApplicationId:
                        this.targetApplicationId || null
                });

            this.processingMessage =
                'Finding the right answers, one field at a time...';

            this.notifyAIStatus(
                true,
                this.processingMessage
            );

            await this.processResults(result);

            this.showCompletionMessage(result);

        }

        catch (error) {

            this.handleError(error);

        }

        finally {

            this.isProcessing = false;

            this.showButton = true;

            this.notifyAIStatus(
                false,
                ''
            );

        }

    }

    notifyAIStatus(isLoading, message) {

        this.dispatchEvent(
            new CustomEvent(
                'aistatuschange',
                {
                    detail: {
                        isLoading,
                        message
                    },
                    bubbles: true,
                    composed: true
                }
            )
        );

    }

    // PROCESS RESULTS

    async processResults(result) {

        const normalizedResult =
            this.normalizeFillResult(
                result
            );

        const filledData =
            normalizedResult.filledFields;

        const scopedFilledData =
            this.filterResultByScope(
                filledData
            );

        const scopedFieldMessages =
            this.filterResultByScope(
                normalizedResult.fieldMessages
            );

        this.filledFieldsCount =

            Object.keys(scopedFilledData).length;

        this.sourceBreakdown =
            this.buildSourceBreakdown(
                scopedFilledData
            );

        // SEND DATA TO PARENT

        const fillEvent =
            new CustomEvent(

                'aifilled',

                {

                    detail: {

                        filledData:
                            scopedFilledData,

                        metadata:
                            result.metadata,

                        aiComparisonResults:
                            result.aiComparisonResults,

                        fieldMessages:
                            scopedFieldMessages,

                        confidence:
                            result.overallConfidence

                    }

                }

            );

        this.dispatchEvent(fillEvent);
      //  System.debug(('fillEvent-->'+fillEvent));

    }

    normalizeFillResult(result) {

        const filledFields = {

            ...(result?.filledFields || {})

        };

        const fieldMessages = {

            ...(result?.fieldMessages || {})

        };

        Object.keys(
            fieldMessages
        ).forEach(questionId => {

            const fieldValue =
                filledFields[questionId]?.value;

            if (

                this.isBlankValue(
                    fieldValue
                )

            ) {

                delete filledFields[questionId];

            }

        });

        return {
            filledFields,
            fieldMessages
        };

    }

    isBlankValue(value) {

        return value === '' ||
            value === null ||
            value === undefined ||
            String(value).trim() === '';

    }

    filterResultByScope(resultByQuestionId) {

        if (

            !resultByQuestionId ||
            typeof resultByQuestionId !== 'object'

        ) {

            return {};

        }

        return Object.keys(resultByQuestionId).reduce((filtered, questionId) => {

            if (

                this.shouldIncludeQuestionForScope(
                    questionId
                )

            ) {

                filtered[questionId] =
                    resultByQuestionId[questionId];

            }

            return filtered;

        }, {});

    }

    shouldIncludeQuestionForScope(questionId) {

        const field =
            this.findQuestionConfig(
                questionId
            );

        if (

            this.fillScope === 'fill-current' &&
            !this.isQuestionOnCurrentPage(
                field
            )

        ) {

            return false;

        }

        if (

            this.fillScope === 'fill-empty' &&
            this.hasExistingValue(
                questionId
            )

        ) {

            return false;

        }

        return true;

    }

    findQuestionConfig(questionId) {

        if (

            !Array.isArray(
                this.formConfig
            )

        ) {

            return null;

        }

        return this.formConfig.find(config => {

            return config.id === questionId ||
                config.Question_Id__c === questionId ||
                config.questionId === questionId;

        }) || null;

    }

    isQuestionOnCurrentPage(field) {

        if (

            !field ||
            this.currentPage === undefined ||
            this.currentPage === null

        ) {

            return true;

        }

        const fieldPage =
            field.page ||
            field.Page_Number__c ||
            field.pageNumber;

        return String(fieldPage) ===
            String(this.currentPage);

    }

    hasExistingValue(questionId) {

        const value =
            this.formData?.[questionId];

        if (

            Array.isArray(
                value
            )

        ) {

            return value.length > 0;

        }

        if (

            value === true ||
            value === false ||
            value === 0

        ) {

            return true;

        }

        return String(
            value || ''
        ).trim() !== '';

    }

    // SUCCESS MESSAGE

    showCompletionMessage(result) {

        this.showResults = true;

        const toastTitle =

            result.hasWarnings

                ? 'Form Partially Filled'

                : 'Form Filled Successfully';

        const toastVariant =

            result.hasWarnings

                ? 'warning'

                : 'success';

        let message =

            `${this.filledFieldsCount}
             fields filled automatically.`;

        if (

            result.hasWarnings &&
            result.unfillableFields

        ) {

            message +=
                ` ${result.unfillableFields} field(s) need manual input.`;

        }

        this.dispatchEvent(

            new ShowToastEvent({

                title: toastTitle,

                message: message,

                variant: toastVariant,

                mode: 'sticky'

            })

        );

    }

    // CONFIRM

    confirmFill() {

        return new Promise((resolve) => {

            const message =

                this.fillScope === 'fill-all'

                    ? 'AI will fill all pages of your form using previous application data.'

                    : 'AI will fill the current page using previous application data.';

            resolve(confirm(message));

        });

    }

    // MENU

    handleMenuSelect(event) {

        const selectedValue =
            event.detail.value;

        switch (selectedValue) {

            case 'fill-all':

            case 'fill-current':

            case 'fill-empty':

                this.fillScope =
                    selectedValue;

                this.handleFillClick();

                break;

            case 'configure':

                this.openConfigurationModal();

                break;

            case 'sources':

                this.showDetailsModal();

                break;

        }

    }

    // CONFIG

    openConfigurationModal() {

        this.dispatchEvent(

            new CustomEvent('openconfig')

        );

    }

    // DETAILS

    showDetailsModal() {

        if (

            !this.hasSourceBreakdown

        ) {

            this.dispatchEvent(

                new ShowToastEvent({

                    title: 'No Source Details',

                    message:
                        'No combined source fields were returned for the latest fill.',

                    variant: 'info'

                })

            );

            return;

        }

        alert(
            this.sourceBreakdown.join(
                '\n\n'
            )
        );

        this.dispatchEvent(

            new CustomEvent(
                'showdetails',
                {
                    detail: {
                        sourceBreakdown:
                            this.sourceBreakdown
                    }
                }
            )

        );

    }

    get hasSourceBreakdown() {

        return Array.isArray(
            this.sourceBreakdown
        ) &&
            this.sourceBreakdown.length > 0;

    }

    get noSourceBreakdown() {

        return !this.hasSourceBreakdown;

    }

    buildSourceBreakdown(filledData) {

        return Object.keys(
            filledData || {}
        )
            .map(questionId => {

                const sourceFields =
                    filledData[questionId]?.sourceFields || [];

                const realSourceFields =
                    Array.isArray(
                        sourceFields
                    )
                        ? sourceFields
                            .map(sourceField => {

                                return this.normalizeSourceField(
                                    sourceField
                                );

                            })
                            .filter(sourceField => {

                                return !this.isGenericSourceField(
                                    sourceField
                                );

                            })
                        : [];

                if (

                    realSourceFields.length < 2

                ) {

                    return null;

                }

                return `${this.getQuestionLabel(questionId)}: ${realSourceFields.join(', ')}`;

            })
            .filter(Boolean);

    }

    normalizeSourceField(sourceField) {

        return String(
            sourceField || ''
        )
            .replace(/^fields merged:\s*/i, '')
            .replace(/^combined from:\s*/i, '')
            .replace(/^extracted from:\s*/i, '')
            .replace(/^fetched from:\s*/i, '')
            .trim();

    }

    isGenericSourceField(sourceField) {

        const lowerSource =
            this.normalizeSourceField(
                sourceField
            ).toLowerCase();

        return !lowerSource ||
            lowerSource === 'prompt builder' ||
            lowerSource === 'einstein prompt builder' ||
            lowerSource === 'applicant knowledge' ||
            lowerSource === 'ai' ||
            lowerSource === 'chat prompt' ||
            lowerSource.includes(
                'prompt builder'
            ) ||
            lowerSource.includes(
                'openai semantic extraction'
            );

    }

    getQuestionLabel(questionId) {

        const field =
            Array.isArray(
                this.formConfig
            )
                ? this.formConfig.find(config => {

                    return config.id === questionId ||
                        config.Question_Id__c === questionId ||
                        config.questionId === questionId;

                })
                : null;

        return field?.label ||
            field?.MasterLabel ||
            field?.questionText ||
            questionId;

    }

    // FIELD COUNT

    calculateTotalFields() {

        if (!Array.isArray(this.formConfig)) {

            return 0;

        }

        if (
            this.fillScope === 'fill-current'
        ) {

            return this.formConfig.filter(

                q =>

                    (q.page ||
                     q.Page_Number__c)

                    === this.currentPage

            ).length;

        }

        return this.formConfig.length;

    }

    // ERROR

    handleError(error) {

        console.error(
            'AI Fill Error:',
            error
        );

        const message =
            error?.body?.message ||
            error?.message ||
            'An error occurred while filling the form. Please try again.';

        console.error(
            'AI Fill Error Details:',
            JSON.stringify(
                {
                    status: error?.status,
                    statusText: error?.statusText,
                    message
                }
            )
        );

        this.dispatchEvent(

            new ShowToastEvent({

                title: 'AI Fill Failed',

                message:
                    message,

                variant: 'error'

            })

        );

    }

}
