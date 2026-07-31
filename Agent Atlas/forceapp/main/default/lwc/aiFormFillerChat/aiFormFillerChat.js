import { LightningElement, api, track }
from 'lwc';

import { ShowToastEvent }
from 'lightning/platformShowToastEvent';

import fillFormWithAI
from '@salesforce/apex/AIFormFillerController.fillFormWithAI';

import fillSingleFieldWithAI
from '@salesforce/apex/AIFormFillerController.fillSingleFieldWithAI';

import interpretPromptCommand
from '@salesforce/apex/PromptBuilderCommandInterpreter.interpretCommand';

import logChatDecision
from '@salesforce/apex/AIFormFillLogger.logChatDecision';

export default class AiFormFillerChat
    extends LightningElement {

    minimumSemanticConfidence = 0.7;

    maxClarificationOptions = 8;

    @api formConfig = [];

    @api formData = {};

    @api currentPage;

    @api submissionId;

    @api targetApplicationId;

    @api canUpdateAdminFields = false;

    @track messages = [
        {
            id: 1,
            text:
                'Ask me to fill all fields, current page, empty fields, or one specific field.',
            cssClass: 'message assistant'
        }
    ];

    @track draftPrompt = '';

    @track isProcessing = false;

    @track usePageOverlay = false;

    messageCounter = 1;

    pendingField = null;

    pendingClarification = null;

    clarificationMemory = {};

    clarificationLog = [];

    useLocalCommandFallback = true;

    showPromptBuilderDiagnostics = false;

    lastCommandInterpreterFailure = '';

    get isSendDisabled() {

        return this.isProcessing ||
            !this.draftPrompt ||
            !this.draftPrompt.trim();

    }

    get showInlineProcessing() {

        return this.isProcessing &&
            !this.usePageOverlay;

    }

    isAdminOnlyField(field) {

        if (
            !field
        ) {

            return false;

        }

        const fieldId =
            String(
                field.id || field.Question_Id__c || ''
            )
                .toLowerCase();

        return fieldId.startsWith(
            'admin_'
        ) ||
            Number(
                field.page || field.Page_Number__c || 0
            ) === 6;

    }

    canModifyFieldFromChat(field) {

        return !this.isAdminOnlyField(
            field
        ) ||
            this.canUpdateAdminFields === true;

    }

    blockUnauthorizedAdminField(field) {

        const message =
            `Only an authorized admin can update ${field?.label || 'this admin field'}.`;

        this.addMessage(
            message,
            'assistant'
        );

        if (
            field?.id
        ) {

            this.logChatDecisionSafely({
                action:
                    'admin_field_update',
                status:
                    'Denied',
                questionId:
                    field.id,
                questionLabel:
                    field.label,
                source:
                    'AI Form Chat',
                confidence:
                    0,
                reason:
                    message,
                value:
                    null
            });

        }

    }

    handlePromptChange(event) {

        this.draftPrompt =
            event.target.value;

    }

    handlePromptKeyDown(event) {

        if (

            event.key === 'Enter'

        ) {

            event.preventDefault();
            this.handleSendPrompt();

        }

    }

    async handleSendPrompt() {

        const prompt =
            this.draftPrompt
                ? this.draftPrompt.trim()
                : '';

        if (

            !prompt ||
            this.isProcessing

        ) {

            return;

        }

        this.addMessage(
            prompt,
            'user'
        );

        this.draftPrompt = '';
        this.isProcessing = true;
        this.usePageOverlay =
            this.shouldRunAutoFill(
                prompt
            );

        if (
            this.usePageOverlay
        ) {

            this.notifyAIStatus(
                true
            );

        }

        try {

            if (

                this.isGreetingPrompt(
                    prompt
                )

            ) {

                this.addMessage(
                    'Hi. I can fill all fields, fill one field, clear a field, or replace a field value.',
                    'assistant'
                );

                return;

            }

            if (

                this.shouldRunAutoFill(
                    prompt
                )

            ) {

                await this.runAutoFillFromPrompt(
                    prompt
                );

                return;

            }

            const normalizedPrompt =
                this.normalizeText(
                    prompt
                );

            const clarificationSelection =
                await this.handleClarificationSelectionPrompt(
                    prompt
                );

            if (

                clarificationSelection

            ) {

                return;

            }

            if (

                this.isQuestionPrompt(
                    prompt,
                    normalizedPrompt
                ) &&
                !this.hasActionIntent(
                    normalizedPrompt
                )

            ) {

                this.respondToQuestionPrompt(
                    prompt
                );

                return;

            }

            const pendingCommand =
                this.parsePendingFieldCommand(
                    prompt
                );

            if (

                pendingCommand

            ) {

                await this.applyEditCommand(
                    pendingCommand,
                    prompt
                );

                return;

            }

            const promptCommand =
                await this.getPromptBuilderCommand(
                    prompt
                );

            if (

                promptCommand

            ) {

                await this.applyEditCommand(
                    promptCommand,
                    prompt
                );

                return;

            }

            if (

                this.showPromptBuilderDiagnostics &&
                this.hasActionIntent(
                    normalizedPrompt
                ) &&
                this.lastCommandInterpreterFailure

            ) {

                this.addMessage(
                    `Prompt Builder did not return a usable command, so I used the controller fallback. Reason: ${this.lastCommandInterpreterFailure}`,
                    'assistant'
                );

            }

            if (

                !this.useLocalCommandFallback &&
                this.hasActionIntent(
                    this.normalizeText(
                        prompt
                    )
                )

            ) {

                this.addMessage(
                    this.lastCommandInterpreterFailure
                        ? `I could not process that with the AI command interpreter yet: ${this.lastCommandInterpreterFailure}`
                        : 'I could not process that with the AI command interpreter yet. Please try a clearer command.',
                    'assistant'
                );

                return;

            }

            const editCommand =
                this.parseEditCommand(
                    prompt
                ) ||
                this.parseNaturalLanguageCommand(
                    prompt
                );

            if (

                editCommand

            ) {

                await this.applyEditCommand(
                    editCommand,
                    prompt
                );

                return;

            }

            const fieldOnly =
                this.findFieldOnlyPrompt(
                    prompt
                );

            if (

                fieldOnly

            ) {

                this.pendingField =
                    fieldOnly;

                this.addMessage(
                    `What would you like to do with ${fieldOnly.label}? You can fill it, change it, or clear it.`,
                    'assistant'
                );

                return;

            }

            if (

                !this.shouldRunAutoFill(
                    prompt
                )

            ) {

                this.addMessage(
                    this.lastCommandInterpreterFailure &&
                    this.hasActionIntent(
                        this.normalizeText(
                            prompt
                        )
                    )
                        ? this.normalizeErrorMessage(
                            this.lastCommandInterpreterFailure
                        )
                        : 'Please mention the field and what you want me to do with it.',
                    'assistant'
                );

                return;

            }

        }

        catch (error) {

            this.handleError(error);

        }

        finally {

            this.isProcessing = false;
            this.usePageOverlay = false;

            this.notifyAIStatus(
                false
            );

        }

    }

    notifyAIStatus(isLoading) {

        this.dispatchEvent(
            new CustomEvent(
                'aistatuschange',
                {
                    detail: {
                        isLoading,
                        message:
                            'Finding the right answers, one field at a time...'
                    },
                    bubbles: true,
                    composed: true
                }
            )
        );

    }

    async runAutoFillFromPrompt(prompt) {

        const result =
            await fillFormWithAI({
                targetApplicationId:
                    this.targetApplicationId || null
            });

        const filledData =
            result?.filledFields || {};

        const selectedData =
            this.filterFilledData(
                filledData,
                prompt
            );

        const selectedFieldMessages =
            this.filterFilledData(
                result?.fieldMessages || {},
                prompt
            );

        const selectedCount =
            Object.keys(
                selectedData
            ).length;

        const selectedMessageCount =
            Object.keys(
                selectedFieldMessages
            ).length;

        if (

            selectedCount === 0

        ) {

            if (

                selectedMessageCount > 0

            ) {

                this.dispatchEvent(
                    new CustomEvent(
                        'aifilled',
                        {
                            detail: {
                                filledData: {},
                                fieldMessages:
                                    selectedFieldMessages,
                                metadata:
                                    result.metadata,
                                aiComparisonResults:
                                    result.aiComparisonResults,
                                confidence:
                                    result.overallConfidence,
                                prompt:
                                    prompt
                            }
                        }
                    )
                );

                this.addMessage(
                    'I could not find saved data for that field. Please enter it manually.',
                    'assistant'
                );

                return;

            }

            this.addMessage(
                'I could not find a matching field with available data for that prompt.',
                'assistant'
            );

            this.logChatDecisionSafely({
                action:
                    'no_data',
                status:
                    'No Data',
                source:
                    'AI Form Chat',
                reason:
                    'No matching field with available data was found for the chat prompt.',
                value:
                    prompt
            });

            return;

        }

        this.dispatchEvent(
            new CustomEvent(
                'aifilled',
                {
                    detail: {
                        filledData:
                            selectedData,
                        metadata:
                            result.metadata,
                        aiComparisonResults:
                            result.aiComparisonResults,
                        fieldMessages:
                            selectedFieldMessages,
                        confidence:
                            result.overallConfidence,
                        prompt:
                            prompt
                    }
                }
            )
        );

        this.addMessage(
            this.buildSuccessMessage(
                selectedCount,
                prompt
            ),
            'assistant'
        );

        this.dispatchEvent(
            new ShowToastEvent({
                title: 'Fields Filled',
                message:
                    `${selectedCount} field(s) updated from chat.`,
                variant: 'success'
            })
        );

    }

    async getPromptBuilderCommand(prompt) {

        if (

            this.shouldRunAutoFill(
                prompt
            )

        ) {

            return null;

        }

        this.lastCommandInterpreterFailure = '';

        try {

            const likelyField =
                this.findBestFieldMatch(
                    prompt
                );

            const existingValues =
                this.buildPromptBuilderExistingValues(
                    likelyField,
                    null
                );

            const result =
                await interpretPromptCommand({
                    command:
                        prompt,
                    fieldContextJson:
                        JSON.stringify(
                            this.buildPromptFieldContext(
                                prompt
                            )
                        ),
                    existingValuesJson:
                        JSON.stringify(
                            existingValues
                        ),
                    applicantKnowledge:
                        this.buildPromptBuilderApplicantKnowledge(
                            likelyField,
                            null
                        )
                });

            if (

                !result ||
                result.handled !== true

            ) {

                this.lastCommandInterpreterFailure =
                    result?.reason ||
                    result?.promptResponse ||
                    'Prompt Builder did not return a usable command.';

                // eslint-disable-next-line no-console
                console.warn(
                    'Prompt Builder command was not handled',
                    result
                );

                return null;

            }

            const normalizedCommand =
                this.normalizePromptBuilderCommand(
                    result
                );

            const ambiguousPromptClarification =
                this.buildAmbiguousPromptClarification(
                    prompt,
                    normalizedCommand
                );

            if (

                ambiguousPromptClarification

            ) {

                return ambiguousPromptClarification;

            }

            if (

                normalizedCommand &&
                normalizedCommand.type === 'fill' &&
                !normalizedCommand.value

            ) {

                // eslint-disable-next-line no-console
                console.warn(
                    'Prompt Builder fill command returned no direct value',
                    result
                );

            }

            return normalizedCommand;

        } catch (error) {

            this.lastCommandInterpreterFailure =
                this.extractErrorMessage(
                    error
                ) ||
                'Prompt Builder command call failed.';

            // Prompt Builder command understanding is a fallback. Keep the local chat working.
            // eslint-disable-next-line no-console
            console.warn(
                'Prompt Builder command interpretation skipped',
                error
            );

            return null;

        }

    }

    buildPromptFieldContext() {

        return this.normalizedConfig.map(field => {

            return {
                questionId:
                    field.id,
                label:
                    field.label,
                type:
                    field.type,
                options:
                    this.isChoiceField(
                        field
                    )
                        ? this.getFieldOptions(
                            field
                        )
                        : []
            };

        });

    }

    normalizePromptBuilderCommand(result) {

        const action =
            this.normalizeText(
                result.action || ''
            );

        const normalizedAction =
            this.normalizePromptBuilderAction(
                action
            );

        if (

            result.needsClarification === true ||
            normalizedAction === 'clarify'

        ) {

            return {
                type:
                    'clarify',
                originalType:
                    this.normalizePromptBuilderAction(
                        result.pendingAction ||
                        result.intendedAction ||
                        result.actionType ||
                        result.action ||
                        ''
                    ),
                fieldPhrase:
                    result.fieldLabel || '',
                value:
                    result.clarificationQuestion || '',
                pendingValue:
                    result.newValue ||
                    result.value ||
                    result.answer ||
                    result.recommendedValue ||
                    result.fieldValue ||
                    result.extractedValue ||
                    '',
                clarificationOptions:
                    this.normalizePromptBuilderClarificationOptions(
                        result.clarificationOptions ||
                        result.options ||
                        result.choices ||
                        result.possibleValues
                    )
            };

        }

        if (

            normalizedAction === 'help' ||
            normalizedAction === 'greeting'

        ) {

            this.addMessage(
                result.answer ||
                    result.promptResponse ||
                    'I can fill fields, clear fields, replace values, and understand changed question labels.',
                'assistant'
            );

            return {
                type:
                    'handled',
                fieldPhrase:
                    '',
                value:
                    ''
            };

        }

        if (

            normalizedAction === 'autofill'

        ) {

            return {
                type:
                    'autofill',
                fieldPhrase:
                    'all fields',
                value:
                    ''
            };

        }

        const confidence =
            this.normalizeConfidence(
                result.confidence
            );

        if (

            normalizedAction !== 'replace' &&
            normalizedAction !== 'clear' &&
            normalizedAction !== 'fill'

        ) {

            return null;

        }

        if (

            confidence !== null &&
            confidence < this.minimumSemanticConfidence

        ) {

            return {
                type:
                    'clarify',
                fieldPhrase:
                    result.fieldLabel || '',
                value:
                    result.clarificationQuestion ||
                    'I found a possible match, but I am not confident enough. Which field should I update?'
            };

        }

        return {
            type:
                normalizedAction,
            fromPromptBuilder:
                true,
            promptBuilderRawResponse:
                result.promptResponse || '',
            questionId:
                result.questionId ||
                result.targetQuestionId ||
                '',
            fieldPhrase:
                result.fieldLabel ||
                result.targetLabel ||
                result.questionId ||
                result.targetQuestionId ||
                '',
            value:
                normalizedAction === 'clear'
                    ? ''
                    : result.newValue ||
                    result.value ||
                    result.answer ||
                    result.recommendedValue ||
                    result.fieldValue ||
                    result.extractedValue ||
                    '',
            sourceFields:
                this.normalizePromptBuilderSourceFields(
                    result.sourceFields ||
                    result.sources ||
                    result.sourceField ||
                    result.source ||
                    result.sourceFieldNames
                ),
            isMergedAnswer:
                this.normalizePromptBuilderBoolean(
                    result.isMergedAnswer ||
                    result.mergedAnswer ||
                    result.isCombinedAnswer ||
                    result.combinedAnswer
                ),
            confidence:
                confidence
        };

    }

    normalizePromptBuilderBoolean(value) {

        if (

            value === true ||
            value === false

        ) {

            return value;

        }

        const normalizedValue =
            String(
                value || ''
            )
                .trim()
                .toLowerCase();

        if (

            normalizedValue === 'true' ||
            normalizedValue === 'yes'

        ) {

            return true;

        }

        if (

            normalizedValue === 'false' ||
            normalizedValue === 'no'

        ) {

            return false;

        }

        return false;

    }

    normalizeConfidence(confidence) {

        if (

            confidence === undefined ||
            confidence === null ||
            confidence === ''

        ) {

            return null;

        }

        let normalizedConfidence =
            Number(
                String(
                    confidence
                ).replace(
                    '%',
                    ''
                )
            );

        if (

            Number.isNaN(
                normalizedConfidence
            )

        ) {

            return null;

        }

        if (

            normalizedConfidence > 1

        ) {

            normalizedConfidence =
                normalizedConfidence / 100;

        }

        return normalizedConfidence;

    }

    normalizePromptBuilderSourceFields(sourceFields) {

        if (

            Array.isArray(
                sourceFields
            )

        ) {

            return sourceFields.reduce(
                (normalizedFields, sourceField) => {

                    normalizedFields.push(
                        ...this.normalizePromptBuilderSourceFields(
                            sourceField
                        )
                    );

                    return normalizedFields;

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

                        return this.normalizePromptBuilderSourceFields(
                            parsedSourceFields
                        );

                    }

                } catch (error) {

                    // Fall through to comma parsing.

                }

            }

            return trimmedSourceFields
                .split(',')
                .map(sourceField => sourceField.trim())
                .map(sourceField => sourceField.replace(/^["'\[]+|["'\]]+$/g, ''))
                .filter(sourceField => sourceField);

        }

        return [];

    }

    normalizePromptBuilderClarificationOptions(options) {

        if (

            Array.isArray(
                options
            )

        ) {

            return options
                .map(option => {

                    if (

                        typeof option === 'string'

                    ) {

                        const cleanedOption =
                            this.stripClarificationOptionLabel(
                                option
                            );

                        const matchedField =
                            this.findBestFieldMatch(
                                cleanedOption
                            );

                        if (

                            matchedField

                        ) {

                            return {
                                fieldId:
                                    matchedField.id,
                                label:
                                    matchedField.label,
                                value:
                                    ''
                            };

                        }

                        return {
                            label:
                                cleanedOption,
                            value:
                                cleanedOption
                        };

                    }

                    const rawLabel =
                        this.stripClarificationOptionLabel(
                            option.label ||
                            option.name ||
                            option.value ||
                            option.answer ||
                            ''
                        );

                    const matchedField =
                        option.fieldId ||
                        option.questionId ||
                        option.targetQuestionId
                            ? null
                            : this.findBestFieldMatch(
                                rawLabel
                            );

                    if (

                        matchedField

                    ) {

                        return {
                            fieldId:
                                matchedField.id,
                            label:
                                matchedField.label,
                            value:
                                ''
                        };

                    }

                    return {
                        fieldId:
                            option.fieldId ||
                            option.questionId ||
                            option.targetQuestionId ||
                            '',
                        label:
                            this.stripClarificationOptionLabel(
                                rawLabel
                            ),
                        value:
                            (
                                option.fieldId ||
                                option.questionId ||
                                option.targetQuestionId
                            )
                                ? option.value || option.answer || ''
                                : option.value ||
                                    option.answer ||
                                    this.stripClarificationOptionLabel(
                                        option.label ||
                                        option.name ||
                                        ''
                                    ) ||
                                    ''
                    };

                })
                .filter(option => {

                    return option.label || option.value;

                });

        }

        if (

            typeof options === 'string' &&
            options.trim()

        ) {

            const trimmedOptions =
                options.trim();

            if (

                trimmedOptions.startsWith(
                    '['
                )

            ) {

                try {

                    return this.normalizePromptBuilderClarificationOptions(
                        JSON.parse(
                            trimmedOptions
                        )
                    );

                } catch (error) {

                    // Fall through to comma parsing.

                }

            }

            return trimmedOptions
                .split(',')
                .map(option => {

                    const trimmedOption =
                        this.stripClarificationOptionLabel(
                            option.trim()
                        );

                    const matchedField =
                        this.findBestFieldMatch(
                            trimmedOption
                        );

                    if (

                        matchedField

                    ) {

                        return {
                            fieldId:
                                matchedField.id,
                            label:
                                matchedField.label,
                            value:
                                ''
                        };

                    }

                    return {
                        label:
                            trimmedOption,
                        value:
                            trimmedOption
                    };

                })
                .filter(option => option.label);

        }

        return [];

    }

    stripClarificationOptionLabel(label) {

        return String(
            label || ''
        )
            .replace(
                /\s*-\s*Q\d+(?:\.\d+)?\s*$/i,
                ''
            )
            .replace(
                /\s+Q\d+(?:\.\d+)?\s*$/i,
                ''
            )
            .replace(
                /^Q\d+(?:\.\d+)?\s+/i,
                ''
            )
            .trim();

    }

    normalizePromptBuilderAction(action) {

        if (

            action === 'fill field' ||
            action === 'fillfield' ||
            action === 'fill'

        ) {

            return 'fill';

        }

        if (

            action === 'replace field' ||
            action === 'replacefield' ||
            action === 'replace' ||
            action === 'update field' ||
            action === 'updatefield' ||
            action === 'update' ||
            action === 'set field' ||
            action === 'setfield' ||
            action === 'set'

        ) {

            return 'replace';

        }

        if (

            action === 'clear field' ||
            action === 'clearfield' ||
            action === 'clear' ||
            action === 'remove field' ||
            action === 'removefield' ||
            action === 'remove' ||
            action === 'delete field' ||
            action === 'deletefield' ||
            action === 'delete'

        ) {

            return 'clear';

        }

        if (

            action === 'fill all' ||
            action === 'fillall' ||
            action === 'fill all fields' ||
            action === 'autofill' ||
            action === 'auto fill' ||
            action === 'auto populate'

        ) {

            return 'autofill';

        }

        return action;

    }

    buildAmbiguousPromptClarification(

        prompt,

        command

    ) {

        if (

            !command ||
            !command.fromPromptBuilder ||
            ![
                'fill',
                'replace',
                'clear'
            ].includes(
                command.type
            )

        ) {

            return null;

        }

        const broadTarget =
            this.extractBroadAmbiguousTarget(
                prompt
            );

        if (

            !broadTarget

        ) {

            return null;

        }

        const candidates =
            this.getAmbiguousFieldCandidates(
                broadTarget
            );

        if (

            candidates.length < 2

        ) {

            return null;

        }

        return {
            type:
                'clarify',
            originalType:
                command.type,
            fieldPhrase:
                broadTarget,
            pendingValue:
                command.value || '',
            value:
                this.buildActionClarificationMessage(
                    broadTarget,
                    command.type
                ),
            clarificationOptions:
                candidates.map(candidate => {

                    return {
                        fieldId:
                            candidate.id,
                        label:
                            candidate.label,
                        value:
                            ''
                    };

                })
        };

    }

    buildActionClarificationMessage(target, commandType) {

        const normalizedCommandType =
            this.normalizePromptBuilderAction(
                commandType || ''
            );

        if (

            normalizedCommandType === 'clear'

        ) {

            return `Which ${target} field should I remove or clear?`;

        }

        if (

            normalizedCommandType === 'replace'

        ) {

            return `Which ${target} field should I update?`;

        }

        return `Which ${target} field should I fill?`;

    }

    extractBroadAmbiguousTarget(prompt) {

        const tokens =
            this.getMeaningfulTokens(
                this.normalizeText(
                    prompt
                )
            );

        const commandTokens =
            tokens.filter(token => {

                return ![
                    'fill',
                    'replace',
                    'clear',
                    'remove',
                    'delete',
                    'update',
                    'change',
                    'set',
                    'enter'
                ].includes(
                    token
                );

            });

        if (

            commandTokens.length !== 1

        ) {

            return '';

        }

        return this.isBroadAmbiguousFieldToken(
            commandTokens[0]
        )
            ? commandTokens[0]
            : '';

    }

    isBroadAmbiguousFieldToken(token) {

        return [
            'contact',
            'address',
            'name',
            'phone',
            'email',
            'school',
            'institution',
            'program',
            'employment',
            'work'
        ].includes(
            token
        );

    }

    getAmbiguousFieldCandidates(target) {

        const candidates =
            [];

        const normalizedTarget =
            this.normalizeText(
                target
            );

        this.normalizedConfig.forEach(field => {

            const matchScore =
                this.fieldMatchScore(
                    normalizedTarget,
                    field
                );

            if (

                matchScore.score > 0 ||
                field.normalizedLabel.includes(
                    normalizedTarget
                )

            ) {

                candidates.push({
                    id:
                        field.id,
                    label:
                        field.label,
                    score:
                        matchScore.score,
                    confidence:
                        matchScore.confidence
                });

            }

        });

        return candidates
            .sort((first, second) => {

                if (

                    second.score !== first.score

                ) {

                    return second.score - first.score;

                }

                return second.confidence - first.confidence;

            })
            .slice(
                0,
                this.maxClarificationOptions
            )
            .map(candidate => candidate);

    }

    buildFieldMatchClarification(

        fieldPhrase,

        commandType,

        pendingValue,

        prompt

    ) {

        const normalizedPhrase =
            this.normalizeText(
                fieldPhrase || prompt || ''
            );

        if (

            !normalizedPhrase ||
            this.hasExactFieldMatch(
                normalizedPhrase
            )

        ) {

            return null;

        }

        const candidates =
            this.getFieldMatchCandidates(
                normalizedPhrase
            )
                .filter(candidate => {

                    return this.isAcceptableFieldMatch(
                        normalizedPhrase,
                        candidate.field,
                        candidate.score,
                        candidate.confidence
                    );

                })
                .slice(
                    0,
                    this.maxClarificationOptions
                );

        if (

            candidates.length < 2

        ) {

            return null;

        }

        const broadTarget =
            this.extractBroadAmbiguousTarget(
                prompt
            );

        const topCandidate =
            candidates[0];

        const secondCandidate =
            candidates[1];

        const similarConfidence =
            topCandidate.score === secondCandidate.score ||
            Math.abs(
                topCandidate.confidence - secondCandidate.confidence
            ) <= 0.15;

        const shouldClarify =
            !!broadTarget ||
            similarConfidence ||
            topCandidate.confidence < this.minimumSemanticConfidence;

        if (

            !shouldClarify

        ) {

            return null;

        }

        const targetText =
            broadTarget || fieldPhrase || 'that request';

        return {
            reason:
                'Multiple possible field matches were found with similar confidence.',
            commandType:
                commandType,
            fieldPhrase:
                fieldPhrase || '',
            prompt:
                prompt,
            value:
                pendingValue || '',
            memoryKey:
                this.buildClarificationMemoryKey(
                    targetText
                ),
            message:
                `I found more than one possible field for "${targetText}". Which one should I use?`,
            options:
                candidates.map(candidate => {

                    return {
                        fieldId:
                            candidate.field.id,
                        label:
                            candidate.field.label,
                        value:
                            '',
                        confidence:
                            candidate.confidence
                    };

                })
        };

    }

    hasExactFieldMatch(normalizedPhrase) {

        return this.normalizedConfig.some(field => {

            return normalizedPhrase === field.normalizedLabel ||
                normalizedPhrase === field.normalizedId;

        });

    }

    getFieldMatchCandidates(normalizedPhrase) {

        return this.normalizedConfig
            .map(field => {

                const matchScore =
                    this.fieldMatchScore(
                        normalizedPhrase,
                        field
                    );

                return {
                    field:
                        field,
                    score:
                        matchScore.score,
                    confidence:
                        matchScore.confidence
                };

            })
            .filter(candidate => {

                return candidate.score > 0 ||
                    candidate.confidence > 0 ||
                    candidate.field.normalizedLabel.includes(
                        normalizedPhrase
                    ) ||
                    normalizedPhrase.includes(
                        candidate.field.normalizedLabel
                    );

            })
            .sort((first, second) => {

                if (

                    second.score !== first.score

                ) {

                    return second.score - first.score;

                }

                return second.confidence - first.confidence;

            });

    }

    filterFilledData(

        filledData,

        prompt

    ) {

        const normalizedPrompt =
            this.normalizeText(
                prompt
            );

        const fillEverything =
            this.shouldFillEverything(
                prompt
            );

        const fillCurrentPage =
            this.shouldFillCurrentPage(
                prompt
            );

        const fillEmptyFields =
            this.shouldFillEmptyFields(
                prompt
            );

        let scopedData =
            filledData;

        if (

            fillCurrentPage

        ) {

            scopedData =
                this.filterByCurrentPage(
                    scopedData
                );

        }

        if (

            fillEmptyFields

        ) {

            scopedData =
                this.filterEmptyFields(
                    scopedData
                );

        }

        if (

            fillEverything ||
            fillCurrentPage ||
            fillEmptyFields

        ) {

            return scopedData;

        }

        const selectedData = {};

        this.normalizedConfig.forEach(field => {

            if (

                scopedData[field.id] &&
                this.promptMatchesField(
                    normalizedPrompt,
                    field
                )

            ) {

                selectedData[field.id] =
                    scopedData[field.id];

            }

        });

        return selectedData;

    }

    get normalizedConfig() {

        if (

            !Array.isArray(
                this.formConfig
            )

        ) {

            return [];

        }

        return this.formConfig.map(field => {

            const id =
                field.id ||
                field.Question_Id__c;

            const label =
                field.label ||
                field.MasterLabel ||
                id ||
                '';

            return {
                id,
                label,
                type:
                    (
                        field.type ||
                        field.Question_Type__c ||
                        ''
                    ).toLowerCase(),
                options:
                    this.getFieldOptions(
                        field
                    ),
                normalizedId:
                    this.normalizeText(
                        id
                    ),
                normalizedLabel:
                    this.normalizeText(
                        label
                    ),
                page:
                    Number(
                        field.page ||
                        field.Page_Number__c
                    )
            };

        }).filter(field => {

            return !!field.id;

        });

    }

    parseEditCommand(prompt) {

        const correctionReplaceMatch =
            prompt.match(
                /^(?:.*?)(?:don'?t|do not)\s+want\s+(.+?)\s+(?:to be|to say|to read|as|like|set to|equal to|equals?)\s+(.+?)(?:,?\s*(?:please\s*)?(?:change|replace|update|set)\s+(?:it|that|this)?\s*(?:to|with|as)\s+(.+))$/i
            );

        if (

            correctionReplaceMatch

        ) {

            return {
                type:
                    'replace',
                fieldPhrase:
                    this.cleanFieldPhrase(
                        correctionReplaceMatch[1]
                    ),
                value:
                    this.cleanPromptValue(
                        correctionReplaceMatch[3]
                    )
            };

        }

        const replaceMatch =
            prompt.match(
                /^(?:please\s+)?(?:replace|change|update|set)\s+(.+?)\s+(?:with|to|as)\s+(.+)$/i
            );

        if (

            replaceMatch

        ) {

            return {
                type:
                    'replace',
                fieldPhrase:
                    this.cleanFieldPhrase(
                        replaceMatch[1]
                    ),
                value:
                    this.cleanPromptValue(
                        replaceMatch[2]
                    )
            };

        }

        const clearMatch =
            prompt.match(
                /^(?:please\s+)?(?:remove|clear|delete|empty)\s+(.+)$/i
            );

        if (

            clearMatch

        ) {

            return {
                type:
                    'clear',
                fieldPhrase:
                    this.cleanFieldPhrase(
                        clearMatch[1]
                    ),
                value:
                    ''
            };

        }

        const valueForFieldMatch =
            prompt.match(
                /^(?:please\s+)?(?:use|put|enter|make|set)\s+(.+?)\s+(?:for|in|into|on)\s+(.+)$/i
            );

        if (

            valueForFieldMatch

        ) {

            return {
                type:
                    'replace',
                fieldPhrase:
                    this.cleanFieldPhrase(
                        valueForFieldMatch[2]
                    ),
                value:
                    this.cleanPromptValue(
                        valueForFieldMatch[1]
                    )
            };

        }

        const correctionClearMatch =
            prompt.match(
                /^(?:.*?)(?:don'?t|do not)\s+want\s+(.+?)(?:\s+(?:to be|to say|to read|as|like|set to|equal to|equals?)\s+.+)?$/i
            );

        if (

            correctionClearMatch

        ) {

            const fieldPhrase =
                this.cleanFieldPhrase(
                    correctionClearMatch[1]
                );

            if (

                this.isVagueFieldReference(
                    fieldPhrase
                )

            ) {

                return {
                    type:
                        'clarify',
                    fieldPhrase:
                        fieldPhrase,
                    value:
                        ''
                };

            }

            return {
                type:
                    'clear',
                fieldPhrase:
                    fieldPhrase,
                value:
                    ''
            };

        }

        return null;

    }

    parsePendingFieldCommand(prompt) {

        if (

            !this.pendingField

        ) {

            return null;

        }

        const normalizedPrompt =
            this.normalizeText(
                prompt
            );

        const promptField =
            this.findFieldByDomainPhrase(
                prompt
            ) ||
            this.findBestFieldMatch(
                prompt
            );

        if (

            promptField &&
            promptField.id !== this.pendingField.id

        ) {

            this.pendingField = null;
            return null;

        }

        if (

            this.hasClearIntent(
                normalizedPrompt
            )

        ) {

            return {
                type:
                    'clear',
                fieldPhrase:
                    this.pendingField.label,
                value:
                    ''
            };

        }

        if (

            this.hasFillIntent(
                normalizedPrompt
            )

        ) {

            return {
                type:
                    'fill',
                fieldPhrase:
                    this.pendingField.label,
                value:
                    ''
            };

        }

        if (

            this.isBareUpdateCommand(
                normalizedPrompt
            )

        ) {

            return {
                type:
                    'clarify',
                fieldPhrase:
                    this.pendingField.label,
                value:
                    ''
            };

        }

        const value =
            this.extractPendingFieldValue(
                prompt
            );

        if (

            value

        ) {

            return {
                type:
                    'replace',
                fieldPhrase:
                    this.pendingField.label,
                value:
                    value
            };

        }

        if (

            this.hasUpdateIntent(
                normalizedPrompt
            )

        ) {

            return {
                type:
                    'clarify',
                fieldPhrase:
                    this.pendingField.label,
                value:
                    ''
            };

        }

        return null;

    }

    parseNaturalLanguageCommand(prompt) {

        const normalizedPrompt =
            this.normalizeText(
                prompt
            );

        const optionField =
            this.findFieldByDomainPhrase(
                prompt
            );

        const field =
            this.findBestFieldMatch(
                prompt
            ) ||
            optionField;

        if (

            optionField &&
            this.hasNegationIntent(
                normalizedPrompt
            )

        ) {

            return {
                type:
                    'clarify',
                fieldPhrase:
                    optionField.label,
                value:
                    ''
            };

        }

        if (

            this.hasCorrectionIntent(
                normalizedPrompt
            ) &&
            this.hasVagueFieldReference(
                normalizedPrompt
            )

        ) {

            return {
                type:
                    'clarify',
                fieldPhrase:
                    field ? field.label : '',
                value:
                    ''
            };

        }

        if (

            this.hasClearIntent(
                normalizedPrompt
            ) &&
            field

        ) {

            return {
                type:
                    'clear',
                fieldPhrase:
                    field.label,
                value:
                    ''
            };

        }

        if (

            this.hasFillIntent(
                normalizedPrompt
            )

        ) {

            if (

                field

            ) {

                return {
                    type:
                        'fill',
                    fieldPhrase:
                        field.label,
                    value:
                        ''
                };

            }

            const fillFieldPhrase =
                this.extractFillFieldPhrase(
                    prompt
                );

            if (

                fillFieldPhrase

            ) {

                return {
                    type:
                        'fill',
                    fieldPhrase:
                        fillFieldPhrase,
                    value:
                        ''
                };

            }

            return null;

        }

        if (

            this.isQuestionPrompt(
                prompt,
                normalizedPrompt
            )

        ) {

            return null;

        }

        if (

            !field

        ) {

            if (

                this.hasActionIntent(
                    normalizedPrompt
                )

            ) {

                return {
                    type:
                        'clarify',
                    fieldPhrase:
                        '',
                    value:
                        ''
                };

            }

            return null;

        }

        const value =
            this.extractNaturalLanguageValue(
                prompt,
                field
            );

        if (

            !value

        ) {

            if (

                this.hasUpdateIntent(
                    normalizedPrompt
                )

            ) {

                return {
                    type:
                        'clarify',
                    fieldPhrase:
                        field.label,
                    value:
                        ''
                };

            }

            return null;

        }

        return {
            type:
                'replace',
            fieldPhrase:
                field.label,
            value:
                value
        };

    }

    extractFillFieldPhrase(prompt) {

        let phrase =
            (prompt || '').trim();

        phrase =
            phrase.replace(
                /^can\s+you\s+/i,
                ''
            );

        phrase =
            phrase.replace(
                /^please\s+/i,
                ''
            );

        phrase =
            phrase.replace(
                /^(fill|populate|complete|autofill)\s+/i,
                ''
            );

        phrase =
            phrase.replace(
                /^(the\s+)?field\s+/i,
                ''
            );

        phrase =
            phrase.replace(
                /\s+(with|using|from)\s+(ai|applicant knowledge|my data)$/i,
                ''
            );

        phrase =
            phrase.replace(
                /^['"]|['"]$/g,
                ''
            ).trim();

        return phrase || '';

    }

    async applyEditCommand(

        command,

        prompt

    ) {

        const normalizedPrompt =
            this.normalizeText(
                prompt
            );

        if (

            this.isQuestionPrompt(
                prompt,
                normalizedPrompt
            ) &&
            !this.hasActionIntent(
                normalizedPrompt
            )

        ) {

            this.respondToQuestionPrompt(
                prompt
            );

            return;

        }

        if (

            command.type === 'handled'

        ) {

            return;

        }

        if (

            command.type === 'clarify'

        ) {

            const normalizedIntendedType =
                this.normalizePromptBuilderAction(
                    command.originalType ||
                    command.pendingAction ||
                    command.intendedAction ||
                    ''
                );

            const promptIntendedType =
                this.hasClearIntent(
                    normalizedPrompt
                )
                    ? 'clear'
                    : this.hasFillIntent(
                        normalizedPrompt
                    )
                        ? 'fill'
                        : this.hasUpdateIntent(
                            normalizedPrompt
                        )
                            ? 'replace'
                            : '';

            const intendedType =
                promptIntendedType ||
                (
                    [
                        'fill',
                        'clear',
                        'replace',
                        'autofill'
                    ].includes(
                        normalizedIntendedType
                    ) &&
                    normalizedIntendedType !== 'autofill'
                        ? normalizedIntendedType
                        : 'fill'
                );

            const clarificationMessage =
                command.value ||
                (
                    command.fieldPhrase
                        ? `What should ${command.fieldPhrase} be? Say "fill it" to use AI, say "clear it", or type the new value.`
                        : 'Please tell me the field name and the new value, for example: "Change preferred contact method to Email."'
                );

            const exactClarifiedField =
                this.findExactFieldMatch(
                    command.fieldPhrase
                );

            const broadClarificationTarget =
                command.fieldPhrase ||
                this.extractBroadAmbiguousTarget(
                    prompt
                ) ||
                '';

            const broadPromptTarget =
                this.extractBroadAmbiguousTarget(
                    prompt
                );

            const hasPromptFieldOptions =
                command.clarificationOptions &&
                command.clarificationOptions.some(option => {

                    return !!option.fieldId;

                });

            const shouldUsePromptClarificationOptions =
                command.clarificationOptions &&
                command.clarificationOptions.length &&
                !broadPromptTarget &&
                (
                    hasPromptFieldOptions ||
                    !this.extractBroadAmbiguousTarget(
                        prompt
                    )
                );

            if (

                exactClarifiedField

            ) {

                if (

                    intendedType === 'fill'

                ) {

                    if (

                        command.pendingValue

                    ) {

                        await this.applyPromptBuilderFillValue(
                            {
                                ...command,
                                type:
                                    'fill',
                                fieldPhrase:
                                    exactClarifiedField.label,
                                value:
                                    command.pendingValue
                            },
                            prompt
                        );

                    } else {

                        const filledFromPromptBuilder =
                            await this.fillSingleFieldWithPromptBuilderFirst(
                                exactClarifiedField,
                                prompt
                            );

                        if (

                            !filledFromPromptBuilder

                        ) {

                            await this.fillSingleFieldFromAI(
                                exactClarifiedField.label,
                                prompt,
                                true
                            );

                        }

                    }

                    return;

                }

                await this.applyEditCommand(
                    {
                        type:
                            intendedType,
                        fieldPhrase:
                            exactClarifiedField.label,
                        value:
                            command.pendingValue || ''
                    },
                    prompt
                );

                return;

            }

            if (

                shouldUsePromptClarificationOptions

            ) {

                this.askClarification(
                    {
                        reason:
                            'Multiple possible field matches were found with similar confidence.',
                        commandType:
                            intendedType,
                        fieldPhrase:
                            command.fieldPhrase || '',
                        prompt:
                            prompt,
                        value:
                            command.pendingValue || '',
                        memoryKey:
                            this.buildClarificationMemoryKey(
                                command.fieldPhrase || prompt
                            ),
                        options:
                            command.clarificationOptions.map(option => {

                                return {
                                    fieldId:
                                        option.fieldId,
                                    label:
                                        option.label || option.value,
                                    value:
                                        option.fieldId
                                            ? option.value || ''
                                            : option.value || option.label
                                };

                            })
                    },
                    clarificationMessage
                );

                return;

            }

            const fieldClarification =
                this.buildFieldMatchClarification(
                    broadClarificationTarget ||
                    prompt,
                    intendedType,
                    command.pendingValue || '',
                    prompt
                );

            if (

                fieldClarification

            ) {

                this.askClarification(
                    {
                        ...fieldClarification,
                        message:
                            clarificationMessage || fieldClarification.message
                    },
                    clarificationMessage || fieldClarification.message
                );

                return;

            }

            this.addMessage(
                clarificationMessage,
                'assistant'
            );

            return;

        }

        if (

            command.type === 'fill'

        ) {

            if (

                command.value

            ) {

                await this.applyPromptBuilderFillValue(
                    command,
                    prompt
                );

                this.pendingField = null;

                return;

            }

            const field =
                this.findFieldByPromptBuilderCommand(
                    command
                ) ||
                this.findBestFieldMatch(
                    command.fieldPhrase
                );

            if (

                !field

            ) {

                this.addMessage(
                    'I could not identify which field you want me to fill.',
                    'assistant'
                );

                this.logChatDecisionSafely({
                    action:
                        'fill',
                    status:
                        'Failed',
                    questionId:
                        command.questionId,
                    questionLabel:
                        command.fieldPhrase,
                    source:
                        command.fromPromptBuilder
                            ? 'Prompt Builder'
                            : 'AI Form Chat',
                    confidence:
                        command.confidence,
                    reason:
                        'Fill command was understood, but no matching form field was found.',
                    value:
                        ''
                });

                this.pendingField = null;

                return;

            }

            const filledFromPromptBuilder =
                await this.fillSingleFieldWithPromptBuilderFirst(
                    field,
                    prompt
                );

            if (

                !filledFromPromptBuilder

            ) {

                await this.fillSingleFieldFromAI(
                    field.label,
                    prompt,
                    true
                );

            }

            this.pendingField = null;

            return;

        }

        if (

            command.type === 'autofill'

        ) {

            await this.runAutoFillFromPrompt(
                prompt
            );

            this.pendingField = null;

            return;

        }

        if (

            this.isAllFieldsPhrase(
                command.fieldPhrase
            )

        ) {

            this.addMessage(
                'Please name the specific field you want me to update.',
                'assistant'
            );

            return;

        }

        const rememberedField =
            this.getRememberedClarificationField(
                command.fieldPhrase
            );

        if (

            !rememberedField

        ) {

            const clarification =
                this.buildFieldMatchClarification(
                    command.fieldPhrase,
                    command.type,
                    command.value,
                    prompt
                );

            if (

                clarification

            ) {

                this.askClarification(
                    clarification,
                    clarification.message
                );

                return;

            }

        }

        const field =
            rememberedField ||
            this.findBestFieldMatch(
                command.fieldPhrase
            );

        if (

            !field

        ) {

            this.addMessage(
                'I could not identify which field you want to update.',
                'assistant'
            );

            return;

        }

        if (
            !this.canModifyFieldFromChat(
                field
            )
        ) {

            this.blockUnauthorizedAdminField(
                field
            );

            return;

        }

        const value =
            command.type === 'clear'
                ? ''
                : this.normalizeValueForField(
                    command.value,
                    field
                );

        if (

            command.type !== 'clear' &&
            this.isVagueReplacementValue(
                value
            )

        ) {

            this.pendingField =
                field;

            this.addMessage(
                `What should ${field.label} be? Say "fill it" to use AI, say "clear it", or type the new value.`,
                'assistant'
            );

            return;

        }

        if (

            command.type !== 'clear' &&
            !this.isValidValueForField(
                value,
                field
            )

        ) {

            const message =
                this.buildInvalidValueMessage(
                    field
                );

            this.logChatDecisionSafely({
                action:
                    command.type,
                status:
                    'Failed',
                questionId:
                    field.id,
                questionLabel:
                    field.label,
                source:
                    'AI Form Chat',
                confidence:
                    command.confidence,
                reason:
                    message,
                value:
                    value
            });

            this.showFieldAIMessage(
                field.id,
                message
            );

            this.addMessage(
                message,
                'assistant'
            );

            return;

        }

        const filledData = {
            [field.id]: {
                value:
                    value,
                confidence:
                    1,
                reasoning:
                    'Updated from chat prompt.',
                sourceFields:
                    [
                        'Chat Prompt'
                    ]
            }
        };

        this.dispatchEvent(
            new CustomEvent(
                'aifilled',
                {
                    detail: {
                        filledData:
                            filledData,
                        confidence:
                            1,
                        prompt:
                            prompt
                    }
                }
            )
        );

        const message =
            command.type === 'clear'
                ? `Done. I cleared ${field.label}.`
                : `Done. I changed ${field.label} to ${value}.`;

        this.addMessage(
            message,
            'assistant'
        );

        await this.logChatDecisionSafely({
            action:
                command.type,
            status:
                'Success',
            questionId:
                field.id,
            questionLabel:
                field.label,
            source:
                'AI Form Chat',
            confidence:
                1,
            reason:
                'Updated from chat prompt.',
            value:
                value,
            durationMs:
                0
        });

        this.pendingField = null;

        this.dispatchEvent(
            new ShowToastEvent({
                title:
                    command.type === 'clear'
                        ? 'Field Cleared'
                        : 'Field Updated',
                message:
                    message,
                variant:
                    'success'
            })
        );

    }

    async applyPromptBuilderFillValue(

        command,

        prompt

    ) {

        const field =
            this.findFieldByPromptBuilderCommand(
                command
            ) ||
            this.findBestFieldMatch(
                command.fieldPhrase
            );

        if (

            !field

        ) {

            this.logChatDecisionSafely({
                action:
                    'fill',
                status:
                    'Failed',
                questionLabel:
                    command.fieldPhrase,
                source:
                    'Prompt Builder',
                confidence:
                    command.confidence,
                reason:
                    'Prompt Builder returned a field value, but the chat could not match it to a form field.',
                value:
                    command.value
            });

            await this.fillSingleFieldFromAI(
                command.fieldPhrase,
                prompt
            );

            return;

        }

        if (
            !this.canModifyFieldFromChat(
                field
            )
        ) {

            this.blockUnauthorizedAdminField(
                field
            );

            return;

        }

        const value =
            this.normalizeValueForField(
                command.value,
                field
            );

        const displayValue =
            this.formatGeneratedValueForField(
                value,
                field
            );

        if (

            !this.isValidValueForField(
                displayValue,
                field
            )

        ) {

            const message =
                this.buildInvalidValueMessage(
                    field
                );

            this.logChatDecisionSafely({
                action:
                    'fill',
                status:
                    'Failed',
                questionId:
                    field.id,
                questionLabel:
                    field.label,
                source:
                    'Prompt Builder',
                confidence:
                    command.confidence,
                reason:
                    message,
                value:
                    displayValue
            });

            this.showFieldAIMessage(
                field.id,
                message
            );

            this.addMessage(
                message,
                'assistant'
            );

            return;

        }

        if (

            this.isVagueReplacementValue(
                displayValue
            )

        ) {

            await this.fillSingleFieldFromAI(
                command.fieldPhrase,
                prompt
            );

            return;

        }

        const sourceFields =
            command.sourceFields &&
            command.sourceFields.length
                ? command.sourceFields
                : [];

        const filledData = {
            [field.id]: {
                value:
                    displayValue,
                confidence:
                    command.confidence || 0.9,
                reasoning:
                    'Prompt Builder understood the user command and returned this value.',
                isMergedAnswer:
                    command.isMergedAnswer === true,
                sourceFields:
                    sourceFields
            }
        };

        this.dispatchEvent(
            new CustomEvent(
                'aifilled',
                {
                    detail: {
                        filledData:
                            filledData,
                        confidence:
                            command.confidence || 0.9,
                        prompt:
                            prompt
                    }
                }
            )
        );

        this.addMessage(
            `Done. I filled ${field.label} from Prompt Builder.`,
            'assistant'
        );

        this.logChatDecisionSafely({
            action:
                'fill',
            status:
                'Success',
            questionId:
                field.id,
            questionLabel:
                field.label,
            source:
                'Prompt Builder',
            confidence:
                command.confidence || 0.9,
            reason:
                command.reasoning ||
                'Prompt Builder understood the user command and returned this value.',
            value:
                displayValue
        });

        this.dispatchEvent(
            new ShowToastEvent({
                title: 'Field Filled',
                message:
                    `${field.label} was filled from Prompt Builder.`,
                variant:
                    'success'
            })
        );

    }

    showFieldAIMessage(questionId, message) {

        if (

            !questionId ||
            !message

        ) {

            return;

        }

        const field =
            (this.questions || []).find(question => {

                return question.id === questionId;

            }) ||
            (this.normalizedConfig || []).find(question => {

                return question.id === questionId;

            });

        if (

            this.isCheckboxLikeField(
                field
            )

        ) {

            return;

        }

        this.dispatchEvent(
            new CustomEvent(
                'fieldaimessage',
                {
                    detail: {
                        questionId:
                            questionId,
                        message:
                            message
                    }
                }
            )
        );

    }

    isCheckboxLikeField(field) {

        const fieldType =
            String(
                field?.type || ''
            )
                .toLowerCase()
                .trim();

        return fieldType === 'checkbox' ||
            fieldType === 'check box' ||
            fieldType === 'boolean';

    }

    askClarification(context, message) {

        const normalizedPrompt =
            this.normalizeText(
                context.prompt || message || ''
            );

        const contextCommandType =
            this.normalizePromptBuilderAction(
                context.commandType || ''
            );

        const promptCommandType =
            this.hasClearIntent(
                normalizedPrompt
            )
                ? 'clear'
                : this.hasFillIntent(
                    normalizedPrompt
                )
                    ? 'fill'
                    : this.hasUpdateIntent(
                        normalizedPrompt
                    )
                        ? 'replace'
                        : '';

        const normalizedContextCommandType =
            contextCommandType === 'autofill'
                ? 'fill'
                : contextCommandType;

        const clarificationCommandType =
            promptCommandType ||
            (
                [
                    'fill',
                    'clear',
                    'replace'
                ].includes(
                    normalizedContextCommandType
                )
                    ? normalizedContextCommandType
                    : 'fill'
            );

        const options =
            (context.options || [])
                .slice(
                    0,
                    this.maxClarificationOptions
                )
                .map((option, index) => {

                    const isFieldChoice =
                        option.fieldId &&
                        !option.value;

                    const cleanLabel =
                        this.stripClarificationOptionLabel(
                            option.label || ''
                        )
                            .replace(
                                /^(autofill|clear|update)\s+/i,
                                ''
                            );

                    const fieldChoiceLabelPrefix =
                        clarificationCommandType === 'fill'
                            ? 'Autofill'
                            : clarificationCommandType === 'clear'
                                ? 'Clear'
                                : clarificationCommandType === 'replace'
                                    ? 'Update'
                                    : '';

                    return {
                        id:
                            `clarification-${Date.now()}-${index}`,
                        action:
                            option.action || (
                                clarificationCommandType === 'fill' &&
                                isFieldChoice
                                    ? 'autofill'
                                    : clarificationCommandType
                            ),
                        fieldId:
                            option.fieldId,
                        label:
                            isFieldChoice &&
                            fieldChoiceLabelPrefix
                                ? `${fieldChoiceLabelPrefix} ${cleanLabel}`
                                : cleanLabel,
                        value:
                            option.value,
                        confidence:
                            option.confidence
                    };

                });

        this.pendingClarification = {
            ...context,
            commandType:
                clarificationCommandType,
            options:
                options
        };

        this.addMessage(
            `${message} You can also type the answer manually if none of these are correct.`,
            'assistant',
            options
        );

        this.logChatDecisionSafely({
            action:
                'clarify',
            status:
                'Clarification',
            questionLabel:
                context.fieldPhrase,
            source:
                'AI Form Chat',
            confidence:
                context.confidence,
            reason:
                context.reason ||
                message,
            value:
                options.map(option => option.label).join(', ')
        });

        // eslint-disable-next-line no-console
        console.log(
            'Clarification requested:',
            JSON.stringify(
                {
                    reason:
                        context.reason,
                    prompt:
                        context.prompt,
                    options:
                        options.map(option => option.label)
                }
            )
        );

    }

    async handleClarificationOption(event) {

        const optionId =
            event.currentTarget.dataset.optionId;

        const option =
            this.pendingClarification?.options?.find(candidate => {

                return candidate.id === optionId;

            });

        if (

            !option ||
            this.isProcessing

        ) {

            return;

        }

        this.addMessage(
            option.label,
            'user'
        );

        this.isProcessing = true;

        try {

            await this.applyClarificationChoice(
                option
            );

        } catch (error) {

            this.handleError(
                error
            );

        } finally {

            this.isProcessing = false;

        }

    }

    async handleClarificationSelectionPrompt(prompt) {

        if (

            !this.pendingClarification

        ) {

            return false;

        }

        const normalizedPrompt =
            this.normalizeText(
                prompt
            );

        const option =
            this.pendingClarification.options.find((candidate, index) => {

                const normalizedLabel =
                    this.normalizeText(
                        candidate.label
                    );

                return normalizedPrompt === normalizedLabel ||
                    normalizedPrompt.includes(
                        normalizedLabel
                    ) ||
                    normalizedPrompt === String(
                        index + 1
                    );

            });

        if (

            !option

        ) {

            return false;

        }

        await this.applyClarificationChoice(
            option
        );

        return true;

    }

    async applyClarificationChoice(option) {

        const clarification =
            this.pendingClarification;

        if (

            !clarification

        ) {

            return;

        }

        const field =
            option.fieldId
                ? this.normalizedConfig.find(candidate => {

                    return candidate.id === option.fieldId;

                })
                : this.findBestFieldMatch(
                    clarification.fieldPhrase
                );

        if (

            !field

        ) {

            this.pendingClarification = null;

            this.addMessage(
                'I could not find that field anymore. Please try the command again.',
                'assistant'
            );

            return;

        }

        this.rememberClarificationChoice(
            clarification.memoryKey,
            field
        );

        this.logClarificationChoice(
            clarification,
            field
        );

        this.pendingClarification = null;

        const selectedPrompt =
            this.buildClarificationPromptForSelectedField(
                clarification,
                field,
                option
            );

        if (

            option.action === 'autofill'

        ) {

            const filledFromPromptBuilder =
                await this.fillSingleFieldWithPromptBuilderFirst(
                    field,
                    selectedPrompt
                );

            if (

                !filledFromPromptBuilder

            ) {

                await this.fillSingleFieldFromAI(
                    field.label,
                    selectedPrompt,
                    true
                );

            }

            return;

        }

        const selectedValue =
            option.fieldId
                ? clarification.value || ''
                : option.value || clarification.value || '';

        if (

            clarification.commandType === 'fill' &&
            !selectedValue

        ) {

            const filledFromPromptBuilder =
                await this.fillSingleFieldWithPromptBuilderFirst(
                    field,
                    selectedPrompt
                );

            if (

                !filledFromPromptBuilder

            ) {

                await this.fillSingleFieldFromAI(
                    field.label,
                    selectedPrompt,
                    true
                );

            }

            return;

        }

        await this.applyEditCommand(
            {
                type:
                    selectedValue
                        ? 'replace'
                        : clarification.commandType,
                fieldPhrase:
                    field.label,
                value:
                    selectedValue
            },
            selectedPrompt
        );

    }

    buildClarificationPromptForSelectedField(clarification, field, option) {

        const commandType =
            this.normalizePromptBuilderAction(
                clarification.commandType || option.action || ''
            );

        const normalizedCommandType =
            commandType === 'autofill'
                ? 'fill'
                : commandType;

        const selectedValue =
            option.fieldId
                ? clarification.value || option.value || ''
                : option.value || clarification.value || '';

        if (

            normalizedCommandType === 'clear'

        ) {

            return `clear ${field.label}`;

        }

        if (

            normalizedCommandType === 'replace'

        ) {

            return selectedValue
                ? `replace ${field.label} with ${selectedValue}`
                : `update ${field.label}`;

        }

        return `fill ${field.label}`;

    }

    buildClarificationMemoryKey(fieldPhrase) {

        return `field:${this.normalizeText(
            fieldPhrase || ''
        )}`;

    }

    getRememberedClarificationField(fieldPhrase) {

        const fieldId =
            this.clarificationMemory[
                this.buildClarificationMemoryKey(
                    fieldPhrase
                )
            ];

        if (

            !fieldId

        ) {

            return null;

        }

        return this.normalizedConfig.find(field => {

            return field.id === fieldId;

        }) || null;

    }

    rememberClarificationChoice(memoryKey, field) {

        if (

            !memoryKey ||
            !field

        ) {

            return;

        }

        this.clarificationMemory = {
            ...this.clarificationMemory,
            [memoryKey]:
                field.id
        };

    }

    logClarificationChoice(clarification, field) {

        const logEntry = {
            prompt:
                clarification.prompt,
            reason:
                clarification.reason,
            selectedFieldId:
                field.id,
            selectedFieldLabel:
                field.label,
            selectedAt:
                new Date().toISOString()
        };

        this.clarificationLog = [
            ...this.clarificationLog,
            logEntry
        ];

        // eslint-disable-next-line no-console
        console.log(
            'Clarification response:',
            JSON.stringify(
                logEntry
            )
        );

    }

    async getControllerFieldData(field) {

        if (

            !field ||
            !field.id

        ) {

            return null;

        }

        try {

            const result =
                await fillSingleFieldWithAI({
                    questionId:
                        field.id,
                    questionLabel:
                        field.label,
                    questionType:
                        field.type,
                    picklistValues:
                        this.isChoiceField(
                            field
                        )
                            ? this.getFieldOptions(
                                field
                            )
                                .map(
                                    option =>
                                        option.value || option.label
                                )
                                .join(
                                    ','
                                )
                            : '',
                    targetApplicationId:
                        this.targetApplicationId || null
                });

            return result?.filledFields?.[field.id] || null;

        } catch (error) {

            console.warn(
                'Unable to enrich Prompt Builder field with controller source fields',
                error
            );

            return null;

        }

    }

    buildPromptBuilderExistingValues(field, controllerFieldData) {

        const existingValues = {
            ...(this.formData || {})
        };

        if (

            field &&
            field.id &&
            existingValues[field.id]

        ) {

            delete existingValues[field.id];

        }

        return existingValues;

    }

    buildPromptBuilderApplicantKnowledge(field, controllerFieldData) {

        return '';

    }

    buildPromptFieldContextForField(field) {

        if (

            !field

        ) {

            return [];

        }

        return [
            {
                questionId:
                    field.id,
                label:
                    field.label,
                type:
                    field.type,
                options:
                    this.isChoiceField(
                        field
                    )
                        ? this.getFieldOptions(
                            field
                        )
                        : []
            }
        ];

    }

    async fillSingleFieldWithPromptBuilderFirst(field, prompt) {

        if (

            !field

        ) {

            return false;

        }

        try {

            const existingValues =
                this.buildPromptBuilderExistingValues(
                    field,
                    null
                );

            const result =
                await interpretPromptCommand({
                    command:
                        prompt || `fill ${field.label}`,
                    fieldContextJson:
                        JSON.stringify(
                            this.buildPromptFieldContextForField(
                                field
                            )
                        ),
                    existingValuesJson:
                        JSON.stringify(
                            existingValues
                        ),
                    applicantKnowledge:
                        this.buildPromptBuilderApplicantKnowledge(
                            field,
                            null
                        )
                });

            if (

                !result ||
                result.handled !== true

            ) {

                return false;

            }

            const command =
                this.normalizePromptBuilderCommand(
                    result
                );

            if (

                command &&
                command.type === 'fill' &&
                command.value

            ) {

                await this.applyPromptBuilderFillValue(
                    {
                        ...command,
                        fieldPhrase:
                            field.label
                    },
                    prompt
                );

                return true;

            }

            if (

                command &&
                command.type === 'clarify' &&
                command.pendingValue

            ) {

                await this.applyPromptBuilderFillValue(
                    {
                        ...command,
                        type:
                            'fill',
                        fieldPhrase:
                            field.label,
                        value:
                            command.pendingValue
                    },
                    prompt
                );

                return true;

            }

        } catch (error) {

            // Prompt Builder is the first choice, but the controller remains the fallback.
            // eslint-disable-next-line no-console
            console.warn(
                'Prompt Builder selected-field fill skipped',
                error
            );

        }

        return false;

    }

    async fillSingleFieldFromAI(

        fieldPhrase,

        prompt,

        skipClarification = false

    ) {

        const rememberedField =
            this.getRememberedClarificationField(
                fieldPhrase
            );

        if (

            !skipClarification &&
            !rememberedField

        ) {

            const clarification =
                this.buildFieldMatchClarification(
                    fieldPhrase,
                    'fill',
                    '',
                    prompt
                );

            if (

                clarification

            ) {

                this.askClarification(
                    clarification,
                    clarification.message
                );

                return;

            }

        }

        const field =
            rememberedField ||
            this.findBestFieldMatch(
                fieldPhrase
            );

        if (

            !field

        ) {

            this.addMessage(
                'I could not identify which field you want me to fill.',
                'assistant'
            );

            return;

        }

        if (
            !this.canModifyFieldFromChat(
                field
            )
        ) {

            this.blockUnauthorizedAdminField(
                field
            );

            return;

        }

        const result =
            await fillSingleFieldWithAI({
                questionId:
                    field.id,
                questionLabel:
                    field.label,
                questionType:
                    field.type,
                picklistValues:
                    this.isChoiceField(field)
                        ? this.getFieldOptions(field)
                            .map(option => option.value || option.label)
                            .join(',')
                        : '',
                targetApplicationId:
                    this.targetApplicationId || null
            });

        const filledData =
            result?.filledFields || {};

        const fieldData =
            filledData[field.id];

        const fieldMessage =
            result?.fieldMessages?.[field.id];

        if (

            !fieldData ||
            !this.isValidValueForField(
                fieldData.value,
                field
            ) ||
            this.isVagueReplacementValue(
                fieldData.value
            )

        ) {

            if (

                fieldMessage

            ) {

                this.logChatDecisionSafely({
                    action:
                        'no_data',
                    status:
                        'No Data',
                    questionId:
                        field.id,
                    questionLabel:
                        field.label,
                    source:
                        'AI',
                    confidence:
                        fieldData?.confidence,
                    reason:
                        fieldMessage,
                    value:
                        fieldData?.value
                });

                this.showFieldAIMessage(
                    field.id,
                    fieldMessage
                );

                this.addMessage(
                    fieldMessage,
                    'assistant'
                );

                return;

            }

            if (

                fieldData &&
                !this.isValidValueForField(
                    fieldData.value,
                    field
                )

            ) {

                const message =
                    this.buildInvalidValueMessage(
                        field
                    );

                this.logChatDecisionSafely({
                    action:
                        'fill',
                    status:
                        'Failed',
                    questionId:
                        field.id,
                    questionLabel:
                        field.label,
                    source:
                        'AI',
                    confidence:
                        fieldData.confidence,
                    reason:
                        message,
                    value:
                        fieldData.value
                });

                this.showFieldAIMessage(
                    field.id,
                    message
                );

                this.addMessage(
                    message,
                    'assistant'
                );

                return;

            }

            const noDataMessage =
                this.buildNoDataMessageForField(
                    field
                );

            this.logChatDecisionSafely({
                action:
                    'no_data',
                status:
                    'No Data',
                questionId:
                    field.id,
                questionLabel:
                    field.label,
                source:
                    'AI',
                confidence:
                    fieldData?.confidence,
                reason:
                    noDataMessage,
                value:
                    fieldData?.value
            });

            this.showFieldAIMessage(
                field.id,
                noDataMessage
            );

            this.addMessage(
                noDataMessage,
                'assistant'
            );

            this.pendingField =
                field;

            return;

        }

        const formattedFieldData = {
            ...fieldData,
            value:
                this.formatGeneratedValueForField(
                    fieldData.value,
                    field
                )
        };

        this.dispatchEvent(
            new CustomEvent(
                'aifilled',
                {
                    detail: {
                        filledData: {
                            [field.id]:
                                formattedFieldData
                        },
                        metadata:
                            result.metadata,
                        aiComparisonResults:
                            result.aiComparisonResults,
                        fieldMessages:
                            fieldMessage
                                ? {
                                    [field.id]:
                                        fieldMessage
                                }
                                : {},
                        confidence:
                            result.overallConfidence,
                        prompt:
                            prompt
                    }
                }
            )
        );

        this.addMessage(
            `Done. I filled ${field.label} from AI.`,
            'assistant'
        );

        this.logChatDecisionSafely({
            action:
                'fill',
            status:
                'Success',
            questionId:
                field.id,
            questionLabel:
                field.label,
            source:
                'AI',
            confidence:
                formattedFieldData.confidence,
            reason:
                formattedFieldData.reasoning ||
                'Filled by controller fallback after chat command.',
            value:
                formattedFieldData.value
        });

        this.dispatchEvent(
            new ShowToastEvent({
                title: 'Field Filled',
                message:
                    `${field.label} was filled from AI.`,
                variant: 'success'
            })
        );

    }

    findBestFieldMatch(fieldPhrase) {

        const match =
            this.getBestFieldMatch(
                fieldPhrase
            );

        return match?.field || null;

    }

    findExactFieldMatch(fieldPhrase) {

        const normalizedPhrase =
            this.normalizeText(
                fieldPhrase
            );

        if (

            !normalizedPhrase

        ) {

            return null;

        }

        return this.normalizedConfig.find(field => {

            return normalizedPhrase === field.normalizedLabel ||
                normalizedPhrase === field.normalizedId;

        }) || null;

    }

    findFieldByPromptBuilderCommand(command) {

        const normalizedQuestionId =
            this.normalizeText(
                command?.questionId ||
                command?.targetQuestionId ||
                ''
            );

        if (
            normalizedQuestionId
        ) {

            const idMatch =
                this.normalizedConfig.find(field => {

                    return normalizedQuestionId === field.normalizedId;

                });

            if (
                idMatch
            ) {

                return idMatch;

            }

        }

        return this.findExactFieldMatch(
            command?.fieldPhrase
        );

    }

    getBestFieldMatch(fieldPhrase) {

        const normalizedPhrase =
            this.normalizeText(
                fieldPhrase
            );

        const directField =
            this.normalizedConfig.find(field =>
                normalizedPhrase === field.normalizedLabel ||
                normalizedPhrase.includes(
                    field.normalizedLabel
                ) ||
                field.normalizedLabel.includes(
                    normalizedPhrase
                )
            );

        if (

            directField

        ) {

            return {
                field:
                    directField,
                score:
                    100,
                confidence:
                    1
            };

        }

        let bestField;
        let bestScore = 0;
        let bestConfidence = 0;

        this.normalizedConfig.forEach(field => {

            const matchScore =
                this.fieldMatchScore(
                    normalizedPhrase,
                    field
                );

            if (

                matchScore.score > bestScore ||
                (
                    matchScore.score === bestScore &&
                    matchScore.confidence > bestConfidence
                )

            ) {

                bestScore = matchScore.score;
                bestConfidence = matchScore.confidence;
                bestField = field;

            }

        });

        return this.isAcceptableFieldMatch(
            normalizedPhrase,
            bestField,
            bestScore,
            bestConfidence
        )
            ? {
                field:
                    bestField,
                score:
                    bestScore,
                confidence:
                    bestConfidence
            }
            : null;

    }

    isAcceptableFieldMatch(

        normalizedPhrase,

        field,

        score,

        confidence

    ) {

        if (

            !field ||
            score === 0

        ) {

            return false;

        }

        if (

            score >= 100

        ) {

            return true;

        }

        const labelTokens =
            this.getMeaningfulTokens(
                field.normalizedLabel
            );

        if (

            labelTokens.length === 0

        ) {

            return false;

        }

        if (

            labelTokens.length <= 1

        ) {

            const expandedPhraseTokens =
                new Set(
                    this.expandSemanticTokens(
                        this.getMeaningfulTokens(
                            normalizedPhrase
                        )
                    )
                );

            return confidence >= this.minimumSemanticConfidence &&
                expandedPhraseTokens.has(
                    labelTokens[0]
                );

        }

        return score >= 2 ||
            confidence >= this.minimumSemanticConfidence;

    }

    findFieldOnlyPrompt(prompt) {

        if (

            this.hasActionIntent(
                this.normalizeText(
                    prompt
                )
            )

        ) {

            return null;

        }

        const field =
            this.findBestFieldMatch(
                prompt
            );

        if (

            !field

        ) {

            return null;

        }

        const normalizedPrompt =
            this.normalizeText(
                prompt
            );

        const meaningfulPromptTokens =
            normalizedPrompt
                .split(' ')
                .filter(token => {

                    return this.isMeaningfulToken(
                        token
                    );

                });

        const meaningfulFieldTokens =
            field.normalizedLabel
                .split(' ')
                .filter(token => {

                    return this.isMeaningfulToken(
                        token
                    );

                });

        const extraTokens =
            meaningfulPromptTokens.filter(token => {

                return !meaningfulFieldTokens.includes(
                    token
                );

            });

        return extraTokens.length === 0
            ? field
            : null;

    }

    findFieldByDomainPhrase(prompt) {

        const normalizedPrompt =
            this.normalizeText(
                prompt
            );

        if (

            normalizedPrompt.includes(
                'gpa'
            )

        ) {

            return this.normalizedConfig.find(field => {

                return field.normalizedLabel.includes(
                    'gpa'
                );

            });

        }

        if (

            normalizedPrompt.includes(
                'major'
            )

        ) {

            return this.normalizedConfig.find(field => {

                return field.normalizedLabel.includes(
                    'major'
                ) ||
                    field.normalizedLabel.includes(
                        'field of study'
                    ) ||
                    field.normalizedLabel.includes(
                        'specialization'
                    ) ||
                    field.normalizedLabel.includes(
                        'concentration'
                    );

            });

        }

        if (

            !this.hasNegationIntent(
                normalizedPrompt
            )

        ) {

            return null;

        }

        if (

            normalizedPrompt.includes(
                'international student'
            ) ||

            normalizedPrompt.includes(
                'domestic student'
            ) ||

            normalizedPrompt.includes(
                'citizenship'
            )

        ) {

            return this.normalizedConfig.find(field => {

                return field.normalizedLabel.includes(
                    'citizenship'
                );

            });

        }

        return null;

    }

    fieldMatchScore(

        normalizedPrompt,

        field

    ) {

        if (

            normalizedPrompt.includes(
                field.normalizedLabel
            ) ||

            normalizedPrompt.includes(
                field.normalizedId
            )

        ) {

            return {
                score:
                    100,
                confidence:
                    1
            };

        }

        const promptTokens =
            new Set(
                this.expandSemanticTokens(
                    this.getMeaningfulTokens(
                        normalizedPrompt
                    )
                )
            );

        const labelTokens =
            this.expandSemanticTokens(
                this.getMeaningfulTokens(
                    field.normalizedLabel
                )
            );

        const matchedCount =
            labelTokens.filter(token => {

                return promptTokens.has(
                    token
                );

            }).length;

        const uniqueLabelTokenCount =
            new Set(
                labelTokens
            ).size || 1;

        return {
            score:
                matchedCount,
            confidence:
                Math.min(
                    1,
                    matchedCount / uniqueLabelTokenCount
                )
        };

    }

    expandSemanticTokens(tokens) {

        const expandedTokens =
            new Set();

        (tokens || []).forEach(token => {

            expandedTokens.add(
                token
            );

            (this.semanticTokenAliases[token] || []).forEach(alias => {

                expandedTokens.add(
                    alias
                );

            });

        });

        return Array.from(
            expandedTokens
        );

    }

    get semanticTokenAliases() {

        return {
            phone: ['mobile', 'cell', 'contact', 'number', 'call', 'reach'],
            mobile: ['phone', 'cell', 'contact', 'number', 'call', 'reach'],
            cell: ['phone', 'mobile', 'contact', 'number'],
            number: ['phone', 'mobile', 'contact'],
            reach: ['contact', 'phone', 'email'],
            contact: ['reach', 'phone', 'email', 'mobile'],
            email: ['mail', 'contact', 'reach'],
            mail: ['email'],
            employed: ['employment', 'work', 'job'],
            employment: ['employed', 'work', 'job', 'company'],
            employer: ['company', 'work', 'job', 'organization'],
            company: ['employer', 'work', 'job', 'organization'],
            work: ['employer', 'company', 'job', 'employment'],
            job: ['employer', 'company', 'work', 'employment', 'role'],
            role: ['title', 'job', 'position'],
            title: ['role', 'position', 'job'],
            name: ['call', 'called', 'firstname', 'first', 'nickname'],
            nickname: ['name', 'call', 'called'],
            call: ['name', 'phone', 'reach', 'nickname'],
            address: ['street', 'city', 'state', 'zip', 'postal', 'country'],
            street: ['address'],
            city: ['address'],
            state: ['address', 'province'],
            province: ['state', 'address'],
            country: ['address'],
            zip: ['postal'],
            postal: ['zip'],
            dob: ['birth', 'date'],
            birth: ['dob', 'date'],
            date: ['dob', 'birth'],
            university: ['institution', 'school', 'college'],
            institution: ['university', 'school', 'college'],
            school: ['university', 'institution', 'college'],
            program: ['degree', 'course'],
            course: ['program', 'degree', 'specialization'],
            specialization: ['course', 'program', 'track'],
            sop: ['statement', 'purpose'],
            gpa: ['grade', 'grades']
        };

    }

    getMeaningfulTokens(value) {

        return String(value || '')
            .split(' ')
            .filter(token => {

                return this.isMeaningfulToken(
                    token
                );

            });

    }

    promptMatchesField(

        normalizedPrompt,

        field

    ) {

        if (

            normalizedPrompt.includes(
                field.normalizedLabel
            ) ||

            normalizedPrompt.includes(
                field.normalizedId
            )

        ) {

            return true;

        }

        const labelTokens =
            field.normalizedLabel
                .split(' ')
                .filter(token => {

                    return this.isMeaningfulToken(
                        token
                    );

                });

        const matchedTokens =
            this.fieldMatchScore(
                normalizedPrompt,
                field
            );

        return matchedTokens.score >=
            Math.min(
                2,
                labelTokens.length
            ) ||
            matchedTokens.confidence >= this.minimumSemanticConfidence;

    }

    shouldFillEverything(prompt) {

        const normalizedPrompt =
            this.normalizeText(
                prompt
            );

        return normalizedPrompt === 'fill' ||
            normalizedPrompt === 'autofill' ||
            normalizedPrompt === 'fill fields' ||
            normalizedPrompt.includes('fill all') ||
            normalizedPrompt.includes('all fields') ||
            normalizedPrompt.includes('whole form') ||
            normalizedPrompt.includes('everything') ||
            normalizedPrompt.includes('auto populate all') ||
            normalizedPrompt.includes('autopopulate all');

    }

    shouldFillEmptyFields(prompt) {

        const normalizedPrompt =
            this.normalizeText(
                prompt
            );

        return normalizedPrompt.includes('empty field') ||
            normalizedPrompt.includes('blank field') ||
            normalizedPrompt.includes('missing field') ||
            normalizedPrompt.includes('unfilled field') ||
            normalizedPrompt.includes('fill empty') ||
            normalizedPrompt.includes('fill blanks');

    }

    shouldFillCurrentPage(prompt) {

        const normalizedPrompt =
            this.normalizeText(
                prompt
            );

        return normalizedPrompt.includes(
            'current page'
        );

    }

    filterByCurrentPage(filledData) {

        const selectedData = {};

        this.normalizedConfig.forEach(field => {

            if (

                filledData[field.id] &&
                Number(field.page) === Number(this.currentPage)

            ) {

                selectedData[field.id] =
                    filledData[field.id];

            }

        });

        return selectedData;

    }

    filterEmptyFields(filledData) {

        const selectedData = {};

        this.normalizedConfig.forEach(field => {

            if (

                !filledData[field.id]

            ) {

                return;

            }

            const currentValue =
                this.formData?.[field.id]?.value;

            if (

                currentValue === undefined ||
                currentValue === null ||
                String(currentValue).trim() === ''

            ) {

                selectedData[field.id] =
                    filledData[field.id];

            }

        });

        return selectedData;

    }

    getFieldOptions(field) {

        if (

            Array.isArray(
                field.options
            )

        ) {

            return field.options.map(option => {

                return {
                    label:
                        option.label || option.value,
                    value:
                        option.value || option.label
                };

            });

        }

        const rawOptions =
            field.picklistValues ||
            field.Picklist_Values__c;

        if (

            typeof rawOptions === 'string'

        ) {

            return rawOptions.split(',').map(option => {

                const trimmed =
                    option.trim();

                return {
                    label:
                        trimmed,
                    value:
                        trimmed
                };

            });

        }

        return [];

    }

    normalizeValueForField(

        value,

        field

    ) {

        const cleanedValue =
            this.cleanPromptValue(
                value
            );

        const normalizedValue =
            this.normalizeText(
                cleanedValue
            );

        if (

            [
                'picklist',
                'dropdown',
                'radio'
            ].includes(
                String(
                    field?.type || ''
                ).toLowerCase()
            )

        ) {

            const matchingChoice =
                this.findBestOptionMatch(
                    cleanedValue,
                    field
                );

            return matchingChoice
                ? matchingChoice.value
                : cleanedValue;

        }

        const matchingOption =
            this.getFieldOptions(
                field
            ).find(option => {

                return this.normalizeText(
                    option.label
                ) === normalizedValue ||
                    this.normalizeText(
                        option.value
                    ) === normalizedValue;

            });

        return matchingOption
            ? matchingOption.value
            : cleanedValue;

    }

    findBestOptionMatch(

        value,

        field

    ) {

        const options =
            this.getFieldOptions(
                field || {}
            );

        const normalizedValue =
            this.normalizeText(
                value
            );

        if (

            !normalizedValue ||
            options.length === 0

        ) {

            return null;

        }

        const exactMatch =
            options.find(option => {

                return this.normalizeText(
                    option.label
                ) === normalizedValue ||
                    this.normalizeText(
                        option.value
                    ) === normalizedValue;

            });

        if (

            exactMatch

        ) {

            return exactMatch;

        }

        const valueTokens =
            new Set(
                normalizedValue
                    .split(' ')
                    .filter(token => this.isMeaningfulToken(token))
            );

        let bestMatch =
            null;

        let bestScore =
            0;

        options.forEach(option => {

            const optionText =
                this.normalizeText(
                    `${option.label || ''} ${option.value || ''}`
                );

            const optionTokens =
                optionText
                    .split(' ')
                    .filter(token => this.isMeaningfulToken(token));

            let score =
                0;

            optionTokens.forEach(token => {

                if (

                    valueTokens.has(
                        token
                    )

                ) {

                    score += 2;

                }

                else if (

                    normalizedValue.includes(
                        token
                    )

                ) {

                    score += 1;

                }

            });

            if (

                score > bestScore

            ) {

                bestScore =
                    score;

                bestMatch =
                    option;

            }

        });

        return bestScore > 0
            ? bestMatch
            : null;

    }

    formatGeneratedValueForField(

        value,

        field

    ) {

        return value;

    }

    isContactInformationField(field) {

        const fieldLabel =
            this.normalizeText(
                field?.label
            );

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

    isValidValueForField(

        value,

        field

    ) {

        if (

            !field ||
            !field.type ||
            value === ''

        ) {

            return true;

        }

        const type =
            String(
                field.type || ''
            ).toLowerCase();

        switch (type) {
            case 'date':
                return this.isValidDateValue(
                    value
                );
            case 'number':
                return !Number.isNaN(
                    Number(value)
                );
            case 'email':
                return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(
                    value
                );
            case 'phone':
                return this.isValidPhoneValue(
                    value
                );
            case 'picklist':
            case 'dropdown':
            case 'radio':
                const options =
                    this.getFieldOptions(
                        field
                    );

                return options.length === 0 ||
                    options.some(option => {

                        return option.value === value ||
                            option.label === value;

                    });
            default:
                if (

                    this.isDateField(
                        field
                    )

                ) {

                    return this.isValidDateValue(
                        value
                    );

                }

                return true;
        }

    }

    isDateField(field) {

        const type =
            String(
                field?.type || ''
            ).toLowerCase();

        const label =
            this.normalizeText(
                field?.label || ''
            );

        return type === 'date' ||
            label.includes('date');

    }

    isValidDateValue(value) {

        if (

            !/^\d{4}-\d{2}-\d{2}$/.test(
                value
            )

        ) {

            return false;

        }

        const date =
            new Date(
                `${value}T00:00:00`
            );

        return !Number.isNaN(
            date.getTime()
        ) &&
            date.toISOString()
                .startsWith(
                    value
                );

    }

    isChoiceField(field) {

        return [
            'picklist',
            'dropdown',
            'radio'
        ].includes(
            String(
                field?.type || ''
            ).toLowerCase()
        );

    }

    buildInvalidValueMessage(field) {

        if (

            String(
                field.type || ''
            ).toLowerCase() === 'date'

        ) {

            return `${field.label} needs a date value in YYYY-MM-DD format, for example 2024-12-31.`;

        }

        if (

            String(
                field.type || ''
            ).toLowerCase() === 'number'

        ) {

            return `${field.label} needs a numeric value.`;

        }

        if (

            String(
                field.type || ''
            ).toLowerCase() === 'email'

        ) {

            return `${field.label} needs a valid email address.`;

        }

        if (

            String(
                field.type || ''
            ).toLowerCase() === 'phone'

        ) {

            return `${field.label} needs a phone number. Please enter only numbers or standard phone formatting characters.`;

        }

        if (

            ['picklist', 'dropdown', 'radio'].includes(
                String(
                    field.type || ''
                ).toLowerCase()
            ) &&
            this.getFieldOptions(
                field
            ).length > 0

        ) {

            return `${field.label} must match one of the available options.`;

        }

        return `That value does not look valid for ${field.label}.`;

    }

    buildNoDataMessageForField(field) {

        const location =
            this.suggestMissingDataLocation(
                field
            );

        return `No saved data found for ${field.label}. Please enter it manually. You can add it under ${location} in Salesforce for future use.`;

    }

    suggestMissingDataLocation(field) {

        const fingerprint =
            this.normalizeText(
                `${field?.label || ''} ${field?.type || ''}`
            );

        if (

            [
                'contact',
                'email',
                'phone',
                'mobile',
                'address',
                'street',
                'city',
                'state',
                'province',
                'postal',
                'zip',
                'birth',
                'gender',
                'citizen'
            ].some((term) => fingerprint.includes(term))

        ) {

            return 'Contact Info';

        }

        if (

            [
                'name',
                'profile',
                'user'
            ].some((term) => fingerprint.includes(term))

        ) {

            return 'your profile';

        }

        if (

            [
                'program',
                'education',
                'institution',
                'degree',
                'term',
                'enrollment',
                'study'
            ].some((term) => fingerprint.includes(term))

        ) {

            return 'the related application or education record';

        }

        return 'Applicant Knowledge or the related Salesforce record';

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

    respondToQuestionPrompt(prompt) {

        const field =
            this.findBestFieldMatch(
                prompt
            );

        if (

            field

        ) {

            this.pendingField =
                field;

            this.addMessage(
                `Do you want to change, replace, or clear ${field.label}? Tell me the new value or say "clear it".`,
                'assistant'
            );

            return;

        }

        this.pendingField = null;

        this.addMessage(
            'Which field do you want to change, replace, or clear?',
            'assistant'
        );

    }

    extractNaturalLanguageValue(

        prompt,

        field

    ) {

        if (

            this.isQuestionPrompt(
                prompt,
                this.normalizeText(
                    prompt
                )
            )

        ) {

            return null;

        }

        const optionValue =
            this.extractOptionValueFromPrompt(
                prompt,
                field
            );

        if (

            optionValue

        ) {

            return optionValue;

        }

        const labelBasedValue =
            this.extractValueAfterFieldLabel(
                prompt,
                field
            );

        if (

            labelBasedValue

        ) {

            return labelBasedValue;

        }

        const assignmentValue =
            this.extractAssignmentValue(
                prompt
            );

        if (

            assignmentValue &&
            this.looksLikeUpdateSentence(
                prompt
            )

        ) {

            return assignmentValue;

        }

        const trailingValue =
            this.extractTrailingUpdateValue(
                prompt
            );

        if (

            trailingValue

        ) {

            return trailingValue;

        }

        return null;

    }

    extractOptionValueFromPrompt(

        prompt,

        field

    ) {

        const normalizedPrompt =
            this.normalizeText(
                prompt
            );

        const matchingOptions =
            this.getFieldOptions(
                field
            )
                .map(option => {

                    const normalizedLabel =
                        this.normalizeText(
                            option.label
                        );

                    const normalizedValue =
                        this.normalizeText(
                            option.value
                        );

                    const matchedText =
                        normalizedPrompt.includes(
                            normalizedLabel
                        )
                            ? normalizedLabel
                            : normalizedPrompt.includes(
                                normalizedValue
                            )
                                ? normalizedValue
                                : null;

                    if (

                        !matchedText

                    ) {

                        return null;

                    }

                    return {
                        option:
                            option,
                        matchedText:
                            matchedText,
                        index:
                            normalizedPrompt.indexOf(
                                matchedText
                            ),
                        negated:
                            this.isNegatedOption(
                                normalizedPrompt,
                                matchedText
                            )
                    };

                })
                .filter(match => {

                    return !!match;

                });

        if (

            matchingOptions.length === 0

        ) {

            return null;

        }

        const positiveOptions =
            matchingOptions.filter(match => {

                return !match.negated;

            });

        const bestMatch =
            (
                positiveOptions.length > 0
                    ? positiveOptions
                    : matchingOptions
            ).sort((a, b) => {

                return a.index - b.index;

            })[0];

        return bestMatch.option.value;

    }

    isNegatedOption(

        normalizedPrompt,

        normalizedOption

    ) {

        const optionIndex =
            normalizedPrompt.indexOf(
                normalizedOption
            );

        if (

            optionIndex === -1

        ) {

            return false;

        }

        const beforeOption =
            normalizedPrompt
                .slice(
                    Math.max(
                        0,
                        optionIndex - 18
                    ),
                    optionIndex
                )
                .trim();

        const afterOption =
            normalizedPrompt
                .slice(
                    optionIndex + normalizedOption.length,
                    optionIndex + normalizedOption.length + 18
                )
                .trim();

        return beforeOption.endsWith('not') ||
            beforeOption.endsWith('no') ||
            beforeOption.endsWith('dont') ||
            beforeOption.endsWith('don t') ||
            beforeOption.endsWith('do not') ||
            afterOption.startsWith('not');

    }

    extractValueAfterFieldLabel(

        prompt,

        field

    ) {

        const labelAliases =
            this.getFieldLabelAliases(
                field
            );

        for (

            const alias of labelAliases

        ) {

            const escapedAlias =
                this.escapeRegExp(
                    alias
                );

            const pattern =
                new RegExp(
                    `${escapedAlias}\\s*(?:is|are|should be|must be|needs to be|has to be|=|:|-|to|as)?\\s+(.+)$`,
                    'i'
                );

            const match =
                prompt.match(
                    pattern
                );

            if (

                match &&
                match[1]

            ) {

                return this.cleanNaturalLanguageValue(
                    match[1]
                );

            }

        }

        return null;

    }

    extractAssignmentValue(prompt) {

        const match =
            prompt.match(
                /\b(?:is|are|should be|must be|needs to be|has to be|equals|=|:)\s+(.+)$/i
            );

        if (

            match &&
            match[1]

        ) {

            return this.cleanNaturalLanguageValue(
                match[1]
            );

        }

        return null;

    }

    extractTrailingUpdateValue(prompt) {

        const match =
            prompt.match(
                /\b(?:change|replace|update|set|make|correct)\s+(?:it|that|this|field|answer|value)?\s*(?:to|with|as)\s+(.+)$/i
            );

        if (

            match &&
            match[1]

        ) {

            const value =
                this.cleanNaturalLanguageValue(
                    match[1]
                );

            return this.isVagueReplacementValue(
                value
            )
                ? null
                : value;

        }

        return null;

    }

    isBareUpdateCommand(normalizedPrompt) {

        return [
            'change',
            'replace',
            'update',
            'set',
            'correct',
            'change it',
            'replace it',
            'update it',
            'set it',
            'correct it',
            'change this',
            'replace this',
            'update this',
            'change that',
            'replace that',
            'update that'
        ].includes(
            normalizedPrompt
        );

    }

    extractPendingFieldValue(prompt) {

        const explicitValue =
            this.extractAssignmentValue(
                prompt
            ) ||
            this.extractTrailingUpdateValue(
                prompt
            );

        if (

            explicitValue

        ) {

            return explicitValue;

        }

        const normalizedPrompt =
            this.normalizeText(
                prompt
            );

        const fillerOnly =
            [
                'change',
                'replace',
                'update',
                'set',
                'make',
                'correct',
                'it',
                'to',
                'with',
                'as',
                'the',
                'field',
                'value',
                'answer',
                'please'
            ].includes(
                normalizedPrompt
            );

        if (

            fillerOnly

        ) {

            return null;

        }

        return this.cleanPromptValue(
            prompt
        );

    }

    getFieldLabelAliases(field) {

        const aliases =
            new Set();

        aliases.add(
            field.label
        );

        aliases.add(
            field.normalizedLabel
        );

        const meaningfulLabel =
            field.normalizedLabel
                .split(' ')
                .filter(token => {

                    return this.isMeaningfulToken(
                        token
                    );

                })
                .join(' ');

        if (

            meaningfulLabel

        ) {

            aliases.add(
                meaningfulLabel
            );

        }

        return Array.from(
            aliases
        ).filter(alias => {

            return !!alias;

        });

    }

    cleanNaturalLanguageValue(value) {

        return this.cleanPromptValue(
            String(value || '')
                .replace(/\b(?:instead|now|please)\b/gi, ' ')
                .replace(/\s+/g, ' ')
                .trim()
        );

    }

    hasClearIntent(normalizedPrompt) {

        return normalizedPrompt.includes('remove') ||
            normalizedPrompt.includes('clear') ||
            normalizedPrompt.includes('delete') ||
            normalizedPrompt.includes('empty') ||
            normalizedPrompt.includes('blank out') ||
            normalizedPrompt.includes('erase') ||
            normalizedPrompt.includes('dont want') ||
            normalizedPrompt.includes('don t want') ||
            normalizedPrompt.includes('do not want') ||
            normalizedPrompt.includes('do not use') ||
            normalizedPrompt.includes('dont use') ||
            normalizedPrompt.includes('don t use') ||
            normalizedPrompt.includes('no longer want');

    }

    hasCorrectionIntent(normalizedPrompt) {

        return normalizedPrompt.includes('dont want') ||
            normalizedPrompt.includes('don t want') ||
            normalizedPrompt.includes('do not want') ||
            normalizedPrompt.includes('should not be') ||
            normalizedPrompt.includes('shouldnt be') ||
            normalizedPrompt.includes('shouldn t be') ||
            normalizedPrompt.includes('not supposed to be') ||
            normalizedPrompt.includes('wrong') ||
            normalizedPrompt.includes('incorrect') ||
            normalizedPrompt.includes('not right') ||
            normalizedPrompt.includes('change it') ||
            normalizedPrompt.includes('replace it') ||
            normalizedPrompt.includes('update it');

    }

    hasNegationIntent(normalizedPrompt) {

        return normalizedPrompt.includes(' not ') ||
            normalizedPrompt.startsWith('not ') ||
            normalizedPrompt.includes('dont') ||
            normalizedPrompt.includes('don t') ||
            normalizedPrompt.includes('do not') ||
            normalizedPrompt.includes('isnt') ||
            normalizedPrompt.includes('isn t') ||
            normalizedPrompt.includes('not a') ||
            normalizedPrompt.includes('not an');

    }

    hasUpdateIntent(normalizedPrompt) {

        return normalizedPrompt.includes('replace') ||
            normalizedPrompt.includes('change') ||
            normalizedPrompt.includes('update') ||
            normalizedPrompt.includes('set') ||
            normalizedPrompt.includes('make') ||
            normalizedPrompt.includes('enter') ||
            normalizedPrompt.includes('put') ||
            normalizedPrompt.includes('use') ||
            normalizedPrompt.includes('input') ||
            normalizedPrompt.includes('insert') ||
            normalizedPrompt.includes('correct') ||
            normalizedPrompt.includes('should be') ||
            normalizedPrompt.includes('needs to be') ||
            normalizedPrompt.includes('has to be') ||
            normalizedPrompt.includes('must be');

    }

    isQuestionPrompt(

        prompt,

        normalizedPrompt

    ) {

        const normalized =
            normalizedPrompt ||
            this.normalizeText(
                prompt
            );

        return String(prompt || '').trim().endsWith('?') ||
            normalized.startsWith('do you think') ||
            normalized.startsWith('dont you think') ||
            normalized.startsWith('don t you think') ||
            normalized.startsWith('do not you think') ||
            normalized.includes(' you think ') ||
            normalized.startsWith('why ') ||
            normalized.startsWith('what ') ||
            normalized.startsWith('how ') ||
            normalized.startsWith('when ') ||
            normalized.startsWith('where ') ||
            normalized.startsWith('who ') ||
            normalized.startsWith('can you explain') ||
            normalized.startsWith('could you explain') ||
            normalized.includes('can you check') ||
            normalized.includes('could you check') ||
            normalized.includes('please check') ||
            normalized.includes('not sure') ||
            normalized.includes('verify') ||
            normalized.includes('is correct') ||
            normalized.includes('looks correct') ||
            normalized.includes(' why ') ||
            normalized.includes(' what ') ||
            normalized.includes(' how ');

    }

    hasActionIntent(normalizedPrompt) {

        return this.hasClearIntent(
            normalizedPrompt
        ) ||
            this.hasFillIntent(
                normalizedPrompt
            ) ||
            this.hasCorrectionIntent(
                normalizedPrompt
            ) ||
            this.hasUpdateIntent(
                normalizedPrompt
            );

    }

    hasFillIntent(normalizedPrompt) {

        return normalizedPrompt.includes('fill') ||
            normalizedPrompt.includes('autofill') ||
            normalizedPrompt.includes('auto fill') ||
            normalizedPrompt.includes('populate') ||
            normalizedPrompt.includes('auto populate') ||
            normalizedPrompt.includes('autopopulate');

    }

    isGreetingPrompt(prompt) {

        const normalizedPrompt =
            this.normalizeText(
                prompt
            );

        return [
            'hi',
            'hello',
            'hey',
            'hai',
            'good morning',
            'good afternoon',
            'good evening'
        ].includes(
            normalizedPrompt
        );

    }

    looksLikeUpdateSentence(prompt) {

        const normalizedPrompt =
            this.normalizeText(
                prompt
            );

        return normalizedPrompt.includes(' should be ') ||
            normalizedPrompt.includes(' must be ') ||
            normalizedPrompt.includes(' needs to be ') ||
            normalizedPrompt.includes(' has to be ') ||
            normalizedPrompt.includes(' equals ');

    }

    shouldRunAutoFill(prompt) {

        const normalizedPrompt =
            this.normalizeText(
                prompt
            );

        if (

            this.isQuestionPrompt(
                prompt,
                normalizedPrompt
            )

        ) {

            return false;

        }

        return this.shouldFillEverything(
            prompt
        ) ||
            this.shouldFillCurrentPage(
                prompt
            ) ||
            this.shouldFillEmptyFields(
                prompt
            );

    }

    hasExplicitFillReplacementValue(prompt) {

        const normalizedPrompt =
            this.normalizeText(
                prompt
            );

        if (

            !this.hasFillIntent(
                normalizedPrompt
            )

        ) {

            return false;

        }

        return /\b(?:fill|populate|autofill|autopopulate)\b.+\b(?:to|with|as)\b.+/i.test(
            prompt
        );

    }

    hasVagueFieldReference(normalizedPrompt) {

        return normalizedPrompt.includes('this field') ||
            normalizedPrompt.includes('that field') ||
            normalizedPrompt.includes('this value') ||
            normalizedPrompt.includes('that value') ||
            normalizedPrompt.includes('it to be') ||
            normalizedPrompt.includes('change it') ||
            normalizedPrompt.includes('replace it') ||
            normalizedPrompt.includes('update it');

    }

    isVagueFieldReference(value) {

        const normalizedValue =
            this.normalizeText(
                value
            );

        return normalizedValue === 'this' ||
            normalizedValue === 'that' ||
            normalizedValue === 'it' ||
            normalizedValue === 'this field' ||
            normalizedValue === 'that field' ||
            normalizedValue === 'field' ||
            normalizedValue === 'value' ||
            normalizedValue === 'answer';

    }

    cleanFieldPhrase(value) {

        return String(value || '')
            .replace(/\s+(?:to be|to say|to read|as|like|set to|equal to|equals?)\s+.*$/i, ' ')
            .replace(/\b(?:the|my|field|value|answer)\b/gi, ' ')
            .replace(/\b(?:from|of)\b/gi, ' ')
            .replace(/\s+/g, ' ')
            .trim();

    }

    cleanPromptValue(value) {

        return String(value || '')
            .replace(/^["']|["']$/g, '')
            .replace(/[.。]\s*$/g, '')
            .trim();

    }

    isVagueReplacementValue(value) {

        const normalizedValue =
            this.normalizeText(
                value
            );

        return this.isBareUpdateCommand(
            normalizedValue
        ) ||
            [
                'it',
                'this',
                'that',
                'field',
                'value',
                'answer',
                'new value',
                'different value',
                'something else'
            ].includes(
                normalizedValue
            );

    }

    escapeRegExp(value) {

        return String(value || '')
            .replace(/[.*+?^${}()|[\]\\]/g, '\\$&');

    }

    isAllFieldsPhrase(value) {

        const normalizedValue =
            this.normalizeText(
                value
            );

        return normalizedValue === 'all' ||
            normalizedValue === 'all fields' ||
            normalizedValue === 'everything' ||
            normalizedValue === 'whole form';

    }

    normalizeText(value) {

        return String(value || '')
            .toLowerCase()
            .replace(/[^a-z0-9]+/g, ' ')
            .replace(/\s+/g, ' ')
            .trim();

    }

    isMeaningfulToken(token) {

        return token &&
            token.length > 2 &&
            ![
                'the',
                'and',
                'for',
                'with',
                'field',
                'fields',
                'fill',
                'remove',
                'clear',
                'delete',
                'replace',
                'change',
                'update',
                'set',
                'value',
                'answer',
                'please',
                'have',
                'has',
                'had',
                'you',
                'your',
                'my',
                'this',
                'that',
                'once',
                'wrong',
                'incorrect',
                'changed',
                'change',
                'so',
                'is',
                'are',
                'current',
                'question'
            ].includes(token);

    }

    buildSuccessMessage(

        selectedCount,

        prompt

    ) {

        if (

            this.shouldFillEmptyFields(
                prompt
            )

        ) {

            return `Done. I filled ${selectedCount} empty field(s).`;

        }

        if (

            this.shouldFillEverything(
                prompt
            )

        ) {

            return `Done. I filled ${selectedCount} available field(s).`;

        }

        if (

            this.shouldFillCurrentPage(
                prompt
            )

        ) {

            return `Done. I filled ${selectedCount} available field(s) on this page.`;

        }

        return `Done. I filled ${selectedCount} matching field(s).`;

    }

    addMessage(

        text,

        type,

        options = []

    ) {

        this.messageCounter += 1;

        this.messages = [
            ...this.messages,
            {
                id:
                    this.messageCounter,
                text:
                    text,
                cssClass:
                    `message ${type}`,
                options:
                    options,
                hasOptions:
                    Array.isArray(
                        options
                    ) &&
                    options.length > 0
            }
        ];

    }

    logFilledDataDecisions(filledData, action, status, prompt) {

        Object.keys(
            filledData || {}
        ).forEach(fieldId => {

            const field =
                this.normalizedConfig.find(candidate => {

                    return candidate.id === fieldId;

                });

            const fieldData =
                filledData[fieldId] || {};

            this.logChatDecisionSafely({
                action:
                    action,
                status:
                    status,
                questionId:
                    fieldId,
                questionLabel:
                    field?.label,
                source:
                    this.buildLogSource(
                        fieldData
                    ),
                confidence:
                    fieldData.confidence,
                reason:
                    fieldData.reasoning ||
                    `Filled from chat prompt: ${prompt || ''}`,
                value:
                    fieldData.value
            });

        });

    }

    logFieldMessageDecisions(fieldMessages, status, prompt) {

        Object.keys(
            fieldMessages || {}
        ).forEach(fieldId => {

            const field =
                this.normalizedConfig.find(candidate => {

                    return candidate.id === fieldId;

                });

            this.logChatDecisionSafely({
                action:
                    status === 'No Data'
                        ? 'no_data'
                        : 'skip',
                status:
                    status,
                questionId:
                    fieldId,
                questionLabel:
                    field?.label,
                source:
                    'AI',
                reason:
                    fieldMessages[fieldId] ||
                    `No data returned for chat prompt: ${prompt || ''}`
            });

        });

    }

    logChatDecisionSafely(detail = {}) {

        return logChatDecision({
            action:
                this.normalizeLogAction(
                    detail.action
                ),
            status:
                this.normalizeLogStatus(
                    detail.status
                ),
            questionId:
                detail.questionId || '',
            questionLabel:
                detail.questionLabel || '',
            source:
                detail.source || 'AI Form Chat',
            confidence:
                detail.confidence === undefined || detail.confidence === null
                    ? null
                    : detail.confidence,
            reason:
                detail.reason || '',
            value:
                detail.value === undefined || detail.value === null
                    ? ''
                    : String(
                        detail.value
                    ),
            durationMs:
                detail.durationMs === undefined || detail.durationMs === null
                    ? null
                    : detail.durationMs,
            formSubmissionId:
                detail.formSubmissionId || this.submissionId || null
        }).catch(error => {

            // Logging should never block form filling or chat commands.
            // eslint-disable-next-line no-console
            console.warn(
                'AI form chat logging skipped',
                error?.body?.message || error?.message || error
            );

        });

    }

    normalizeLogAction(action) {

        const rawAction =
            this.normalizeText(
                action || ''
            )
                .replace(
                    /\s+/g,
                    '_'
                );

        if (
            rawAction === 'no_data'
        ) {
            return 'no_data';
        }

        const normalized =
            this.normalizePromptBuilderAction(
                action || ''
            );

        if (
            [
                'fill',
                'clear',
                'replace',
                'clarify',
                'skip',
                'no_data'
            ].includes(
                normalized
            )
        ) {
            return normalized;
        }

        if (
            normalized === 'autofill'
        ) {
            return 'fill';
        }

        return 'fill';

    }

    normalizeLogStatus(status) {

        const normalized =
            this.normalizeText(
                status || ''
            );

        if (
            normalized === 'success'
        ) {
            return 'Success';
        }

        if (
            normalized === 'failed' ||
            normalized === 'failure' ||
            normalized === 'error'
        ) {
            return 'Failed';
        }

        if (
            normalized === 'skipped' ||
            normalized === 'skip'
        ) {
            return 'Skipped';
        }

        if (
            normalized === 'no data' ||
            normalized === 'no_data'
        ) {
            return 'No Data';
        }

        if (
            normalized === 'clarification' ||
            normalized === 'clarify'
        ) {
            return 'Clarification';
        }

        return 'Success';

    }

    buildLogSource(fieldData) {

        if (
            fieldData?.sourceFields &&
            fieldData.sourceFields.length
        ) {
            return fieldData.sourceFields.join(', ');
        }

        return fieldData?.source || 'AI';

    }

    extractErrorMessage(error) {

        if (

            !error

        ) {

            return '';

        }

        if (

            typeof error === 'string'

        ) {

            return error;

        }

        const messages = [];

        const addMessage = value => {

            if (

                value

            ) {

                messages.push(
                    String(
                        value
                    )
                );

            }

        };

        addMessage(
            error?.body?.message
        );

        addMessage(
            error?.message
        );

        if (

            Array.isArray(
                error?.body
            )

        ) {

            error.body.forEach(item => {

                addMessage(
                    item?.message
                );

            });

        }

        if (

            Array.isArray(
                error?.body?.pageErrors
            )

        ) {

            error.body.pageErrors.forEach(item => {

                addMessage(
                    item?.message
                );

            });

        }

        if (

            error?.body?.fieldErrors

        ) {

            Object.values(
                error.body.fieldErrors
            ).forEach(items => {

                if (

                    Array.isArray(
                        items
                    )

                ) {

                    items.forEach(item => {

                        addMessage(
                            item?.message
                        );

                    });

                }

            });

        }

        if (

            Array.isArray(
                error?.body?.output?.errors
            )

        ) {

            error.body.output.errors.forEach(item => {

                addMessage(
                    item?.message
                );

            });

        }

        if (

            error?.body?.output?.fieldErrors

        ) {

            Object.values(
                error.body.output.fieldErrors
            ).forEach(items => {

                if (

                    Array.isArray(
                        items
                    )

                ) {

                    items.forEach(item => {

                        addMessage(
                            item?.message
                        );

                    });

                }

            });

        }

        const usefulMessage =
            messages.find(message => {

                const normalizedMessage =
                    this.normalizeText(
                        message
                    );

                return normalizedMessage &&
                    normalizedMessage !== 'failed to get error from response';

            });

        return usefulMessage || '';

    }

    handleError(error) {

        const rawMessage =
            this.extractErrorMessage(
                error
            ) ||
            'Something went wrong while filling the form.';

        const message =
            this.normalizeErrorMessage(
                rawMessage
            );

        this.addMessage(
            message,
            'assistant'
        );

        this.logChatDecisionSafely({
            action:
                'skip',
            status:
                'Failed',
            source:
                'AI Form Chat',
            reason:
                message
        });

        this.dispatchEvent(
            new ShowToastEvent({
                title: 'Chat Fill Failed',
                message,
                variant: 'error'
            })
        );

    }

    normalizeErrorMessage(message) {

        const text =
            message
                ? String(
                    message
                )
                : '';

        const lower =
            this.normalizeText(
                text
            );

        if (
            lower.includes(
                'failed to get error from response'
            )
        ) {
            return 'I could not complete that chat command. Please try the field label again, or use Fill with AI.';
        }

        if (
            lower.includes(
                'apex request is invalid'
            )
        ) {
            return 'I could not reach the AI service for this request. Please check the Prompt Builder app configuration, then try again.';
        }

        return text ||
            'Something went wrong while filling the form.';

    }

}
