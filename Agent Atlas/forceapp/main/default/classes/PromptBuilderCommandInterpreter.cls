public without sharing class PromptBuilderCommandInterpreter {

    private static final String PROMPT_TEMPLATE_API_NAME =
        'AI_Form_Chat_Command_Interpreter';

    @AuraEnabled
    public static Map<String, Object> interpretCommand(
        String command,
        String fieldContextJson,
        String existingValuesJson,
        String applicantKnowledge
    ) {
        Map<String, Object> response =
            new Map<String, Object>{
                'handled' => false,
                'enabled' => true
            };

        if (String.isBlank(command)) {
            response.put(
                'reason',
                'Blank command.'
            );
            return response;
        }

        try {
            if (String.isBlank(applicantKnowledge)) {
                applicantKnowledge =
                    loadApplicantKnowledge();
            }

            String promptResponse =
                invokePromptTemplate(
                    command,
                    fieldContextJson,
                    existingValuesJson,
                    applicantKnowledge
                );

            response.put(
                'promptResponse',
                promptResponse
            );

            Map<String, Object> parsed =
                parseJsonObject(
                    promptResponse
                );

            if (parsed == null || parsed.isEmpty()) {
                response.put(
                    'reason',
                    'Prompt Builder did not return structured command JSON.'
                );
                return response;
            }

            normalizeParsedCommand(
                parsed
            );

            String action =
                valueAsString(
                    parsed.get('action')
                );

            if (String.isBlank(action)) {
                response.put(
                    'reason',
                    'Prompt Builder response did not include an action.'
                );
                return response;
            }

            response.putAll(
                parsed
            );

            response.put(
                'handled',
                true
            );

            return response;
        }

        catch (Exception e) {
            response.put(
                'reason',
                e.getTypeName() +
                ': ' +
                e.getMessage()
            );
            response.put(
                'stackTrace',
                e.getStackTraceString()
            );
            return response;
        }
    }

    private static String loadApplicantKnowledge() {
        try {
            UserDataDiscoveryService.DiscoveryContext context =
                UserDataDiscoveryService.loadDiscoveryContext(
                    UserInfo.getUserId()
                );

            return buildApplicantKnowledgeInput(
                context
            );
        }

        catch (Exception e) {
            return '';
        }
    }

    private static String buildApplicantKnowledgeInput(
        UserDataDiscoveryService.DiscoveryContext context
    ) {
        if (context == null) {
            return '';
        }

        Map<String, Object> sourceData =
            new Map<String, Object>{
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
                        }
            };

        return JSON.serialize(
            sourceData
        );
    }

    private static String invokePromptTemplate(
        String command,
        String fieldContextJson,
        String existingValuesJson,
        String applicantKnowledge
    ) {
        Map<String, ConnectApi.WrappedValue> inputParams =
            new Map<String, ConnectApi.WrappedValue>();

        putInputParam(
            inputParams,
            'Input:userMessage',
            command
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

    private static void normalizeParsedCommand(
        Map<String, Object> parsed
    ) {
        mergeFirstNestedCommand(
            parsed
        );

        String action =
            valueAsString(
                parsed.get('action')
            );

        if (!String.isBlank(action)) {
            String normalizedAction =
                action.toLowerCase().trim();

            if (normalizedAction == 'fill_field') {
                parsed.put(
                    'action',
                    'fill'
                );
            } else if (normalizedAction == 'replace_field') {
                parsed.put(
                    'action',
                    'replace'
                );
            } else if (normalizedAction == 'clear_field') {
                parsed.put(
                    'action',
                    'clear'
                );
            } else {
                parsed.put(
                    'action',
                    normalizedAction
                );
            }
        }

        if (
            !parsed.containsKey('fieldLabel')
        ) {
            Object fieldLabel =
                firstPresentValue(
                    parsed,
                    new List<String>{
                        'targetLabel',
                        'targetFieldLabel',
                        'fieldName',
                        'field',
                        'label',
                        'questionLabel',
                        'targetField'
                    }
                );

            if (fieldLabel != null) {
                parsed.put(
                    'fieldLabel',
                    fieldLabel
                );
            }
        }

        if (
            !parsed.containsKey('questionId')
        ) {
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

        if (
            !parsed.containsKey('newValue')
        ) {
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

        if (
            nestedValue instanceof List<Object>
        ) {
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

    private static String valueAsString(
        Object value
    ) {
        return value == null
            ? null
            : String.valueOf(value);
    }
}
