import { LightningElement, api, track }
from 'lwc';

import loadFormConfiguration
from '@salesforce/apex/AcademicFormController.loadFormConfiguration';

import canUseAdminApplicationContext
from '@salesforce/apex/AcademicFormController.canUseAdminApplicationContext';

import canAccessAcademicApplication
from '@salesforce/apex/AcademicFormController.canAccessAcademicApplication';

import loadFormDraft
from '@salesforce/apex/AcademicFormController.loadFormDraft';

import loadFormSubmission
from '@salesforce/apex/AcademicFormController.loadFormSubmission';

import saveFormDraft
from '@salesforce/apex/AcademicFormController.saveFormDraft';

import submitForm
from '@salesforce/apex/AcademicFormController.submitForm';

import logChatDecision
from '@salesforce/apex/AIFormFillLogger.logChatDecision';

const FIELD_STATUS = {
    AI_FILLED: 'AI-filled',
    EDITED: 'Edited',
    REVERTED: 'Reverted'
};

const FIELD_MODIFIED_BY = {
    AI: 'AI',
    USER: 'User'
};

export default class AcademicApplicationForm
    extends LightningElement {

    @api recordId;

    @api cardTitle =
        'Academic Application Intake Portal';

    @api iconName =
        'standard:education';

    @api submittedHeading =
        'Application Submitted Successfully';

    @api submitButtonLabel =
        'Submit Application';

    @api pageTitlesString = '';

    @api excludedQuestionLabelsString = '';

    @api formConfigObjectApiName =
        'Form_Configuration_c__mdt';

    @api formKey =
        'academicApplication';

    // FORM CONFIG

    @track schemaQuestions = [];

    // FORM DATA

    @track formData = {};

    // PAGE

    @track currentPage = 1;

    // SAVE STATUS

    @track isSaving = false;

    @track saveStatus = '';

    @track sourceBreakdown = [];

    @track sourceBreakdownByQuestion = {};

    @track aiComparisonResults = {};

    @track aiFieldMessages = {};

    @track aiLoading = false;

    @track aiStatus =
        'Finding the right answers, one field at a time...';

    @track canUseAdminApplicationContext = false;

    @track adminApplicationId = '';

    @track adminApplicationIdIsAccessible = false;

    @track adminApplicationAccessMessage = '';

    // SUBMISSION

    @track isSubmitted = false;

    @track submittedReference = '';

    // SUBMISSION ID

    submissionId;

    // AUTOSAVE TIMER

    saveTimeout;

    localDraftKey =
        'academicApplicationFormDraft:v1';

    // TOTAL PAGES

    totalPages = 5;

    get activeAdminApplicationId() {

        return this.adminApplicationIdIsAccessible
            ? this.adminApplicationId
            : null;

    }

    get isSubmissionRecordMode() {

        return !!this.recordId;

    }

    get showManualAdminApplicationInput() {

        return this.canUseAdminApplicationContext &&
            !this.isSubmissionRecordMode;

    }

    get applicationLayoutClass() {

        return this.isSubmissionRecordMode
            ? 'application-layout record-page-layout'
            : 'application-layout';

    }

    get maxAccessiblePage() {

        return this.canUseAdminApplicationContext
            ? this.totalPages
            : Math.min(
                this.totalPages,
                5
            );

    }

    get sidebarTotalPages() {

        return this.totalPages;

    }

    get hasAutoFilledData() {

        return Object.values(
            this.formData || {}
        ).some(fieldData => {

            return fieldData?.isAutoFilled === true;

        });

    }

    // LOAD FORM

    connectedCallback() {

        this.initializeForm();

    }

    // INITIALIZE

    async initializeForm() {

        try {

            this.canUseAdminApplicationContext =
                await canUseAdminApplicationContext();

            // LOAD CONFIGURATION

            const configResult =

                await loadFormConfiguration();

            // MAP CONFIG

            this.schemaQuestions =

                configResult.map(field => {

                    return {

                        id:
                            field.Question_Id__c,

                        label:
                            field.MasterLabel,

                        type:
                            field.Question_Type__c,

                        page:
                            Number(
                                field.Page_Number__c
                            ),

                        displayOrder:
                            Number(
                                field.Display_Order__c
                            ),

                        required:
                            field.Is_Required__c,

                        helpText:
                            field.Help_Text__c,

                        validationRule:
                            field.Validation_Rule__c,

                        // FIXED PICKLIST OPTIONS

                        options:
                            field.Picklist_Values__c

                                ? field
                                    .Picklist_Values__c
                                    .split(',')

                                    .map(option => {

                                        return {

                                            label:
                                                option.trim(),

                                            value:
                                                option.trim()

                                        };

                                    })

                                : []

                    };

                });

            this.totalPages =
                Math.max(
                    1,
                    ...this.schemaQuestions.map(field => {

                        return Number(
                            field.page || 1
                        );

                    })
                );

            console.log(
                'SCHEMA:',
                JSON.stringify(
                    this.schemaQuestions
                )
            );

            // LOAD SUBMISSION RECORD OR CURRENT USER DRAFT

            const draftResult =
                this.isSubmissionRecordMode
                    ? await loadFormSubmission({
                        submissionId:
                            this.recordId
                    })
                    : await loadFormDraft();

            console.log(
                'DRAFT:',
                JSON.stringify(
                    draftResult
                )
            );

            if (draftResult) {

                this.submissionId =
                    draftResult.submissionId;

                if (
                    draftResult.academicApplicationId
                ) {

                    this.adminApplicationId =
                        draftResult.academicApplicationId;
                    this.adminApplicationIdIsAccessible = true;
                    this.adminApplicationAccessMessage =
                        'Loaded from this form submission record.';

                }

                this.currentPage =
                    draftResult.currentPage || 1;

                if (
                    this.currentPage >
                    this.maxAccessiblePage
                ) {

                    this.currentPage =
                        this.maxAccessiblePage;

                }

                const sanitizedDraft =
                    this.sanitizeFormData(
                        draftResult.formData || {}
                    );

                // REACTIVE COPY

                this.formData =

                    JSON.parse(

                        JSON.stringify(

                            sanitizedDraft.data

                        )

                    );

                this.sourceBreakdown =
                    this.buildSourceBreakdown(
                        this.formData
                    );

                this.sourceBreakdownByQuestion =
                    this.buildSourceBreakdownByQuestion(
                        this.sourceBreakdown
                    );

                this.clearMessagesForCurrentValues();

                if (

                    sanitizedDraft.changed

                ) {

                    await this.handleAutoSave();

                }

            }

            if (
                !this.isSubmissionRecordMode &&
                !this.hasStoredFormData(
                    this.formData
                )
            ) {

                this.restoreLocalDraftBackup();

            }

        }

        catch(error) {

            console.error(
                'INIT ERROR:',
                JSON.stringify(error)
            );

            this.restoreLocalDraftBackup();

        }

    }

    // FIELD CHANGE

    handleFieldChange(event) {

        const fieldId =
            event.detail.questionId;

        const value =
            event.detail.value;

        const existingFieldData =
            this.formData[fieldId] || {};

        const wasAutoFilled =
            existingFieldData.isAutoFilled === true;

        const originalAIValue =
            existingFieldData.originalAIValue !== undefined
                ? existingFieldData.originalAIValue
                : existingFieldData.value;

        const historyState =
            this.appendFieldHistory(
                existingFieldData,
                value
            );

        // UPDATE DATA

        this.formData = {

            ...this.formData,

            [fieldId]: {

                ...existingFieldData,

                value:
                    value,

                originalAIValue:
                    originalAIValue,

                isAutoFilled:
                    wasAutoFilled,

                isUserEdited:
                    wasAutoFilled,

                lastModifiedBy:
                    FIELD_MODIFIED_BY.USER,

                fieldStatus:
                    wasAutoFilled
                        ? FIELD_STATUS.EDITED
                        : existingFieldData.fieldStatus,

                confidence:
                    wasAutoFilled
                        ? existingFieldData.confidence
                        : undefined,

                reasoning:
                    wasAutoFilled
                        ? existingFieldData.reasoning
                        : undefined,

                selectionType:
                    wasAutoFilled
                        ? existingFieldData.selectionType
                        : undefined,

                sourceUpdatedAt:
                    wasAutoFilled
                        ? existingFieldData.sourceUpdatedAt
                        : undefined,

                alternativeOptions:
                    wasAutoFilled
                        ? existingFieldData.alternativeOptions
                        : undefined,

                sourceFields:
                    wasAutoFilled
                        ? existingFieldData.sourceFields
                        : undefined,

                userEditedAt:
                    new Date().toISOString(),

                valueHistory:
                    historyState.history,

                valueHistoryIndex:
                    historyState.index

            }

        };

        if (

            wasAutoFilled

        ) {

            this.logUserFieldModification(
                fieldId,
                existingFieldData,
                value
            );

        }

        this.saveLocalDraftBackup();

        this.clearFieldAIMessage(
            fieldId
        );

        console.log(
            'UPDATED FORM DATA:',
            JSON.stringify(
                this.formData
            )
        );

        // SAVE STATUS

        this.saveStatus =
            'Saving...';

        // CLEAR TIMER

        clearTimeout(this.saveTimeout);

        // AUTOSAVE

        this.saveTimeout =
            setTimeout(() => {

                this.handleAutoSave();

            }, 1000);

    }

    async handleAdminApplicationIdChange(event) {

        this.adminApplicationId =
            event.target.value
                ? event.target.value.trim()
                : '';

        this.adminApplicationIdIsAccessible = false;
        this.adminApplicationAccessMessage = '';

        if (
            !this.adminApplicationId
        ) {

            return;

        }

        try {

            const hasAccess =
                await canAccessAcademicApplication({
                    applicationId:
                        this.adminApplicationId
                });

            this.adminApplicationIdIsAccessible =
                hasAccess === true;

            this.adminApplicationAccessMessage =
                hasAccess
                    ? 'Application selected. AI will use this application and its applicant Contact.'
                    : 'You do not have access to this application record, or the record id is invalid.';

        } catch (error) {

            this.adminApplicationIdIsAccessible = false;
            this.adminApplicationAccessMessage =
                this.getErrorMessage(
                    error
                ) ||
                'Application record could not be verified.';

        }

    }

    // AI FILLED EVENT

    handleAIFilled(event) {

        if (

            this.isQuestionPrompt(
                event.detail?.prompt
            )

        ) {

            console.warn(
                'Ignored AI/chat update because prompt was a question.'
            );

            return;

        }

        const fieldMessages =
            this.normalizeFieldMessages(
                event.detail.fieldMessages || {}
            );

        const filledData =
            this.formatFilledDataValues(
                this.filterValidFilledData(
                    event.detail.filledData || {},
                    fieldMessages
                )
            );

        const displayFieldMessages =
            this.removeMessagesForFilledFields(
                fieldMessages,
                filledData
            );

        const aiMergeResult =
            this.buildAIMergedFormData(
                filledData
            );

        const appliedFilledData =
            aiMergeResult.appliedFilledData;

        const skippedEditedFieldIds =
            aiMergeResult.skippedEditedFieldIds;

        console.log(
            'AI FILLED:',
            JSON.stringify(
                filledData
            )
        );

        this.aiComparisonResults =
            event.detail.aiComparisonResults || {};

        if (

            Object.keys(
                displayFieldMessages
            ).length > 0

        ) {

            this.aiFieldMessages = {

                ...this.aiFieldMessages,

                ...displayFieldMessages

            };

        }

        this.clearFieldAIMessages(
            Object.keys(
                appliedFilledData
            )
        );

        if (

            skippedEditedFieldIds.length > 0

        ) {

            this.saveStatus =
                'AI kept your edited fields unchanged.';

            setTimeout(() => {

                if (
                    this.saveStatus ===
                    'AI kept your edited fields unchanged.'
                ) {

                    this.saveStatus = '';

                }

            }, 2500);

        }

        if (

            Object.keys(
                this.aiComparisonResults
            ).length > 0

        ) {

            console.log(
                'AI COMPARISON RESULTS:',
                JSON.stringify(
                    this.aiComparisonResults
                )
            );

        }

        if (

            Object.keys(
                appliedFilledData
            ).length === 0

        ) {

            console.warn(
                'AI fill ignored because no valid field values were provided.'
            );

            return;

        }

        // MERGE DATA

        const sanitizedMergedData =
            this.sanitizeFormData(
                aiMergeResult.formData
            ).data;

        this.formData =
            sanitizedMergedData;

        this.clearMessagesForCurrentValues();

        this.sourceBreakdown =
            this.buildSourceBreakdown(
                this.formData
            );

        this.sourceBreakdownByQuestion =
            this.buildSourceBreakdownByQuestion(
                this.sourceBreakdown
            );

        // FORCE REFRESH

        this.formData =
            JSON.parse(
                JSON.stringify(
                    this.formData
                )
            );

        this.saveLocalDraftBackup();

        console.log(
            'AI FORM DATA:',
            JSON.stringify(
                this.formData
            )
        );

        this.refreshAIFieldValidity(
            Object.keys(
                appliedFilledData
            )
        );

        // AUTO SAVE

        this.handleAutoSave();

    }

    handleAIStatusChange(event) {

        this.aiLoading =
            event.detail?.isLoading === true;

        this.aiStatus =
            event.detail?.message ||
            'Finding the right answers, one field at a time...';

    }

    buildAIMergedFormData(filledData = {}) {

        const nextFormData = {

            ...this.formData

        };

        const appliedFilledData = {};

        const skippedEditedFieldIds = [];

        Object.keys(
            filledData || {}
        ).forEach(questionId => {

            if (
                this.isAdminOnlyQuestion(
                    questionId
                ) &&
                this.canUseAdminApplicationContext !== true
            ) {

                skippedEditedFieldIds.push(
                    questionId
                );

                return;

            }

            const existingFieldData =
                this.formData[questionId] || {};

            if (

                existingFieldData.isUserEdited === true

            ) {

                skippedEditedFieldIds.push(
                    questionId
                );

                return;

            }

            const fieldData =
                filledData[questionId] || {};

            const originalAIValue =
                fieldData.value;

            const historyState =
                this.appendFieldHistory(
                    existingFieldData,
                    fieldData.value
                );

            const mergedFieldData = {

                ...existingFieldData,

                ...fieldData,

                value:
                    fieldData.value,

                originalAIValue:
                    originalAIValue,

                isAutoFilled:
                    true,

                isUserEdited:
                    false,

                lastModifiedBy:
                    FIELD_MODIFIED_BY.AI,

                fieldStatus:
                    FIELD_STATUS.AI_FILLED,

                autoFilledAt:
                    new Date().toISOString(),

                valueHistory:
                    historyState.history,

                valueHistoryIndex:
                    historyState.index

            };

            nextFormData[questionId] =
                mergedFieldData;

            appliedFilledData[questionId] =
                mergedFieldData;

        });

        return {
            formData:
                nextFormData,
            appliedFilledData:
                appliedFilledData,
            skippedEditedFieldIds:
                skippedEditedFieldIds
        };

    }

    isAdminOnlyQuestion(questionId) {

        if (
            !questionId
        ) {

            return false;

        }

        const normalizedQuestionId =
            String(
                questionId
            )
                .toLowerCase();

        if (
            normalizedQuestionId.startsWith(
                'admin_'
            )
        ) {

            return true;

        }

        const fieldConfig =
            this.schemaQuestions.find(field => {

                return field.id === questionId;

            });

        return Number(
            fieldConfig?.page || 0
        ) === 6;

    }

    appendFieldHistory(fieldData = {}, nextValue) {

        const existingHistory =
            Array.isArray(
                fieldData.valueHistory
            ) &&
            fieldData.valueHistory.length > 0
                ? fieldData.valueHistory
                : [
                    fieldData.value
                ];

        const currentIndex =
            Number.isInteger(
                fieldData.valueHistoryIndex
            )
                ? fieldData.valueHistoryIndex
                : existingHistory.length - 1;

        const trimmedHistory =
            existingHistory.slice(
                0,
                currentIndex + 1
            );

        const currentValue =
            trimmedHistory[
                trimmedHistory.length - 1
            ];

        if (

            currentValue === nextValue

        ) {

            return {
                history:
                    trimmedHistory,
                index:
                    trimmedHistory.length - 1
            };

        }

        const history =
            [
                ...trimmedHistory,
                nextValue
            ];

        return {
            history:
                history,
            index:
                history.length - 1
        };

    }

    moveFieldHistory(questionId, direction) {

        const existingFieldData =
            this.formData[questionId];

        if (

            !existingFieldData ||
            !Array.isArray(
                existingFieldData.valueHistory
            )

        ) {

            return;

        }

        const currentIndex =
            Number.isInteger(
                existingFieldData.valueHistoryIndex
            )
                ? existingFieldData.valueHistoryIndex
                : existingFieldData.valueHistory.length - 1;

        const nextIndex =
            currentIndex + direction;

        if (

            nextIndex < 0 ||
            nextIndex >= existingFieldData.valueHistory.length

        ) {

            return;

        }

        const nextValue =
            existingFieldData.valueHistory[nextIndex];

        this.formData = {

            ...this.formData,

            [questionId]: {

                ...existingFieldData,

                value:
                    nextValue,

                isUserEdited:
                    existingFieldData.isAutoFilled === true &&
                    nextValue !== existingFieldData.originalAIValue,

                lastModifiedBy:
                    FIELD_MODIFIED_BY.USER,

                fieldStatus:
                    existingFieldData.isAutoFilled === true &&
                    nextValue !== existingFieldData.originalAIValue
                        ? FIELD_STATUS.EDITED
                        : existingFieldData.isAutoFilled === true
                            ? FIELD_STATUS.REVERTED
                            : existingFieldData.fieldStatus,

                valueHistoryIndex:
                    nextIndex,

                historyMovedAt:
                    new Date().toISOString()

            }

        };

        this.sourceBreakdown =
            this.buildSourceBreakdown(
                this.formData
            );

        this.sourceBreakdownByQuestion =
            this.buildSourceBreakdownByQuestion(
                this.sourceBreakdown
            );

        this.clearFieldAIMessage(
            questionId
        );

        this.saveLocalDraftBackup();

        this.logUserFieldModification(
            questionId,
            existingFieldData,
            nextValue,
            direction < 0
                ? 'User undid a field value change before submission.'
                : 'User redid a field value change before submission.'
        );

        this.handleAutoSave();

    }

    normalizeFieldMessages(fieldMessages) {

        if (

            !fieldMessages ||
            typeof fieldMessages !== 'object'

        ) {

            return {};

        }

        return Object.keys(fieldMessages).reduce((messages, questionId) => {

            const message =
                fieldMessages[questionId];

            const fieldConfig =
                this.schemaQuestions.find(field => {

                    return field.id === questionId;

                });

            if (

                questionId &&
                typeof message === 'string' &&
                message.trim() &&
                !this.hasNonBlankFieldValue(
                    questionId
                ) &&
                !this.isCheckboxField(
                    fieldConfig
                )

            ) {

                messages[questionId] =
                    message.trim();

            }

            return messages;

        }, {});

    }

    hasNonBlankFieldValue(questionId) {

        const value =
            this.formData[questionId]?.value;

        if (

            value === null ||
            value === undefined

        ) {

            return false;

        }

        if (

            typeof value === 'boolean'

        ) {

            return value === true;

        }

        return String(
            value
        )
            .trim() !== '';

    }

    removeMessagesForFilledFields(

        fieldMessages = {},

        filledData = {}

    ) {

        const displayMessages = {

            ...fieldMessages

        };

        Object.keys(
            filledData || {}
        ).forEach(questionId => {

            delete displayMessages[questionId];

        });

        return displayMessages;

    }

    isCheckboxField(fieldConfig) {

        const fieldType =
            String(
                fieldConfig?.type || ''
            )
                .toLowerCase()
                .trim();

        return fieldType === 'checkbox' ||
            fieldType === 'check box' ||
            fieldType === 'boolean';

    }

    handleFieldAIMessage(event) {

        const questionId =
            event.detail?.questionId;

        if (!questionId) {

            return;

        }

        const fieldConfig =
            this.schemaQuestions.find(field => {

                return field.id === questionId;

            });

        if (

            this.isCheckboxField(
                fieldConfig
            )

        ) {

            return;

        }

        this.aiFieldMessages = {

            ...this.aiFieldMessages,

            [questionId]:
                event.detail?.message || ''

        };

    }

    clearFieldAIMessage(questionId) {

        if (

            !questionId ||
            !this.aiFieldMessages[questionId]

        ) {

            return;

        }

        const nextMessages = {

            ...this.aiFieldMessages

        };

        delete nextMessages[questionId];

        this.aiFieldMessages =
            nextMessages;

    }

    clearFieldAIMessages(questionIds) {

        if (

            !Array.isArray(
                questionIds
            )

        ) {

            return;

        }

        const nextMessages = {

            ...this.aiFieldMessages

        };

        let changed = false;

        questionIds.forEach(questionId => {

            if (

                nextMessages[questionId]

            ) {

                delete nextMessages[questionId];
                changed = true;

            }

        });

        if (

            changed

        ) {

            this.aiFieldMessages =
                nextMessages;

        }

    }

    clearMessagesForCurrentValues() {

        const nextMessages = {

            ...this.aiFieldMessages

        };

        let changed = false;

        Object.keys(
            nextMessages
        ).forEach(questionId => {

            if (

                this.hasNonBlankFieldValue(
                    questionId
                )

            ) {

                delete nextMessages[questionId];
                changed = true;

            }

        });

        if (

            changed

        ) {

            this.aiFieldMessages =
                nextMessages;

        }

    }

    handleFieldRevert(event) {

        const questionId =
            event.detail?.questionId;

        if (

            !questionId ||
            !this.formData[questionId]

        ) {

            return;

        }

        const existingFieldData =
            this.formData[questionId];

        if (

            existingFieldData.originalAIValue === undefined

        ) {

            return;

        }

        const historyState =
            this.appendFieldHistory(
                existingFieldData,
                existingFieldData.originalAIValue
            );

        this.formData = {

            ...this.formData,

            [questionId]: {

                ...existingFieldData,

                value:
                    existingFieldData.originalAIValue,

                isAutoFilled:
                    true,

                isUserEdited:
                    false,

                lastModifiedBy:
                    FIELD_MODIFIED_BY.AI,

                fieldStatus:
                    FIELD_STATUS.REVERTED,

                revertedAt:
                    new Date().toISOString(),

                valueHistory:
                    historyState.history,

                valueHistoryIndex:
                    historyState.index

            }

        };

        this.clearFieldAIMessage(
            questionId
        );

        this.saveLocalDraftBackup();

        this.logUserFieldModification(
            questionId,
            existingFieldData,
            existingFieldData.originalAIValue,
            'User reverted field to original AI-filled value.'
        );

        this.handleAutoSave();

    }

    handleFieldUndo(event) {

        this.moveFieldHistory(
            event.detail?.questionId,
            -1
        );

    }

    handleFieldRedo(event) {

        this.moveFieldHistory(
            event.detail?.questionId,
            1
        );

    }

    handleClearAllAIFilledData() {

        const aiFilledFieldIds =
            Object.keys(
                this.formData || {}
            ).filter(questionId => {

                return this.formData[questionId]?.isAutoFilled === true;

            });

        if (

            aiFilledFieldIds.length === 0

        ) {

            this.saveStatus =
                'No AI-filled data to clear.';

            return;

        }

        this.clearAIFilledFields(
            aiFilledFieldIds
        );

    }

    clearAIFilledFields(questionIds) {

        if (

            !Array.isArray(
                questionIds
            ) ||
            questionIds.length === 0

        ) {

            return;

        }

        const nextFormData = {

            ...this.formData

        };

        questionIds.forEach(questionId => {

            const existingFieldData =
                nextFormData[questionId] || {};

            const clearedValue =
                this.isCheckboxField(
                    this.schemaQuestions.find(field => {

                        return field.id === questionId;

                    })
                )
                    ? false
                    : '';

            const historyState =
                this.appendFieldHistory(
                    existingFieldData,
                    clearedValue
                );

            nextFormData[questionId] = {

                ...existingFieldData,

                value:
                    clearedValue,

                isAutoFilled:
                    false,

                isUserEdited:
                    false,

                lastModifiedBy:
                    FIELD_MODIFIED_BY.USER,

                fieldStatus:
                    undefined,

                clearedAt:
                    new Date().toISOString(),

                valueHistory:
                    historyState.history,

                valueHistoryIndex:
                    historyState.index

            };

            this.logUserFieldModification(
                questionId,
                existingFieldData,
                '',
                'User cleared AI-filled value before submission.'
            );

        });

        this.formData =
            nextFormData;

        this.clearFieldAIMessages(
            questionIds
        );

        this.sourceBreakdown =
            this.buildSourceBreakdown(
                this.formData
            );

        this.sourceBreakdownByQuestion =
            this.buildSourceBreakdownByQuestion(
                this.sourceBreakdown
            );

        this.saveLocalDraftBackup();

        this.saveStatus =
            'Cleared AI-filled data.';

        this.handleAutoSave();

    }

    logUserFieldModification(
        questionId,
        previousFieldData = {},
        newValue,
        reason = 'User modified auto-filled value before submission.'
    ) {

        const fieldConfig =
            this.schemaQuestions.find(field => {

                return field.id === questionId;

            });

        logChatDecision({
            action:
                'replace',
            status:
                'Success',
            questionId:
                questionId || '',
            questionLabel:
                fieldConfig?.label || questionId || '',
            source:
                'User Review',
            confidence:
                previousFieldData.confidence === undefined ||
                previousFieldData.confidence === null
                    ? null
                    : previousFieldData.confidence,
            reason:
                reason,
            value:
                newValue === undefined || newValue === null
                    ? ''
                    : String(
                        newValue
                    ),
            durationMs:
                null,
            formSubmissionId:
                this.submissionId || null
        }).catch(error => {

            console.warn(
                'User field modification logging skipped',
                error?.body?.message || error?.message || error
            );

        });

    }

    refreshAIFieldValidity(questionIds) {

        window.setTimeout(
            () => {

                const pageComponent =
                    this.template.querySelector(
                        'c-dynamicformpage'
                    );

                if (

                    pageComponent &&
                    typeof pageComponent.refreshValidityForFields ===
                        'function'

                ) {

                    pageComponent.refreshValidityForFields(
                        questionIds
                    );

                }

            },
            0
        );

    }

    buildSourceBreakdown(filledData) {

        return Object.keys(
            filledData || {}
        )
            .map(questionId => {

                const sourceFields =
                    this.parseSourceFields(
                        filledData[questionId]?.sourceFields
                    );

                const realSourceFields =
                    sourceFields
                        .map(sourceField => {

                            return this.normalizeSourceField(
                                sourceField
                            );

                        })
                        .filter(sourceField => {

                            return !this.isGenericSourceField(
                                sourceField
                            );

                        });

                if (

                    !this.shouldShowMergedSourceFields(
                        questionId,
                        filledData[questionId],
                        realSourceFields
                    )

                ) {

                    return null;

                }

                if (

                    realSourceFields.length < 2

                ) {

                    return null;

                }

                return {
                    id:
                        questionId,
                    isMergedAnswer:
                        true,
                    label:
                        this.getQuestionLabel(
                            questionId
                        ),
                    sourcesText:
                        realSourceFields
                            .map(sourceField => {

                                return this.formatSourceField(
                                    sourceField
                                );

                            })
                            .join(', ')
                };

            })
            .filter(Boolean);

    }

    shouldShowMergedSourceFields(

        questionId,

        fieldResult,

        realSourceFields

    ) {

        if (

            !realSourceFields ||
            realSourceFields.length < 2

        ) {

            return false;

        }

        if (

            fieldResult?.isMergedAnswer === true

        ) {

            return true;

        }

        const fieldConfig =
            this.schemaQuestions.find(field => {

                return field.id === questionId;

            });

        const fieldType =
            String(
                fieldConfig?.type || ''
            )
                .toLowerCase();

        if (

            this.isSingleValueSourceBreakdownType(
                fieldType
            )

        ) {

            return false;

        }

        const normalizedLabel =
            this.normalizeMergedAnswerText(
                fieldConfig?.label || ''
            );

        if (

            this.isMergedAnswerLabel(
                normalizedLabel
            )

        ) {

            return true;

        }

        return fieldType === 'textarea' &&
            this.hasMergedSourcePattern(
                realSourceFields
            );

    }

    isSingleValueSourceBreakdownType(fieldType) {

        return [
            'checkbox',
            'date',
            'dropdown',
            'email',
            'number',
            'phone',
            'picklist',
            'radio'
        ].includes(
            fieldType
        );

    }

    isMergedAnswerLabel(normalizedLabel) {

        return this.isFullAddressMergedLabel(
                normalizedLabel
            ) ||
            this.isContactInformationMergedLabel(
                normalizedLabel
            ) ||
            this.isEmploymentMergedLabel(
                normalizedLabel
            );

    }

    isFullAddressMergedLabel(normalizedLabel) {

        return (
            normalizedLabel.includes(
                'full address'
            ) ||
            normalizedLabel.includes(
                'mailing address'
            )
        ) &&
            !this.containsAnyMergedAnswerTerm(
                normalizedLabel,
                [
                    'city',
                    'country',
                    'postal',
                    'province',
                    'state',
                    'street',
                    'zip'
                ]
            );

    }

    isContactInformationMergedLabel(normalizedLabel) {

        return (
            normalizedLabel.includes(
                'contact information'
            ) ||
            normalizedLabel.includes(
                'contact details'
            ) ||
            normalizedLabel.includes(
                'contact info'
            )
        ) &&
            !this.containsAnyMergedAnswerTerm(
                normalizedLabel,
                [
                    'email',
                    'method',
                    'number',
                    'phone'
                ]
            );

    }

    isEmploymentMergedLabel(normalizedLabel) {

        return normalizedLabel.includes(
                'describe your employment'
            ) ||
            normalizedLabel.includes(
                'employment summary'
            ) ||
            normalizedLabel.includes(
                'employment information'
            ) ||
            normalizedLabel.includes(
                'current work details'
            ) ||
            normalizedLabel.includes(
                'job information'
            ) ||
            normalizedLabel.includes(
                'work information'
            );

    }

    hasMergedSourcePattern(realSourceFields) {

        const normalizedSources =
            realSourceFields
                .map(sourceField => {

                    return this.normalizeMergedAnswerText(
                        sourceField
                    );

                })
                .join(' ');

        const addressMatchCount =
            this.countMergedAnswerTerms(
                normalizedSources,
                [
                    'city',
                    'country',
                    'mailing',
                    'postal',
                    'province',
                    'state',
                    'street',
                    'zip'
                ]
            );

        const contactMatchCount =
            this.countMergedAnswerTerms(
                normalizedSources,
                [
                    'email',
                    'mobile',
                    'phone'
                ]
            );

        const employmentMatchCount =
            this.countMergedAnswerTerms(
                normalizedSources,
                [
                    'company',
                    'employer',
                    'employment',
                    'job title',
                    'schedule',
                    'status',
                    'title'
                ]
            );

        return addressMatchCount >= 2 ||
            contactMatchCount >= 2 ||
            employmentMatchCount >= 2;

    }

    countMergedAnswerTerms(text, terms) {

        return terms.reduce(
            (count, term) => {

                return text.includes(
                    term
                )
                    ? count + 1
                    : count;

            },
            0
        );

    }

    containsAnyMergedAnswerTerm(text, terms) {

        return terms.some(term => {

            return text.includes(
                term
            );

        });

    }

    normalizeMergedAnswerText(value) {

        return String(
            value || ''
        )
            .toLowerCase()
            .replace(/[_./-]+/g, ' ')
            .replace(/\s+/g, ' ')
            .trim();

    }

    buildSourceBreakdownByQuestion(sourceBreakdown) {

        return (sourceBreakdown || []).reduce(
            (breakdownByQuestion, item) => {

                breakdownByQuestion[item.id] =
                    item;

                return breakdownByQuestion;

            },
            {}
        );

    }

    parseSourceFields(sourceFields) {

        if (

            Array.isArray(
                sourceFields
            )

        ) {

            return sourceFields.reduce(
                (parsedFields, sourceField) => {

                    parsedFields.push(
                        ...this.parseSourceFields(
                            sourceField
                        )
                    );

                    return parsedFields;

                },
                []
            );

        }

        if (

            typeof sourceFields === 'string' &&
            sourceFields.trim()

        ) {

            const trimmedSourceFields =
                sourceFields.trim();

            if (

                trimmedSourceFields.startsWith(
                    '['
                )

            ) {

                try {

                    const parsedSourceFields =
                        JSON.parse(
                            trimmedSourceFields
                        );

                    if (

                        Array.isArray(
                            parsedSourceFields
                        )

                    ) {

                        return parsedSourceFields;

                    }

                } catch (error) {

                    // Fall through to comma parsing.

                }

            }

            return trimmedSourceFields.split(
                ','
            )
                .map(sourceField => sourceField.trim())
                .filter(sourceField => sourceField);

        }

        return [];

    }

    isGenericSourceField(sourceField) {

        const normalizedSource =
            this.normalizeSourceField(
                sourceField
            );

        const lowerSource =
            normalizedSource.toLowerCase();

        return lowerSource.includes(
                'prompt builder'
            ) ||
            lowerSource === 'prompt builder' ||
            lowerSource === 'einstein prompt builder' ||
            lowerSource === 'applicant knowledge' ||
            lowerSource === 'ai' ||
            lowerSource === 'chat prompt';

    }

    normalizeSourceField(sourceField) {

        return String(
            sourceField || ''
        )
            .replace(/^["'\[]+/g, '')
            .replace(/["'\]]+$/g, '')
            .replace(/^fields merged:\s*/i, '')
            .replace(/^combined from:\s*/i, '')
            .replace(/^extracted from:\s*/i, '')
            .replace(/^fetched from:\s*/i, '')
            .trim();

    }

    getQuestionLabel(questionId) {

        const fieldConfig =
            this.schemaQuestions.find(field => {

                return field.id === questionId;

            });

        return fieldConfig?.label || questionId;

    }

    formatSourceField(sourceField) {

        return String(
            sourceField || ''
        )
            .replace(/__c$/g, '')
            .replace(/_/g, ' ')
            .replace(/\./g, ' ');

    }

    get hasSourceBreakdown() {

        return this.sourceBreakdown.length > 0;

    }

    filterValidFilledData(

        filledData,

        fieldMessages = {}

    ) {

        const validData = {};

        Object.keys(
            filledData
        ).forEach(questionId => {

            const fieldConfig =
                this.schemaQuestions.find(field => {

                    return field.id === questionId;

                });

            if (

                !fieldConfig

            ) {

                return;

            }

            const fieldValue =
                filledData[questionId]?.value;

            if (

                this.isBlankAIValue(
                    fieldValue
                ) &&
                fieldMessages[questionId]

            ) {

                return;

            }

            if (

                this.isValidFieldValue(
                    fieldValue,
                    fieldConfig
                )

            ) {

                validData[questionId] =
                    filledData[questionId];

            }

            else {

                console.warn(
                    `Ignored invalid value for ${fieldConfig.label}: ${fieldValue}`
                );

            }

        });

        return validData;

    }

    isBlankAIValue(value) {

        return value === '' ||
            value === null ||
            value === undefined;

    }

    formatFilledDataValues(filledData) {

        const formattedData = {};

        Object.keys(
            filledData || {}
        ).forEach(questionId => {

            const fieldConfig =
                this.schemaQuestions.find(field => {

                    return field.id === questionId;

                });

            const fieldData =
                filledData[questionId];

            formattedData[questionId] = {
                ...fieldData,
                value:
                    this.formatGeneratedValueForField(
                        fieldData?.value,
                        fieldConfig
                    )
            };

        });

        return formattedData;

    }

    formatGeneratedValueForField(

        value,

        fieldConfig

    ) {

        return value;

    }

    isContactInformationField(fieldConfig) {

        const fieldLabel =
            String(
                fieldConfig?.label || ''
            )
                .toLowerCase()
                .replace(/[^a-z0-9]+/g, ' ')
                .replace(/\s+/g, ' ')
                .trim();

        return fieldLabel === 'contact information' ||
            fieldLabel === 'contact info' ||
            fieldLabel.includes(
                'contact information'
            ) ||
            fieldLabel.includes(
                'contact details'
            );

    }

    formatContactInformationValue(value) {

        const rawValue =
            String(
                value || ''
            )
                .replace(/\s+/g, ' ')
                .trim();

        if (

            !rawValue

        ) {

            return value;

        }

        const lowerValue =
            rawValue.toLowerCase();

        if (

            lowerValue.includes(
                'you can reach me by'
            ) ||
            (
                lowerValue.startsWith(
                    'my mailing address is'
                ) &&
                (
                    lowerValue.includes(
                        'phone at'
                    ) ||
                    lowerValue.includes(
                        'email at'
                    )
                )
            )

        ) {

            return this.cleanContactInformationSentence(
                rawValue
            );

        }

        const emailMatch =
            rawValue.match(
                /(?:email|e-mail)\s*:\s*([A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,})/i
            );

        const phoneMatch =
            rawValue.match(
                /(?:phone|mobile|telephone|contact number)\s*:\s*([+()0-9][+()0-9\s.-]{5,}[0-9])/i
            );

        const email =
            emailMatch
                ? emailMatch[1].trim()
                : '';

        const phone =
            phoneMatch
                ? phoneMatch[1]
                    .replace(/[.;,]+$/g, '')
                    .trim()
                : '';

        let address =
            rawValue
                .replace(
                    /(?:phone|mobile|telephone|contact number)\s*:\s*[+()0-9][+()0-9\s.-]{5,}[0-9][.;,]?\s*/gi,
                    ''
                )
                .replace(
                    /(?:email|e-mail)\s*:\s*[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}[.;,]?\s*/gi,
                    ''
                )
                .replace(/\s+/g, ' ')
                .trim();

        address =
            address
                .replace(
                    /^my mailing address is\s+/i,
                    ''
                )
                .replace(/[.;,]+$/g, '');

        const sentences =
            [];

        if (

            address

        ) {

            sentences.push(
                `My mailing address is ${address}.`
            );

        }

        const contactParts =
            [];

        if (

            phone

        ) {

            contactParts.push(
                `phone at ${phone}`
            );

        }

        if (

            email

        ) {

            contactParts.push(
                `email at ${email}`
            );

        }

        if (

            contactParts.length > 0

        ) {

            sentences.push(
                `You can reach me by ${this.joinHumanReadable(contactParts)}.`
            );

        }

        return sentences.length > 0
            ? sentences.join(' ')
            : value;

    }

    cleanContactInformationSentence(value) {

        let cleanedValue =
            String(
                value || ''
            )
                .replace(/\s+/g, ' ')
                .trim();

        cleanedValue =
            cleanedValue.replace(
                /^(my mailing address is\s*){2,}/i,
                'My mailing address is '
            );

        cleanedValue =
            cleanedValue.replace(
                /^my mailing address is\s+(?=you can reach me by)/i,
                ''
            );

        cleanedValue =
            cleanedValue.replace(
                /^my mailing address is\s+(?=phone at|email at)/i,
                'You can reach me by '
            );

        cleanedValue =
            cleanedValue.replace(
                /\s+(?=You can reach me by)/,
                '. '
            );

        cleanedValue =
            cleanedValue.replace(
                /\.\s*\./g,
                '.'
            );

        return cleanedValue;

    }

    joinHumanReadable(values) {

        const filteredValues =
            (values || []).filter(Boolean);

        if (

            filteredValues.length <= 1

        ) {

            return filteredValues[0] || '';

        }

        if (

            filteredValues.length === 2

        ) {

            return `${filteredValues[0]} and ${filteredValues[1]}`;

        }

        return `${filteredValues
            .slice(0, -1)
            .join(', ')}, and ${filteredValues[filteredValues.length - 1]}`;

    }

    sanitizeFormData(formData) {

        const sanitizedData = {};
        let changed = false;

        Object.keys(
            formData || {}
        ).forEach(questionId => {

            const fieldConfig =
                this.schemaQuestions.find(field => {

                    return field.id === questionId;

                });

            if (

                !fieldConfig

            ) {

                sanitizedData[questionId] =
                    formData[questionId];

                return;

            }

            const fieldValue =
                formData[questionId]?.value;

            if (

                this.isValidFieldValue(
                    fieldValue,
                    fieldConfig
                )

            ) {

                sanitizedData[questionId] =
                    formData[questionId];

            }

            else {

                changed = true;

                console.warn(
                    `Removed invalid saved value for ${fieldConfig.label}: ${fieldValue}`
                );

            }

        });

        return {
            data:
                sanitizedData,
            changed:
                changed
        };

    }

    isValidFieldValue(

        value,

        fieldConfig

    ) {

        if (

            value === '' ||
            value === null ||
            value === undefined

        ) {

            return true;

        }

        const fieldType =
            String(
                fieldConfig.type || ''
            ).toLowerCase();

        if (

            this.isEssayField(
                fieldConfig
            )

        ) {

            return this.isMeaningfulEssayValue(
                value
            );

        }

        if (

            this.isDateField(
                fieldConfig
            )

        ) {

            return this.isValidDateValue(
                value
            );

        }

        if (

            fieldType === 'number'

        ) {

            return !Number.isNaN(
                Number(value)
            );

        }

        if (

            this.isEmailField(
                fieldConfig
            )

        ) {

            return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(
                value
            );

        }

        if (

            this.isPhoneField(
                fieldConfig
            )

        ) {

            return this.isValidPhoneValue(
                value
            );

        }

        return true;

    }

    isEssayField(fieldConfig) {

        const fieldType =
            String(
                fieldConfig.type || ''
            ).toLowerCase();

        const fieldLabel =
            String(
                fieldConfig.label || ''
            ).toLowerCase();

        return fieldType === 'textarea' &&
            (
                fieldLabel.includes(
                    'statement of purpose'
                ) ||
                fieldLabel.includes(
                    'purpose statement'
                ) ||
                fieldLabel.includes(
                    'personal statement'
                ) ||
                fieldLabel.includes(
                    'personal essay'
                )
            );

    }

    isMeaningfulEssayValue(value) {

        const normalizedValue =
            String(value || '')
                .toLowerCase()
                .replace(/[^a-z0-9]+/g, ' ')
                .replace(/\s+/g, ' ')
                .trim();

        if (

            normalizedValue.length < 80

        ) {

            return false;

        }

        return normalizedValue
            .split(' ')
            .filter(Boolean)
            .length >= 12;

    }

    isDateField(fieldConfig) {

        const fieldType =
            String(
                fieldConfig.type || ''
            ).toLowerCase();

        const fieldLabel =
            String(
                fieldConfig.label || ''
            ).toLowerCase();

        return fieldType === 'date' ||
            fieldLabel.includes('date');

    }

    isEmailField(fieldConfig) {

        const fieldType =
            String(
                fieldConfig.type || ''
            ).toLowerCase();

        const fieldLabel =
            String(
                fieldConfig.label || ''
            ).toLowerCase();

        return fieldType === 'email' ||
            fieldLabel.includes('email');

    }

    isPhoneField(fieldConfig) {

        const fieldType =
            String(
                fieldConfig.type || ''
            ).toLowerCase();

        return fieldType === 'phone';

    }

    isValidPhoneValue(value) {

        const phoneValue =
            String(
                value || ''
            ).trim();

        if (

            !phoneValue

        ) {

            return true;

        }

        const digitCount =
            (
                phoneValue.match(
                    /\d/g
                ) || []
            ).length;

        return digitCount >= 7 &&
            /^[+()0-9\s.-]+$/.test(
                phoneValue
            );

    }

    isValidDateValue(value) {

        if (

            !/^\d{4}-\d{2}-\d{2}$/.test(
                value
            )

        ) {

            return false;

        }

        const parsedDate =
            new Date(
                `${value}T00:00:00`
            );

        return !Number.isNaN(
            parsedDate.getTime()
        ) &&
            parsedDate.toISOString()
                .startsWith(
                    value
                );

    }

    isQuestionPrompt(prompt) {

        const normalizedPrompt =
            String(prompt || '')
                .toLowerCase()
                .replace(/[^a-z0-9]+/g, ' ')
                .replace(/\s+/g, ' ')
                .trim();

        if (

            this.hasFormActionIntent(
                normalizedPrompt
            )

        ) {

            return false;

        }

        return String(prompt || '').trim().endsWith('?') ||
            normalizedPrompt.startsWith('do you think') ||
            normalizedPrompt.startsWith('dont you think') ||
            normalizedPrompt.startsWith('don t you think') ||
            normalizedPrompt.startsWith('do not you think') ||
            normalizedPrompt.includes(' you think ') ||
            normalizedPrompt.startsWith('why ') ||
            normalizedPrompt.startsWith('what ') ||
            normalizedPrompt.startsWith('how ') ||
            normalizedPrompt.startsWith('when ') ||
            normalizedPrompt.startsWith('where ') ||
            normalizedPrompt.startsWith('who ') ||
            normalizedPrompt.includes('can you check') ||
            normalizedPrompt.includes('could you check') ||
            normalizedPrompt.includes('please check') ||
            normalizedPrompt.includes('not sure') ||
            normalizedPrompt.includes('verify') ||
            normalizedPrompt.includes('is correct') ||
            normalizedPrompt.includes('looks correct');

    }

    hasFormActionIntent(normalizedPrompt) {

        return normalizedPrompt.includes('fill') ||
            normalizedPrompt.includes('autofill') ||
            normalizedPrompt.includes('auto fill') ||
            normalizedPrompt.includes('populate') ||
            normalizedPrompt.includes('complete') ||
            normalizedPrompt.includes('clear') ||
            normalizedPrompt.includes('remove') ||
            normalizedPrompt.includes('delete') ||
            normalizedPrompt.includes('replace') ||
            normalizedPrompt.includes('change') ||
            normalizedPrompt.includes('update') ||
            normalizedPrompt.includes('set') ||
            normalizedPrompt.includes('enter') ||
            normalizedPrompt.includes('put') ||
            normalizedPrompt.includes('use');

    }

    // NEXT

    async handleNext() {

        const pageComponent =

            this.template.querySelector(
                'c-dynamicformpage'
            );

        if (

            pageComponent &&

            !pageComponent.validateAllFields()

        ) {

            return;

        }

        // SAVE

        await this.handleAutoSave();

        if (
            this.currentPage <
            this.maxAccessiblePage
        ) {

            this.currentPage += 1;

        }

    }

    // PREVIOUS

    async handlePrevious() {

        // SAVE

        await this.handleAutoSave();

        if (this.currentPage > 1) {

            this.currentPage -= 1;

        }

    }

    // AUTO SAVE

    async handleAutoSave() {

        try {

            this.isSaving = true;

            this.saveStatus =
                'Saving...';

            this.saveLocalDraftBackup();

            const result =

                await saveFormDraft({

                    submissionId:
                        this.submissionId,

                    userId: null,

                    currentPage:
                        this.currentPage,

                    formData:
                        JSON.stringify(
                            this.formData
                        ),

                    sessionId: null,

                    targetApplicationId:
                        this.activeAdminApplicationId

                });

            if (
                !result ||
                result.success === false
            ) {

                const message =
                    result && result.errorMessage
                        ? result.errorMessage
                        : 'Draft could not be saved.';

                this.saveStatus =
                    this.getSaveFailedMessage(
                        message
                    );

                return false;

            }

            this.submissionId =
                result.submissionId;

            if (
                !this.submissionId
            ) {

                this.saveStatus =
                    'Save Failed: Draft save did not return a submission id.';

                return false;

            }

            if (
                result.responseSaveErrors &&
                result.responseSaveErrors.length
            ) {

                console.warn(
                    'Some response rows were not saved:',
                    JSON.stringify(
                        result.responseSaveErrors
                    )
                );

            }

            this.saveStatus =
                'Saved';

            this.saveLocalDraftBackup();

            setTimeout(() => {

                if (
                    this.saveStatus === 'Saved'
                ) {

                    this.saveStatus = '';

                }

            }, 2000);

            return true;

        }

        catch(error) {

            console.error(
                'SAVE ERROR:',
                JSON.stringify(error)
            );

            const message =
                this.getErrorMessage(
                    error
                );

            this.saveStatus =
                message
                    ? this.getSaveFailedMessage(
                        message
                    )
                    : 'Save Failed';

            return false;

        }

        finally {

            this.isSaving = false;

        }

    }

    // SUBMIT

    async handleSubmit() {

        try {

            // FINAL SAVE

            const saved =
                await this.handleAutoSave();

            if (
                !saved
            ) {

                return;

            }

            const result =

                await submitForm({

                    submissionId:
                        this.submissionId,

                    formData:
                        JSON.stringify(
                            this.formData
                        )

                });

            this.submittedReference =
                result.submissionId;

            this.isSubmitted = true;

            this.clearLocalDraftBackup();

        }

        catch(error) {

            console.error(
                'SUBMIT ERROR:',
                JSON.stringify(error)
            );

        }

    }

    getSaveFailedMessage(message) {

        const details =
            message || 'Draft could not be saved.';

        if (
            String(details)
                .includes(
                    'STORAGE_LIMIT_EXCEEDED'
                )
        ) {

            return `Save Failed: Salesforce storage is full, so the server draft cannot be saved yet. Your work is kept in this browser. Details: ${details}`;

        }

        return `Save Failed: ${details}`;

    }

    hasStoredFormData(formData) {

        return Object.values(
            formData || {}
        ).some(fieldValue => {

            const value =
                fieldValue?.value;

            return value !== null &&
                value !== undefined &&
                String(value).trim() !== '';

        });

    }

    saveLocalDraftBackup() {

        try {

            window.localStorage.setItem(
                this.localDraftKey,
                JSON.stringify({
                    formData:
                        this.formData || {},
                    currentPage:
                        this.currentPage,
                    submissionId:
                        this.submissionId || null,
                    aiFieldMessages:
                        this.aiFieldMessages || {},
                    savedAt:
                        new Date().toISOString()
                })
            );

        }

        catch(error) {

            console.warn(
                'LOCAL DRAFT BACKUP FAILED:',
                error
            );

        }

    }

    restoreLocalDraftBackup() {

        try {

            const rawDraft =
                window.localStorage.getItem(
                    this.localDraftKey
                );

            if (
                !rawDraft
            ) {

                return false;

            }

            const draft =
                JSON.parse(
                    rawDraft
                );

            if (
                !draft ||
                !this.hasStoredFormData(
                    draft.formData
                )
            ) {

                return false;

            }

            const sanitizedDraft =
                this.sanitizeFormData(
                    draft.formData || {}
                );

            this.formData =
                JSON.parse(
                    JSON.stringify(
                        sanitizedDraft.data
                    )
                );

            this.currentPage =
                draft.currentPage || this.currentPage;

            this.submissionId =
                draft.submissionId || this.submissionId;

            this.aiFieldMessages =
                this.normalizeFieldMessages(
                    draft.aiFieldMessages || {}
                );

            this.sourceBreakdown =
                this.buildSourceBreakdown(
                    this.formData
                );

            this.sourceBreakdownByQuestion =
                this.buildSourceBreakdownByQuestion(
                    this.sourceBreakdown
                );

            this.clearMessagesForCurrentValues();

            this.saveStatus =
                'Restored unsaved draft from this browser.';

            setTimeout(() => {

                if (
                    this.saveStatus ===
                    'Restored unsaved draft from this browser.'
                ) {

                    this.saveStatus = '';

                }

            }, 2500);

            return true;

        }

        catch(error) {

            console.warn(
                'LOCAL DRAFT RESTORE FAILED:',
                error
            );

            return false;

        }

    }

    clearLocalDraftBackup() {

        try {

            window.localStorage.removeItem(
                this.localDraftKey
            );

        }

        catch(error) {

            console.warn(
                'LOCAL DRAFT CLEAR FAILED:',
                error
            );

        }

    }

    getErrorMessage(error) {

        if (
            !error
        ) {

            return '';

        }

        if (
            Array.isArray(
                error.body
            )
        ) {

            return error.body
                .map(item => item.message)
                .filter(Boolean)
                .join(', ');

        }

        if (
            error.body &&
            typeof error.body.message === 'string'
        ) {

            return error.body.message;

        }

        if (
            typeof error.message === 'string'
        ) {

            return error.message;

        }

        return '';

    }

    // HELPERS

    get isFirstPage() {

        return this.currentPage === 1;

    }

    get saveStatusClass() {

        return String(
            this.saveStatus || ''
        )
            .toLowerCase()
            .startsWith(
                'save failed'
            )
                ? 'text-save-error'
                : 'text-saved';

    }

    get isLastPage() {

        return this.currentPage ===
               this.maxAccessiblePage;

    }

}
