public without sharing class AcademicFormController {

    private static final Integer STUDENT_TOTAL_PAGES = 5;
    private static final Integer ADMIN_REVIEW_PAGE = 6;

    // LOAD FORM CONFIGURATION
    
    @AuraEnabled
    public static List<Map<String, Object>>
    loadFormConfiguration() {
    
        List<Map<String, Object>> result =
            new List<Map<String, Object>>();

        Boolean hasAdminReviewMetadata =
            false;
    
        List<Form_Configuration_c__mdt> configs = [
    
            SELECT
    
                MasterLabel,
    
                Question_Id__c,
    
                Question_Type__c,
    
                Page_Number__c,
    
                Display_Order__c,
    
                Is_Required__c,
    
                Help_Text__c,
    
                Validation_Rule__c,
    
                Picklist_Values__c
    
            FROM Form_Configuration_c__mdt
    
            ORDER BY
    
                Page_Number__c,
    
                Display_Order__c
    
        ];
    
        for (
    
            Form_Configuration_c__mdt config
            : configs
    
        ) {
    
            Map<String, Object> fieldMap =
                new Map<String, Object>();
    
            // NEW FORMAT
    
            fieldMap.put(
                'id',
                config.Question_Id__c
            );
    
            fieldMap.put(
                'label',
                config.MasterLabel
            );
    
            fieldMap.put(
                'type',
                config.Question_Type__c
            );
    
            fieldMap.put(
                'page',
                Integer.valueOf(
                    config.Page_Number__c
                )
            );
    
            fieldMap.put(
                'displayOrder',
                Integer.valueOf(
                    config.Display_Order__c
                )
            );
    
            fieldMap.put(
                'required',
                config.Is_Required__c
            );
    
            fieldMap.put(
                'helpText',
                config.Help_Text__c
            );
    
            fieldMap.put(
                'validationRule',
                config.Validation_Rule__c
            );
    
            fieldMap.put(
                'picklistValues',
                config.Picklist_Values__c
            );
    
            // OLD FORMAT SUPPORT
    
            fieldMap.put(
                'MasterLabel',
                config.MasterLabel
            );
    
            fieldMap.put(
                'Question_Type__c',
                config.Question_Type__c
            );
    
            fieldMap.put(
                'Question_Id__c',
                config.Question_Id__c
            );
    
            fieldMap.put(
                'Page_Number__c',
                config.Page_Number__c
            );
    
            fieldMap.put(
                'Display_Order__c',
                config.Display_Order__c
            );
    
            fieldMap.put(
                'Is_Required__c',
                config.Is_Required__c
            );
    
            fieldMap.put(
                'Help_Text__c',
                config.Help_Text__c
            );
    
            fieldMap.put(
                'Validation_Rule__c',
                config.Validation_Rule__c
            );
    
            fieldMap.put(
                'Picklist_Values__c',
                config.Picklist_Values__c
            );
    
            result.add(fieldMap);

            if (
                isAdminReviewQuestion(
                    config.Question_Id__c
                )
            ) {

                hasAdminReviewMetadata =
                    true;

            }
    
        }

        if (
            canUseAdminApplicationContext() &&
            !hasAdminReviewMetadata
        ) {

            result.addAll(
                buildAdminReviewConfiguration()
            );

        }
    
        return result;
    
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

    @AuraEnabled(cacheable=true)
    public static Boolean canUseAdminApplicationContext() {

        return Schema.sObjectType.Academic_Application__c.isAccessible() &&
            Schema.sObjectType.Academic_Application__c.fields.Applicant__c.isAccessible() &&
            Schema.sObjectType.Academic_Application__c.fields.Decision_Status__c.isAccessible() &&
            Schema.sObjectType.Academic_Application__c.fields.Admin_Review_Comments__c.isAccessible();

    }

    @AuraEnabled(cacheable=true)
    public static Boolean canAccessAcademicApplication(Id applicationId) {

        if (
            applicationId == null ||
            !canUseAdminApplicationContext()
        ) {

            return false;

        }

        List<Academic_Application__c> applications = [
            SELECT Id
            FROM Academic_Application__c
            WHERE Id = :applicationId
            WITH USER_MODE
            LIMIT 1
        ];

        return !applications.isEmpty();

    }

    private static List<Map<String, Object>> buildAdminReviewConfiguration() {

        List<Map<String, Object>> fields =
            new List<Map<String, Object>>();

        fields.add(
            buildAdminField(
                'admin_decision_status',
                'Decision Status',
                'picklist',
                1,
                false,
                'Pending Review,Approved,Rejected,Waitlisted',
                'Academic_Application__c',
                'Decision_Status__c'
            )
        );

        fields.add(
            buildAdminField(
                'admin_admission_granted',
                'Admission Granted',
                'checkbox',
                2,
                false,
                null,
                'Academic_Application__c',
                'Admission_Granted__c'
            )
        );

        fields.add(
            buildAdminField(
                'admin_review_comments',
                'Admin Review Comments',
                'textarea',
                3,
                false,
                null,
                'Academic_Application__c',
                'Admin_Review_Comments__c'
            )
        );

        fields.add(
            buildAdminField(
                'admin_approval_comments',
                'Approval Decision Comments',
                'textarea',
                4,
                false,
                null,
                'Academic_Application__c',
                'Approval_Decision_Comments__c'
            )
        );

        fields.add(
            buildAdminField(
                'admin_rejection_comments',
                'Rejection Comments',
                'textarea',
                5,
                false,
                null,
                'Academic_Application__c',
                'Rejection_Comments__c'
            )
        );

        fields.add(
            buildAdminField(
                'admin_reviewer_notes',
                'Reviewer Notes',
                'textarea',
                6,
                false,
                null,
                'Academic_Application__c',
                'Reviewer_Notes__c'
            )
        );

        fields.add(
            buildAdminField(
                'admin_decision_date',
                'Decision Date',
                'date',
                7,
                false,
                null,
                'Academic_Application__c',
                'Decision_Date__c'
            )
        );

        return fields;

    }

    private static Map<String, Object> buildAdminField(
        String questionId,
        String label,
        String type,
        Integer displayOrder,
        Boolean required,
        String picklistValues,
        String objectApiName,
        String fieldApiName
    ) {

        Map<String, Object> fieldMap =
            new Map<String, Object>();

        fieldMap.put('id', questionId);
        fieldMap.put('label', label);
        fieldMap.put('type', type);
        fieldMap.put('page', ADMIN_REVIEW_PAGE);
        fieldMap.put('displayOrder', displayOrder);
        fieldMap.put('required', required);
        fieldMap.put('helpText', 'Admin-only review field.');
        fieldMap.put('validationRule', null);
        fieldMap.put('picklistValues', picklistValues);
        fieldMap.put('isAdminOnly', true);
        fieldMap.put('objectApiName', objectApiName);
        fieldMap.put('fieldApiName', fieldApiName);
        fieldMap.put('MasterLabel', label);
        fieldMap.put('Question_Type__c', type);
        fieldMap.put('Question_Id__c', questionId);
        fieldMap.put('Page_Number__c', ADMIN_REVIEW_PAGE);
        fieldMap.put('Display_Order__c', displayOrder);
        fieldMap.put('Is_Required__c', required);
        fieldMap.put('Help_Text__c', 'Admin-only review field.');
        fieldMap.put('Validation_Rule__c', null);
        fieldMap.put('Picklist_Values__c', picklistValues);

        return fieldMap;

    }
    
    // LOAD FORM DRAFT
    
    @AuraEnabled
    public static Map<String, Object>
    loadFormDraft(Id userId) {
    
        Map<String, Object> result =
            new Map<String, Object>();
    
        List<Form_Submission__c> drafts = [
    
            SELECT
    
                Id,
    
                Current_Page__c,
    
                Status__c,
    
                User__c,
    
                (
    
                    SELECT
    
                        Id,
    
                        Question_Id__c,
    
                        Response_Value__c
    
                    FROM Form_Responses__r
    
                )
    
            FROM Form_Submission__c
    
            WHERE Status__c = 'In Progress'
    
            AND User__c =
                :UserInfo.getUserId()
    
            LIMIT 1
    
        ];
    
        if (!drafts.isEmpty()) {
    
            Form_Submission__c draft =
                drafts[0];

            String confidenceFieldApiName =
                getFormResponseConfidenceFieldApiName();

            Map<Id, Object> confidenceByResponseId =
                getSavedResponseConfidenceById(
                    draft.Id,
                    confidenceFieldApiName
                );
    
            result.put(
                'submissionId',
                draft.Id
            );
    
            result.put(
                'currentPage',
                draft.Current_Page__c
            );
    
            Map<String, Object> formData =
                new Map<String, Object>();
    
            for (
    
                Form_Response__c response
                : draft.Form_Responses__r
    
            ) {
    
                Map<String, Object> valueObj =
                    new Map<String, Object>();
    
                valueObj.put(
                    'value',
                    response.Response_Value__c
                );

                if (
                    confidenceByResponseId.containsKey(
                        response.Id
                    )
                ) {

                    valueObj.put(
                        'confidence',
                        normalizeStoredConfidenceForFormData(
                            confidenceFieldApiName,
                            confidenceByResponseId.get(
                                response.Id
                            )
                        )
                    );

                }
    
                formData.put(
                    response.Question_Id__c,
                    valueObj
                );
    
            }
    
            result.put(
                'formData',
                formData
            );
    
        }
    
        return result;
    
    }

    private static Form_Submission__c buildDraftSubmission(

        Integer currentPage,

        String sessionId

    ) {

        return new Form_Submission__c(

            Status__c =
                'In Progress',

            Current_Page__c =
                currentPage,

            User__c =
                UserInfo.getUserId(),

            Application_Type__c =
                'Graduate Admission',

            Total_Pages__c =
                STUDENT_TOTAL_PAGES,

            Percent_Complete__c =
                (currentPage * 100) / STUDENT_TOTAL_PAGES,

            Started_Date__c =
                System.now(),

            Last_Saved__c =
                System.now(),

            Session_ID__c =
                sessionId

        );

    }

    @AuraEnabled
    public static Map<String, Object>
    loadFormSubmission(Id submissionId) {

        Map<String, Object> result =
            new Map<String, Object>();

        if (
            submissionId == null
        ) {

            return result;

        }

        Form_Submission__c submission = [

            SELECT
                Id,
                Current_Page__c,
                Status__c,
                User__c,
                Academic_Application__c,
                (
                    SELECT
                        Id,
                        Question_Id__c,
                        Response_Value__c
                    FROM Form_Responses__r
                )

            FROM Form_Submission__c

            WHERE Id = :submissionId

            LIMIT 1

        ];

        if (
            submission.Academic_Application__c == null &&
            submission.Status__c == 'Submitted'
        ) {

            Id createdApplicationId =
                ensureAcademicApplicationForSubmission(
                    submission
                );

            if (
                createdApplicationId != null
            ) {

                update submission;

            }

        }

        String confidenceFieldApiName =
            getFormResponseConfidenceFieldApiName();

        Map<Id, Object> confidenceByResponseId =
            getSavedResponseConfidenceById(
                submission.Id,
                confidenceFieldApiName
            );

        Map<String, Object> formData =
            buildFormDataFromResponses(
                submission.Form_Responses__r,
                confidenceByResponseId,
                confidenceFieldApiName
            );

        if (
            submission.Academic_Application__c != null &&
            canUseAdminApplicationContext()
        ) {

            addAcademicApplicationFormData(
                formData,
                submission.Academic_Application__c
            );

        }

        result.put(
            'submissionId',
            submission.Id
        );

        result.put(
            'academicApplicationId',
            submission.Academic_Application__c
        );

        result.put(
            'currentPage',
            canUseAdminApplicationContext()
                ? ADMIN_REVIEW_PAGE
                : (
                    submission.Current_Page__c == null
                        ? 1
                        : submission.Current_Page__c
                )
        );

        result.put(
            'formData',
            formData
        );

        return result;

    }

    private static Map<String, Object> buildFormDataFromResponses(

        List<Form_Response__c> responses,

        Map<Id, Object> confidenceByResponseId,

        String confidenceFieldApiName

    ) {

        Map<String, Object> formData =
            new Map<String, Object>();

        if (
            responses == null
        ) {

            return formData;

        }

        for (
            Form_Response__c response :
            responses
        ) {

            Map<String, Object> valueObj =
                new Map<String, Object>();

            valueObj.put(
                'value',
                response.Response_Value__c
            );

            if (
                confidenceByResponseId != null &&
                confidenceByResponseId.containsKey(
                    response.Id
                )
            ) {

                valueObj.put(
                    'confidence',
                    normalizeStoredConfidenceForFormData(
                        confidenceFieldApiName,
                        confidenceByResponseId.get(
                            response.Id
                        )
                    )
                );

            }

            formData.put(
                response.Question_Id__c,
                valueObj
            );

        }

        return formData;

    }

    private static void addAcademicApplicationFormData(

        Map<String, Object> formData,

        Id academicApplicationId

    ) {

        List<Academic_Application__c> applications = [

            SELECT
                Id,
                Decision_Status__c,
                Admission_Granted__c,
                Admin_Review_Comments__c,
                Approval_Decision_Comments__c,
                Rejection_Comments__c,
                Reviewer_Notes__c,
                Decision_Date__c

            FROM Academic_Application__c

            WHERE Id = :academicApplicationId

            WITH USER_MODE

            LIMIT 1

        ];

        if (
            applications.isEmpty()
        ) {

            return;

        }

        Academic_Application__c application =
            applications[0];

        putFormValue(
            formData,
            'admin_decision_status',
            application.Decision_Status__c
        );

        putFormValue(
            formData,
            'admin_admission_granted',
            application.Admission_Granted__c
        );

        putFormValue(
            formData,
            'admin_review_comments',
            application.Admin_Review_Comments__c
        );

        putFormValue(
            formData,
            'admin_approval_comments',
            application.Approval_Decision_Comments__c
        );

        putFormValue(
            formData,
            'admin_rejection_comments',
            application.Rejection_Comments__c
        );

        putFormValue(
            formData,
            'admin_reviewer_notes',
            application.Reviewer_Notes__c
        );

        putFormValue(
            formData,
            'admin_decision_date',
            application.Decision_Date__c
        );

    }

    private static void putFormValue(

        Map<String, Object> formData,

        String questionId,

        Object value

    ) {

        if (
            formData == null ||
            String.isBlank(
                questionId
            ) ||
            value == null ||
            String.isBlank(
                String.valueOf(
                    value
                )
            )
        ) {

            return;

        }

        formData.put(
            questionId,
            new Map<String, Object>{
                'value' => String.valueOf(
                    value
                ),
                'confidence' => 1
            }
        );

    }
    
    // SAVE FORM DRAFT
    
    @AuraEnabled
    public static Map<String, Object>
    saveFormDraft(
    
        Id submissionId,
    
        Id userId,
    
        Integer currentPage,
    
        String formData,
    
        String sessionId,

        Id targetApplicationId
    
    ) {
    
        Map<String, Object> result =
            new Map<String, Object>();

        try {
    
        Form_Submission__c submission;
    
        /*
         * CREATE SUBMISSION
         */
    
        if (submissionId == null) {

            submission =
                buildDraftSubmission(
                    currentPage,
                    sessionId
                );

            insert submission;

        }
    
        /*
         * UPDATE SUBMISSION
         */
    
        else {
    
            List<Form_Submission__c> submissions = [

                SELECT
                    Id,
                    Current_Page__c,
                    User__c

                FROM Form_Submission__c

                WHERE Id = :submissionId

                LIMIT 1

            ];

            if (
                submissions.isEmpty()
            ) {

                submission =
                    buildDraftSubmission(
                        currentPage,
                        sessionId
                    );

                insert submission;

                result.put(
                    'recreatedSubmission',
                    true
                );

            }

            else {

                submission =
                    submissions[0];

                submission.Current_Page__c =
                    currentPage;

                submission.Total_Pages__c =
                    STUDENT_TOTAL_PAGES;

                submission.Percent_Complete__c =
                    (currentPage * 100) / STUDENT_TOTAL_PAGES;

                submission.Last_Saved__c =
                    System.now();

                submission.Session_ID__c =
                    sessionId;

                update submission;

            }
    
        }
    
        /*
         * EXISTING RESPONSES
         */
    
        Map<String, Form_Response__c>
            existingResponses =
                new Map<String, Form_Response__c>();
    
        for (
    
            Form_Response__c existing :
    
            [
    
                SELECT
                    Id,
                    Question_Id__c,
                    Response_Value__c
    
                FROM Form_Response__c
    
                WHERE Form_Submission__c =
                    :submission.Id
    
            ]
    
        ) {
    
            existingResponses.put(
    
                existing.Question_Id__c,
    
                existing
    
            );
    
        }
    
        /*
         * PARSE FORM DATA
         */
    
        Map<String, Object> parsedData =
            String.isBlank(
                formData
            )
                ? new Map<String, Object>()
                : (Map<String, Object>)
                    JSON.deserializeUntyped(
                        formData
                    );

        saveAcademicApplicationAnswers(
            targetApplicationId,
            parsedData,
            result
        );

        String confidenceFieldApiName =
            getFormResponseConfidenceFieldApiName();

        Integer responseValueMaxLength =
            getFieldLength(
                Form_Response__c.Response_Value__c
            );
    
        /*
         * UPSERT LISTS
         */
    
        List<Form_Response__c>
            responsesToInsert =
                new List<Form_Response__c>();
    
        List<Form_Response__c>
            responsesToUpdate =
                new List<Form_Response__c>();

        /*
         * PROCESS RESPONSES
         */
    
        for (
    
            String key
            : parsedData.keySet()
    
        ) {
    
            Object rawValueObj =
                parsedData.get(key);

            if (
                !(rawValueObj instanceof Map<String, Object>)
            ) {

                continue;

            }

            Map<String, Object> valueObj =

                (Map<String, Object>)
                rawValueObj;
    
            String responseValue =
                valueObj != null &&
                valueObj.containsKey('value') &&
                valueObj.get('value') != null
                    ? String.valueOf(
                        valueObj.get('value')
                    )
                    : null;

            if (
                String.isBlank(
                    responseValue
                )
            ) {

                if (

                    existingResponses.containsKey(
                        key
                    )

                ) {

                    Form_Response__c existingBlankResponse =

                        existingResponses.get(
                            key
                        );

                    existingBlankResponse.Response_Value__c =
                        '';

                    responsesToUpdate.add(
                        existingBlankResponse
                    );

                }

                continue;

            }

            responseValue =
                truncateToFieldLength(
                    responseValue,
                    responseValueMaxLength
                );

            Decimal confidence =
                getResponseConfidence(
                    valueObj
                );

            Boolean confidenceProvided =
                hasResponseConfidence(
                    valueObj
                );
    
            /*
             * UPDATE EXISTING
             */
    
            if (
    
                existingResponses.containsKey(
                    key
                )
    
            ) {
    
                Form_Response__c existingResponse =
    
                    existingResponses.get(
                        key
                    );
    
                existingResponse.Response_Value__c =
                    responseValue;

                applyResponseConfidence(
                    existingResponse,
                    confidenceFieldApiName,
                    confidence,
                    confidenceProvided
                );
    
                responsesToUpdate.add(
                    existingResponse
                );
    
            }
    
            /*
             * INSERT NEW
             */
    
            else {
    
                Form_Response__c newResponse =
                    new Form_Response__c(
    
                        Form_Submission__c =
                            submission.Id,
    
                        Question_Id__c =
                            key,
    
                        Response_Value__c =
                            responseValue
    
                    );

                applyResponseConfidence(
                    newResponse,
                    confidenceFieldApiName,
                    confidence,
                    confidenceProvided
                );
    
                responsesToInsert.add(
                    newResponse
                );
    
            }
    
        }
    
        /*
         * SAVE UPDATES
         */
    
        if (!responsesToUpdate.isEmpty()) {
    
            saveResponsesWithoutBlockingDraft(
                responsesToUpdate,
                result,
                'updated'
            );
    
        }

        /*
         * SAVE INSERTSss
         */
    
        if (!responsesToInsert.isEmpty()) {
    
            saveResponsesWithoutBlockingDraft(
                responsesToInsert,
                result,
                'inserted'
            );
    
        }
    
        /*
         * RETURN
         */
    
        result.put(
            'submissionId',
            submission.Id
        );

        result.put(
            'success',
            true
        );
    
        return result;

        } catch (Exception e) {

            result.put(
                'success',
                false
            );

            result.put(
                'errorMessage',
                e.getTypeName() +
                ': ' +
                e.getMessage()
            );

            return result;

        }
    
    }

    private static Integer getFieldLength(

        Schema.SObjectField fieldToken

    ) {

        if (
            fieldToken == null
        ) {

            return 0;

        }

        try {

            return fieldToken
                .getDescribe()
                .getLength();

        } catch (Exception e) {

            return 0;

        }

    }

    private static String truncateToFieldLength(

        String value,

        Integer maxLength

    ) {

        if (
            String.isBlank(
                value
            ) ||
            maxLength == null ||
            maxLength <= 0 ||
            value.length() <= maxLength
        ) {

            return value;

        }

        return value.substring(
            0,
            maxLength
        );

    }

    private static void saveResponsesWithoutBlockingDraft(

        List<Form_Response__c> responses,

        Map<String, Object> result,

        String operation

    ) {

        if (
            responses == null ||
            responses.isEmpty()
        ) {

            return;

        }

        Database.SaveResult[] saveResults;

        if (
            operation == 'inserted'
        ) {

            saveResults =
                Database.insert(
                    responses,
                    false
                );

        } else {

            saveResults =
                Database.update(
                    responses,
                    false
                );

        }

        List<String> errors =
            (List<String>) result.get(
                'responseSaveErrors'
            );

        if (
            errors == null
        ) {

            errors =
                new List<String>();

        }

        Integer savedCount = 0;

        for (
            Integer index = 0;
            index < saveResults.size();
            index++
        ) {

            Database.SaveResult saveResult =
                saveResults[index];

            if (
                saveResult.isSuccess()
            ) {

                savedCount++;
                continue;

            }

            Form_Response__c response =
                responses[index];

            for (
                Database.Error error :
                saveResult.getErrors()
            ) {

                errors.add(
                    String.valueOf(
                        response.Question_Id__c
                    ) +
                    ': ' +
                    error.getMessage()
                );

            }

        }

        result.put(
            operation + 'ResponseCount',
            savedCount
        );

        if (
            !errors.isEmpty()
        ) {

            result.put(
                'responseSaveErrors',
                errors
            );

        }

    }

    private static Map<Id, Object> getSavedResponseConfidenceById(

        Id submissionId,

        String confidenceFieldApiName

    ) {

        Map<Id, Object> confidenceByResponseId =
            new Map<Id, Object>();

        if (
            submissionId == null ||
            String.isBlank(
                confidenceFieldApiName
            )
        ) {

            return confidenceByResponseId;

        }

        String query =
            'SELECT Id, ' +
            confidenceFieldApiName +
            ' FROM Form_Response__c WHERE Form_Submission__c = :submissionId';

        for (
            SObject response :
            Database.query(
                query
            )
        ) {

            Object confidence =
                response.get(
                    confidenceFieldApiName
                );

            if (
                confidence != null
            ) {

                confidenceByResponseId.put(
                    (Id) response.get(
                        'Id'
                    ),
                    confidence
                );

            }

        }

        return confidenceByResponseId;

    }

    private static String getFormResponseConfidenceFieldApiName() {

        Map<String, Schema.SObjectField> fieldMap =
            Form_Response__c.SObjectType.getDescribe().fields.getMap();

        for (
            String candidate :
            new List<String>{
                'Confidence__c',
                'AI_Confidence__c',
                'Match_Confidence__c',
                'Field_Confidence__c',
                'Field_Match_Confidence__c',
                'Extraction_Confidence__c',
                'AI_Extraction_Confidence__c',
                'Confidence_Score__c',
                'AI_Confidence_Score__c'
            }
        ) {

            if (
                fieldMap.containsKey(
                    candidate
                )
            ) {

                return candidate;

            }

        }

        return null;

    }

    private static Decimal getResponseConfidence(

        Map<String, Object> valueObj

    ) {

        if (
            valueObj == null
        ) {

            return null;

        }

        Object rawConfidence =
            valueObj.containsKey(
                'confidence'
            )
                ? valueObj.get(
                    'confidence'
                )
                : valueObj.get(
                    'bestMatchConfidence'
                );

        if (
            rawConfidence == null ||
            String.isBlank(
                String.valueOf(
                    rawConfidence
                )
            )
        ) {

            return null;

        }

        try {

            return Decimal.valueOf(
                String.valueOf(
                    rawConfidence
                ).replace(
                    '%',
                    ''
                )
            );

        } catch (Exception e) {

            return null;

        }

    }

    private static Boolean hasResponseConfidence(

        Map<String, Object> valueObj

    ) {

        return valueObj != null &&
            (
                valueObj.containsKey(
                    'confidence'
                ) ||
                valueObj.containsKey(
                    'bestMatchConfidence'
                )
            );

    }

    private static Object normalizeStoredConfidenceForFormData(

        String confidenceFieldApiName,

        Object storedConfidence

    ) {

        if (
            storedConfidence == null ||
            String.isBlank(
                confidenceFieldApiName
            )
        ) {

            return storedConfidence;

        }

        Schema.DescribeFieldResult fieldDescribe =
            Form_Response__c.SObjectType
                .getDescribe()
                .fields
                .getMap()
                .get(
                    confidenceFieldApiName
                )
                .getDescribe();

        if (
            fieldDescribe.getType() !=
            Schema.DisplayType.Percent
        ) {

            return storedConfidence;

        }

        try {

            Decimal confidence =
                Decimal.valueOf(
                    String.valueOf(
                        storedConfidence
                    )
                );

            return confidence > 1
                ? confidence / 100
                : confidence;

        } catch (Exception e) {

            return storedConfidence;

        }

    }

    private static void applyResponseConfidence(

        Form_Response__c response,

        String confidenceFieldApiName,

        Decimal confidence,

        Boolean confidenceProvided

    ) {

        if (
            response == null ||
            String.isBlank(
                confidenceFieldApiName
            )
        ) {

            return;

        }

        Schema.DescribeFieldResult fieldDescribe =
            Form_Response__c.SObjectType
                .getDescribe()
                .fields
                .getMap()
                .get(
                    confidenceFieldApiName
                )
                .getDescribe();

        if (
            confidence == null
        ) {

            if (
                confidenceProvided == false
            ) {

                response.put(
                    confidenceFieldApiName,
                    null
                );

            }

            return;

        }

        Decimal numericValueToStore =
            confidence;

        if (
            fieldDescribe.getType() ==
            Schema.DisplayType.Percent &&
            numericValueToStore <= 1
        ) {

            numericValueToStore =
                numericValueToStore * 100;

        }

        if (
            fieldDescribe.getType() ==
            Schema.DisplayType.Percent &&
            fieldDescribe.getScale() == 0
        ) {

            numericValueToStore =
                numericValueToStore.setScale(
                    0
                );

        }

        if (
            fieldDescribe.getType() ==
            Schema.DisplayType.String ||
            fieldDescribe.getType() ==
            Schema.DisplayType.TextArea
        ) {

            response.put(
                confidenceFieldApiName,
                String.valueOf(
                    numericValueToStore
                )
            );

        } else {

            response.put(
                confidenceFieldApiName,
                numericValueToStore
            );

        }

    }

    private static void saveAcademicApplicationAnswers(

        Id targetApplicationId,

        Map<String, Object> parsedData,

        Map<String, Object> result

    ) {

        if (
            targetApplicationId == null ||
            parsedData == null ||
            parsedData.isEmpty() ||
            !Schema.sObjectType.Academic_Application__c.isAccessible() ||
            !Schema.sObjectType.Academic_Application__c.isUpdateable()
        ) {

            return;

        }

        List<Academic_Application__c> applications = [

            SELECT
                Id

            FROM Academic_Application__c

            WHERE Id = :targetApplicationId

            WITH USER_MODE

            LIMIT 1

        ];

        if (
            applications.isEmpty()
        ) {

            result.put(
                'academicApplicationSaveWarning',
                'Selected academic application record was not accessible.'
            );

            return;

        }

        Academic_Application__c application =
            applications[0];

        setApplicationFieldValue(
            application,
            parsedData,
            'admin_decision_status',
            'Decision_Status__c',
            Schema.sObjectType.Academic_Application__c.fields.Decision_Status__c
        );

        setApplicationFieldValue(
            application,
            parsedData,
            'admin_admission_granted',
            'Admission_Granted__c',
            Schema.sObjectType.Academic_Application__c.fields.Admission_Granted__c
        );

        setApplicationFieldValue(
            application,
            parsedData,
            'admin_review_comments',
            'Admin_Review_Comments__c',
            Schema.sObjectType.Academic_Application__c.fields.Admin_Review_Comments__c
        );

        setApplicationFieldValue(
            application,
            parsedData,
            'admin_approval_comments',
            'Approval_Decision_Comments__c',
            Schema.sObjectType.Academic_Application__c.fields.Approval_Decision_Comments__c
        );

        setApplicationFieldValue(
            application,
            parsedData,
            'admin_rejection_comments',
            'Rejection_Comments__c',
            Schema.sObjectType.Academic_Application__c.fields.Rejection_Comments__c
        );

        setApplicationFieldValue(
            application,
            parsedData,
            'admin_reviewer_notes',
            'Reviewer_Notes__c',
            Schema.sObjectType.Academic_Application__c.fields.Reviewer_Notes__c
        );

        setApplicationFieldValue(
            application,
            parsedData,
            'admin_decision_date',
            'Decision_Date__c',
            Schema.sObjectType.Academic_Application__c.fields.Decision_Date__c
        );

        SObjectAccessDecision decision =
            Security.stripInaccessible(
                AccessType.UPDATABLE,
                new List<SObject>{
                    application
                }
            );

        List<SObject> sanitizedRecords =
            decision.getRecords();

        if (
            sanitizedRecords.isEmpty()
        ) {

            return;

        }

        Database.SaveResult saveResult =
            Database.update(
                sanitizedRecords[0],
                false
            );

        if (
            !saveResult.isSuccess()
        ) {

            result.put(
                'academicApplicationSaveWarning',
                saveResult.getErrors().isEmpty()
                    ? 'Academic application fields could not be saved.'
                    : saveResult.getErrors()[0].getMessage()
            );

            return;

        }

        result.put(
            'academicApplicationUpdated',
            true
        );

    }

    private static void setApplicationFieldValue(

        Academic_Application__c application,

        Map<String, Object> parsedData,

        String questionId,

        String fieldApiName,

        Schema.DescribeFieldResult fieldDescribe

    ) {

        if (
            application == null ||
            parsedData == null ||
            !parsedData.containsKey(
                questionId
            ) ||
            fieldDescribe == null ||
            !fieldDescribe.isUpdateable()
        ) {

            return;

        }

        Object rawValueObj =
            parsedData.get(
                questionId
            );

        if (
            !(rawValueObj instanceof Map<String, Object>)
        ) {

            return;

        }

        Map<String, Object> valueObj =
            (Map<String, Object>) rawValueObj;

        Object rawValue =
            valueObj.get(
                'value'
            );

        Schema.DisplayType fieldType =
            fieldDescribe.getType();

        if (
            rawValue == null ||
            String.isBlank(
                String.valueOf(
                    rawValue
                )
            )
        ) {

            application.put(
                fieldApiName,
                null
            );

            return;

        }

        if (
            fieldType == Schema.DisplayType.Boolean
        ) {

            application.put(
                fieldApiName,
                Boolean.valueOf(
                    String.valueOf(
                        rawValue
                    )
                )
            );

            return;

        }

        if (
            fieldType == Schema.DisplayType.Date
        ) {

            try {

                application.put(
                    fieldApiName,
                    Date.valueOf(
                        String.valueOf(
                            rawValue
                        )
                    )
                );

            } catch (Exception e) {

                application.put(
                    fieldApiName,
                    null
                );

            }

            return;

        }

        application.put(
            fieldApiName,
            String.valueOf(
                rawValue
            )
        );

    }
    
    // SUBMIT FORM
    
    @AuraEnabled
    public static Map<String, Object>
    submitForm(
    
        Id submissionId,
    
        String formData
    
    ) {
    
        Map<String, Object> result =
            new Map<String, Object>();
    
        Form_Submission__c submission = [
    
            SELECT
    
                Id,
    
                Status__c,
    
                User__c,

                Academic_Application__c
    
            FROM Form_Submission__c
    
            WHERE Id = :submissionId
    
            LIMIT 1
    
        ];
    
        submission.Status__c =
            'Submitted';
    
        submission.Completed_Date__c =
            System.now();
    
        submission.Percent_Complete__c =
            100;
    
        submission.Total_Pages__c =
            STUDENT_TOTAL_PAGES;
    
        submission.Last_Saved__c =
            System.now();

        Id academicApplicationId =
            ensureAcademicApplicationForSubmission(
                submission
            );
    
        update submission;
    
        result.put(
            'submissionId',
            submission.Id
        );

        if (
            academicApplicationId != null
        ) {

            result.put(
                'academicApplicationId',
                academicApplicationId
            );

        }
    
        return result;
    
    }

    private static Id ensureAcademicApplicationForSubmission(

        Form_Submission__c submission

    ) {

        if (
            submission == null ||
            submission.Academic_Application__c != null
        ) {

            return submission == null
                ? null
                : submission.Academic_Application__c;

        }

        Id applicantContactId =
            getSubmissionUserContactId(
                submission.User__c
            );

        if (
            applicantContactId == null
        ) {

            return null;

        }

        Academic_Application__c application =
            new Academic_Application__c(
                Applicant__c =
                    applicantContactId,
                Decision_Status__c =
                    'Pending Review',
                Admission_Granted__c =
                    false
            );

        Database.SaveResult saveResult =
            Database.insert(
                application,
                false
            );

        if (
            !saveResult.isSuccess()
        ) {

            System.debug(
                LoggingLevel.WARN,
                'Academic application was not created for submission ' +
                submission.Id +
                ': ' +
                (
                    saveResult.getErrors().isEmpty()
                        ? 'Unknown error'
                        : saveResult.getErrors()[0].getMessage()
                )
            );

            return null;

        }

        submission.Academic_Application__c =
            saveResult.getId();

        return saveResult.getId();

    }

    private static Id getSubmissionUserContactId(

        Id userId

    ) {

        if (
            userId == null
        ) {

            return null;

        }

        List<User> users = [

            SELECT
                ContactId

            FROM User

            WHERE Id = :userId

            LIMIT 1

        ];

        if (
            users.isEmpty()
        ) {

            return null;

        }

        return users[0].ContactId;

    }
    
    }
