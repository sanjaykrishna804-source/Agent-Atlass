public without sharing class AIFormFillerController {

    public class AgentFillRequest {
        @InvocableVariable(
            label='Command'
            description='Optional user command, such as fill all fields or fill missing fields.'
        )
        public String command;
    }

    public class AgentFillResponse {
        @InvocableVariable(
            label='Result JSON'
            description='JSON response from the existing AI form fill controller.'
        )
        public String resultJson;
    }

    @InvocableMethod(
        label='Fill Form Fields With AI'
        description='Runs the existing AI form autofill flow and returns the filled field results as JSON.'
    )
    public static List<AgentFillResponse>
    fillFormFieldsForAgent(
        List<AgentFillRequest> requests
    ) {
        List<AgentFillResponse> responses =
            new List<AgentFillResponse>();

        Integer requestCount =
            requests == null || requests.isEmpty()
                ? 1
                : requests.size();

        for (
            Integer i = 0;
            i < requestCount;
            i++
        ) {
            AgentFillResponse response =
                new AgentFillResponse();

            response.resultJson =
                JSON.serialize(
                    fillFormWithAI(null)
                );

            responses.add(
                response
            );
        }

        return responses;
    }

    @AuraEnabled
    public static Map<String, Object>
    fillFormWithAI(Id targetApplicationId) {

        try {

        Long operationStartMs =
            DateTime.now().getTime();

        /*
         * FINAL RESPONSE
         */

        Map<String, Object> response =
            new Map<String, Object>();

        /*
         * FILLED FIELDS
         */

        Map<String, Object> filledFields =
            new Map<String, Object>();

        Map<String, Object> fieldMessages =
            new Map<String, Object>();

        List<AIFormFillLogger.Entry> logEntries =
            new List<AIFormFillLogger.Entry>();

        /*
         * QUESTION LIST
         */

        List<UserDataDiscoveryService.FormQuestion>
            questions =
                new List<UserDataDiscoveryService.FormQuestion>();

        Boolean hasAdminReviewMetadata =
            false;

        /*
         * LOAD QUESTIONS FROM METADATA
         */

        for (

            Form_Configuration_c__mdt q :

            [

                SELECT
                    Question_Id__c,
                    MasterLabel,
                    Question_Type__c,
                    Picklist_Values__c,
                    Display_Order__c

                FROM Form_Configuration_c__mdt

                ORDER BY Display_Order__c ASC

            ]

        ) {

            if (

                String.isBlank(
                    q.Question_Id__c
                )

            ) {

                System.debug(
                    'Skipping form configuration with blank Question_Id__c: ' +
                    q.MasterLabel
                );

                continue;

            }

            UserDataDiscoveryService.FormQuestion question =
                new UserDataDiscoveryService.FormQuestion();

            question.questionId =
                q.Question_Id__c;

            question.questionText =
                q.MasterLabel;

            question.questionType =
                q.Question_Type__c;

            question.picklistValues =
                q.Picklist_Values__c;

            questions.add(question);

            if (
                isAdminReviewQuestion(
                    q.Question_Id__c
                )
            ) {

                hasAdminReviewMetadata =
                    true;

            }

        }

        if (

            targetApplicationId != null &&
            canUseAdminApplicationContext() &&
            !hasAdminReviewMetadata

        ) {

            questions.addAll(
                buildAdminReviewQuestions()
            );

        }

        /*
         * RUN EINSTEIN PROMPT BUILDER SEMANTIC EXTRACTION FIRST
         */

        Map<String, UserDataDiscoveryService.DataDiscoveryResult>
            einsteinPromptResults =
                new Map<String, UserDataDiscoveryService.DataDiscoveryResult>();

        try {

            einsteinPromptResults =
                EinsteinPromptExtractionService.extractAnswers(
                    UserInfo.getUserId(),
                    questions,
                    targetApplicationId
                );

        }

        catch (Exception e) {

            System.debug(
                LoggingLevel.WARN,
                'Einstein Prompt Builder extraction skipped: ' +
                e.getMessage()
            );

        }

        Map<String, UserDataDiscoveryService.DataDiscoveryResult>
            discoveryResults =
                new Map<String, UserDataDiscoveryService.DataDiscoveryResult>(
                    einsteinPromptResults
                );

        /*
         * RUN CLASS-BASED DISCOVERY ONLY AS FALLBACK
         */

        Map<String, UserDataDiscoveryService.DataDiscoveryResult>
            userDiscoveryResults =
                UserDataDiscoveryService.discoverDataForForm(
                    UserInfo.getUserId(),
                    questions,
                    targetApplicationId
                );

        for (

            String questionId
            : userDiscoveryResults.keySet()

        ) {

            UserDataDiscoveryService.DataDiscoveryResult existingResult =
                discoveryResults.get(
                    questionId
                );

            Boolean existingHasValue =
                existingResult != null &&

                (

                    !String.isBlank(
                        existingResult.recommendedValue
                    ) ||

                    existingResult.clearValue == true ||

                    existingResult.noDataFound == true

                );

            if (

                !existingHasValue

            ) {

                discoveryResults.put(
                    questionId,
                    userDiscoveryResults.get(
                        questionId
                    )
                );

            }

            else {

                applyFallbackMergedSourceMetadata(
                    existingResult,
                    userDiscoveryResults.get(
                        questionId
                    )
                );

            }

        }

        applyApplicantKnowledgeChoiceCorrections(
            discoveryResults,
            questions,
            UserInfo.getUserId()
        );

        Decimal totalConfidence = 0;

        Integer confidenceCount = 0;

        Integer unfillableFields = 0;

        /*
         * BUILD RESPONSE
         */

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

            String questionId =
                question.questionId;

            UserDataDiscoveryService.DataDiscoveryResult result =
                discoveryResults.get(questionId);

            if (

                result != null &&

                (

                    !String.isBlank(
                        result.recommendedValue
                    ) ||

                    result.clearValue == true

                )

            ) {

                filledFields.put(

                    questionId,

                    new Map<String, Object>{

                        'value' =>
                            result.clearValue == true
                                ? ''
                                : result.recommendedValue,

                        'confidence' =>
                            result.bestMatchConfidence,

                        'reasoning' =>
                            result.reasoning,

                        'isMergedAnswer' =>
                            result.isMergedAnswer,

                        'sourceFields' =>
                            result.sourceFields,

                        'sourceUpdatedAt' =>
                            result.sourceUpdatedAt,

                        'selectionType' =>
                            result.selectionType,

                        'alternativeOptions' =>
                            result.alternativeOptions == null
                                ? new List<String>()
                                : result.alternativeOptions

                    }

                );

                AIFormFillLogger.Entry logEntry =
                    buildFillLogEntry(
                        question,
                        result,
                        determineSelectedSource(
                            questionId,
                            result,
                            einsteinPromptResults,
                            userDiscoveryResults
                        ),
                        'Success',
                        operationStartMs
                    );

                logEntries.add(
                    logEntry
                );

                if (

                    result.bestMatchConfidence
                        != null

                ) {

                    totalConfidence +=
                        result.bestMatchConfidence;

                    confidenceCount++;

                }

            }

            else {

                if (

                    shouldShowNoDataMessage(
                        question,
                        result
                    )

                ) {

                    UserDataDiscoveryService.DataDiscoveryResult
                        noDataResult =
                            result == null
                                ? buildEmptyNoDataResult()
                                : result;

                    noDataResult.noDataFound =
                        true;

                    String noDataMessage =
                        buildNoDataMessage(
                            question,
                            noDataResult
                        );

                    if (

                        !String.isBlank(
                            noDataMessage
                        )

                    ) {

                        fieldMessages.put(
                            questionId,
                            noDataMessage
                        );

                        unfillableFields++;

                        AIFormFillLogger.Entry logEntry =
                            buildNoDataLogEntry(
                                question,
                                noDataResult,
                                noDataMessage,
                                operationStartMs
                            );

                        logEntries.add(
                            logEntry
                        );

                        System.debug(
                            LoggingLevel.INFO,
                            'AI_NO_DATA -> QUESTION: ' +
                            question.questionText +
                            ' | MESSAGE: ' +
                            noDataMessage
                        );

                    }

                }

            }

        }

        /*
         * OVERALL CONFIDENCE
         */

        Decimal overallConfidence = 0;

        if (confidenceCount > 0) {

            overallConfidence =
                totalConfidence /
                confidenceCount;

        }

        /*
         * FINAL PAYLOAD
         */

        AIFormFillLogger.logAll(
            logEntries
        );

        response.put(
            'filledFields',
            filledFields
        );

        response.put(
            'fieldMessages',
            fieldMessages
        );

        response.put(
            'aiComparisonResults',
            buildAiComparisonResults(
                questions,
                userDiscoveryResults,
                einsteinPromptResults,
                discoveryResults
            )
        );

        response.put(
            'overallConfidence',
            overallConfidence
        );

        response.put(
            'hasWarnings',
            !fieldMessages.isEmpty()
        );

        response.put(
            'unfillableFields',
            unfillableFields
        );

        response.put(
            'clarificationsNeeded',
            0
        );

        return response;

        }

        catch (Exception e) {

            System.debug(
                LoggingLevel.ERROR,
                'AIFormFillerController.fillFormWithAI failed: ' +
                e.getMessage() +
                '\n' +
                e.getStackTraceString()
            );

            throw new AuraHandledException(
                'AI form fill failed: ' +
                e.getMessage()
            );

        }

    }

    @AuraEnabled
    public static Map<String, Object>
    fillSingleFieldWithAI(

        String questionId,

        String questionLabel,

        String questionType,

        String picklistValues,

        Id targetApplicationId

    ) {

        try {

            Long operationStartMs =
                DateTime.now().getTime();

            Map<String, Object> response =
                new Map<String, Object>();

            Map<String, Object> filledFields =
                new Map<String, Object>();

            Map<String, Object> fieldMessages =
                new Map<String, Object>();

            List<UserDataDiscoveryService.FormQuestion> questions =
                new List<UserDataDiscoveryService.FormQuestion>();

            UserDataDiscoveryService.FormQuestion question =
                new UserDataDiscoveryService.FormQuestion();

            question.questionId =
                questionId;

            question.questionText =
                questionLabel;

            question.questionType =
                questionType;

            question.picklistValues =
                picklistValues;

            questions.add(
                question
            );

            Map<String, UserDataDiscoveryService.DataDiscoveryResult>
                einsteinPromptResults =
                    new Map<String, UserDataDiscoveryService.DataDiscoveryResult>();

            try {

                einsteinPromptResults =
                    EinsteinPromptExtractionService.extractAnswers(
                        UserInfo.getUserId(),
                        questions,
                        targetApplicationId
                    );

            }

            catch (Exception e) {

                System.debug(
                    LoggingLevel.WARN,
                    'Einstein Prompt Builder single-field extraction skipped: ' +
                    e.getMessage()
                );

            }

            Map<String, UserDataDiscoveryService.DataDiscoveryResult>
                userDiscoveryResults =
                    UserDataDiscoveryService.discoverDataForForm(
                        UserInfo.getUserId(),
                        questions,
                        targetApplicationId
                    );

            Map<String, UserDataDiscoveryService.DataDiscoveryResult>
                discoveryResults =
                    new Map<String, UserDataDiscoveryService.DataDiscoveryResult>();

            UserDataDiscoveryService.DataDiscoveryResult promptResult =
                einsteinPromptResults.get(
                    questionId
                );

            UserDataDiscoveryService.DataDiscoveryResult fallbackResult =
                userDiscoveryResults.get(
                    questionId
                );

            Boolean promptHasValue =
                promptResult != null &&
                (
                    !String.isBlank(
                        promptResult.recommendedValue
                    ) ||
                    promptResult.clearValue == true ||
                    promptResult.noDataFound == true
                );

            if (
                promptHasValue
            ) {

                discoveryResults.put(
                    questionId,
                    promptResult
                );

                applyFallbackMergedSourceMetadata(
                    promptResult,
                    fallbackResult
                );

            }

            else if (
                fallbackResult != null
            ) {

                discoveryResults.put(
                    questionId,
                    fallbackResult
                );

            }

            applyApplicantKnowledgeChoiceCorrections(
                discoveryResults,
                questions,
                UserInfo.getUserId()
            );

            UserDataDiscoveryService.DataDiscoveryResult result =
                discoveryResults.get(
                    questionId
                );

            Decimal overallConfidence =
                0;

            Integer unfillableFields =
                0;

            if (

                result != null &&
                (
                    !String.isBlank(
                        result.recommendedValue
                    ) ||
                    result.clearValue == true
                )

            ) {

                filledFields.put(
                    questionId,
                    buildFieldPayload(
                        result
                    )
                );

                if (
                    result.bestMatchConfidence != null
                ) {

                    overallConfidence =
                        result.bestMatchConfidence;

                }

            }

            else if (
                shouldShowNoDataMessage(
                    question,
                    result
                )
            ) {

                UserDataDiscoveryService.DataDiscoveryResult noDataResult =
                    result == null
                        ? buildEmptyNoDataResult()
                        : result;

                noDataResult.noDataFound =
                    true;

                String noDataMessage =
                    buildNoDataMessage(
                        question,
                        noDataResult
                    );

                if (
                    !String.isBlank(
                        noDataMessage
                    )
                ) {

                    fieldMessages.put(
                        questionId,
                        noDataMessage
                    );

                    unfillableFields =
                        1;

                    System.debug(
                        LoggingLevel.INFO,
                        'AI_NO_DATA_SINGLE -> QUESTION: ' +
                        question.questionText +
                        ' | MESSAGE: ' +
                        noDataMessage +
                        ' | DURATION_MS: ' +
                        elapsedMs(
                            operationStartMs
                        )
                    );

                }

            }

            response.put(
                'filledFields',
                filledFields
            );

            response.put(
                'fieldMessages',
                fieldMessages
            );

            response.put(
                'aiComparisonResults',
                buildAiComparisonResults(
                    questions,
                    userDiscoveryResults,
                    einsteinPromptResults,
                    discoveryResults
                )
            );

            response.put(
                'overallConfidence',
                overallConfidence
            );

            response.put(
                'hasWarnings',
                !fieldMessages.isEmpty()
            );

            response.put(
                'unfillableFields',
                unfillableFields
            );

            response.put(
                'clarificationsNeeded',
                0
            );

            return response;

        }

        catch (Exception e) {

            System.debug(
                LoggingLevel.ERROR,
                'AIFormFillerController.fillSingleFieldWithAI failed: ' +
                e.getMessage() +
                '\n' +
                e.getStackTraceString()
            );

            throw new AuraHandledException(
                'AI single field fill failed: ' +
                e.getMessage()
            );

        }

    }

    private static Map<String, Object> buildFieldPayload(

        UserDataDiscoveryService.DataDiscoveryResult result

    ) {

        if (
            result == null
        ) {

            return new Map<String, Object>{
                'value' => null,
                'confidence' => null,
                'reasoning' => null,
                'isMergedAnswer' => false,
                'sourceFields' => new List<String>(),
                'sourceUpdatedAt' => null,
                'selectionType' => null,
                'alternativeOptions' => new List<String>(),
                'noDataFound' => false,
                'noDataMessage' => null
            };

        }

        return new Map<String, Object>{
            'value' =>
                result.clearValue == true
                    ? ''
                    : result.recommendedValue,
            'confidence' =>
                result.bestMatchConfidence,
            'reasoning' =>
                result.reasoning,
            'isMergedAnswer' =>
                result.isMergedAnswer,
            'sourceFields' =>
                result.sourceFields == null
                    ? new List<String>()
                    : result.sourceFields,
            'sourceUpdatedAt' =>
                result.sourceUpdatedAt,
            'selectionType' =>
                result.selectionType,
            'alternativeOptions' =>
                result.alternativeOptions == null
                    ? new List<String>()
                    : result.alternativeOptions,
            'noDataFound' =>
                result.noDataFound,
            'noDataMessage' =>
                result.noDataMessage
        };

    }

    private static AIFormFillLogger.Entry buildFillLogEntry(

        UserDataDiscoveryService.FormQuestion question,

        UserDataDiscoveryService.DataDiscoveryResult result,

        String selectedSource,

        String status,

        Long operationStartMs

    ) {

        AIFormFillLogger.Entry entry =
            new AIFormFillLogger.Entry();

        entry.action =
            'fill';

        entry.status =
            status;

        entry.questionId =
            question == null
                ? null
                : question.questionId;

        entry.questionLabel =
            question == null
                ? null
                : question.questionText;

        entry.source =
            selectedSource;

        entry.confidence =
            result == null
                ? null
                : result.bestMatchConfidence;

        entry.reason =
            result == null
                ? null
                : buildAuditReason(
                    result
                );

        entry.value =
            result == null ||
            result.clearValue == true
                ? ''
                : result.recommendedValue;

        entry.durationMs =
            elapsedMs(
                operationStartMs
            );

        return entry;

    }

    private static AIFormFillLogger.Entry buildNoDataLogEntry(

        UserDataDiscoveryService.FormQuestion question,

        UserDataDiscoveryService.DataDiscoveryResult result,

        String noDataMessage,

        Long operationStartMs

    ) {

        AIFormFillLogger.Entry entry =
            new AIFormFillLogger.Entry();

        entry.action =
            'no_data';

        entry.status =
            'No Data';

        entry.questionId =
            question == null
                ? null
                : question.questionId;

        entry.questionLabel =
            question == null
                ? null
                : question.questionText;

        entry.source =
            result == null ||
            result.sourceFields == null ||
            result.sourceFields.isEmpty()
                ? 'No source'
                : String.join(
                    result.sourceFields,
                    ', '
                );

        entry.confidence =
            result == null
                ? null
                : result.bestMatchConfidence;

        entry.reason =
            String.isBlank(noDataMessage)
                ? 'No matching saved data was found.'
                : noDataMessage;

        entry.value =
            null;

        entry.durationMs =
            elapsedMs(
                operationStartMs
            );

        return entry;

    }

    private static String determineSelectedSource(

        String questionId,

        UserDataDiscoveryService.DataDiscoveryResult selectedResult,

        Map<String, UserDataDiscoveryService.DataDiscoveryResult>
            einsteinPromptResults,

        Map<String, UserDataDiscoveryService.DataDiscoveryResult>
            userDiscoveryResults

    ) {

        UserDataDiscoveryService.DataDiscoveryResult promptResult =
            einsteinPromptResults == null
                ? null
                : einsteinPromptResults.get(questionId);

        if (
            hasSameSelectedValue(
                selectedResult,
                promptResult
            )
        ) {
            return 'Prompt Builder';
        }

        UserDataDiscoveryService.DataDiscoveryResult fallbackResult =
            userDiscoveryResults == null
                ? null
                : userDiscoveryResults.get(questionId);

        if (
            hasSameSelectedValue(
                selectedResult,
                fallbackResult
            )
        ) {
            return 'UserDataDiscoveryService';
        }

        return 'AIFormFillerController';

    }

    private static Boolean hasSameSelectedValue(

        UserDataDiscoveryService.DataDiscoveryResult selectedResult,

        UserDataDiscoveryService.DataDiscoveryResult candidateResult

    ) {

        if (
            selectedResult == null ||
            candidateResult == null
        ) {
            return false;
        }

        String selectedValue =
            selectedResult.clearValue == true
                ? ''
                : selectedResult.recommendedValue;

        String candidateValue =
            candidateResult.clearValue == true
                ? ''
                : candidateResult.recommendedValue;

        return selectedValue == candidateValue;

    }

    private static String buildLogReason(

        String reasoning,

        List<String> sourceFields

    ) {

        List<String> parts =
            new List<String>();

        if (
            !String.isBlank(reasoning)
        ) {
            parts.add(
                reasoning
            );
        }

        if (
            sourceFields != null &&
            !sourceFields.isEmpty()
        ) {
            parts.add(
                'Source fields: ' +
                String.join(
                    sourceFields,
                    ', '
                )
            );
        }

        return parts.isEmpty()
            ? null
            : String.join(
                parts,
                '\n'
            );

    }

    private static String buildAuditReason(

        UserDataDiscoveryService.DataDiscoveryResult result

    ) {

        if (

            result == null

        ) {

            return null;

        }

        List<String> parts =
            new List<String>();

        String baseReason =
            buildLogReason(
                result.reasoning,
                result.sourceFields
            );

        if (

            !String.isBlank(
                baseReason
            )

        ) {

            parts.add(
                baseReason
            );

        }

        if (

            !String.isBlank(
                result.selectionType
            )

        ) {

            parts.add(
                'Selection type: ' +
                result.selectionType
            );

        }

        if (

            !String.isBlank(
                result.sourceUpdatedAt
            )

        ) {

            parts.add(
                'Source data timestamp: ' +
                result.sourceUpdatedAt
            );

        }

        if (

            result.alternativeOptions != null &&
            !result.alternativeOptions.isEmpty()

        ) {

            parts.add(
                'Alternatives considered: ' +
                String.join(
                    result.alternativeOptions,
                    '; '
                )
            );

        }

        return parts.isEmpty()
            ? null
            : String.join(
                parts,
                '\n'
            );

    }

    private static Long elapsedMs(

        Long operationStartMs

    ) {

        if (
            operationStartMs == null
        ) {
            return null;
        }

        return DateTime.now().getTime() -
            operationStartMs;

    }

    private static Map<String, Object> buildAiComparisonResults(

        List<UserDataDiscoveryService.FormQuestion> questions,

        Map<String, UserDataDiscoveryService.DataDiscoveryResult>
            userDiscoveryResults,

        Map<String, UserDataDiscoveryService.DataDiscoveryResult>
            einsteinPromptResults,

        Map<String, UserDataDiscoveryService.DataDiscoveryResult>
            finalResults

    ) {

        Map<String, Object> comparison =
            new Map<String, Object>();

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

            String questionId =
                question.questionId;

            Map<String, Object> row =
                new Map<String, Object>{
                    'label' =>
                        question.questionText,
                    'userDiscovery' =>
                        summarizeProviderResult(
                            userDiscoveryResults.get(
                                questionId
                            )
                        ),
                    'einsteinPromptBuilder' =>
                        summarizeProviderResult(
                            einsteinPromptResults.get(
                                questionId
                            )
                        ),
                    'selected' =>
                        summarizeProviderResult(
                            finalResults.get(
                                questionId
                            )
                        )
                };

            comparison.put(
                questionId,
                row
            );

            System.debug(
                LoggingLevel.INFO,
                'AI_COMPARE -> QUESTION: ' +
                question.questionText +
                ' | USERDISCOVERY: ' +
                summarizeValue(
                    userDiscoveryResults.get(
                        questionId
                    )
                ) +
                ' | EINSTEIN: ' +
                summarizeValue(
                    einsteinPromptResults.get(
                        questionId
                    )
                ) +
                ' | SELECTED: ' +
                summarizeValue(
                    finalResults.get(
                        questionId
                    )
                )
            );

        }

        return comparison;

    }

    private static Boolean isAdminReviewQuestion(

        String questionId

    ) {

        return !String.isBlank(
            questionId
        ) &&
            questionId
                .toLowerCase()
                .startsWith(
                    'admin_'
                );

    }

    private static Boolean canUseAdminApplicationContext() {

        return Schema.sObjectType.Academic_Application__c.isAccessible() &&
            Schema.sObjectType.Academic_Application__c.fields.Applicant__c.isAccessible() &&
            Schema.sObjectType.Academic_Application__c.fields.Decision_Status__c.isAccessible() &&
            Schema.sObjectType.Academic_Application__c.fields.Admin_Review_Comments__c.isAccessible();

    }

    private static List<UserDataDiscoveryService.FormQuestion>
        buildAdminReviewQuestions() {

        List<UserDataDiscoveryService.FormQuestion> questions =
            new List<UserDataDiscoveryService.FormQuestion>();

        questions.add(
            buildAdminReviewQuestion(
                'admin_decision_status',
                'Decision Status',
                'picklist',
                'Pending Review,Approved,Rejected,Waitlisted'
            )
        );

        questions.add(
            buildAdminReviewQuestion(
                'admin_admission_granted',
                'Admission Granted',
                'checkbox',
                null
            )
        );

        questions.add(
            buildAdminReviewQuestion(
                'admin_review_comments',
                'Admin Review Comments',
                'textarea',
                null
            )
        );

        questions.add(
            buildAdminReviewQuestion(
                'admin_approval_comments',
                'Approval Decision Comments',
                'textarea',
                null
            )
        );

        questions.add(
            buildAdminReviewQuestion(
                'admin_rejection_comments',
                'Rejection Comments',
                'textarea',
                null
            )
        );

        questions.add(
            buildAdminReviewQuestion(
                'admin_reviewer_notes',
                'Reviewer Notes',
                'textarea',
                null
            )
        );

        questions.add(
            buildAdminReviewQuestion(
                'admin_decision_date',
                'Decision Date',
                'date',
                null
            )
        );

        return questions;

    }

    private static UserDataDiscoveryService.FormQuestion
        buildAdminReviewQuestion(
            String questionId,
            String questionText,
            String questionType,
            String picklistValues
        ) {

        UserDataDiscoveryService.FormQuestion question =
            new UserDataDiscoveryService.FormQuestion();

        question.questionId =
            questionId;
        question.questionText =
            questionText;
        question.questionType =
            questionType;
        question.picklistValues =
            picklistValues;
        question.pageNumber =
            6;

        return question;

    }

    private static Map<String, Object> summarizeProviderResult(

        UserDataDiscoveryService.DataDiscoveryResult result

    ) {

        if (

            result == null

        ) {

            return new Map<String, Object>{
                'value' => null,
                'confidence' => null,
                'reasoning' => null,
                'isMergedAnswer' => false,
                'sourceFields' => new List<String>(),
                'sourceUpdatedAt' => null,
                'selectionType' => null,
                'alternativeOptions' => new List<String>(),
                'noDataFound' => false,
                'noDataMessage' => null
            };

        }

        return new Map<String, Object>{
            'value' =>
                result.clearValue == true
                    ? ''
                    : result.recommendedValue,
            'confidence' =>
                result.bestMatchConfidence,
            'reasoning' =>
                result.reasoning,
            'isMergedAnswer' =>
                result.isMergedAnswer,
            'sourceFields' =>
                result.sourceFields == null
                    ? new List<String>()
                    : result.sourceFields,
            'sourceUpdatedAt' =>
                result.sourceUpdatedAt,
            'selectionType' =>
                result.selectionType,
            'alternativeOptions' =>
                result.alternativeOptions == null
                    ? new List<String>()
                    : result.alternativeOptions,
            'noDataFound' =>
                result.noDataFound,
            'noDataMessage' =>
                result.noDataMessage
        };

    }

    private static String buildNoDataMessage(

        UserDataDiscoveryService.FormQuestion question,

        UserDataDiscoveryService.DataDiscoveryResult result

    ) {

        if (

            result != null &&
            result.noDataFound == true &&
            !String.isBlank(
                result.noDataMessage
            )

        ) {

            return result.noDataMessage;

        }

        String label =
            question == null ||
            String.isBlank(
                question.questionText
            )
                ? 'this field'
                : question.questionText;

        String sourceLocation =
            suggestMissingDataLocation(
                question
            );

        return 'No saved data found for ' +
            label +
            '. Please enter it manually. You can add it under ' +
            sourceLocation +
            ' in Salesforce for future use.';

    }

    private static Boolean shouldShowNoDataMessage(

        UserDataDiscoveryService.FormQuestion question,

        UserDataDiscoveryService.DataDiscoveryResult result

    ) {

        if (

            question == null ||
            isCheckboxQuestion(
                question
            )

        ) {

            return false;

        }

        return result == null ||
            result.noDataFound == true;

    }

    private static Boolean isCheckboxQuestion(

        UserDataDiscoveryService.FormQuestion question

    ) {

        String questionType =
            normalize(
                question == null
                    ? ''
                    : question.questionType
            );

        return questionType.contains(
            'checkbox'
        ) ||
            questionType.contains(
                'check box'
            ) ||
            questionType == 'boolean';

    }

    private static UserDataDiscoveryService.DataDiscoveryResult
        buildEmptyNoDataResult() {

        UserDataDiscoveryService.DataDiscoveryResult result =
            new UserDataDiscoveryService.DataDiscoveryResult();

        result.noDataFound =
            true;

        result.noDataMessage =
            null;

        result.bestMatchConfidence =
            0;

        result.sourceFields =
            new List<String>();

        return result;

    }

    private static String suggestMissingDataLocation(

        UserDataDiscoveryService.FormQuestion question

    ) {

        String fingerprint =
            normalize(
                (question == null ? '' : question.questionText) +
                ' ' +
                (question == null ? '' : question.questionType)
            );

        if (

            fingerprint.contains(
                'email'
            ) ||
            fingerprint.contains(
                'phone'
            ) ||
            fingerprint.contains(
                'mobile'
            ) ||
            fingerprint.contains(
                'address'
            ) ||
            fingerprint.contains(
                'birth'
            ) ||
            fingerprint.contains(
                'gender'
            ) ||
            fingerprint.contains(
                'citizen'
            ) ||
            fingerprint.contains(
                'contact'
            )

        ) {

            return 'Contact Info';

        }

        if (

            fingerprint.contains(
                'name'
            ) ||
            fingerprint.contains(
                'profile'
            ) ||
            fingerprint.contains(
                'user'
            )

        ) {

            return 'your profile';

        }

        if (

            fingerprint.contains(
                'program'
            ) ||
            fingerprint.contains(
                'education'
            ) ||
            fingerprint.contains(
                'institution'
            ) ||
            fingerprint.contains(
                'degree'
            ) ||
            fingerprint.contains(
                'term'
            )

        ) {

            return 'the related application or education record';

        }

        return 'Applicant Knowledge or the related Salesforce record';

    }

    private static void applyFallbackMergedSourceMetadata(

        UserDataDiscoveryService.DataDiscoveryResult existingResult,

        UserDataDiscoveryService.DataDiscoveryResult fallbackResult

    ) {

        if (

            existingResult == null ||
            fallbackResult == null

        ) {

            return;

        }

        if (

            String.isBlank(
                existingResult.sourceUpdatedAt
            )

        ) {

            existingResult.sourceUpdatedAt =
                fallbackResult.sourceUpdatedAt;

        }

        if (

            String.isBlank(
                existingResult.selectionType
            )

        ) {

            existingResult.selectionType =
                fallbackResult.selectionType;

        }

        if (

            (
                existingResult.alternativeOptions == null ||
                existingResult.alternativeOptions.isEmpty()
            ) &&
            fallbackResult.alternativeOptions != null

        ) {

            existingResult.alternativeOptions =
                new List<String>(
                    fallbackResult.alternativeOptions
                );

        }

        if (

            (
                existingResult.sourceFields == null ||
                existingResult.sourceFields.isEmpty()
            ) &&
            fallbackResult.sourceFields != null &&
            !fallbackResult.sourceFields.isEmpty()

        ) {

            existingResult.sourceFields =
                new List<String>(
                    fallbackResult.sourceFields
                );

        }

        if (

            fallbackResult.isMergedAnswer != true ||
            fallbackResult.sourceFields == null ||
            fallbackResult.sourceFields.size() < 2

        ) {

            return;

        }

        if (

            existingResult.sourceFields != null &&
            existingResult.sourceFields.size() >= 2

        ) {

            return;

        }

        existingResult.isMergedAnswer =
            true;

        existingResult.sourceFields =
            new List<String>(
                fallbackResult.sourceFields
            );

        if (

            !String.isBlank(
                fallbackResult.reasoning
            )

        ) {

            existingResult.reasoning =
                String.isBlank(
                    existingResult.reasoning
                )
                    ? fallbackResult.reasoning
                    : existingResult.reasoning +
                        ' | Merged source metadata from fallback synthesis: ' +
                        fallbackResult.reasoning;

        }

    }

    private static String summarizeValue(

        UserDataDiscoveryService.DataDiscoveryResult result

    ) {

        if (

            result == null

        ) {

            return 'null';

        }

        return result.clearValue == true
            ? '[CLEAR]'
            : result.recommendedValue;

    }

    private static Boolean isEssayQuestion(

        UserDataDiscoveryService.FormQuestion question

    ) {

        if (

            question == null

        ) {

            return false;

        }

        String label =
            normalize(
                question.questionText
            );

        return label.contains(
            'statement of purpose'
        ) ||

        label.contains(
            'purpose statement'
        ) ||

        label.contains(
            'personal statement'
        ) ||

        label.contains(
            'personal essay'
        );

    }

    private static Boolean isMeaningfulEssayValue(

        String value

    ) {

        if (

            String.isBlank(
                value
            )

        ) {

            return false;

        }

        String normalizedValue =
            normalize(
                value
            );

        if (

            normalizedValue.length() < 80

        ) {

            return false;

        }

        Integer wordCount =
            normalizedValue.split(
                '\\s+'
            ).size();

        return wordCount >= 12;

    }

    private static void applyApplicantKnowledgeChoiceCorrections(

        Map<String, UserDataDiscoveryService.DataDiscoveryResult> results,

        List<UserDataDiscoveryService.FormQuestion> questions,

        Id userId

    ) {

        if (

            results == null ||

            questions == null ||

            questions.isEmpty()

        ) {

            return;

        }

        UserDataDiscoveryService.DiscoveryContext context =
            UserDataDiscoveryService.loadDiscoveryContext(
                userId
            );

        if (

            context == null ||

            context.con == null ||

            String.isBlank(
                UserDataDiscoveryService.getContactText(
                    context.con,
                    'Applicant_Knowledge__c'
                )
            )

        ) {

            return;

        }

        String knowledge =
            UserDataDiscoveryService.getContactText(
                context.con,
                'Applicant_Knowledge__c'
            );

        for (

            UserDataDiscoveryService.FormQuestion question
            : questions

        ) {

            if (

                question == null ||

                String.isBlank(
                    question.questionId
                ) ||

                !isChoiceQuestion(
                    question
                )

            ) {

                continue;

            }

            String correctedValue =
                extractExplicitChoiceFromKnowledge(
                    question,
                    knowledge
                );

            if (

                String.isBlank(
                    correctedValue
                )

            ) {

                continue;

            }

            UserDataDiscoveryService.DataDiscoveryResult result =
                results.containsKey(
                    question.questionId
                )
                    ? results.get(
                        question.questionId
                    )
                    : new UserDataDiscoveryService.DataDiscoveryResult();

            if (

                result == null

            ) {

                result =
                    new UserDataDiscoveryService.DataDiscoveryResult();

            }

            if (

                result.recommendedValue == correctedValue

            ) {

                System.debug(
                    LoggingLevel.INFO,
                    'AI choice correction kept existing value -> QUESTION: ' +
                    question.questionText +
                    ' | VALUE: ' +
                    correctedValue
                );

                continue;

            }

            result.questionId =
                question.questionId;

            result.recommendedValue =
                correctedValue;

            result.clearValue =
                false;

            result.bestMatchConfidence =
                0.97;

            result.reasoning =
                'Applicant knowledge explicit choice correction';

            if (

                result.sourceFields == null

            ) {

                result.sourceFields =
                    new List<String>();

            }

            result.sourceFields.add(
                'Applicant_Knowledge__c explicit choice'
            );

            System.debug(
                LoggingLevel.INFO,
                'AI choice correction replaced value -> QUESTION: ' +
                question.questionText +
                ' | VALUE: ' +
                correctedValue
            );

            results.put(
                question.questionId,
                result
            );

        }

    }

    private static String extractExplicitChoiceFromKnowledge(

        UserDataDiscoveryService.FormQuestion question,

        String knowledge

    ) {

        List<String> options =
            parseOptions(
                question.picklistValues
            );

        if (

            options.isEmpty() ||

            String.isBlank(
                knowledge
            ) ||

            !isAcademicChoiceLabel(
                question.questionText
            )

        ) {

            return null;

        }

        String normalizedQuestionLabel =
            normalize(
                question.questionText
            );

        if (

            normalizedQuestionLabel.contains(
                'financing'
            ) ||

            normalizedQuestionLabel.contains(
                'funding'
            ) ||

            normalizedQuestionLabel.contains(
                'tuition'
            )

        ) {

            return matchOptionFromList(
                extractFinancingChoiceFromKnowledge(
                    knowledge
                ),
                options
            );

        }

        if (

            normalizedQuestionLabel.contains(
                'enrollment'
            ) ||

            normalizedQuestionLabel.contains(
                'student status'
            ) ||

            normalizedQuestionLabel.contains(
                'study load'
            )

        ) {

            return matchOptionFromList(
                extractEnrollmentChoiceFromKnowledge(
                    knowledge
                ),
                options
            );

        }

        if (

            normalizedQuestionLabel.contains(
                'currently employed'
            ) ||

            normalizedQuestionLabel.contains(
                'employment status'
            ) ||

            normalizedQuestionLabel.contains(
                'working now'
            )

        ) {

            return matchOptionFromList(
                extractEmploymentChoiceFromKnowledge(
                    knowledge
                ),
                options
            );

        }

        if (

            !isAcademicChoiceLabel(
                question.questionText
            )

        ) {

            return null;

        }

        List<Pattern> explicitPatterns =
            new List<Pattern>{
                Pattern.compile(
                    '(?i)\\bpreferred\\s+(?:specialization|concentration|track|focus\\s+area|major|course)\\s+(?:is|as|:|=)\\s*([^.;\\n]+)'
                ),
                Pattern.compile(
                    '(?i)\\b(?:specialization|concentration|track|focus\\s+area|major|course)\\s+(?:is|as|:|=)\\s*([^.;\\n]+)'
                )
            };

        for (

            Pattern explicitPattern
            : explicitPatterns

        ) {

            Matcher matcher =
                explicitPattern.matcher(
                    knowledge
                );

            if (

                matcher.find()

            ) {

                String matchedOption =
                    matchOptionFromList(
                        matcher.group(1),
                        options
                    );

                if (

                    !String.isBlank(
                        matchedOption
                    )

                ) {

                    return matchedOption;

                }

            }

        }

        return null;

    }

    private static String extractFinancingChoiceFromKnowledge(

        String knowledge

    ) {

        String lower =
            normalize(
                knowledge
            );

        Integer fundingSignals = 0;

        if (
            lower.contains('personal fund') ||
            lower.contains('self fund') ||
            lower.contains('saving')
        ) {
            fundingSignals++;
        }

        if (
            lower.contains('family support') ||
            lower.contains('parent')
        ) {
            fundingSignals++;
        }

        if (
            lower.contains('scholarship') ||
            lower.contains('fellowship')
        ) {
            fundingSignals++;
        }

        if (
            lower.contains('student loan') ||
            lower.contains('education loan') ||
            lower.contains('loan')
        ) {
            fundingSignals++;
        }

        if (
            lower.contains('employer sponsorship') ||
            lower.contains('employer sponsor') ||
            lower.contains('company sponsorship')
        ) {
            fundingSignals++;
        }

        if (
            lower.contains('combination') ||
            lower.contains('combined') ||
            fundingSignals > 1
        ) {
            return 'Combination';
        }

        if (lower.contains('employer')) {
            return 'Employer Sponsorship';
        }

        if (lower.contains('scholarship') || lower.contains('fellowship')) {
            return 'Scholarship';
        }

        if (lower.contains('loan')) {
            return 'Student Loan';
        }

        if (lower.contains('family') || lower.contains('parent')) {
            return 'Family Support';
        }

        if (
            lower.contains('personal fund') ||
            lower.contains('self fund') ||
            lower.contains('saving')
        ) {
            return 'Personal Funds';
        }

        return null;

    }

    private static String extractEnrollmentChoiceFromKnowledge(

        String knowledge

    ) {

        String lower =
            normalize(
                knowledge
            );

        if (
            lower.contains('part time') ||
            lower.contains('part-time')
        ) {
            return 'Part-time';
        }

        if (
            lower.contains('full time') ||
            lower.contains('full-time')
        ) {
            return 'Full-time';
        }

        return null;

    }

    private static String extractEmploymentChoiceFromKnowledge(

        String knowledge

    ) {

        String lower =
            normalize(
                knowledge
            );

        if (
            lower.contains('currently employed full time') ||
            lower.contains('currently employed fulltime') ||
            lower.contains('employed full time') ||
            lower.contains('employed fulltime') ||
            lower.contains('working full time') ||
            lower.contains('working fulltime')
        ) {
            return 'Yes - Full time';
        }

        if (
            lower.contains('currently employed part time') ||
            lower.contains('currently employed parttime') ||
            lower.contains('employed part time') ||
            lower.contains('employed parttime') ||
            lower.contains('working part time') ||
            lower.contains('working parttime')
        ) {
            return 'Yes - Part time';
        }

        if (
            lower.contains('not employed') ||
            lower.contains('unemployed') ||
            lower.contains('not currently working')
        ) {
            return 'No';
        }

        if (
            lower.contains('currently employed') ||
            lower.contains('working')
        ) {
            return 'Yes - Full time';
        }

        return null;

    }

    private static Boolean isAcademicChoiceLabel(

        String label

    ) {

        String normalizedLabel =
            normalize(
                label
            );

        return normalizedLabel.contains(
            'specialization'
        ) ||

        normalizedLabel.contains(
            'concentration'
        ) ||

        normalizedLabel.contains(
            'track'
        ) ||

        normalizedLabel.contains(
            'focus area'
        ) ||

        normalizedLabel.contains(
            'major'
        ) ||

        normalizedLabel.contains(
            'course'
        ) ||

        normalizedLabel.contains(
            'area of study'
        ) ||

        normalizedLabel.contains(
            'field of study'
        ) ||

        normalizedLabel.contains(
            'subject'
        ) ||

        normalizedLabel.contains(
            'discipline'
        ) ||

        normalizedLabel.contains(
            'financing'
        ) ||

        normalizedLabel.contains(
            'funding'
        ) ||

        normalizedLabel.contains(
            'financial plan'
        ) ||

        normalizedLabel.contains(
            'tuition'
        ) ||

        normalizedLabel.contains(
            'enrollment'
        ) ||

        normalizedLabel.contains(
            'student status'
        ) ||

        normalizedLabel.contains(
            'study load'
        ) ||

        normalizedLabel.contains(
            'currently employed'
        ) ||

        normalizedLabel.contains(
            'employment status'
        ) ||

        normalizedLabel.contains(
            'working now'
        ) ||

        normalizedLabel.contains(
            'current job'
        );

    }

    private static Boolean isChoiceQuestion(

        UserDataDiscoveryService.FormQuestion question

    ) {

        if (

            question == null

        ) {

            return false;

        }

        String type =
            String.isBlank(
                question.questionType
            )
                ? ''
                : question.questionType.toLowerCase();

        return type == 'picklist' ||

        type == 'dropdown' ||

        type == 'radio' ||

        !String.isBlank(
            question.picklistValues
        );

    }

    private static String matchOptionFromList(

        String value,

        List<String> options

    ) {

        if (

            String.isBlank(
                value
            ) ||

            options == null ||

            options.isEmpty()

        ) {

            return null;

        }

        String normalizedValue =
            normalize(
                value
            );

        for (

            String option
            : options

        ) {

            String normalizedOption =
                normalize(
                    option
                );

            if (

                normalizedValue == normalizedOption ||

                normalizedValue.contains(
                    normalizedOption
                ) ||

                normalizedOption.contains(
                    normalizedValue
                )

            ) {

                return option;

            }

        }

        return null;

    }

    private static List<String> parseOptions(

        String picklistValues

    ) {

        List<String> options =
            new List<String>();

        if (

            String.isBlank(
                picklistValues
            )

        ) {

            return options;

        }

        for (

            String rawOption
            : picklistValues.split(
                '[,;\\n]'
            )

        ) {

            String option =
                rawOption.trim();

            if (

                !String.isBlank(
                    option
                )

            ) {

                options.add(
                    option
                );

            }

        }

        return options;

    }

    private static String normalize(

        String value

    ) {

        return String.isBlank(
            value
        )
            ? ''
            : value.toLowerCase()
                .replaceAll(
                    '[^a-z0-9]+',
                    ' '
                )
                .replaceAll(
                    '\\s+',
                    ' '
                )
                .trim();

    }

}
