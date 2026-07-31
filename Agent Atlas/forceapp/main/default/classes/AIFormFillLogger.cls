public without sharing class AIFormFillLogger {

    private static final String LOG_OBJECT_API =
        'AI_Form_Fill_Log__c';

    public class Entry {
        public String action;
        public String status;
        public String questionId;
        public String questionLabel;
        public String source;
        public Decimal confidence;
        public String reason;
        public String value;
        public Long durationMs;
        public Id formSubmissionId;
    }

    public static void log(
        Entry entry
    ) {
        if (
            entry == null
        ) {
            return;
        }

        logAll(
            new List<Entry>{
                entry
            }
        );
    }

    @AuraEnabled
    public static void logChatDecision(
        String action,
        String status,
        String questionId,
        String questionLabel,
        String source,
        Decimal confidence,
        String reason,
        String value,
        Decimal durationMs,
        Id formSubmissionId
    ) {
        Entry entry =
            new Entry();

        entry.action =
            action;
        entry.status =
            status;
        entry.questionId =
            questionId;
        entry.questionLabel =
            questionLabel;
        entry.source =
            source;
        entry.confidence =
            confidence;
        entry.reason =
            reason;
        entry.value =
            value;
        entry.durationMs =
            durationMs == null
                ? null
                : durationMs.longValue();
        entry.formSubmissionId =
            formSubmissionId;

        log(
            entry
        );
    }

    public static void logAll(
        List<Entry> entries
    ) {
        if (
            entries == null ||
            entries.isEmpty()
        ) {
            return;
        }

        Schema.SObjectType logType =
            Schema.getGlobalDescribe().get(
                LOG_OBJECT_API
            );

        if (
            logType == null
        ) {
            System.debug(
                LoggingLevel.WARN,
                'AI form fill logging skipped because ' +
                LOG_OBJECT_API +
                ' is not available in this org.'
            );

            return;
        }

        Map<String, Schema.SObjectField> fields =
            logType.getDescribe().fields.getMap();

        List<SObject> records =
            new List<SObject>();

        for (
            Entry entry
            : entries
        ) {
            if (
                entry == null
            ) {
                continue;
            }

            SObject record =
                logType.newSObject();

            putIfFieldExists(
                record,
                fields,
                'Name',
                buildName(entry)
            );

            putIfFieldExists(
                record,
                fields,
                'Action__c',
                entry.action
            );

            putIfFieldExists(
                record,
                fields,
                'Status__c',
                entry.status
            );

            putIfFieldExists(
                record,
                fields,
                'Question_Id__c',
                truncate(entry.questionId, 100)
            );

            putIfFieldExists(
                record,
                fields,
                'Question_Label__c',
                truncate(entry.questionLabel, 255)
            );

            putIfFieldExists(
                record,
                fields,
                'Source__c',
                truncate(entry.source, 255)
            );

            putIfFieldExists(
                record,
                fields,
                'Confidence__c',
                normalizeConfidencePercent(
                    entry.confidence
                )
            );

            putIfFieldExists(
                record,
                fields,
                'Reason__c',
                entry.reason
            );

            putIfFieldExists(
                record,
                fields,
                'Masked_Value__c',
                truncate(
                    maskValue(entry.value),
                    255
                )
            );

            putIfFieldExists(
                record,
                fields,
                'Duration_MS__c',
                entry.durationMs == null
                    ? null
                    : Decimal.valueOf(
                        String.valueOf(entry.durationMs)
                    )
            );

            putIfFieldExists(
                record,
                fields,
                'Form_Submission__c',
                entry.formSubmissionId
            );

            putIfFieldExists(
                record,
                fields,
                'User__c',
                UserInfo.getUserId()
            );

            records.add(
                record
            );
        }

        if (
            records.isEmpty()
        ) {
            return;
        }

        try {
            insert records;
        }

        catch (DmlException e) {
            System.debug(
                LoggingLevel.WARN,
                'AI form fill logging failed but form fill will continue: ' +
                e.getMessage()
            );
        }
    }

    private static void putIfFieldExists(
        SObject record,
        Map<String, Schema.SObjectField> fields,
        String fieldName,
        Object value
    ) {
        if (
            value == null ||
            !fields.containsKey(fieldName)
        ) {
            return;
        }

        Schema.DescribeFieldResult fieldDescribe =
            fields.get(fieldName).getDescribe();

        if (
            fieldDescribe.getType() ==
                Schema.DisplayType.Picklist &&
            value instanceof String &&
            !isActivePicklistValue(
                fieldDescribe,
                (String) value
            )
        ) {
            return;
        }

        record.put(
            fieldName,
            value
        );
    }

    private static Boolean isActivePicklistValue(
        Schema.DescribeFieldResult fieldDescribe,
        String value
    ) {
        for (
            Schema.PicklistEntry entry
            : fieldDescribe.getPicklistValues()
        ) {
            if (
                entry.isActive() &&
                entry.getValue() == value
            ) {
                return true;
            }
        }

        return false;
    }

    private static String buildName(
        Entry entry
    ) {
        String label =
            String.isBlank(entry.questionLabel)
                ? entry.questionId
                : entry.questionLabel;

        String name =
            (String.isBlank(entry.action)
                ? 'AI Fill'
                : entry.action) +
            ' - ' +
            (String.isBlank(label)
                ? 'Field'
                : label);

        return truncate(
            name,
            80
        );
    }

    private static Decimal normalizeConfidencePercent(
        Decimal confidence
    ) {
        if (
            confidence == null
        ) {
            return null;
        }

        Decimal percent =
            confidence <= 1
                ? confidence * 100
                : confidence;

        if (
            percent < 0
        ) {
            return 0;
        }

        if (
            percent > 100
        ) {
            return 100;
        }

        return percent.setScale(0);
    }

    private static String maskValue(
        String value
    ) {
        if (
            String.isBlank(value)
        ) {
            return value;
        }

        String trimmed =
            value.trim();

        if (
            trimmed.contains('@')
        ) {
            Integer atIndex =
                trimmed.indexOf('@');

            if (
                atIndex > 0 &&
                atIndex < trimmed.length() - 1
            ) {
                return trimmed.substring(0, 1) +
                    '***@' +
                    trimmed.substring(atIndex + 1);
            }
        }

        String digitsOnly =
            trimmed.replaceAll('[^0-9]', '');

        if (
            digitsOnly.length() >= 7
        ) {
            return '***-***-' +
                digitsOnly.substring(
                    digitsOnly.length() - 4
                );
        }

        if (
            trimmed.length() <= 2
        ) {
            return '***';
        }

        return trimmed.substring(0, 1) +
            '***' +
            trimmed.substring(
                trimmed.length() - 1
            );
    }

    private static String truncate(
        String value,
        Integer maxLength
    ) {
        if (
            value == null ||
            maxLength == null ||
            value.length() <= maxLength
        ) {
            return value;
        }

        return value.substring(
            0,
            maxLength
        );
    }

}
