public without sharing class EinsteinPromptExtractionService {

    /*
     * Prompt Builder template API name shared with chat command interpretation.
     */
    private static final String PROMPT_TEMPLATE_API_NAME =
        'AI_Form_Chat_Command_Interpreter';

    public static Map<String, UserDataDiscoveryService.DataDiscoveryResult>
    extractAnswers(

        Id userId,

        List<UserDataDiscoveryService.FormQuestion> questions

    ) {

        return extractAnswers(
            userId,
            questions,
            null
        );

    }

    public static Map<String, UserDataDiscoveryService.DataDiscoveryResult>
    extractAnswers(

        Id userId,

        List<UserDataDiscoveryService.FormQuestion> questions,

        Id targetApplicationId

    ) {

        Map<String, UserDataDiscoveryService.DataDiscoveryResult> results =
            new Map<String, UserDataDiscoveryService.DataDiscoveryResult>();

        if (

            questions == null ||

            questions.isEmpty()

        ) {

            return results;

        }

        UserDataDiscoveryService.DiscoveryContext context =
            UserDataDiscoveryService.loadDiscoveryContext(
                userId,
                targetApplicationId
            );

        String sourceDataJson =
            JSON.serialize(
                buildSourceData(
                    context
                )
            );

        fillMissingFieldsWithSinglePromptBuilderPass(
            results,
            questions,
            sourceDataJson
        );

        return results;

    }

    private static void fillMissingFieldsWithSinglePromptBuilderPass(

        Map<String, UserDataDiscoveryService.DataDiscoveryResult> results,

        List<UserDataDiscoveryService.FormQuestion> questions,

        String sourceDataJson

    ) {

        try {

            String promptResponse =
                invokePromptTemplate(
                    'fill all available form fields',
                    JSON.serialize(
                        buildFieldContext(
                            questions
                        )
                    ),
                    '{}',
                    sourceDataJson
                );

            Map<String, UserDataDiscoveryService.DataDiscoveryResult>
                promptResults =
                    parseResults(
                        promptResponse,
                        questions,
                        null
                    );

            for (

                String questionId
                : promptResults.keySet()

            ) {

                if (

                    !hasUsableResult(
                        results.get(
                            questionId
                        )
                    )

                ) {

                    results.put(
                        questionId,
                        promptResults.get(
                            questionId
                        )
                    );

                }

            }

        } catch (Exception e) {

            System.debug(
                LoggingLevel.WARN,
                'Bulk Prompt Builder fill skipped: ' +
                e.getMessage()
            );

        }

    }

    private static Boolean hasUsableResult(

        UserDataDiscoveryService.DataDiscoveryResult result

    ) {

        return result != null &&
            (
                !String.isBlank(
                    result.recommendedValue
                ) ||
                result.clearValue == true
            );

    }

    private static UserDataDiscoveryService.DataDiscoveryResult extractSingleAnswer(

        UserDataDiscoveryService.FormQuestion question,

        String sourceDataJson

    ) {

        try {

            String promptResponse =
                invokePromptTemplate(
                    'fill ' + question.questionText,
                    JSON.serialize(
                        buildFieldContext(
                            new List<UserDataDiscoveryService.FormQuestion>{
                                question
                            }
                        )
                    ),
                    '{}',
                    sourceDataJson
                );

            if (

                String.isBlank(
                    promptResponse
                )

            ) {

                return null;

            }

            Map<String, Object> parsed =
                parseJsonObject(
                    promptResponse
                );

            if (

                parsed == null ||
                parsed.isEmpty()

            ) {

                return null;

            }

            normalizeParsedCommand(
                parsed
            );

            String action =
                firstStringValue(
                    parsed,
                    new List<String>{
                        'action',
                        'type',
                        'command'
                    }
                );

            if (

                !String.isBlank(
                    action
                )

            ) {

                String normalizedAction =
                    action.toLowerCase().trim();

                if (

                    normalizedAction != 'fill' &&
                    normalizedAction != 'fill_field' &&
                    normalizedAction != 'autofill' &&
                    normalizedAction != 'no_data_found' &&
                    normalizedAction != 'no data found' &&
                    normalizedAction != 'missing_data' &&
                    normalizedAction != 'missing data' &&
                    normalizedAction != 'not_found' &&
                    normalizedAction != 'not found' &&
                    normalizedAction != 'unfillable'

                ) {

                    return null;

                }

            }

            String value =
                firstStringValue(
                    parsed,
                    new List<String>{
                        'value',
                        'newValue',
                        'answer',
                        'recommendedValue',
                        'fieldValue',
                        'extractedValue',
                        'selectedValue',
                        'outputValue',
                        'replacementValue'
                    }
                );

            if (

                isUnsupportedGeneralKnowledgeQuestion(
                    question
                )

            ) {

                return buildNoDataResult(
                    question.questionId,
                    parsed,
                    'Question is not tied to saved Salesforce/applicant data, so the answer was not used.'
                );

            }

            Boolean noDataFound =
                isNoDataResponse(
                    parsed,
                    value
                );

            if (

                noDataFound

            ) {

                UserDataDiscoveryService.DataDiscoveryResult result =
                    new UserDataDiscoveryService.DataDiscoveryResult();

                result.questionId =
                    question.questionId;

                result.bestMatchConfidence =
                    toDecimal(
                        parsed.get(
                            'confidence'
                        ),
                        0
                    );

                result.noDataFound =
                    true;

                result.noDataMessage =
                    firstStringValue(
                        parsed,
                        new List<String>{
                            'noDataMessage',
                            'message',
                            'userMessage',
                            'clarificationQuestion',
                            'reasoning',
                            'reason'
                        }
                    );

                result.reasoning =
                    'Einstein Prompt Builder no-data response: ' +
                    firstStringValue(
                        parsed,
                        new List<String>{
                            'reasoning',
                            'reason'
                        }
                    );

                applyPromptExplanationMetadata(
                    result,
                    parsed
                );

                return result;

            }

            String validatedValue =
                validateValue(
                    question,
                    value
                );

            if (

                String.isBlank(
                    validatedValue
                )

            ) {

                return null;

            }

            List<String> sourceFields =
                parseSourceFields(
                    parsed.get(
                        'sourceFields'
                    )
                );

            if (

                sourceFields.isEmpty()

            ) {

                return buildNoDataResult(
                    question.questionId,
                    parsed,
                    'Prompt Builder returned a value without source fields, so the answer was not used.'
                );

            }

            UserDataDiscoveryService.DataDiscoveryResult result =
                new UserDataDiscoveryService.DataDiscoveryResult();

            result.questionId =
                question.questionId;

            result.recommendedValue =
                validatedValue;

            result.bestMatchConfidence =
                toDecimal(
                    parsed.get(
                        'confidence'
                    ),
                    0.9
                );

            result.reasoning =
                'Einstein Prompt Builder single-field extraction: ' +
                String.valueOf(
                    parsed.get(
                        'reasoning'
                    )
                );

            result.isMergedAnswer =
                toBoolean(
                    parsed.get(
                        'isMergedAnswer'
                    ),
                    false
                );

            result.sourceFields.addAll(
                sourceFields
            );

            applyPromptExplanationMetadata(
                result,
                parsed
            );

            return result;

        } catch (Exception e) {

            System.debug(
                LoggingLevel.WARN,
                'Single-field Prompt Builder fill skipped for ' +
                question.questionText +
                ': ' +
                e.getMessage()
            );

            return null;

        }

    }

    private static String invokePromptTemplate(

        String userMessage,

        String fieldContextJson,

        String existingValuesJson,

        String applicantKnowledge

    ) {

        Map<String, ConnectApi.WrappedValue> inputParams =
            new Map<String, ConnectApi.WrappedValue>();

        putInputParam(
            inputParams,
            'Input:userMessage',
            userMessage
        );
        putInputParam(
            inputParams,
            'Input:fieldContextJson',
            String.isBlank(fieldContextJson)
                ? '[]'
                : fieldContextJson
        );
        putInputParam(
            inputParams,
            'Input:existingValuesJson',
            String.isBlank(existingValuesJson)
                ? '{}'
                : existingValuesJson
        );
        putInputParam(
            inputParams,
            'Input:applicantKnowledge',
            String.isBlank(applicantKnowledge)
                ? ''
                : applicantKnowledge
        );

        ConnectApi.EinsteinPromptTemplateGenerationsInput input =
            new ConnectApi.EinsteinPromptTemplateGenerationsInput();

        input.isPreview =
            false;

        input.inputParams =
            inputParams;

        input.additionalConfig =
            new ConnectApi.EinsteinLlmAdditionalConfigInput();

        input.additionalConfig.applicationName =
            'PromptBuilderPreview';

        ConnectApi.EinsteinPromptTemplateGenerationsRepresentation output =
            ConnectApi.EinsteinLLM.generateMessagesForPromptTemplate(
                PROMPT_TEMPLATE_API_NAME,
                input
            );

        if (

            output == null ||

            output.generations == null ||

            output.generations.isEmpty()

        ) {

            return null;

        }

        return output.generations[0].text;

    }

    private static void putInputParam(
        Map<String, ConnectApi.WrappedValue> inputParams,
        String key,
        String value
    ) {
        ConnectApi.WrappedValue wrappedValue =
            new ConnectApi.WrappedValue();

        wrappedValue.value =
            value;

        inputParams.put(
            key,
            wrappedValue
        );
    }

    private static List<Object> buildFieldContext(

        List<UserDataDiscoveryService.FormQuestion> questions

    ) {

        List<Object> questionPayload =
            new List<Object>();

        for (

            UserDataDiscoveryService.FormQuestion question
            : questions

        ) {

            if (

                question == null ||

                String.isBlank(
                    question.questionId
                )

            ) {

                continue;

            }

            questionPayload.add(
                new Map<String, Object>{
                    'questionId' =>
                        question.questionId,
                    'label' =>
                        question.questionText,
                    'type' =>
                        question.questionType,
                    'options' =>
                        parseOptions(
                            question.picklistValues
                        )
                }
            );

        }

        return questionPayload;

    }

    private static Map<String, Object> buildSourceData(

        UserDataDiscoveryService.DiscoveryContext context

    ) {

        if (context == null) {
            return new Map<String, Object>();
        }

        return new Map<String, Object>{
            'applicantKnowledge' =>
                context.con == null
                    ? null
                    : UserDataDiscoveryService.getContactText(
                        context.con,
                        'Applicant_Knowledge__c'
                    ),
            'user' =>
                context.usr == null
                    ? null
                    : new Map<String, Object>{
                        'firstName' => context.usr.FirstName,
                        'lastName' => context.usr.LastName,
                        'email' => context.usr.Email,
                        'phone' => context.usr.Phone,
                        'street' => context.usr.Street,
                        'city' => context.usr.City,
                        'state' => context.usr.State,
                        'postalCode' => context.usr.PostalCode,
                        'country' => context.usr.Country
                    },
            'contact' =>
                context.con == null
                    ? null
                    : new Map<String, Object>{
                        'birthdate' => context.con.Birthdate,
                        'phone' => context.con.Phone,
                        'mobilePhone' => context.con.MobilePhone,
                        'gender' =>
                            UserDataDiscoveryService.getContactText(
                                context.con,
                                'Gender__c'
                            ),
                        'citizenshipStatus' =>
                            UserDataDiscoveryService.getContactText(
                                context.con,
                                'Citizenship_Status__c'
                            ),
                        'languages' =>
                            UserDataDiscoveryService.getContactText(
                                context.con,
                                'Languages__c'
                            ),
                        'mailingStreet' => context.con.MailingStreet,
                        'mailingCity' => context.con.MailingCity,
                        'mailingState' => context.con.MailingState,
                        'mailingPostalCode' =>
                            context.con.MailingPostalCode,
                        'mailingCountry' => context.con.MailingCountry
                    },
            'application' =>
                context.application == null
                    ? null
                    : new Map<String, Object>{
                        'id' => context.application.Id,
                        'applicantId' => context.application.Applicant__c,
                        'admissionGranted' =>
                            context.application.Admission_Granted__c,
                        'decisionStatus' =>
                            context.application.Decision_Status__c,
                        'adminReviewComments' =>
                            context.application.Admin_Review_Comments__c,
                        'approvalDecisionComments' =>
                            context.application.Approval_Decision_Comments__c,
                        'rejectionComments' =>
                            context.application.Rejection_Comments__c,
                        'reviewerNotes' =>
                            context.application.Reviewer_Notes__c,
                        'decisionDate' =>
                            context.application.Decision_Date__c
                    }
        };

    }

    private static Map<String, UserDataDiscoveryService.DataDiscoveryResult>
    parseResults(

        String responseText,

        List<UserDataDiscoveryService.FormQuestion> questions,

        UserDataDiscoveryService.DiscoveryContext context

    ) {

        Map<String, UserDataDiscoveryService.DataDiscoveryResult> results =
            new Map<String, UserDataDiscoveryService.DataDiscoveryResult>();

        Map<String, Object> parsed =
            parseJsonObject(
                responseText
            );

        if (

            parsed == null ||

            parsed.isEmpty()

        ) {

            return results;

        }

        List<Object> answers =
            firstListValue(
                parsed,
                new List<String>{
                    'answers',
                    'fields',
                    'filledFields',
                    'fieldUpdates',
                    'results'
                }
            );

        if (

            answers == null

        ) {

            answers =
                buildSingleAnswerList(
                    parsed
                );

        }

        if (

            answers == null ||

            answers.isEmpty()

        ) {

            return results;

        }

        Map<String, UserDataDiscoveryService.FormQuestion> questionById =
            new Map<String, UserDataDiscoveryService.FormQuestion>();

        for (

            UserDataDiscoveryService.FormQuestion question
            : questions

        ) {

            if (

                question != null &&

                !String.isBlank(
                    question.questionId
                )

            ) {

                questionById.put(
                    question.questionId,
                    question
                );

            }

        }

        for (

            Object rawAnswer
            : answers

        ) {

            if (

                !(rawAnswer instanceof Map<String, Object>)

            ) {

                continue;

            }

            Map<String, Object> answer =
                (Map<String, Object>) rawAnswer;

            normalizeParsedCommand(
                answer
            );

            String questionId =
                firstStringValue(
                    answer,
                    new List<String>{
                        'questionId',
                        'targetQuestionId',
                        'id'
                    }
                );

            if (

                String.isBlank(
                    questionId
                )

            ) {

                questionId =
                    findQuestionIdByLabel(
                        questionById,
                        firstStringValue(
                            answer,
                            new List<String>{
                                'fieldLabel',
                                'targetLabel',
                                'label'
                            }
                        )
                    );

            }

            if (

                String.isBlank(
                    questionId
                ) ||

                !questionById.containsKey(
                    questionId
                )

            ) {

                continue;

            }

            String value =
                firstStringValue(
                    answer,
                    new List<String>{
                        'value',
                        'newValue',
                        'answer',
                        'recommendedValue',
                        'fieldValue',
                        'extractedValue',
                        'selectedValue',
                        'outputValue',
                        'replacementValue'
                    }
                );

            if (

                isUnsupportedGeneralKnowledgeQuestion(
                    questionById.get(
                        questionId
                    )
                )

            ) {

                results.put(
                    questionId,
                    buildNoDataResult(
                        questionId,
                        answer,
                        'Question is not tied to saved Salesforce/applicant data, so the answer was not used.'
                    )
                );

                continue;

            }

            Boolean noDataFound =
                isNoDataResponse(
                    answer,
                    value
                );

            if (

                noDataFound

            ) {

                UserDataDiscoveryService.DataDiscoveryResult result =
                    new UserDataDiscoveryService.DataDiscoveryResult();

                result.questionId =
                    questionId;

                result.bestMatchConfidence =
                    toDecimal(
                        answer.get(
                            'confidence'
                        ),
                        0
                    );

                result.noDataFound =
                    true;

                result.noDataMessage =
                    firstStringValue(
                        answer,
                        new List<String>{
                            'noDataMessage',
                            'message',
                            'userMessage',
                            'clarificationQuestion',
                            'reasoning',
                            'reason'
                        }
                    );

                result.reasoning =
                    'Einstein Prompt Builder no-data response: ' +
                    firstStringValue(
                        answer,
                        new List<String>{
                            'reasoning',
                            'reason'
                        }
                    );

                result.sourceFields.addAll(
                    parseSourceFields(
                        answer.get(
                            'sourceFields'
                        )
                    )
                );

                applyPromptExplanationMetadata(
                    result,
                    answer
                );

                results.put(
                    questionId,
                    result
                );

                continue;

            }

            String validatedValue =
                validateValue(
                    questionById.get(
                        questionId
                    ),
                    value
                );

            if (

                String.isBlank(
                    validatedValue
                )

            ) {

                continue;

            }

            List<String> sourceFields =
                parseSourceFields(
                    answer.get(
                        'sourceFields'
                    )
                );

            if (

                sourceFields.isEmpty()

            ) {

                results.put(
                    questionId,
                    buildNoDataResult(
                        questionId,
                        answer,
                        'Prompt Builder returned a value without source fields, so the answer was not used.'
                    )
                );

                continue;

            }

            UserDataDiscoveryService.DataDiscoveryResult result =
                new UserDataDiscoveryService.DataDiscoveryResult();

            result.questionId =
                questionId;

            result.recommendedValue =
                validatedValue;

            result.bestMatchConfidence =
                toDecimal(
                    answer.get(
                        'confidence'
                    ),
                    0.9
                );

            result.reasoning =
                'Einstein Prompt Builder extraction: ' +
                firstStringValue(
                    answer,
                    new List<String>{
                        'reasoning',
                        'reason'
                    }
                );

            result.isMergedAnswer =
                toBoolean(
                    answer.get(
                        'isMergedAnswer'
                    ),
                    false
                );

            result.sourceFields.addAll(
                sourceFields
            );

            applyPromptExplanationMetadata(
                result,
                answer
            );

            results.put(
                questionId,
                result
            );

        }

        return results;

    }

    private static Map<String, Object> parseJsonObject(
        String value
    ) {
        if (String.isBlank(value)) {
            return null;
        }

        String jsonText =
            value.trim();

        Integer startIndex =
            jsonText.indexOf('{');

        Integer endIndex =
            jsonText.lastIndexOf('}');

        if (
            startIndex < 0 ||
            endIndex < startIndex
        ) {
            return null;
        }

        jsonText =
            jsonText.substring(
                startIndex,
                endIndex + 1
            );

        try {
            return (Map<String, Object>) JSON.deserializeUntyped(
                jsonText
            );
        }

        catch (Exception e) {
            return null;
        }
    }

    private static List<Object> firstListValue(
        Map<String, Object> values,
        List<String> keys
    ) {
        for (String key : keys) {
            if (
                values.containsKey(key) &&
                values.get(key) instanceof List<Object>
            ) {
                return (List<Object>) values.get(key);
            }
        }

        return null;
    }

    private static List<Object> buildSingleAnswerList(
        Map<String, Object> parsed
    ) {
        String value =
            firstStringValue(
                parsed,
                new List<String>{
                    'value',
                    'newValue',
                    'answer',
                    'recommendedValue',
                    'fieldValue',
                    'extractedValue',
                    'selectedValue',
                    'outputValue',
                    'replacementValue'
                }
            );

        if (String.isBlank(value)) {
            return null;
        }

        return new List<Object>{
            parsed
        };
    }

    private static String firstStringValue(
        Map<String, Object> values,
        List<String> keys
    ) {
        if (values == null) {
            return null;
        }

        for (String key : keys) {
            if (
                values.containsKey(key) &&
                values.get(key) != null
            ) {
                return String.valueOf(
                    values.get(key)
                );
            }
        }

        return null;
    }

    private static String findQuestionIdByLabel(
        Map<String, UserDataDiscoveryService.FormQuestion> questionById,
        String label
    ) {
        if (
            questionById == null ||
            String.isBlank(label)
        ) {
            return null;
        }

        String normalizedLabel =
            normalizeText(
                label
            );

        for (
            String questionId
            : questionById.keySet()
        ) {
            UserDataDiscoveryService.FormQuestion question =
                questionById.get(
                    questionId
                );

            if (
                question != null &&
                normalizeText(
                    question.questionText
                ) == normalizedLabel
            ) {
                return questionId;
            }
        }

        return null;
    }

    private static String normalizeText(
        String value
    ) {
        return String.isBlank(value)
            ? ''
            : value.toLowerCase().replaceAll(
                '[^a-z0-9]+',
                ' '
            ).trim();
    }

    private static String validateValue(

        UserDataDiscoveryService.FormQuestion question,

        String value

    ) {

        if (

            question == null ||

            String.isBlank(
                value
            )

        ) {

            return null;

        }

        List<String> options =
            parseOptions(
                question.picklistValues
            );

        String type =
            String.isBlank(
                question.questionType
            )
                ? ''
                : question.questionType.toLowerCase();

        if (

            (
                type == 'picklist' ||
                type == 'dropdown' ||
                type == 'radio'
            ) &&

            !options.isEmpty()

        ) {

            for (

                String option
                : options

            ) {

                if (

                    option.equalsIgnoreCase(
                        value.trim()
                    ) ||
                    normalizeText(
                        option
                    ) == normalizeText(
                        value
                    )

                ) {

                    return option;

                }

            }

            return null;

        }

        return value.trim();

    }

    private static List<String> parseOptions(

        String rawOptions

    ) {

        List<String> options =
            new List<String>();

        if (

            String.isBlank(
                rawOptions
            )

        ) {

            return options;

        }

        for (

            String option
            : rawOptions.split(
                '[;,\\n]'
            )

        ) {

            String cleaned =
                option.trim();

            if (

                !String.isBlank(
                    cleaned
                )

            ) {

                options.add(
                    cleaned
                );

            }

        }

        return options;

    }

    private static List<String> parseSourceFields(

        Object rawSourceFields

    ) {

        List<String> sourceFields =
            new List<String>();

        if (

            rawSourceFields instanceof List<Object>

        ) {

            for (

                Object rawSourceField
                : (List<Object>) rawSourceFields

            ) {

                addSourceField(
                    sourceFields,
                    String.valueOf(
                        rawSourceField
                    )
                );

            }

            return sourceFields;

        }

        if (

            rawSourceFields != null

        ) {

            addSourceField(
                sourceFields,
                String.valueOf(
                    rawSourceFields
                )
            );

        }

        return sourceFields;

    }

    private static void applyPromptExplanationMetadata(

        UserDataDiscoveryService.DataDiscoveryResult result,

        Map<String, Object> parsed

    ) {

        if (

            result == null ||
            parsed == null

        ) {

            return;

        }

        result.sourceUpdatedAt =
            firstStringValue(
                parsed,
                new List<String>{
                    'sourceUpdatedAt',
                    'sourceLastModifiedDate',
                    'sourceTimestamp',
                    'lastUpdatedAt',
                    'lastModifiedDate'
                }
            );

        result.selectionType =
            firstStringValue(
                parsed,
                new List<String>{
                    'selectionType',
                    'mappingType',
                    'answerType'
                }
            );

        if (

            String.isBlank(
                result.selectionType
            )

        ) {

            result.selectionType =
                result.isMergedAnswer == true ||
                (
                    result.sourceFields != null &&
                    result.sourceFields.size() > 1
                )
                    ? 'Synthesized from multiple saved fields'
                    : 'Direct mapping from saved data';

        }

        result.alternativeOptions =
            parseStringList(
                firstNonNullValue(
                    parsed,
                    new List<String>{
                        'alternativeOptions',
                        'alternativesConsidered',
                        'alternatives',
                        'otherOptions'
                    }
                )
            );

        if (

            result.alternativeOptions.isEmpty()

        ) {

            result.alternativeOptions.add(
                'No stronger saved-data alternative was found.'
            );

        }

    }

    private static Object firstNonNullValue(

        Map<String, Object> values,

        List<String> keys

    ) {

        if (

            values == null

        ) {

            return null;

        }

        for (

            String key
            : keys

        ) {

            if (

                values.containsKey(
                    key
                ) &&
                values.get(
                    key
                ) != null

            ) {

                return values.get(
                    key
                );

            }

        }

        return null;

    }

    private static List<String> parseStringList(

        Object rawValues

    ) {

        List<String> values =
            new List<String>();

        if (

            rawValues instanceof List<Object>

        ) {

            for (

                Object rawValue
                : (List<Object>) rawValues

            ) {

                addStringValue(
                    values,
                    String.valueOf(
                        rawValue
                    )
                );

            }

            return values;

        }

        if (

            rawValues != null

        ) {

            addStringValue(
                values,
                String.valueOf(
                    rawValues
                )
            );

        }

        return values;

    }

    private static void addStringValue(

        List<String> values,

        String value

    ) {

        if (

            String.isBlank(
                value
            )

        ) {

            return;

        }

        String cleanedValue =
            value.trim();

        if (

            !values.contains(
                cleanedValue
            )

        ) {

            values.add(
                cleanedValue
            );

        }

    }

    private static void normalizeParsedCommand(
        Map<String, Object> parsed
    ) {
        if (parsed == null) {
            return;
        }

        mergeFirstNestedCommand(
            parsed
        );

        if (!parsed.containsKey('questionId')) {
            Object questionId =
                firstPresentValue(
                    parsed,
                    new List<String>{
                        'targetQuestionId',
                        'questionId',
                        'id',
                        'fieldId'
                    }
                );

            if (questionId != null) {
                parsed.put(
                    'questionId',
                    questionId
                );
            }
        }

        if (!parsed.containsKey('targetLabel')) {
            Object label =
                firstPresentValue(
                    parsed,
                    new List<String>{
                        'targetLabel',
                        'fieldLabel',
                        'targetFieldLabel',
                        'fieldName',
                        'field',
                        'label',
                        'questionLabel',
                        'targetField'
                    }
                );

            if (label != null) {
                parsed.put(
                    'targetLabel',
                    label
                );
            }
        }

        if (!parsed.containsKey('newValue')) {
            Object value =
                firstPresentValue(
                    parsed,
                    new List<String>{
                        'newValue',
                        'value',
                        'answer',
                        'recommendedValue',
                        'fieldValue',
                        'extractedValue',
                        'selectedValue',
                        'outputValue',
                        'replacementValue'
                    }
                );

            if (value != null) {
                parsed.put(
                    'newValue',
                    value
                );
            }
        }
    }

    private static Boolean isNoDataResponse(
        Map<String, Object> parsed,
        String value
    ) {
        if (parsed == null) {
            return false;
        }

        if (
            toBoolean(
                parsed.get(
                    'noDataFound'
                ),
                false
            ) ||
            toBoolean(
                parsed.get(
                    'missingData'
                ),
                false
            )
        ) {
            return true;
        }

        String action =
            firstStringValue(
                parsed,
                new List<String>{
                    'action',
                    'type',
                    'command',
                    'status'
                }
            );

        if (
            !String.isBlank(
                action
            )
        ) {
            String normalizedAction =
                normalizeText(
                    action
                );

            if (
                normalizedAction == 'no data found' ||
                normalizedAction == 'no data' ||
                normalizedAction == 'missing data' ||
                normalizedAction == 'not found' ||
                normalizedAction == 'unfillable'
            ) {
                return true;
            }
        }

        return String.isBlank(
            value
        ) &&
            !String.isBlank(
                firstStringValue(
                    parsed,
                    new List<String>{
                        'noDataMessage',
                        'message',
                        'userMessage'
                    }
                )
            );
    }

    private static Boolean isUnsupportedGeneralKnowledgeQuestion(

        UserDataDiscoveryService.FormQuestion question

    ) {

        if (

            question == null ||
            String.isBlank(
                question.questionText
            )

        ) {

            return false;

        }

        String normalizedQuestion =
            normalizeText(
                question.questionText
            );

        if (

            normalizedQuestion.startsWith(
                'why '
            ) &&
            !normalizedQuestion.contains(
                'why this university'
            ) &&
            !normalizedQuestion.contains(
                'why this school'
            ) &&
            !normalizedQuestion.contains(
                'why this program'
            ) &&
            !normalizedQuestion.contains(
                'choose this university'
            ) &&
            !normalizedQuestion.contains(
                'choose this school'
            ) &&
            !normalizedQuestion.contains(
                'choose this program'
            )

        ) {

            return true;

        }

        return normalizedQuestion.contains(
            'leaves are green'
        ) ||
            normalizedQuestion.contains(
                'leaf green'
            );

    }

    private static UserDataDiscoveryService.DataDiscoveryResult buildNoDataResult(
        String questionId,
        Map<String, Object> parsed,
        String defaultReason
    ) {
        UserDataDiscoveryService.DataDiscoveryResult result =
            new UserDataDiscoveryService.DataDiscoveryResult();

        result.questionId =
            questionId;

        result.bestMatchConfidence =
            toDecimal(
                parsed == null
                    ? null
                    : parsed.get(
                        'confidence'
                    ),
                0
            );

        result.noDataFound =
            true;

        result.noDataMessage =
            parsed == null
                ? null
                : firstStringValue(
                    parsed,
                    new List<String>{
                        'noDataMessage',
                        'message',
                        'userMessage',
                        'clarificationQuestion'
                    }
                );

        String reason =
            parsed == null
                ? null
                : firstStringValue(
                    parsed,
                    new List<String>{
                        'reasoning',
                        'reason'
                    }
                );

        result.reasoning =
            String.isBlank(
                reason
            )
                ? defaultReason
                : reason;

        return result;
    }

    private static void mergeFirstNestedCommand(
        Map<String, Object> parsed
    ) {
        Object nestedValue =
            firstPresentValue(
                parsed,
                new List<String>{
                    'answers',
                    'fields',
                    'fieldUpdates',
                    'updates',
                    'results',
                    'filledFields'
                }
            );

        if (nestedValue instanceof List<Object>) {
            List<Object> nestedList =
                (List<Object>) nestedValue;

            if (
                !nestedList.isEmpty() &&
                nestedList[0] instanceof Map<String, Object>
            ) {
                Map<String, Object> nestedCommand =
                    (Map<String, Object>) nestedList[0];

                for (String key : nestedCommand.keySet()) {
                    if (
                        !parsed.containsKey(key) ||
                        parsed.get(key) == null
                    ) {
                        parsed.put(
                            key,
                            nestedCommand.get(key)
                        );
                    }
                }
            }
        }
    }

    private static Object firstPresentValue(
        Map<String, Object> values,
        List<String> keys
    ) {
        if (values == null) {
            return null;
        }

        for (String key : keys) {
            if (
                values.containsKey(key) &&
                values.get(key) != null
            ) {
                return values.get(key);
            }
        }

        return null;
    }

    private static void addSourceField(

        List<String> sourceFields,

        String sourceField

    ) {

        if (

            String.isBlank(
                sourceField
            )

        ) {

            return;

        }

        String cleanedSourceField =
            sourceField.trim();

        if (

            !sourceFields.contains(
                cleanedSourceField
            )

        ) {

            sourceFields.add(
                cleanedSourceField
            );

        }

    }

    private static Decimal toDecimal(

        Object rawValue,

        Decimal defaultValue

    ) {

        if (

            rawValue == null

        ) {

            return defaultValue;

        }

        try {

            return Decimal.valueOf(
                String.valueOf(
                    rawValue
                )
            );

        }

        catch (Exception e) {

            return defaultValue;

        }

    }

    private static Boolean toBoolean(

        Object rawValue,

        Boolean defaultValue

    ) {

        if (

            rawValue == null

        ) {

            return defaultValue;

        }

        if (

            rawValue instanceof Boolean

        ) {

            return (Boolean) rawValue;

        }

        String normalizedValue =
            String.valueOf(
                rawValue
            )
                .trim()
                .toLowerCase();

        if (

            normalizedValue == 'true'

        ) {

            return true;

        }

        if (

            normalizedValue == 'false'

        ) {

            return false;

        }

        return defaultValue;

    }

}
