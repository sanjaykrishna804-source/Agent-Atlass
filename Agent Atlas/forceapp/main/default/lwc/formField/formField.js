import { LightningElement, api }
from 'lwc';

const FIELD_STATUS = {
    AI_FILLED: 'AI-filled',
    EDITED: 'Edited',
    REVERTED: 'Reverted'
};

const FIELD_STATUS_LABELS = {
    [FIELD_STATUS.AI_FILLED]: 'AI-filled',
    [FIELD_STATUS.EDITED]: 'Edited',
    [FIELD_STATUS.REVERTED]: 'Reverted to AI value'
};

const FIELD_STATUS_CLASSES = {
    AI_FILLED: 'field-status-badge ai-filled',
    EDITED: 'field-status-badge edited'
};

export default class FormField
    extends LightningElement {

    @api fieldConfig;

    @api currentValue;

    isExplanationOpen = false;

    // PICKLIST

    get isPicklist() {

        const type =
            this.fieldConfig?.type
                ?.toLowerCase();

        return type === 'picklist'
            || type === 'dropdown';

    }

    // TEXTAREA

    get isTextarea() {

        return this.fieldConfig?.type
            ?.toLowerCase() === 'textarea';

    }

    // CHECKBOX

    get isCheckbox() {

        return this.fieldConfig?.type
            ?.toLowerCase() === 'checkbox';

    }

    // RADIO

    get isRadio() {

        return this.fieldConfig?.type
            ?.toLowerCase() === 'radio';

    }

    // STANDARD INPUTS

    get isStandardInput() {

        return [

            'text',
            'email',
            'phone',
            'date',
            'number'

        ].includes(

            this.fieldConfig?.type
                ?.toLowerCase()

        );

    }

    get containerClass() {

        const classes =
            [
                'slds-form-element'
            ];

        if (

            this.fieldConfig?.isAutoFilled === true

        ) {

            classes.push(
                'is-ai-filled'
            );

        }

        if (

            this.fieldConfig?.isUserEdited === true

        ) {

            classes.push(
                'is-user-edited'
            );

        }

        return classes.join(
            ' '
        );

    }

    get hasFieldStatus() {

        return this.fieldConfig?.isAutoFilled === true ||
            this.fieldConfig?.isUserEdited === true ||
            !!this.fieldConfig?.fieldStatus;

    }

    get fieldStatusLabel() {

        if (

            this.fieldConfig?.isUserEdited === true

        ) {

            return FIELD_STATUS_LABELS[FIELD_STATUS.EDITED];

        }

        if (

            this.fieldConfig?.fieldStatus === FIELD_STATUS.REVERTED

        ) {

            return FIELD_STATUS_LABELS[FIELD_STATUS.REVERTED];

        }

        if (

            this.fieldConfig?.isAutoFilled === true

        ) {

            return FIELD_STATUS_LABELS[FIELD_STATUS.AI_FILLED];

        }

        return FIELD_STATUS_LABELS[this.fieldConfig?.fieldStatus] ||
            this.fieldConfig?.fieldStatus ||
            '';

    }

    get fieldStatusClass() {

        return this.fieldConfig?.isUserEdited === true
            ? FIELD_STATUS_CLASSES.EDITED
            : FIELD_STATUS_CLASSES.AI_FILLED;

    }

    get canRevertToAIValue() {

        return this.fieldConfig?.isUserEdited === true &&
            this.fieldConfig?.originalAIValue !== undefined;

    }

    get canUndo() {

        return this.fieldConfig?.canUndo === true;

    }

    get canRedo() {

        return this.fieldConfig?.canRedo === true;

    }

    get canUndoDisabled() {

        return !this.canUndo;

    }

    get canRedoDisabled() {

        return !this.canRedo;

    }

    get hasSourceFields() {

        return this.fieldConfig?.isMergedAnswer === true &&
            this.sourceFields.length > 1;

    }

    get sourceFields() {

        let sourceText =
            this.fieldConfig?.sourceFieldsText || '';

        if (

            typeof sourceText === 'string' &&
            sourceText.trim().startsWith(
                '['
            )

        ) {

            try {

                const parsedSourceFields =
                    JSON.parse(
                        sourceText
                    );

                if (

                    Array.isArray(
                        parsedSourceFields
                    )

                ) {

                    sourceText =
                        parsedSourceFields.join(
                            ','
                        );

                }

            } catch (error) {

                sourceText =
                    this.fieldConfig?.sourceFieldsText || '';

            }

        }

        return sourceText
            .split(',')
            .map(sourceField => this.normalizeSourceField(sourceField))
            .filter(sourceField => {

                const lowerSource =
                    sourceField.toLowerCase();

                return sourceField &&
                    lowerSource !== 'prompt builder' &&
                    lowerSource !== 'einstein prompt builder' &&
                    lowerSource !== 'applicant knowledge' &&
                    lowerSource !== 'ai' &&
                    lowerSource !== 'chat prompt' &&
                    !lowerSource.includes(
                        'prompt builder'
                    ) &&
                    !lowerSource.includes(
                        'openai semantic extraction'
                    );

            });

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

    get sourceFieldsText() {

        return this.sourceFields.join(
            ', '
        );

    }

    get sourceFieldsLabel() {

        return 'Fields merged';

    }

    get hasAIConfidence() {

        return !this.isCheckbox &&
            !this.isBlankValue(
                this.currentValue
            ) &&
            this.normalizedAIConfidence !== null;

    }

    isBlankValue(value) {

        return value === null ||
            value === undefined ||
            value === '';

    }

    get normalizedAIConfidence() {

        const rawConfidence =
            this.fieldConfig?.aiConfidence;

        if (

            rawConfidence === null ||
            rawConfidence === undefined ||
            rawConfidence === ''

        ) {

            return null;

        }

        const confidence =
            Number(
                rawConfidence
            );

        if (

            Number.isNaN(
                confidence
            )

        ) {

            return null;

        }

        if (

            confidence <= 1

        ) {

            return Math.max(
                0,
                Math.min(
                    100,
                    Math.round(
                        confidence * 100
                    )
                )
            );

        }

        return Math.max(
            0,
            Math.min(
                100,
                Math.round(
                    confidence
                )
            )
        );

    }

    get confidencePercent() {

        return this.normalizedAIConfidence === null
            ? 'Not available'
            : `${this.normalizedAIConfidence}%`;

    }

    get confidenceTooltip() {

        return this.explanationSummary;

    }

    get aiInsightSummary() {

        return `${this.confidencePercent} confidence • ${this.aiInsightSourcePreview}`;

    }

    get aiInsightSourcePreview() {

        const sourceText =
            this.explanationSourceText;

        return sourceText.length > 44
            ? `${sourceText.slice(
                0,
                41
            )}...`
            : sourceText;

    }

    get hasAIExplanation() {

        return !this.isCheckbox &&
            !this.isBlankValue(
                this.currentValue
            ) &&
            (
                this.normalizedAIConfidence !== null ||
                !!this.fieldConfig?.aiReasoning ||
                this.explanationSourceFields.length > 0
            );

    }

    get explanationSummary() {

        return [
            `Confidence: ${this.confidencePercent}`,
            `Source: ${this.explanationSourceText}`,
            `Reason: ${this.explanationReasoning}`
        ]
            .filter(item => !item.endsWith(': '))
            .join(' | ');

    }

    get explanationSourceFields() {

        const rawSourceFields =
            this.fieldConfig?.aiRawSourceFields;

        if (

            Array.isArray(
                rawSourceFields
            ) &&
            rawSourceFields.length

        ) {

            return rawSourceFields
                .map(sourceField => this.formatSourceField(sourceField))
                .filter(sourceField => !!sourceField);

        }

        if (

            this.sourceFields.length

        ) {

            return this.sourceFields
                .map(sourceField => this.formatSourceField(sourceField))
                .filter(sourceField => !!sourceField);

        }

        return [];

    }

    get explanationSourceText() {

        return this.explanationSourceFields.length
            ? this.explanationSourceFields.join(', ')
            : 'Saved Salesforce data';

    }

    get explanationLeadText() {

        if (

            this.normalizedAIConfidence === null

        ) {

            return `Used ${this.explanationSourceText}. Confidence was not available.`;

        }

        return `Used ${this.explanationSourceText} with ${this.confidencePercent} confidence.`;

    }

    get explanationReasoning() {

        return this.toPlainSentence(
            this.fieldConfig?.aiReasoning ||
            'The value matched what this question is asking for.'
        );

    }

    get explanationSelectionType() {

        return this.fieldConfig?.aiSelectionType ||
            (
                this.fieldConfig?.isMergedAnswer === true
                    ? 'Synthesized from multiple saved fields'
                    : 'Direct mapping from saved data'
            );

    }

    get explanationSourceUpdatedAt() {

        return this.fieldConfig?.aiSourceUpdatedAt ||
            'Timestamp not available';

    }

    get explanationAlternativeOptions() {

        const alternatives =
            this.fieldConfig?.aiAlternativeOptions;

        if (

            Array.isArray(
                alternatives
            ) &&
            alternatives.length

        ) {

            return alternatives.map((alternative, index) => {

                return {
                    id:
                        `${index}-${alternative}`,
                    text:
                        alternative
                };

            });

        }

        return [
            {
                id:
                    'default-alternative',
                text:
                    'No stronger saved-data alternative was found.'
            }
        ];

    }

    get explanationPanelClass() {

        return this.isExplanationOpen
            ? 'ai-explanation-panel ai-insight-panel is-open'
            : 'ai-explanation-panel ai-insight-panel';

    }

    formatSourceField(sourceField) {

        return String(
            sourceField || ''
        )
            .replace(/__c$/g, '')
            .replace(/_/g, ' ')
            .replace(/\./g, ' ')
            .replace(/\s+/g, ' ')
            .trim();

    }

    toPlainSentence(value) {

        const text =
            String(
                value || ''
            )
                .replace(/\s*\|\s*/g, '. ')
                .replace(/\s+/g, ' ')
                .trim();

        if (

            !text

        ) {

            return '';

        }

        return text.endsWith('.') ||
            text.endsWith('!') ||
            text.endsWith('?')
            ? text
            : `${text}.`;

    }

    toggleExplanation() {

        this.isExplanationOpen =
            !this.isExplanationOpen;

    }

    // OPTIONS

    get options() {

        // NO OPTIONS

        if (

            !this.fieldConfig ||

            !this.fieldConfig.options

        ) {

            return [];

        }

        // ALREADY OBJECT FORMAT

        if (

            Array.isArray(
                this.fieldConfig.options
            ) &&

            typeof this.fieldConfig.options[0]
                === 'object'

        ) {

            return this.fieldConfig.options;

        }

        // STRING ARRAY FORMAT

        return this.fieldConfig.options.map(option => {

            return {

                label: option,

                value: option

            };

        });

    }

    // REGEX VALIDATION

    get validationPattern() {

        return this.fieldConfig?.validationRule

            ? new RegExp(

                this.fieldConfig.validationRule

            )

            : null;

    }

    // INPUT CHANGE

    handleInputChange(event) {

        let val;

        // CHECKBOX

        if (this.isCheckbox) {

            val = event.target.checked;

        }

        else {

            val = event.target.value;

        }

        // TRIM STRINGS

        if (typeof val === 'string') {

            val = val.trim();

        }

        this.emitValue(val);

    }

    // RADIO CHANGE

    handleRadioChange(event) {

        this.emitValue(event.detail.value);

    }

    // PICKLIST CHANGE

    handlePicklistChange(event) {

        this.emitValue(event.detail.value);

    }

    // BLUR VALIDATION

    handleBlur() {

        const inputElement =

            this.template.querySelector(
                '.input-node'
            );

        if (inputElement) {

            let value =
                inputElement.value;

            // REGEX CHECK

            if (

                this.validationPattern &&
                value &&
                !this.validationPattern.test(value)

            ) {

                inputElement.setCustomValidity(
                    'Invalid format'
                );

            }

            else {

                inputElement.setCustomValidity('');

            }

            inputElement.reportValidity();

        }

        this.dispatchEvent(

            new CustomEvent('fieldblur', {

                bubbles: true,

                composed: true

            })

        );

    }

    // SEND VALUE

    emitValue(value) {

        this.dispatchEvent(

            new CustomEvent('valuechange', {

                detail: {

                    questionId:
                        this.fieldConfig.id,

                    value: value

                }

            })

        );

    }

    handleRevertToAIValue() {

        this.dispatchEvent(

            new CustomEvent('revertaivalue', {

                detail: {

                    questionId:
                        this.fieldConfig.id

                }

            })

        );

    }

    handleUndoFieldValue() {

        this.dispatchEvent(

            new CustomEvent('undofieldvalue', {

                detail: {

                    questionId:
                        this.fieldConfig.id

                }

            })

        );

    }

    handleRedoFieldValue() {

        this.dispatchEvent(

            new CustomEvent('redofieldvalue', {

                detail: {

                    questionId:
                        this.fieldConfig.id

                }

            })

        );

    }

    // VALIDATE

    @api
    validate() {

        const inputElement =

            this.template.querySelector(
                '.input-node'
            );

        if (!inputElement) {

            return true;

        }

        let value =
            inputElement.value;

        // REGEX VALIDATION

        if (

            this.validationPattern &&
            value &&
            !this.validationPattern.test(value)

        ) {

            inputElement.setCustomValidity(
                'Invalid format'
            );

        }

        else {

            inputElement.setCustomValidity('');

        }

        inputElement.reportValidity();

        return inputElement.checkValidity();

    }

}
