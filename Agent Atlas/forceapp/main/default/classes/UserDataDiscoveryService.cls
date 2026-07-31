public with sharing class UserDataDiscoveryService {

    public class FormQuestion {

        @AuraEnabled
        public String questionId;

        @AuraEnabled
        public String questionText;

        @AuraEnabled
        public String questionType;

        @AuraEnabled
        public String picklistValues;

        @AuraEnabled
        public Integer pageNumber;

    }

    public class DataDiscoveryResult {

        @AuraEnabled
        public String questionId;

        @AuraEnabled
        public String recommendedValue;

        @AuraEnabled
        public Decimal bestMatchConfidence;

        @AuraEnabled
        public String reasoning;

        @AuraEnabled
        public List<String> sourceFields =
            new List<String>();

        @AuraEnabled
        public Boolean isMergedAnswer = false;

        @AuraEnabled
        public Boolean clearValue = false;

        @AuraEnabled
        public Boolean noDataFound = false;

        @AuraEnabled
        public String noDataMessage;

        @AuraEnabled
        public String sourceUpdatedAt;

        @AuraEnabled
        public String selectionType;

        @AuraEnabled
        public List<String> alternativeOptions =
            new List<String>();

    }

    private class SemanticAnswer {

        public String value;

        public String reasoning;

        public List<String> sourceFields =
            new List<String>();

        public Boolean isMergedAnswer = false;

        public SemanticAnswer(

            String value,

            String reasoning

        ) {

            this.value =
                value;

            this.reasoning =
                reasoning;

        }

        public SemanticAnswer(

            String value,

            String reasoning,

            List<String> sourceFields

        ) {

            this.value =
                value;

            this.reasoning =
                reasoning;

            if (

                sourceFields != null

            ) {

                this.sourceFields.addAll(
                    sourceFields
                );

            }

        }

        public SemanticAnswer markAsMerged() {

            this.isMergedAnswer =
                true;

            return this;

        }

    }

    public class DiscoveryContext {

        public User usr;

        public Contact con;

        public Academic_Application__c application;

    }

    public static DiscoveryContext loadDiscoveryContext(

        Id userId

    ) {

        return loadDiscoveryContext(
            userId,
            null
        );

    }

    public static DiscoveryContext loadDiscoveryContext(

        Id userId,

        Id targetApplicationId

    ) {

        DiscoveryContext context =
            new DiscoveryContext();

        context.usr = [

            SELECT
                Id,
                FirstName,
                LastName,
                Email,
                Phone,
                Street,
                City,
                State,
                PostalCode,
                Country,
                ContactId,
                LastModifiedDate

            FROM User

            WHERE Id = :userId

            LIMIT 1

        ];

        context.con =
            null;

        context.application =
            null;

        Id contactId =
            context.usr.ContactId;

        if (

            targetApplicationId != null &&
            Schema.sObjectType.Academic_Application__c.isAccessible() &&
            Schema.sObjectType.Academic_Application__c.fields.Applicant__c.isAccessible()

        ) {

            List<Academic_Application__c> applications = [
                SELECT
                    Id,
                    Applicant__c,
                    Admission_Granted__c,
                    Decision_Status__c,
                    Admin_Review_Comments__c,
                    Approval_Decision_Comments__c,
                    Rejection_Comments__c,
                    Reviewer_Notes__c,
                    Decision_Date__c,
                    LastModifiedDate
                FROM Academic_Application__c
                WHERE Id = :targetApplicationId
                WITH USER_MODE
                LIMIT 1
            ];

            if (

                !applications.isEmpty()

            ) {

                context.application =
                    applications[0];

                contactId =
                    context.application.Applicant__c;

            }

        }

        if (

            contactId != null

        ) {

            List<String> contactFields =
                getContactDiscoveryFields();

            String contactQuery =
                'SELECT ' +
                String.join(
                    contactFields,
                    ','
                ) +
                ' FROM Contact WHERE Id = :contactId WITH USER_MODE LIMIT 1';

            List<Contact> contacts =
                Database.query(
                    contactQuery
                );

            if (

                !contacts.isEmpty()

            ) {

                context.con =
                    contacts[0];

            }

        }

        return context;

    }

    private static List<String> getContactDiscoveryFields() {

        List<String> fields =
            new List<String>{
                'Id',
                'Birthdate',
                'Phone',
                'MobilePhone',
                'MailingStreet',
                'MailingCity',
                'MailingState',
                'MailingPostalCode',
                'MailingCountry',
                'LastModifiedDate'
            };

        for (
            String optionalField :
            new List<String>{
                'Gender__c',
                'Citizenship_Status__c',
                'Languages__c',
                'Applicant_Knowledge__c'
            }
        ) {

            if (
                isContactFieldReadable(
                    optionalField
                )
            ) {

                fields.add(
                    optionalField
                );

            }

        }

        return fields;

    }

    private static Boolean isContactFieldReadable(

        String fieldApiName

    ) {

        Map<String, Schema.SObjectField> fieldMap =
            Contact.SObjectType.getDescribe().fields.getMap();

        return fieldMap.containsKey(
            fieldApiName
        ) &&
            fieldMap.get(
                fieldApiName
            )
                .getDescribe()
                .isAccessible();

    }

    public static String getContactText(

        Contact contactRecord,

        String fieldApiName

    ) {

        if (
            contactRecord == null ||
            String.isBlank(
                fieldApiName
            ) ||
            !isContactFieldReadable(
                fieldApiName
            )
        ) {

            return null;

        }

        try {

            Object value =
                contactRecord.get(
                    fieldApiName
                );

            return value == null
                ? null
                : String.valueOf(
                    value
                );

        } catch (Exception e) {

            return null;

        }

    }

    @AuraEnabled
    public static Map<String, DataDiscoveryResult>
    discoverDataForForm(

        Id userId,

        List<FormQuestion> questions

    ) {

        return discoverDataForForm(
            userId,
            questions,
            null
        );

    }

    public static Map<String, DataDiscoveryResult>
    discoverDataForForm(

        Id userId,

        List<FormQuestion> questions,

        Id targetApplicationId

    ) {

        Map<String, DataDiscoveryResult>
            results =
                new Map<String, DataDiscoveryResult>();

        DiscoveryContext context =
            loadDiscoveryContext(
                userId,
                targetApplicationId
            );

        User usr =
            context.usr;

        Contact con =
            context.con;

        Academic_Application__c application =
            context.application;

        for (

            FormQuestion q
            : questions

        ) {

            if (

                q == null ||

                String.isBlank(
                    q.questionId
                )

            ) {

                System.debug(
                    'Skipping AI discovery question with blank questionId.'
                );

                continue;

            }

            DataDiscoveryResult res =
                new DataDiscoveryResult();

            res.questionId =
                q.questionId;

            String label = '';

            if (

                q.questionText != null

            ) {

                label =
                    q.questionText.toLowerCase().trim();

            }

            Boolean matched = false;

            if (

                application != null

            ) {

                matched =
                    applyApplicationAnswer(
                        q,
                        res,
                        application
                    );

            }

            SemanticAnswer semanticAnswer =
                matched
                    ? null
                    : inferSemanticAnswer(
                        q,
                        usr,
                        con
                    );

            if (

                semanticAnswer != null &&

                !String.isBlank(
                    semanticAnswer.value
                )

            ) {

                res.recommendedValue =
                    semanticAnswer.value;

                res.bestMatchConfidence =
                    0.8;

                res.reasoning =
                    semanticAnswer.reasoning;

                res.isMergedAnswer =
                    semanticAnswer.isMergedAnswer;

                if (

                    semanticAnswer.sourceFields != null &&

                    !semanticAnswer.sourceFields.isEmpty()

                ) {

                    res.sourceFields.addAll(
                        semanticAnswer.sourceFields
                    );

                }

                matched = true;

            }

            /*
             * USER FIELDS
             */

            if (

                !matched &&

                isFirstNameQuestion(
                    q
                )

            ) {

                res.recommendedValue =
                    usr.FirstName;

                addResultSource(
                    res,
                    'User.FirstName'
                );

                matched = true;

            }

            else if (

                !matched &&

                isLastNameQuestion(
                    q
                )

            ) {

                res.recommendedValue =
                    usr.LastName;

                addResultSource(
                    res,
                    'User.LastName'
                );

                matched = true;

            }

            else if (

                !matched &&

                isEmailQuestion(
                    q
                )

            ) {

                res.recommendedValue =
                    usr.Email;

                addResultSource(
                    res,
                    'User.Email'
                );

                matched = true;

            }

            else if (

                !matched &&

                isPhoneQuestion(
                    q
                )

            ) {

                res.recommendedValue =
                    firstNonBlank(
                        con != null
                            ? firstNonBlank(
                                con.MobilePhone,
                                con.Phone
                            )
                            : null,
                        usr.Phone
                    );

                addResultSource(
                    res,
                    con != null &&
                        !String.isBlank(
                            firstNonBlank(
                                con.MobilePhone,
                                con.Phone
                            )
                        )
                        ? 'Contact.MobilePhone/Contact.Phone'
                        : 'User.Phone'
                );

                matched = true;

            }

            else if (

                label.contains('street')

            ) {

                res.recommendedValue =
                    firstNonBlank(
                        con != null
                            ? con.MailingStreet
                            : null,
                        usr.Street
                    );

                addResultSource(
                    res,
                    con != null &&
                        !String.isBlank(
                            con.MailingStreet
                        )
                        ? 'Contact.MailingStreet'
                        : 'User.Street'
                );

                matched = true;

            }

            else if (

                label.contains('current address') &&

                label.contains('city')

            ) {

                res.recommendedValue =
                    firstNonBlank(
                        con != null
                            ? con.MailingCity
                            : null,
                        usr.City
                    );

                addResultSource(
                    res,
                    con != null &&
                        !String.isBlank(
                            con.MailingCity
                        )
                        ? 'Contact.MailingCity'
                        : 'User.City'
                );

                matched = true;

            }

            else if (

                label.contains('state/province') ||

                label.contains('province')

            ) {

                res.recommendedValue =
                    firstNonBlank(
                        con != null
                            ? con.MailingState
                            : null,
                        usr.State
                    );

                addResultSource(
                    res,
                    con != null &&
                        !String.isBlank(
                            con.MailingState
                        )
                        ? 'Contact.MailingState'
                        : 'User.State'
                );

                matched = true;

            }

            else if (

                label.contains('postal') ||

                label.contains('zip')

            ) {

                res.recommendedValue =
                    firstNonBlank(
                        con != null
                            ? con.MailingPostalCode
                            : null,
                        usr.PostalCode
                    );

                addResultSource(
                    res,
                    con != null &&
                        !String.isBlank(
                            con.MailingPostalCode
                        )
                        ? 'Contact.MailingPostalCode'
                        : 'User.PostalCode'
                );

                matched = true;

            }

            else if (

                label.contains(
                    'country of birth'
                ) ||

                label.contains(
                    'birth country'
                )

            ) {

                res.recommendedValue =
                    con != null
                        ? extractCountryOfBirth(
                            getContactText(
                                con,
                                'Applicant_Knowledge__c'
                            )
                        )
                        : null;

                if (

                    String.isBlank(
                        res.recommendedValue
                    )

                ) {

                    res.recommendedValue =
                        usr.Country;

                }

                matched = true;

            }

            else if (

                label.equals(
                    'country'
                )

            ) {

                res.recommendedValue =
                    firstNonBlank(
                        con != null
                            ? con.MailingCountry
                            : null,
                        usr.Country
                    );

                addResultSource(
                    res,
                    con != null &&
                        !String.isBlank(
                            con.MailingCountry
                        )
                        ? 'Contact.MailingCountry'
                        : 'User.Country'
                );

                matched = true;

            }

            /*
             * CONTACT FIELDS
             */

            else if (

                con != null

            ) {

                if (

                    label.contains('date of birth')

                ) {

                    if (

                        con.Birthdate != null

                    ) {

                        res.recommendedValue =
                            String.valueOf(
                                con.Birthdate
                            );

                    }

                    matched = true;

                }

                else if (

                    label.contains('gender')

                ) {

                    res.recommendedValue =
                        getContactText(
                            con,
                            'Gender__c'
                        );

                    matched = true;

                }

                else if (

                    label.contains('citizenship')

                ) {

                    res.recommendedValue =
                        getContactText(
                            con,
                            'Citizenship_Status__c'
                        );

                    matched = true;

                }

                else if (

                    label.contains('primary language')

                ) {

                    res.recommendedValue =
                        getContactText(
                            con,
                            'Languages__c'
                        );

                    matched = true;

                }

            }

            /*
             * KNOWLEDGE FIELD
             */

            if (

                !matched &&

                con != null &&

                !String.isBlank(
                    getContactText(
                        con,
                        'Applicant_Knowledge__c'
                    )
                )

            ) {

                String knowledge =
                    getContactText(
                        con,
                        'Applicant_Knowledge__c'
                    );

                String lower =
                    knowledge.toLowerCase();

                /*
                 * GPA
                 */

                if (

                    label.contains(
                        'gpa'
                    )

                ) {

                    res.recommendedValue =
                        extractGpa(
                            knowledge
                        );

                    matched = true;

                }

                /*
                 * GRADUATION DATE
                 */

                else if (

                    label.contains(
                        'graduation'
                    ) &&

                    (

                        label.contains(
                            'date'
                        ) ||

                        label.contains(
                            'expected'
                        )

                    )

                ) {

                    res.recommendedValue =
                        extractGraduationDate(
                            knowledge
                        );

                    matched = true;

                }

                /*
                 * PREFERRED START TERM
                 */

                else if (

                    label.contains(
                        'preferred start term'
                    ) ||

                    (

                        label.contains(
                            'start'
                        ) &&

                        label.contains(
                            'term'
                        )

                    )

                ) {

                    res.recommendedValue =
                        extractStartTerm(
                            knowledge
                        );

                    matched = true;

                }

                /*
                 * RESEARCH INTERESTS
                 */

                else if (

                    label.contains(
                        'research interest'
                    ) ||

                    (

                        label.contains(
                            'research'
                        ) &&

                        label.contains(
                            'interest'
                        )

                    )

                ) {

                    res.recommendedValue =
                        extractResearchInterests(
                            knowledge
                        );

                    matched = true;

                }

                /*
                 * FACULTY ADVISOR NAME
                 */

                else if (

                    label.contains(
                        'faculty advisor'
                    ) ||

                    (

                        label.contains(
                            'advisor'
                        ) &&

                        label.contains(
                            'name'
                        )

                    )

                ) {

                    res.recommendedValue =
                        extractFacultyAdvisorName(
                            knowledge
                        );

                    res.clearValue =
                        String.isBlank(
                            res.recommendedValue
                        );

                    matched = true;

                }

                /*
                 * STATEMENT OF PURPOSE
                 */

                else if (

                    label.contains(
                        'statement of purpose'
                    )

                ) {

                    res.recommendedValue =
                        extractStatementOfPurpose(
                            knowledge
                        );

                    if (

                        String.isBlank(
                            res.recommendedValue
                        )

                    ) {

                        res.recommendedValue =
                            buildStatementOfPurpose(
                                knowledge
                            );

                    }

                    res.clearValue =
                        String.isBlank(
                            res.recommendedValue
                        );

                    matched = true;

                }

                /*
                 * PERSONAL STATEMENT
                 */

                else if (

                    label.contains(
                        'personal statement'
                    ) ||

                    label.contains(
                        'personal essay'
                    ) ||

                    label.contains(
                        'personal motivation'
                    )

                ) {

                    res.recommendedValue =
                        extractPersonalStatement(
                            knowledge
                        );

                    if (

                        String.isBlank(
                            res.recommendedValue
                        )

                    ) {

                        res.recommendedValue =
                            buildPersonalStatement(
                                knowledge
                            );

                    }

                    System.debug(
                        LoggingLevel.INFO,
                        'Personal Statement extracted -> VALUE: ' +
                        res.recommendedValue
                    );

                    res.clearValue =
                        String.isBlank(
                            res.recommendedValue
                        );

                    matched = true;

                }

                /*
                 * FINANCING PLAN
                 */

                else if (

                    label.contains(
                        'financing plan'
                    ) ||

                    (

                        label.contains(
                            'financ'
                        ) &&

                        label.contains(
                            'plan'
                        )

                    )

                ) {

                    res.recommendedValue =
                        extractFinancingPlan(
                            knowledge
                        );

                    matched = true;

                }

                /*
                 * CURRENTLY EMPLOYED
                 */

                else if (

                    label.contains(
                        'currently employed'
                    ) ||

                    (

                        label.contains(
                            'employed'
                        ) &&

                        label.contains(
                            'current'
                        )

                    )

                ) {

                    res.recommendedValue =
                        extractEmploymentStatus(
                            knowledge
                        );

                    matched = true;

                }

                /*
                 * PREVIOUS RESEARCH / PROFESSIONAL EXPERIENCE
                 */

                else if (

                    (

                        label.contains(
                            'previous'
                        ) ||

                        label.contains(
                            'professional'
                        )

                    ) &&

                    label.contains(
                        'experienc'
                    )

                ) {

                    res.recommendedValue =
                        extractPreviousExperience(
                            knowledge
                        );

                    matched = true;

                }

                /*
                 * NEEDED ACCOMMODATIONS
                 */

                else if (

                    label.contains(
                        'accommodation'
                    )

                ) {

                    res.recommendedValue =
                        extractNeededAccommodations(
                            knowledge
                        );

                    matched = true;

                }

                /*
                 * WHY THIS UNIVERSITY
                 */

                else if (

                    label.contains(
                        'why this university'
                    ) ||

                    (

                        label.contains(
                            'why'
                        ) &&

                        label.contains(
                            'university'
                        )

                    )

                ) {

                    res.recommendedValue =
                        extractEssaySection(
                            knowledge,
                            new List<String>{
                                'why this university:',
                                'why this university is',
                                'why this school:',
                                'why this school is',
                                'why this program:',
                                'why this program is'
                            }
                        );

                    if (

                        String.isBlank(
                            res.recommendedValue
                        )

                    ) {

                        res.recommendedValue =
                            buildWhyThisUniversity(
                                knowledge
                            );

                    }

                    res.clearValue =
                        String.isBlank(
                            res.recommendedValue
                        );

                    matched = true;

                }

                /*
                 * THESIS PLAN
                 */

                else if (

                    label.contains(
                        'thesis plan'
                    ) ||

                    (

                        label.contains(
                            'thesis'
                        ) &&

                        label.contains(
                            'plan'
                        )

                    )

                ) {

                    res.recommendedValue =
                        extractThesisPlan(
                            knowledge
                        );

                    matched = true;

                }

                /*
                 * PREFERRED CONTACT METHOD
                 */

                else if (

                    label.contains(
                        'preferred contact method'
                    ) ||

                    (

                        label.contains(
                            'preferred'
                        ) &&

                        label.contains(
                            'contact'
                        ) &&

                        label.contains(
                            'method'
                        )

                    )

                ) {

                    if (

                        lower.contains(
                            'email'
                        ) ||

                        lower.contains(
                            'e-mail'
                        )

                    ) {

                        res.recommendedValue =
                            'Email';

                    }

                    else if (

                        lower.contains(
                            'phone'
                        ) ||

                        lower.contains(
                            'mobile'
                        ) ||

                        lower.contains(
                            'call'
                        ) ||

                        lower.contains(
                            'text'
                        )

                    ) {

                        res.recommendedValue =
                            'Phone';

                    }

                    else if (

                        lower.contains(
                            'mail'
                        ) ||

                        lower.contains(
                            'postal'
                        ) ||

                        lower.contains(
                            'letter'
                        )

                    ) {

                        res.recommendedValue =
                            'Mail';

                    }

                    matched = true;

                }

                /*
                 * HOW DID YOU HEAR ABOUT PROGRAM
                 */

                else if (

                    label.contains(
                        'how did'
                    ) &&

                    label.contains(
                        'hear'
                    ) &&

                    label.contains(
                        'program'
                    )

                ) {

                    if (

                        lower.contains(
                            'search engine'
                        ) ||

                        lower.contains(
                            'google'
                        ) ||

                        lower.contains(
                            'bing'
                        ) ||

                        lower.contains(
                            'online search'
                        )

                    ) {

                        res.recommendedValue =
                            'Search Engine';

                    }

                    else if (

                        lower.contains(
                            'university website'
                        ) ||

                        lower.contains(
                            'school website'
                        ) ||

                        lower.contains(
                            'website'
                        )

                    ) {

                        res.recommendedValue =
                            'University Website';

                    }

                    else if (

                        lower.contains(
                            'social media'
                        ) ||

                        lower.contains(
                            'facebook'
                        ) ||

                        lower.contains(
                            'instagram'
                        ) ||

                        lower.contains(
                            'linkedin'
                        )

                    ) {

                        res.recommendedValue =
                            'Social Media';

                    }

                    else if (

                        lower.contains(
                            'friend'
                        ) ||

                        lower.contains(
                            'family'
                        ) ||

                        lower.contains(
                            'referral'
                        )

                    ) {

                        res.recommendedValue =
                            'Referral';

                    }

                    else if (

                        lower.contains(
                            'education fair'
                        ) ||

                        lower.contains(
                            'college fair'
                        ) ||

                        lower.contains(
                            'career fair'
                        )

                    ) {

                        res.recommendedValue =
                            'Education Fair';

                    }

                    else if (

                        lower.contains(
                            'advertisement'
                        ) ||

                        lower.contains(
                            ' ad '
                        ) ||

                        lower.contains(
                            'advertising'
                        )

                    ) {

                        res.recommendedValue =
                            'Advertisement';

                    }

                    else {

                        res.recommendedValue =
                            'Other';

                    }

                    matched = true;

                }

                /*
                 * PROGRAM APPLYING FOR
                 */

                else if (

                    label.contains(
                        'program applying'
                    )

                ) {

                    if (

                        lower.contains('ms cs')

                    ) {

                        res.recommendedValue =
                            'MS CS';

                    }

                    else if (

                        lower.contains('mba')

                    ) {

                        res.recommendedValue =
                            'MBA';

                    }

                    else if (

                        lower.contains('mph')

                    ) {

                        res.recommendedValue =
                            'MPH';

                    }

                    else if (

                        lower.contains('med')

                    ) {

                        res.recommendedValue =
                            'MEd';

                    }

                    else if (

                        lower.contains('meng')

                    ) {

                        res.recommendedValue =
                            'MEng';

                    }

                    else if (

                        lower.contains(
                            'phd data science'
                        )

                    ) {

                        res.recommendedValue =
                            'PhD Data Science';

                    }

                    else {

                        res.recommendedValue =
                            'Other';

                    }

                    matched = true;

                }

                /*
                 * ENROLLMENT STATUS
                 */

                else if (

                    label.contains(
                        'enrollment'
                    )

                ) {

                    if (

                        lower.contains(
                            'full time'
                        ) ||

                        lower.contains(
                            'full-time'
                        )

                    ) {

                        res.recommendedValue =
                            'Full-time';

                    }

                    else if (

                        lower.contains(
                            'part time'
                        ) ||

                        lower.contains(
                            'part-time'
                        )

                    ) {

                        res.recommendedValue =
                            'Part-time';

                    }

                    matched = true;

                }

                /*
                 * SPECIALIZATION
                 */

                else if (

                    label.contains(
                        'specialization'
                    ) ||

                    label.contains(
                        'concentration'
                    )

                ) {

                    if (

                        lower.contains(
                            'artificial intelligence'
                        ) ||

                        lower.contains(
                            ' ai '
                        )

                    ) {

                        res.recommendedValue =
                            'AI';

                    }

                    else if (

                        lower.contains(
                            'cybersecurity'
                        )

                    ) {

                        res.recommendedValue =
                            'Cybersecurity';

                    }

                    else if (

                        lower.contains(
                            'data science'
                        )

                    ) {

                        res.recommendedValue =
                            'Data Science';

                    }

                    matched = true;

                }

                /*
                 * FIELD OF STUDY
                 */

                else if (

                    label.contains(
                        'field of study'
                    )

                ) {

                    Pattern p =
                        Pattern.compile(
                            '(?i)degree in\\s+([A-Za-z\\s]+?)\\s+from'
                        );

                    Matcher m =
                        p.matcher(knowledge);

                    if (

                        m.find()

                    ) {

                        res.recommendedValue =
                            m.group(1).trim();

                    }

                    matched = true;

                }

                /*
                 * HIGHEST LEVEL OF EDUCATION
                 */

                else if (

                    label.contains(
                        'highest level of education'
                    )

                ) {

                    if (

                        lower.contains(
                            'bachelor'
                        )

                    ) {

                        res.recommendedValue =
                            'Bachelor\'s';

                    }

                    else if (

                        lower.contains(
                            'master'
                        )

                    ) {

                        res.recommendedValue =
                            'Master\'s';

                    }

                    else if (

                        lower.contains(
                            'doctor'
                        ) ||

                        lower.contains(
                            'phd'
                        )

                    ) {

                        res.recommendedValue =
                            'Doctoral';

                    }

                    else if (

                        lower.contains(
                            'associate'
                        )

                    ) {

                        res.recommendedValue =
                            'Associate';

                    }

                    else {

                        res.recommendedValue =
                            'High School';

                    }

                    matched = true;

                }

                /*
                 * GRE VERBAL
                 */

                else if (

                    label.contains(
                        'gre verbal'
                    )

                ) {

                    Pattern p =
                        Pattern.compile(
                            '(?i)gre verbal score is\\s*(\\d{2,3})'
                        );

                    Matcher m =
                        p.matcher(knowledge);

                    if (

                        m.find()

                    ) {

                        res.recommendedValue =
                            m.group(1);

                    }

                    matched = true;

                }

                /*
                 * GRE QUANT
                 */

                else if (

                    label.contains(
                        'gre quant'
                    )

                ) {

                    Pattern p =
                        Pattern.compile(
                            '(?i)gre quant score is\\s*(\\d{2,3})'
                        );

                    Matcher m =
                        p.matcher(knowledge);

                    if (

                        m.find()

                    ) {

                        res.recommendedValue =
                            m.group(1);

                    }

                    matched = true;

                }

                /*
                 * MOST RECENT INSTITUTION
                 */

                else if (

                    label.contains(
                        'most recent institution'
                    ) ||

                    (

                        label.contains(
                            'institution'
                        ) &&

                        !label.contains(
                            'city'
                        ) &&

                        !label.contains(
                            'country'
                        )

                    )

                ) {

                    res.recommendedValue =
                        extractInstitutionName(
                            knowledge
                        );

                    matched = true;

                }

                /*
                 * CITY OF INSTITUTION
                 */

                else if (

                    label.contains(
                        'city of institution'
                    )

                ) {

                    if (

                        lower.contains(
                            'hyderabad'
                        )

                    ) {

                        res.recommendedValue =
                            'Hyderabad';

                    }

                    else if (

                        lower.contains(
                            'bangalore'
                        )

                    ) {

                        res.recommendedValue =
                            'Bangalore';

                    }

                    else if (

                        lower.contains(
                            'chennai'
                        )

                    ) {

                        res.recommendedValue =
                            'Chennai';

                    }

                    matched = true;

                }

                /*
                 * COUNTRY OF INSTITUTION
                 */

                else if (

                    label.contains(
                        'country of institution'
                    )

                ) {

                    if (

                        lower.contains(
                            'india'
                        )

                    ) {

                        res.recommendedValue =
                            'India';

                    }

                    else if (

                        lower.contains(
                            'canada'
                        )

                    ) {

                        res.recommendedValue =
                            'Canada';

                    }

                    else if (

                        lower.contains(
                            'united kingdom'
                        )

                    ) {

                        res.recommendedValue =
                            'United Kingdom';

                    }

                    else if (

                        lower.contains(
                            'china'
                        )

                    ) {

                        res.recommendedValue =
                            'China';

                    }

                    else if (

                        lower.contains(
                            'united states'
                        ) ||

                        lower.contains(
                            'usa'
                        )

                    ) {

                        res.recommendedValue =
                            'United States';

                    }

                    else {

                        res.recommendedValue =
                            'Other';

                    }

                    matched = true;

                }

                /*
                 * COMPETITIVE EXAMS
                 */

                else if (

                    label.contains(
                        'competitive exams'
                    )

                ) {

                    Pattern p =
                        Pattern.compile(
                            '(?i)have taken\\s+([A-Za-z\\s,]+?)\\s+examinations'
                        );

                    Matcher m =
                        p.matcher(knowledge);

                    if (

                        m.find()

                    ) {

                        String exams =
                            m.group(1).trim();

                        exams =
                            exams.replace(
                                ' and ',
                                ', '
                            );

                        res.recommendedValue =
                            exams;

                    }

                    matched = true;

                }

                if (

                    !matched

                ) {

                    res.recommendedValue =
                        inferGenericKnowledgeAnswer(
                            q.questionText,
                            q.questionType,
                            q.picklistValues,
                            knowledge
                        );

                    matched =
                        !String.isBlank(
                            res.recommendedValue
                        );

                    if (

                        matched

                    ) {

                        res.bestMatchConfidence =
                            0.65;

                        res.reasoning =
                            'Generic metadata question inference from applicant knowledge';

                    }

                }

            }

            if (

                !String.isBlank(
                    res.recommendedValue
                ) ||

                res.clearValue == true

            ) {

                if (

                    res.clearValue == true

                ) {

                    System.debug(
                        'CLEAR -> QUESTION: ' +

                        q.questionText
                    );

                }

                else {

                    System.debug(
                        'SUCCESS -> QUESTION: ' +

                        q.questionText +

                        ' | VALUE: ' +

                        res.recommendedValue
                    );

                }

                if (

                    res.clearValue != true

                ) {

                    if (

                        res.bestMatchConfidence == null

                    ) {

                        res.bestMatchConfidence =
                            0.95;

                    }

                    if (

                        String.isBlank(
                            res.reasoning
                        )

                    ) {

                        res.reasoning =
                            'Dynamic Salesforce field mapping';

                    }

                }

                else {

                    res.bestMatchConfidence =
                        0;

                    res.reasoning =
                        'No valid faculty advisor name found; clearing stale invalid value';

                }

                addExplanationMetadata(
                    res,
                    usr,
                    con
                );

                results.put(
                    q.questionId,
                    res
                );

            }

            else {

                System.debug(
                    'FAILED -> QUESTION: ' +

                    q.questionText +

                    ' | VALUE NOT FOUND'
                );

            }

        }

        return results;

    }

    private static String extractGraduationDate(

        String knowledge

    ) {

        if (

            String.isBlank(
                knowledge
            )

        ) {

            return null;

        }

        Matcher isoMatcher =
            Pattern.compile(
                '(\\d{4})-(\\d{1,2})-(\\d{1,2})'
            ).matcher(
                knowledge
            );

        if (

            isoMatcher.find()

        ) {

            return formatDate(
                Integer.valueOf(
                    isoMatcher.group(1)
                ),
                Integer.valueOf(
                    isoMatcher.group(2)
                ),
                Integer.valueOf(
                    isoMatcher.group(3)
                )
            );

        }

        Matcher slashMatcher =
            Pattern.compile(
                '(\\d{1,2})/(\\d{1,2})/(\\d{4})'
            ).matcher(
                knowledge
            );

        if (

            slashMatcher.find()

        ) {

            return formatDate(
                Integer.valueOf(
                    slashMatcher.group(3)
                ),
                Integer.valueOf(
                    slashMatcher.group(1)
                ),
                Integer.valueOf(
                    slashMatcher.group(2)
                )
            );

        }

        Matcher monthMatcher =
            Pattern.compile(
                '(?i)(jan(?:uary)?|feb(?:ruary)?|mar(?:ch)?|apr(?:il)?|may|jun(?:e)?|jul(?:y)?|aug(?:ust)?|sep(?:tember)?|sept(?:ember)?|oct(?:ober)?|nov(?:ember)?|dec(?:ember)?)\\s+(?:(\\d{1,2}),\\s*)?(\\d{4})'
            ).matcher(
                knowledge
            );

        if (

            monthMatcher.find()

        ) {

            Integer year =
                Integer.valueOf(
                    monthMatcher.group(3)
                );

            Integer month =
                monthNameToNumber(
                    monthMatcher.group(1)
                );

            Integer day;

            if (

                String.isBlank(
                    monthMatcher.group(2)
                )

            ) {

                day =
                    Date.daysInMonth(
                        year,
                        month
                    );

            }

            else {

                day =
                    Integer.valueOf(
                        monthMatcher.group(2)
                    );

            }

            return formatDate(
                year,
                month,
                day
            );

        }

        Matcher seasonMatcher =
            Pattern.compile(
                '(?i)(spring|summer|fall|autumn|winter)\\s+(\\d{4})'
            ).matcher(
                knowledge
            );

        if (

            seasonMatcher.find()

        ) {

            Integer year =
                Integer.valueOf(
                    seasonMatcher.group(2)
                );

            String season =
                seasonMatcher.group(1).toLowerCase();

            if (

                season == 'spring'

            ) {

                return formatDate(
                    year,
                    5,
                    31
                );

            }

            if (

                season == 'summer'

            ) {

                return formatDate(
                    year,
                    8,
                    31
                );

            }

            return formatDate(
                year,
                12,
                31
            );

        }

        return null;

    }

    private static String extractCountryOfBirth(

        String knowledge

    ) {

        if (

            String.isBlank(
                knowledge
            )

        ) {

            return null;

        }

        List<Pattern> patterns =
            new List<Pattern>{
                Pattern.compile(
                    '(?i)\\bcountry of birth\\b\\s*(?:is|:|=|-)?\\s*([A-Za-z\\s]+?)(?:\\.|,|;|\\n|$)'
                ),
                Pattern.compile(
                    '(?i)\\bbirth country\\b\\s*(?:is|:|=|-)?\\s*([A-Za-z\\s]+?)(?:\\.|,|;|\\n|$)'
                ),
                Pattern.compile(
                    '(?i)\\bI\\s+was\\s+born\\s+in\\s+([A-Za-z\\s]+?)(?:\\.|,|;|\\n|$)'
                ),
                Pattern.compile(
                    '(?i)\\bborn\\s+in\\s+([A-Za-z\\s]+?)(?:\\.|,|;|\\n|$)'
                )
            };

        for (

            Pattern p
            : patterns

        ) {

            Matcher m =
                p.matcher(
                    knowledge
                );

            if (

                m.find()

            ) {

                return normalizeCountryName(
                    m.group(1)
                );

            }

        }

        return null;

    }

    private static String normalizeCountryName(

        String country

    ) {

        if (

            String.isBlank(
                country
            )

        ) {

            return null;

        }

        String cleaned =
            country.trim();

        String lower =
            cleaned.toLowerCase();

        if (

            lower == 'usa' ||

            lower == 'u.s.a' ||

            lower == 'us' ||

            lower == 'u.s.' ||

            lower == 'united states of america'

        ) {

            return 'United States';

        }

        if (

            lower == 'uk' ||

            lower == 'u.k.' ||

            lower == 'great britain'

        ) {

            return 'United Kingdom';

        }

        return cleaned;

    }

    private static String extractStartTerm(

        String knowledge

    ) {

        if (

            String.isBlank(
                knowledge
            )

        ) {

            return null;

        }

        Matcher termMatcher =
            Pattern.compile(
                '(?i)(fall|spring|summer)\\s+(2026|2027)'
            ).matcher(
                knowledge
            );

        if (

            termMatcher.find()

        ) {

            return capitalizeTerm(
                termMatcher.group(1)
            ) +
            ' ' +
            termMatcher.group(2);

        }

        return null;

    }

    private static String capitalizeTerm(

        String term

    ) {

        String lowerTerm =
            term.toLowerCase();

        return lowerTerm.left(
            1
        ).toUpperCase() +
        lowerTerm.substring(
            1
        );

    }

    private static String extractResearchInterests(

        String knowledge

    ) {

        if (

            String.isBlank(
                knowledge
            )

        ) {

            return null;

        }

        List<Pattern> patterns =
            new List<Pattern>{
                Pattern.compile(
                    '(?i)\\bresearch interests?\\b\\s*(?:include|includes|are|is|:|=|-)?\\s*([^.;\\n]+)'
                ),
                Pattern.compile(
                    '(?i)\\b(?:research area|research focus)\\b\\s*(?:include|includes|are|is|:|=|-)?\\s*([^.;\\n]+)'
                ),
                Pattern.compile(
                    '(?i)\\binterested in\\s+(?:researching\\s+)?([^.;\\n]+)'
                )
            };

        for (

            Pattern p
            : patterns

        ) {

            Matcher m =
                p.matcher(
                    knowledge
                );

            if (

                m.find()

            ) {

                return cleanResearchInterests(
                    m.group(1)
                );

            }

        }

        return null;

    }

    private static String extractThesisPlan(

        String knowledge

    ) {

        if (

            String.isBlank(
                knowledge
            )

        ) {

            return null;

        }

        String lower =
            knowledge.toLowerCase();

        if (

            lower.contains(
                'non-thesis'
            ) ||

            lower.contains(
                'non thesis'
            ) ||

            lower.contains(
                'without thesis'
            ) ||

            lower.contains(
                'no thesis'
            )

        ) {

            return 'Non-thesis';

        }

        if (

            lower.contains(
                'thesis'
            ) ||

            lower.contains(
                'research track'
            ) ||

            lower.contains(
                'research option'
            )

        ) {

            return 'Thesis';

        }

        if (

            lower.contains(
                'undecided'
            )

            ||

            lower.contains(
                'not decided'
            ) ||

            lower.contains(
                'unsure'
            ) ||

            lower.contains(
                'not sure'
            )

        ) {

            return 'Undecided';

        }

        return null;

    }

    private static String extractEssaySection(

        String knowledge,

        List<String> labels

    ) {

        if (

            String.isBlank(
                knowledge
            ) ||

            labels == null ||

            labels.isEmpty()

        ) {

            return null;

        }

        for (

            String labelText
            : labels

        ) {

            Matcher m =
                Pattern.compile(
                    '(?is)\\b' +
                    labelText +
                    '\\s*(?:=|-)?\\s*(.+)'
                ).matcher(
                    knowledge
                );

            if (

                m.find()

            ) {

                return cleanEssayText(
                    m.group(1)
                );

            }

        }

        return null;

    }

    private static String buildStatementOfPurpose(

        String knowledge

    ) {

        if (

            String.isBlank(
                knowledge
            )

        ) {

            return null;

        }

        String researchInterests =
            extractResearchInterests(
                knowledge
            );

        String program =
            null;

        String lower =
            knowledge.toLowerCase();

        if (

            lower.contains(
                'education technology'
            )

        ) {

            program =
                'education technology and intelligent academic systems';

        }

        else if (

            lower.contains(
                'data science'
            )

        ) {

            program =
                'data science';

        }

        else if (

            lower.contains(
                'cybersecurity'
            )

        ) {

            program =
                'cybersecurity';

        }

        else {

            program =
                'my chosen graduate field';

        }

        String statement =
            'My purpose in pursuing graduate study is to strengthen my expertise in ' +
            program +
            ' and apply that knowledge to meaningful academic and professional work.';

        if (

            !String.isBlank(
                researchInterests
            )

        ) {

            statement +=
                ' My interests include ' +
                researchInterests +
                '.';

        }

        statement +=
            ' I hope to build advanced technical, analytical, and research skills that will help me contribute to innovative, secure, and student-centered learning environments.';

        return statement;

    }

    private static String extractStatementOfPurpose(

        String knowledge

    ) {

        String explicitStatement =
            extractEssaySection(
                knowledge,
                new List<String>{
                    'statement of purpose:',
                    'statement of purpose is',
                    'purpose statement:',
                    'purpose statement is',
                    'sop:',
                    'sop is'
                }
            );

        if (

            isMeaningfulEssayValue(
                explicitStatement
            )

        ) {

            return explicitStatement;

        }

        if (

            String.isBlank(
                knowledge
            )

        ) {

            return null;

        }

        String statementParagraph =
            extractParagraphContaining(
                knowledge,
                new List<String>{
                    'statement of purpose',
                    'purpose statement',
                    'sop'
                }
            );

        if (

            !String.isBlank(
                statementParagraph
            )

        ) {

            return cleanStatementOfPurposeText(
                statementParagraph
            );

        }

        return buildStatementOfPurpose(
            knowledge
        );

    }

    private static String extractPersonalStatement(

        String knowledge

    ) {

        String explicitStatement =
            extractEssaySection(
                knowledge,
                new List<String>{
                    'personal statement:',
                    'personal statement is',
                    'personal essay:',
                    'personal essay is',
                    'personal background:',
                    'personal background is',
                    'personal motivation:',
                    'personal motivation is'
                }
            );

        if (

            isMeaningfulEssayValue(
                explicitStatement
            )

        ) {

            return explicitStatement;

        }

        String experienceParagraph =
            null;

        for (

            String marker
            : new List<String>{
                'through internships',
                'gained experience',
                'software development projects',
                'academic and professional',
                'professional experience',
                'currently employed'
            }

        ) {

            experienceParagraph =
                extractParagraphContaining(
                    knowledge,
                    new List<String>{
                        marker
                    }
                );

            if (

                !String.isBlank(
                    experienceParagraph
                )

            ) {

                break;

            }

        }

        if (

            !String.isBlank(
                experienceParagraph
            )

        ) {

            String cleanedExperience =
                cleanEssayText(
                    experienceParagraph
                );

            if (

                isMeaningfulEssayValue(
                    cleanedExperience
                )

            ) {

                return cleanedExperience;

            }

        }

        return buildPersonalStatement(
            knowledge
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

            // Admin-only questions must come from the selected application,
            // not from a synthesized Contact/User fallback.
            return true;

        }

        String normalizedValue =
            normalizeQuestionText(
                value
            );

        if (

            normalizedValue.length() < 80

        ) {

            return false;

        }

        return normalizedValue.split(
            '\\s+'
        ).size() >= 12;

    }

    private static String extractParagraphContaining(

        String text,

        List<String> markers

    ) {

        if (

            String.isBlank(
                text
            ) ||

            markers == null ||

            markers.isEmpty()

        ) {

            return null;

        }

        List<String> paragraphs =
            text.split(
                '\\n\\s*\\n'
            );

        for (

            String paragraph
            : paragraphs

        ) {

            String lowerParagraph =
                paragraph.toLowerCase();

            for (

                String marker
                : markers

            ) {

                if (

                    lowerParagraph.contains(
                        marker
                    )

                ) {

                    return paragraph.trim();

                }

            }

        }

        return null;

    }

    private static String cleanStatementOfPurposeText(

        String text

    ) {

        String cleaned =
            cleanExtractedText(
                text
            );

        if (

            String.isBlank(
                cleaned
            )

        ) {

            return null;

        }

        cleaned =
            normalizeStatementOfPurposeOpening(
                cleaned
            );

        List<String> stopMarkers =
            new List<String>{
                'personal statement',
                'thesis plan',
                'research interests',
                'faculty advisor',
                'advisor name',
                'potential faculty advisor',
                'potential advisor',
                'preferred start term',
                'preferred contact method',
                'how did you hear',
                'competitive exams'
            };

        for (

            String marker
            : stopMarkers

        ) {

            Matcher markerMatcher =
                Pattern.compile(
                    '(?i)(?:^|\\s)' +
                    marker +
                    '\\b\\s*(?:is|:|=|-)?'
                ).matcher(
                    cleaned
                );

            if (

                markerMatcher.find() &&

                markerMatcher.start() > 0

            ) {

                cleaned =
                    cleaned.left(
                        markerMatcher.start()
                    ).trim();

            }

        }

        return cleanExtractedText(
            cleaned
        );

    }

    private static String normalizeStatementOfPurposeOpening(

        String text

    ) {

        if (

            String.isBlank(
                text
            )

        ) {

            return null;

        }

        String cleaned =
            text.trim();

        List<Pattern> patterns =
            new List<Pattern>{
                Pattern.compile(
                    '(?i)^my statement of purpose focuses on\\s+(.+)'
                ),
                Pattern.compile(
                    '(?i)^the statement of purpose focuses on\\s+(.+)'
                ),
                Pattern.compile(
                    '(?i)^this statement of purpose focuses on\\s+(.+)'
                )
            };

        for (

            Pattern p
            : patterns

        ) {

            Matcher m =
                p.matcher(
                    cleaned
                );

            if (

                m.find()

            ) {

                return 'I am focused on ' +
                    m.group(1).trim();

            }

        }

        return cleaned;

    }

    private static String buildPersonalStatement(

        String knowledge

    ) {

        if (

            String.isBlank(
                knowledge
            )

        ) {

            return null;

        }

        String experience =
            extractExperienceSummary(
                knowledge
            );

        String statement =
            'My academic and professional journey has shaped my commitment to using technology to solve meaningful problems.';

        if (

            !String.isBlank(
                experience
            )

        ) {

            statement +=
                ' ' +
                experience +
                '.';

        }

        statement +=
            ' These experiences have strengthened my curiosity, resilience, and desire to continue growing as a graduate student. I am motivated to contribute thoughtfully to the academic community while developing the skills needed to create practical, responsible, and impactful technology solutions.';

        return statement;

    }

    private static String buildWhyThisUniversity(

        String knowledge

    ) {

        if (

            String.isBlank(
                knowledge
            )

        ) {

            return null;

        }

        String lower =
            knowledge.toLowerCase();

        List<String> reasons =
            new List<String>();

        if (

            lower.contains(
                'faculty'
            )

        ) {

            reasons.add(
                'experienced faculty'
            );

        }

        if (

            lower.contains(
                'research opportunit'
            ) ||

            lower.contains(
                'research'
            )

        ) {

            reasons.add(
                'strong research opportunities'
            );

        }

        if (

            lower.contains(
                'education technology'
            ) ||

            lower.contains(
                'intelligent learning'
            ) ||

            lower.contains(
                'digital education'
            )

        ) {

            reasons.add(
                'alignment with my interests in education technology and intelligent learning systems'
            );

        }

        if (

            lower.contains(
                'cloud'
            ) ||

            lower.contains(
                'data-driven'
            ) ||

            lower.contains(
                'cybersecurity'
            )

        ) {

            reasons.add(
                'opportunities to grow in secure, data-driven, and cloud-based academic technologies'
            );

        }

        if (

            reasons.isEmpty()

        ) {

            return null;

        }

        return 'I am interested in this university because it offers ' +
            joinReasons(
                reasons
            ) +
            '. These strengths make the university a strong fit for my academic goals and my long-term interest in building practical technology solutions that improve student learning and institutional outcomes.';

    }

    private static String extractPreviousExperience(

        String knowledge

    ) {

        String explicitExperience =
            extractEssaySection(
                knowledge,
                new List<String>{
                    'previous research/professional experience:',
                    'previous research experience:',
                    'professional experience:',
                    'previous experience:',
                    'research experience:'
                }
            );

        if (

            !String.isBlank(
                explicitExperience
            )

        ) {

            return explicitExperience;

        }

        String experience =
            extractExperienceSummary(
                knowledge
            );

        if (

            String.isBlank(
                experience
            )

        ) {

            experience =
                buildExperienceFromKeywords(
                    knowledge
                );

        }

        if (

            String.isBlank(
                experience
            )

        ) {

            return null;

        }

        return 'My previous research and professional experience includes ' +
            normalizeExperienceLead(
                experience
            ) +
            '. This background has helped me build practical skills in technical problem solving, collaboration, and applying technology to education-focused systems.';

    }

    private static String extractEmploymentStatus(

        String knowledge

    ) {

        if (

            String.isBlank(
                knowledge
            )

        ) {

            return null;

        }

        String lower =
            knowledge.toLowerCase();

        if (

            lower.contains(
                'not currently employed'
            ) ||

            lower.contains(
                'currently not employed'
            ) ||

            lower.contains(
                'unemployed'
            ) ||

            lower.contains(
                'not employed'
            )

        ) {

            return 'No';

        }

        if (

            lower.contains(
                'full-time'
            ) ||

            lower.contains(
                'full time'
            ) ||

            lower.contains(
                'fulltime'
            )

        ) {

            return 'Yes - Full time';

        }

        if (

            lower.contains(
                'part-time'
            ) ||

            lower.contains(
                'part time'
            ) ||

            lower.contains(
                'parttime'
            )

        ) {

            return 'Yes - Part time';

        }

        if (

            lower.contains(
                'currently employed'
            ) ||

            lower.contains(
                'employed'
            ) ||

            lower.contains(
                'working as'
            ) ||

            lower.contains(
                'work as'
            )

        ) {

            return 'Yes - Full time';

        }

        return null;

    }

    private static String extractFinancingPlan(

        String knowledge

    ) {

        if (

            String.isBlank(
                knowledge
            )

        ) {

            return null;

        }

        String lower =
            knowledge.toLowerCase();

        Integer fundingSignals = 0;

        if (

            lower.contains(
                'personal fund'
            ) ||

            lower.contains(
                'self fund'
            ) ||

            lower.contains(
                'savings'
            )

        ) {

            fundingSignals++;

        }

        if (

            lower.contains(
                'family support'
            ) ||

            lower.contains(
                'family'
            ) ||

            lower.contains(
                'parents'
            )

        ) {

            fundingSignals++;

        }

        if (

            lower.contains(
                'scholarship'
            ) ||

            lower.contains(
                'fellowship'
            )

        ) {

            fundingSignals++;

        }

        if (

            lower.contains(
                'student loan'
            ) ||

            lower.contains(
                'education loan'
            ) ||

            lower.contains(
                'loan'
            )

        ) {

            fundingSignals++;

        }

        if (

            lower.contains(
                'employer sponsorship'
            ) ||

            lower.contains(
                'employer sponsor'
            ) ||

            lower.contains(
                'company sponsorship'
            )

        ) {

            fundingSignals++;

        }

        if (

            lower.contains(
                'combination'
            ) ||

            fundingSignals > 1

        ) {

            return 'Combination';

        }

        if (

            lower.contains(
                'personal fund'
            ) ||

            lower.contains(
                'self fund'
            ) ||

            lower.contains(
                'savings'
            )

        ) {

            return 'Personal Funds';

        }

        if (

            lower.contains(
                'family support'
            ) ||

            lower.contains(
                'family'
            ) ||

            lower.contains(
                'parents'
            )

        ) {

            return 'Family Support';

        }

        if (

            lower.contains(
                'scholarship'
            ) ||

            lower.contains(
                'fellowship'
            )

        ) {

            return 'Scholarships/Fellowships';

        }

        if (

            lower.contains(
                'student loan'
            ) ||

            lower.contains(
                'education loan'
            ) ||

            lower.contains(
                'loan'
            )

        ) {

            return 'Student Loans';

        }

        if (

            lower.contains(
                'employer sponsorship'
            ) ||

            lower.contains(
                'employer sponsor'
            ) ||

            lower.contains(
                'company sponsorship'
            )

        ) {

            return 'Employer Sponsorship';

        }

        if (

            lower.contains(
                'other funding'
            ) ||

            lower.contains(
                'other financing'
            )

        ) {

            return 'Other';

        }

        return null;

    }

    private static String extractNeededAccommodations(

        String knowledge

    ) {

        String explicitAccommodations =
            extractEssaySection(
                knowledge,
                new List<String>{
                    'needed accommodations:',
                    'needed accommodations are',
                    'accommodations needed:',
                    'accommodations needed are',
                    'accommodation support for',
                    'accommodations support for',
                    'require accommodation support for',
                    'requires accommodation support for',
                    'accommodations:',
                    'accommodations are',
                    'special accommodations:',
                    'special accommodations are'
                }
            );

        if (

            !String.isBlank(
                explicitAccommodations
            )

        ) {

            return explicitAccommodations;

        }

        Matcher supportMatcher =
            Pattern.compile(
                '(?i)(?:require|requires|need|needs)?\\s*accommodations? support for\\s+([^.;\\n]+)'
            ).matcher(
                knowledge
            );

        if (

            supportMatcher.find()

        ) {

            return cleanExtractedText(
                supportMatcher.group(1)
            );

        }

        if (

            String.isBlank(
                knowledge
            )

        ) {

            return null;

        }

        String lower =
            knowledge.toLowerCase();

        if (

            lower.contains(
                'no accommodations'
            ) ||

            lower.contains(
                'no accommodation'
            ) ||

            lower.contains(
                'do not need accommodations'
            ) ||

            lower.contains(
                'does not need accommodations'
            ) ||

            lower.contains(
                'not requesting accommodations'
            ) ||

            lower.contains(
                'no special accommodations'
            )

        ) {

            return 'No accommodations requested.';

        }

        return 'No accommodations requested.';

    }

    private static String buildExperienceFromKeywords(

        String knowledge

    ) {

        if (

            String.isBlank(
                knowledge
            )

        ) {

            return null;

        }

        String lower =
            knowledge.toLowerCase();

        List<String> items =
            new List<String>();

        if (

            lower.contains(
                'internship'
            )

        ) {

            items.add(
                'internships'
            );

        }

        if (

            lower.contains(
                'software development project'
            ) ||

            lower.contains(
                'projects'
            )

        ) {

            items.add(
                'software development projects'
            );

        }

        if (

            lower.contains(
                'enterprise education platform'
            )

        ) {

            items.add(
                'enterprise education platforms'
            );

        }

        if (

            lower.contains(
                'automation tool'
            )

        ) {

            items.add(
                'automation tools'
            );

        }

        if (

            lower.contains(
                'cloud'
            )

        ) {

            items.add(
                'cloud technologies'
            );

        }

        if (

            items.isEmpty()

        ) {

            return null;

        }

        return 'experience with ' +
            joinReasons(
                items
            );

    }

    private static String normalizeExperienceLead(

        String experience

    ) {

        if (

            String.isBlank(
                experience
            )

        ) {

            return null;

        }

        String normalized =
            experience.trim();

        String lower =
            normalized.toLowerCase();

        if (

            lower.startsWith(
                'through '
            )

        ) {

            Integer commaIndex =
                normalized.indexOf(
                    ','
                );

            if (

                commaIndex > -1 &&

                commaIndex + 1 < normalized.length()

            ) {

                normalized =
                    normalized.substring(
                        commaIndex + 1
                    ).trim();

            }

        }

        if (

            normalized.toLowerCase().startsWith(
                'i gained experience'
            )

        ) {

            normalized =
                normalized.substring(
                    20
                ).trim();

        }

        if (

            normalized.toLowerCase().startsWith(
                'working with'
            )

        ) {

            return normalized;

        }

        return normalized;

    }

    private static String joinReasons(

        List<String> reasons

    ) {

        if (

            reasons == null ||

            reasons.isEmpty()

        ) {

            return '';

        }

        if (

            reasons.size() == 1

        ) {

            return reasons[0];

        }

        if (

            reasons.size() == 2

        ) {

            return reasons[0] +
                ' and ' +
                reasons[1];

        }

        String result =
            '';

        for (

            Integer i = 0;
            i < reasons.size();
            i++

        ) {

            if (

                i == reasons.size() - 1

            ) {

                result +=
                    'and ' +
                    reasons[i];

            }

            else {

                result +=
                    reasons[i] +
                    ', ';

            }

        }

        return result;

    }

    private static String extractExperienceSummary(

        String knowledge

    ) {

        if (

            String.isBlank(
                knowledge
            )

        ) {

            return null;

        }

        List<Pattern> patterns =
            new List<Pattern>{
                Pattern.compile(
                    '(?i)(through internships[^.]+)'
                ),
                Pattern.compile(
                    '(?i)(through software development projects[^.]+)'
                ),
                Pattern.compile(
                    '(?i)(i gained experience[^.]+)'
                ),
                Pattern.compile(
                    '(?i)(my experience includes[^.]+)'
                )
            };

        for (

            Pattern p
            : patterns

        ) {

            Matcher m =
                p.matcher(
                    knowledge
                );

            if (

                m.find()

            ) {

                return cleanExtractedText(
                    m.group(1)
                );

            }

        }

        return null;

    }

    private static String cleanEssayText(

        String text

    ) {

        String cleaned =
            cleanExtractedText(
                text
            );

        if (

            String.isBlank(
                cleaned
            )

        ) {

            return null;

        }

        List<String> stopMarkers =
            new List<String>{
                'personal statement',
                'statement of purpose',
                'thesis plan',
                'research interests',
                'faculty advisor',
                'advisor name',
                'potential faculty advisor',
                'potential advisor',
                'i identified dr',
                'i identified professor',
                'identified dr',
                'identified professor',
                'i want to work with dr',
                'i want to work with professor',
                'preferred start term',
                'preferred contact method',
                'how did you hear',
                'competitive exams'
            };

        for (

            String marker
            : stopMarkers

        ) {

            Matcher markerMatcher =
                Pattern.compile(
                    '(?i)(?:^|\\s)' +
                    marker +
                    '\\b\\s*(?:is|:|=|-)?'
                ).matcher(
                    cleaned
                );

            if (

                markerMatcher.find() &&

                markerMatcher.start() > 0

            ) {

                cleaned =
                    cleaned.left(
                        markerMatcher.start()
                    ).trim();

            }

        }

        return cleanExtractedText(
            cleaned
        );

    }

    private static String cleanResearchInterests(

        String text

    ) {

        String cleaned =
            cleanExtractedText(
                text
            );

        if (

            String.isBlank(
                cleaned
            )

        ) {

            return null;

        }

        List<String> stopPhrases =
            new List<String>{
                ' through internships',
                ' through internship',
                ' during internships',
                ' during internship',
                ' i gained',
                ' i have gained',
                ' my experience',
                ' experience working',
                ' projects, i',
                ' this experience'
            };

        String lowerCleaned =
            cleaned.toLowerCase();

        for (

            String stopPhrase
            : stopPhrases

        ) {

            Integer stopIndex =
                lowerCleaned.indexOf(
                    stopPhrase
                );

            if (

                stopIndex > -1

            ) {

                cleaned =
                    cleaned.left(
                        stopIndex
                    ).trim();

                lowerCleaned =
                    cleaned.toLowerCase();

            }

        }

        if (

            lowerCleaned.startsWith(
                'include '
            )

        ) {

            cleaned =
                cleaned.substring(
                    8
                ).trim();

        }

        if (

            lowerCleaned.startsWith(
                'includes '
            )

        ) {

            cleaned =
                cleaned.substring(
                    9
                ).trim();

        }

        return cleanExtractedText(
            cleaned
        );

    }

    private static String extractTextAfterLabels(

        String knowledge,

        List<String> labels

    ) {

        if (

            String.isBlank(
                knowledge
            ) ||

            labels == null ||

            labels.isEmpty()

        ) {

            return null;

        }

        for (

            String marker
            : labels

        ) {

            Pattern p =
                Pattern.compile(
                    '(?i)\\b' +
                    marker +
                    '\\b\\s*(?:is|are|:|=|-)?\\s*([^;\\n]+)'
                );

            Matcher m =
                p.matcher(
                    knowledge
                );

            if (

                m.find()

            ) {

                return cleanExtractedText(
                    m.group(1)
                );

            }

        }

        return null;

    }

    private static String extractFacultyAdvisorName(

        String knowledge

    ) {

        if (

            String.isBlank(
                knowledge
            )

        ) {

            return null;

        }

        List<Pattern> patterns =
            new List<Pattern>{
                Pattern.compile(
                    '(?i:\\b(?:faculty advisor name|faculty advisor|advisor name|advisor|mentor)\\b)\\s*(?:is|:|=|-)?\\s*((?:Dr\\.?|Prof\\.?|Professor)?\\s*[A-Z][A-Za-z.\\-]+(?:\\s+[A-Z][A-Za-z.\\-]+){0,3})'
                ),
                Pattern.compile(
                    '(?i:\\b(?:work with|working with|advised by|supervised by)\\b)\\s+((?:Dr\\.?|Prof\\.?|Professor)?\\s*[A-Z][A-Za-z.\\-]+(?:\\s+[A-Z][A-Za-z.\\-]+){0,3})'
                ),
                Pattern.compile(
                    '((?:Dr\\.?|Prof\\.?|Professor)\\s+[A-Z][A-Za-z.\\-]+(?:\\s+[A-Z][A-Za-z.\\-]+){0,3})\\s+(?i:\\b(?:as|for|to be)?\\s*(?:my\\s+)?(?:faculty\\s+)?advisor\\b)'
                ),
                Pattern.compile(
                    '(?i:\\b(?:faculty\\s+)?advisor\\b).*?((?:Dr\\.?|Prof\\.?|Professor)\\s+[A-Z][A-Za-z.\\-]+(?:\\s+[A-Z][A-Za-z.\\-]+){0,3})'
                ),
                Pattern.compile(
                    '((?:Dr\\.?|Prof\\.?|Professor)\\s+[A-Z][A-Za-z.\\-]+(?:\\s+[A-Z][A-Za-z.\\-]+){0,3})\\s+because\\s+(?:his|her|their)\\s+work'
                ),
                Pattern.compile(
                    '([A-Z][A-Za-z.\\-]+(?:\\s+[A-Z][A-Za-z.\\-]+){1,3})\\s+because\\s+(?:his|her|their)\\s+work'
                ),
                Pattern.compile(
                    '(?:with|under|by)\\s+([A-Z][A-Za-z.\\-]+(?:\\s+[A-Z][A-Za-z.\\-]+){1,3})\\s+(?:because|for|whose)'
                ),
                Pattern.compile(
                    '((?:Dr\\.?|Prof\\.?|Professor)\\s+[A-Z][A-Za-z.\\-]+(?:\\s+[A-Z][A-Za-z.\\-]+){0,3})'
                )
            };

        for (

            Pattern p
            : patterns

        ) {

            Matcher m =
                p.matcher(
                    knowledge
                );

            if (

                m.find()

            ) {

                String candidate =
                    cleanFacultyAdvisorName(
                        m.group(1)
                    );

                if (

                    !String.isBlank(
                        candidate
                    )

                ) {

                    return candidate;

                }

            }

        }

        return null;

    }

    private static String cleanFacultyAdvisorName(

        String advisorName

    ) {

        String cleaned =
            cleanExtractedText(
                advisorName
            );

        if (

            String.isBlank(
                cleaned
            )

        ) {

            return null;

        }

        String lowerCleaned =
            cleaned.toLowerCase();

        if (

            cleaned.left(
                1
            ) != cleaned.left(
                1
            ).toUpperCase()

        ) {

            return null;

        }

        if (

            cleaned.split(
                '\\s+'
            ).size() > 5

        ) {

            return null;

        }

        if (

            lowerCleaned.contains(
                'faculty member'
            ) ||

            lowerCleaned.contains(
                'research opportunit'
            ) ||

            lowerCleaned.contains(
                'experienced faculty'
            ) ||

            lowerCleaned.startsWith(
                'because '
            ) ||

            lowerCleaned.contains(
                ' his work '
            ) ||

            lowerCleaned.contains(
                ' her work '
            ) ||

            lowerCleaned.contains(
                ' their work '
            )

        ) {

            return null;

        }

        return cleaned;

    }

    private static String cleanExtractedText(

        String text

    ) {

        if (

            String.isBlank(
                text
            )

        ) {

            return null;

        }

        String cleaned =
            text.trim();

        while (

            cleaned.endsWith(
                ','
            ) ||

            cleaned.endsWith(
                '.'
            ) ||

            cleaned.endsWith(
                ';'
            )

        ) {

            cleaned =
                cleaned.left(
                    cleaned.length() - 1
                ).trim();

        }

        if (

            cleaned.length() < 2

        ) {

            return null;

        }

        return cleaned;

    }

    private static String extractGpa(

        String knowledge

    ) {

        if (

            String.isBlank(
                knowledge
            )

        ) {

            return null;

        }

        List<Pattern> patterns =
            new List<Pattern>{
                Pattern.compile(
                    '(?i)(?:gpa|grade point average)\\s*(?:is|of|:|=|-)?\\s*(\\d(?:\\.\\d{1,2})?)'
                ),
                Pattern.compile(
                    '(?i)(?:gpa|grade point average).*?(?:is|of|:|=)\\s*(\\d(?:\\.\\d{1,2})?)'
                ),
                Pattern.compile(
                    '(?i)(\\d(?:\\.\\d{1,2})?)\\s*/\\s*4(?:\\.0)?'
                )
            };

        for (

            Pattern p
            : patterns

        ) {

            Matcher m =
                p.matcher(
                    knowledge
                );

            if (

                m.find()

            ) {

                Decimal gpa =
                    Decimal.valueOf(
                        m.group(1)
                    );

                if (

                    gpa >= 0 &&

                    gpa <= 4

                ) {

                    return formatGpa(
                        gpa
                    );

                }

            }

        }

        return null;

    }

    private static String formatGpa(

        Decimal gpa

    ) {

        Decimal roundedGpa =
            gpa.setScale(
                2
            );

        String formatted =
            String.valueOf(
                roundedGpa
            );

        if (

            formatted.endsWith(
                '0'
            ) &&

            !formatted.endsWith(
                '.0'
            )

        ) {

            formatted =
                formatted.left(
                    formatted.length() - 1
                );

        }

        if (

            !formatted.contains(
                '.'
            )

        ) {

            formatted +=
                '.0';

        }

        return formatted;

    }

    private static String extractInstitutionName(

        String knowledge

    ) {

        if (

            String.isBlank(
                knowledge
            )

        ) {

            return null;

        }

        List<Pattern> patterns =
            new List<Pattern>{
                Pattern.compile(
                    '(?i)\\b(?:most recent institution|recent institution|institution)\\b\\s*(?:is|was|:|=|-)?\\s*([A-Za-z0-9&.,\\-\\s]+?)(?:\\s+(?:in|located in|where|with|and|,\\s*(?:india|canada|china|united states|usa|united kingdom))|\\.|$)'
                ),
                Pattern.compile(
                    '(?i)\\b(?:graduated from|graduate from|attended|studied at|completed .*? at|degree .*? from)\\b\\s+([A-Za-z0-9&.,\\-\\s]+?)(?:\\s+(?:in|located in|where|with|and|,\\s*(?:india|canada|china|united states|usa|united kingdom))|\\.|$)'
                ),
                Pattern.compile(
                    '(?i)\\bfrom\\s+([A-Za-z0-9&.,\\-\\s]+?\\b(?:university|college|institute|school)\\b)'
                )
            };

        for (

            Pattern p
            : patterns

        ) {

            Matcher m =
                p.matcher(
                    knowledge
                );

            if (

                m.find()

            ) {

                return cleanInstitutionName(
                    m.group(1)
                );

            }

        }

        return null;

    }

    private static String cleanInstitutionName(

        String institutionName

    ) {

        if (

            String.isBlank(
                institutionName
            )

        ) {

            return null;

        }

        String cleaned =
            institutionName.trim();

        if (

            cleaned.length() < 4 ||

            cleaned.startsWith(
                'al '
            )

        ) {

            return null;

        }

        while (

            cleaned.endsWith(
                ','
            ) ||

            cleaned.endsWith(
                '.'
            )

        ) {

            cleaned =
                cleaned.left(
                    cleaned.length() - 1
                ).trim();

        }

        String lowerCleaned =
            cleaned.toLowerCase();

        if (

            lowerCleaned == 'efficiency' ||

            lowerCleaned.endsWith(
                ' efficiency'
            )

        ) {

            return null;

        }

        return cleaned;

    }

    private static Integer monthNameToNumber(

        String monthName

    ) {

        List<String> months =
            new List<String>{
                'jan',
                'feb',
                'mar',
                'apr',
                'may',
                'jun',
                'jul',
                'aug',
                'sep',
                'oct',
                'nov',
                'dec'
            };

        return months.indexOf(
            monthName.toLowerCase().left(
                3
            )
        ) + 1;

    }

    private static SemanticAnswer inferSemanticAnswer(

        FormQuestion question,

        User usr,

        Contact con

    ) {

        String knowledge =
            con != null
                ? getContactText(
                    con,
                    'Applicant_Knowledge__c'
                )
                : null;

        if (

            isFullAddressSynthesisQuestion(
                question
            )

        ) {

            return synthesizeFullAddress(
                usr,
                con
            );

        }

        if (

            isContactInfoSynthesisQuestion(
                question
            )

        ) {

            return synthesizeContactInformation(
                usr,
                con
            );

        }

        if (

            isEmploymentSynthesisQuestion(
                question
            )

        ) {

            return synthesizeEmploymentSummary(
                knowledge
            );

        }

        if (

            isStatementOfPurposeQuestion(
                question
            )

        ) {

            return answerFromValue(
                firstNonBlank(
                    extractStatementOfPurpose(
                        knowledge
                    ),
                    buildStatementOfPurpose(
                        knowledge
                    )
                ),
                'Semantic match to statement of purpose in applicant knowledge'
            );

        }

        if (

            isPersonalStatementQuestion(
                question
            )

        ) {

            return answerFromValue(
                extractPersonalStatement(
                    knowledge
                ),
                'Semantic match to personal statement in applicant knowledge'
            );

        }

        if (

            !isChoiceQuestion(
                question
            ) &&

            (

                isFirstNameQuestion(
                    question
                ) ||

                questionMeansAll(
                    question,
                    new List<String>{
                        'your',
                        'name'
                    }
                ) ||

                questionMeansAll(
                    question,
                    new List<String>{
                        'applicant',
                        'name'
                    }
                )

            )

        ) {

            return answerFromValue(
                usr.FirstName,
                'Semantic match to applicant first name'
            );

        }

        if (

            isLastNameQuestion(
                question
            )

        ) {

            return answerFromValue(
                usr.LastName,
                'Semantic match to applicant last name'
            );

        }

        if (

            isEmailQuestion(
                question
            )

        ) {

            return answerFromValue(
                usr.Email,
                'Semantic match to email address'
            );

        }

        if (

            isPhoneQuestion(
                question
            )

        ) {

            return answerFromValue(
                firstNonBlank(
                    con != null
                        ? firstNonBlank(
                            con.MobilePhone,
                            con.Phone
                        )
                        : null,
                    usr.Phone
                ),
                'Semantic match to phone/contact number'
            );

        }

        if (

            questionMeansAny(
                question,
                new List<String>{
                    'date of birth',
                    'birth date',
                    'dob',
                    'born'
                }
            )

        ) {

            return answerFromValue(
                con != null &&
                    con.Birthdate != null
                    ? String.valueOf(
                        con.Birthdate
                    )
                    : null,
                'Semantic match to date of birth'
            );

        }

        if (

            questionMeansAny(
                question,
                new List<String>{
                    'gender',
                    'sex'
                }
            )

        ) {

            return answerFromValue(
                con != null
                    ? getContactText(
                        con,
                        'Gender__c'
                    )
                    : null,
                'Semantic match to gender'
            );

        }

        if (

            isCitizenshipStatusQuestion(
                question
            )

        ) {

            return answerFromValue(
                con != null
                    ? getContactText(
                        con,
                        'Citizenship_Status__c'
                    )
                    : null,
                'Semantic match to citizenship status'
            );

        }

        if (

            questionMeansAny(
                question,
                new List<String>{
                    'primary language',
                    'native language',
                    'first language',
                    'language spoken'
                }
            )

        ) {

            return answerFromValue(
                con != null
                    ? getContactText(
                        con,
                        'Languages__c'
                    )
                    : null,
                'Semantic match to primary language'
            );

        }

        if (

            questionMeansAny(
                question,
                new List<String>{
                    'street',
                    'address line',
                    'current address'
                }
            ) &&

            !questionMeansAny(
                question,
                new List<String>{
                    'city',
                    'state',
                    'province',
                    'postal',
                    'zip',
                    'country'
                }
            )

        ) {

            return answerFromValue(
                firstNonBlank(
                    con != null
                        ? con.MailingStreet
                        : null,
                    usr.Street
                ),
                'Semantic match to current street address'
            );

        }

        if (

            questionMeansAny(
                question,
                new List<String>{
                    'city',
                    'town'
                }
            ) &&

            questionMeansAny(
                question,
                new List<String>{
                    'address',
                    'current',
                    'residence'
                }
            )

        ) {

            return answerFromValue(
                firstNonBlank(
                    con != null
                        ? con.MailingCity
                        : null,
                    usr.City
                ),
                'Semantic match to current address city'
            );

        }

        if (

            questionMeansAny(
                question,
                new List<String>{
                    'state',
                    'province',
                    'region'
                }
            ) &&

            questionMeansAny(
                question,
                new List<String>{
                    'address',
                    'current',
                    'residence',
                    'mailing',
                    'location',
                    'located'
                }
            )

        ) {

            return answerFromValue(
                firstNonBlank(
                    con != null
                        ? con.MailingState
                        : null,
                    usr.State
                ),
                'Semantic match to current address state/province'
            );

        }

        if (

            questionMeansAny(
                question,
                new List<String>{
                    'postal',
                    'zip',
                    'postcode'
                }
            )

        ) {

            return answerFromValue(
                firstNonBlank(
                    con != null
                        ? con.MailingPostalCode
                        : null,
                    usr.PostalCode
                ),
                'Semantic match to current address postal code'
            );

        }

        if (

            questionMeansAny(
                question,
                new List<String>{
                    'country of birth',
                    'birth country',
                    'born country',
                    'country born'
                }
            )

        ) {

            return answerFromValue(
                firstNonBlank(
                    extractCountryOfBirth(
                        knowledge
                    ),
                    usr.Country
                ),
                'Semantic match to country of birth'
            );

        }

        if (

            questionMeansAny(
                question,
                new List<String>{
                    'country'
                }
            ) &&

            questionMeansAny(
                question,
                new List<String>{
                    'address',
                    'current',
                    'residence'
                }
            )

        ) {

            return answerFromValue(
                firstNonBlank(
                    con != null
                        ? con.MailingCountry
                        : null,
                    usr.Country
                ),
                'Semantic match to current address country'
            );

        }

        if (

            String.isBlank(
                knowledge
            )

        ) {

            return null;

        }

        if (

            questionMeansAny(
                question,
                new List<String>{
                    'gpa',
                    'grade point',
                    'academic average',
                    '4 0 scale'
                }
            )

        ) {

            return answerFromValue(
                extractGpa(
                    knowledge
                ),
                'Semantic match to GPA in applicant knowledge'
            );

        }

        if (

            questionMeansAny(
                question,
                new List<String>{
                    'graduation date',
                    'completion date',
                    'degree date',
                    'expected graduation',
                    'graduate',
                    'finish degree',
                    'finish your degree',
                    'complete degree',
                    'completed your degree',
                    'degree completion'
                }
            )

        ) {

            return answerFromValue(
                extractGraduationDate(
                    knowledge
                ),
                'Semantic match to graduation date in applicant knowledge'
            );

        }

        if (

            questionMeansAny(
                question,
                new List<String>{
                    'start term',
                    'start semester',
                    'entry term',
                    'intake',
                    'begin studies'
                }
            )

        ) {

            return answerFromValue(
                extractStartTerm(
                    knowledge
                ),
                'Semantic match to preferred start term in applicant knowledge'
            );

        }

        if (

            questionMeansAny(
                question,
                new List<String>{
                    'research interests',
                    'research topics',
                    'academic interests',
                    'areas of interest',
                    'research areas'
                }
            )

        ) {

            return answerFromValue(
                extractResearchInterests(
                    knowledge
                ),
                'Semantic match to research interests in applicant knowledge'
            );

        }

        if (

            questionMeansAny(
                question,
                new List<String>{
                    'faculty advisor',
                    'advisor name',
                    'potential advisor',
                    'preferred professor',
                    'faculty mentor'
                }
            )

        ) {

            return answerFromValue(
                extractFacultyAdvisorName(
                    knowledge
                ),
                'Semantic match to faculty advisor in applicant knowledge'
            );

        }

        if (

            questionMeansAny(
                question,
                new List<String>{
                    'statement of purpose',
                    'purpose statement',
                    'academic purpose',
                    'study purpose',
                    'program goals'
                }
            )

        ) {

            return answerFromValue(
                firstNonBlank(
                    extractStatementOfPurpose(
                        knowledge
                    ),
                    buildStatementOfPurpose(
                        knowledge
                    )
                ),
                'Semantic match to statement of purpose in applicant knowledge'
            );

        }

        if (

            questionMeansAny(
                question,
                new List<String>{
                    'personal statement',
                    'personal essay',
                    'personal background',
                    'personal motivation',
                    'personal journey',
                    'personal goals',
                    'motivation statement'
                }
            )

        ) {

            return answerFromValue(
                extractPersonalStatement(
                    knowledge
                ),
                'Semantic match to personal statement in applicant knowledge'
            );

        }

        if (

            questionMeansAny(
                question,
                new List<String>{
                    'why this university',
                    'why this school',
                    'why this program',
                    'choose this university',
                    'choose this school',
                    'choose this program'
                }
            )

        ) {

            return answerFromValue(
                firstNonBlank(
                    extractEssaySection(
                        knowledge,
                        new List<String>{
                            'why this university:',
                            'why this university is',
                            'why this school:',
                            'why this school is',
                            'why this program:',
                            'why this program is'
                        }
                    ),
                    buildWhyThisUniversity(
                        knowledge
                    )
                ),
                'Semantic match to why-this-university answer in applicant knowledge'
            );

        }

        if (

            questionMeansAny(
                question,
                new List<String>{
                    'previous experience',
                    'professional experience',
                    'research experience',
                    'work experience',
                    'internship experience'
                }
            )

        ) {

            return answerFromValue(
                extractPreviousExperience(
                    knowledge
                ),
                'Semantic match to experience in applicant knowledge'
            );

        }

        if (

            questionMeansAny(
                question,
                new List<String>{
                    'accommodation',
                    'accessibility',
                    'needed support',
                    'special needs'
                }
            )

        ) {

            return answerFromValue(
                extractNeededAccommodations(
                    knowledge
                ),
                'Semantic match to accommodation needs in applicant knowledge'
            );

        }

        if (

            questionMeansAny(
                question,
                new List<String>{
                    'financing',
                    'funding',
                    'financial plan',
                    'pay for',
                    'tuition support'
                }
            )

        ) {

            return answerFromValue(
                extractFinancingPlan(
                    knowledge
                ),
                'Semantic match to financing plan in applicant knowledge'
            );

        }

        if (

            questionMeansAny(
                question,
                new List<String>{
                    'currently employed',
                    'employment status',
                    'working now',
                    'current job'
                }
            )

        ) {

            return answerFromValue(
                extractEmploymentStatus(
                    knowledge
                ),
                'Semantic match to employment status in applicant knowledge'
            );

        }

        if (

            questionMeansAny(
                question,
                new List<String>{
                    'thesis plan',
                    'thesis track',
                    'thesis option',
                    'research track'
                }
            )

        ) {

            return answerFromValue(
                extractThesisPlan(
                    knowledge
                ),
                'Semantic match to thesis plan in applicant knowledge'
            );

        }

        if (

            isPreferredContactMethodQuestion(
                question
            )

        ) {

            return answerFromValue(
                extractPreferredContactMethod(
                    knowledge
                ),
                'Semantic match to preferred contact method in applicant knowledge'
            );

        }

        if (

            questionMeansAny(
                question,
                new List<String>{
                    'how did you hear',
                    'how did you find',
                    'how did you learn',
                    'discovered this university',
                    'source of awareness'
                }
            )

        ) {

            return answerFromValue(
                extractProgramDiscoverySource(
                    knowledge
                ),
                'Semantic match to program discovery source in applicant knowledge'
            );

        }

        if (

            questionMeansAny(
                question,
                new List<String>{
                    'program applying',
                    'which program',
                    'degree program',
                    'program of interest'
                }
            )

        ) {

            return answerFromValue(
                extractProgramApplyingFor(
                    knowledge
                ),
                'Semantic match to program in applicant knowledge'
            );

        }

        if (

            questionMeansAny(
                question,
                new List<String>{
                    'enrollment status',
                    'student status',
                    'full time',
                    'part time',
                    'study load'
                }
            )

        ) {

            return answerFromValue(
                extractEnrollmentStatus(
                    knowledge
                ),
                'Semantic match to enrollment status in applicant knowledge'
            );

        }

        if (

            questionMeansAny(
                question,
                new List<String>{
                    'specialization',
                    'concentration',
                    'major',
                    'track',
                    'focus area'
                }
            )

        ) {

            return answerFromValue(
                extractSpecialization(
                    knowledge
                ),
                'Semantic match to specialization/major in applicant knowledge'
            );

        }

        if (

            questionMeansAny(
                question,
                new List<String>{
                    'field of study',
                    'undergraduate major',
                    'degree subject',
                    'bachelor degree in'
                }
            )

        ) {

            return answerFromValue(
                extractFieldOfStudy(
                    knowledge
                ),
                'Semantic match to field of study in applicant knowledge'
            );

        }

        if (

            questionMeansAny(
                question,
                new List<String>{
                    'highest education',
                    'highest degree',
                    'education level',
                    'level of education'
                }
            )

        ) {

            return answerFromValue(
                extractHighestEducation(
                    knowledge
                ),
                'Semantic match to education level in applicant knowledge'
            );

        }

        if (

            questionMeansAll(
                question,
                new List<String>{
                    'gre',
                    'verbal'
                }
            )

        ) {

            return answerFromValue(
                extractGreScore(
                    knowledge,
                    'verbal'
                ),
                'Semantic match to GRE verbal score in applicant knowledge'
            );

        }

        if (

            questionMeansAll(
                question,
                new List<String>{
                    'gre',
                    'quant'
                }
            ) ||

            questionMeansAll(
                question,
                new List<String>{
                    'gre',
                    'quantitative'
                }
            )

        ) {

            return answerFromValue(
                extractGreScore(
                    knowledge,
                    'quant'
                ),
                'Semantic match to GRE quant score in applicant knowledge'
            );

        }

        if (

            questionMeansAny(
                question,
                new List<String>{
                    'most recent institution',
                    'school attended',
                    'college attended',
                    'university attended',
                    'previous institution'
                }
            )

        ) {

            return answerFromValue(
                extractInstitutionName(
                    knowledge
                ),
                'Semantic match to institution name in applicant knowledge'
            );

        }

        if (

            questionMeansAll(
                question,
                new List<String>{
                    'institution',
                    'city'
                }
            )

        ) {

            return answerFromValue(
                extractInstitutionCity(
                    knowledge
                ),
                'Semantic match to institution city in applicant knowledge'
            );

        }

        if (

            questionMeansAll(
                question,
                new List<String>{
                    'institution',
                    'country'
                }
            ) ||

            (

                questionMeansAll(
                    question,
                    new List<String>{
                        'institution',
                        'located'
                    }
                ) &&

                questionHasOptions(
                    question,
                    new List<String>{
                        'United States',
                        'Canada',
                        'United Kingdom',
                        'India',
                        'China',
                        'Other'
                    }
                )

            )

        ) {

            return answerFromValue(
                extractInstitutionCountry(
                    knowledge
                ),
                'Semantic match to institution country in applicant knowledge'
            );

        }

        if (

            questionMeansAny(
                question,
                new List<String>{
                    'competitive exams',
                    'standardized tests',
                    'exams taken',
                    'tests taken'
                }
            )

        ) {

            return answerFromValue(
                extractCompetitiveExams(
                    knowledge
                ),
                'Semantic match to exams in applicant knowledge'
            );

        }

        String genericValue =
            inferGenericKnowledgeAnswer(
                question.questionText,
                question.questionType,
                question.picklistValues,
                knowledge
            );

        return answerFromValue(
            genericValue,
            'Generic semantic match from applicant knowledge'
        );

    }

    private static Boolean isFullAddressSynthesisQuestion(

        FormQuestion question

    ) {

        String fingerprint =
            buildQuestionFingerprint(
                question
            );

        Boolean asksForWholeAddress =
            fingerprint.contains(
                'full address'
            ) ||

            fingerprint.contains(
                'complete address'
            ) ||

            fingerprint == 'address' ||

            fingerprint == 'current address' ||

            fingerprint == 'mailing address' ||

            (

                fingerprint.contains(
                    'what is your address'
                ) &&

                !questionMeansAny(
                    question,
                    new List<String>{
                        'street',
                        'city',
                        'state',
                        'province',
                        'postal',
                        'zip',
                        'country'
                    }
                )

            );

        return asksForWholeAddress;

    }

    private static Boolean isContactInfoSynthesisQuestion(

        FormQuestion question

    ) {

        String fingerprint =
            buildQuestionFingerprint(
                question
            );

        if (

            fingerprint == 'contact information' ||

            fingerprint == 'contact info'

        ) {

            return true;

        }

        return questionMeansAny(
            question,
            new List<String>{
                'contact information',
                'contact details',
                'how can we contact',
                'how should we contact',
                'best way to contact',
                'phone and email',
                'email and phone'
            }
        );

    }

    private static Boolean isEmploymentSynthesisQuestion(

        FormQuestion question

    ) {

        return questionMeansAny(
            question,
            new List<String>{
                'describe your employment',
                'employment summary',
                'current employment details',
                'current work details',
                'tell us about your job',
                'work information',
                'job information'
            }
        );

    }

    private static SemanticAnswer synthesizeFullAddress(

        User usr,

        Contact con

    ) {

        List<String> parts =
            new List<String>();

        List<String> sources =
            new List<String>();

        addSourceValue(
            parts,
            sources,
            con != null
                ? con.MailingStreet
                : null,
            'Contact.MailingStreet'
        );

        if (

            parts.isEmpty()

        ) {

            addSourceValue(
                parts,
                sources,
                usr.Street,
                'User.Street'
            );

        }

        addSourceValue(
            parts,
            sources,
            firstNonBlank(
                con != null
                    ? con.MailingCity
                    : null,
                usr.City
            ),
            con != null &&
                !String.isBlank(
                    con.MailingCity
                )
                ? 'Contact.MailingCity'
                : 'User.City'
        );

        String stateValue =
            firstNonBlank(
                con != null
                    ? con.MailingState
                    : null,
                usr.State
            );

        String postalValue =
            firstNonBlank(
                con != null
                    ? con.MailingPostalCode
                    : null,
                usr.PostalCode
            );

        String statePostal =
            String.join(
                nonBlankValues(
                    new List<String>{
                        stateValue,
                        postalValue
                    }
                ),
                ' '
            );

        addSourceValue(
            parts,
            sources,
            statePostal,
            null
        );

        if (

            !String.isBlank(
                stateValue
            )

        ) {

            sources.add(
                con != null &&
                    !String.isBlank(
                        con.MailingState
                    )
                    ? 'Contact.MailingState'
                    : 'User.State'
            );

        }

        if (

            !String.isBlank(
                postalValue
            )

        ) {

            sources.add(
                con != null &&
                    !String.isBlank(
                        con.MailingPostalCode
                    )
                    ? 'Contact.MailingPostalCode'
                    : 'User.PostalCode'
            );

        }

        addSourceValue(
            parts,
            sources,
            firstNonBlank(
                con != null
                    ? con.MailingCountry
                    : null,
                usr.Country
            ),
            con != null &&
                !String.isBlank(
                    con.MailingCountry
                )
                ? 'Contact.MailingCountry'
                : 'User.Country'
        );

        if (

            parts.isEmpty()

        ) {

            return null;

        }

        return answerFromSynthesis(
            'My current address is ' +
            String.join(
                parts,
                ', '
            ) +
            '.',
            'Synthesized full address from multiple address fields',
            sources
        );

    }

    private static SemanticAnswer synthesizeContactInformation(

        User usr,

        Contact con

    ) {

        List<String> clauses =
            new List<String>();

        List<String> sources =
            new List<String>();

        addSourceValue(
            clauses,
            sources,
            !String.isBlank(
                usr.Email
            )
                ? 'email at ' +
                    usr.Email
                : null,
            'User.Email'
        );

        String phone =
            firstNonBlank(
                con != null
                    ? firstNonBlank(
                        con.MobilePhone,
                        con.Phone
                    )
                    : null,
                usr.Phone
            );

        addSourceValue(
            clauses,
            sources,
            !String.isBlank(
                phone
            )
                ? 'phone at ' +
                    phone
                : null,
            con != null &&
                !String.isBlank(
                    firstNonBlank(
                        con.MobilePhone,
                        con.Phone
                    )
                )
                ? 'Contact.Phone/MobilePhone'
                : 'User.Phone'
        );

        if (

            clauses.isEmpty()

        ) {

            return null;

        }

        return answerFromSynthesis(
            'You can contact me by ' +
            joinHumanReadable(
                clauses
            ) +
            '.',
            'Synthesized contact information from email and phone fields',
            sources
        );

    }

    private static SemanticAnswer synthesizeEmploymentSummary(

        String knowledge

    ) {

        if (

            String.isBlank(
                knowledge
            )

        ) {

            return null;

        }

        String employmentStatus =
            extractEmploymentStatus(
                knowledge
            );

        if (

            employmentStatus == 'No'

        ) {

            return answerFromSynthesis(
                'I am not currently employed.',
                'Synthesized employment response from applicant knowledge',
                new List<String>{
                    'Applicant Knowledge: Employment Status'
                }
            );

        }

        Matcher matcher =
            Pattern.compile(
                '(?i)i.{0,2}m currently employed\\s*(full time|part time|full-time|part-time)?\\s*(?:at|with)\\s+([^.;\\n]+?)\\s+as\\s+([^.;\\n]+?)(?:\\s+while|\\.|;|\\n|$)'
            ).matcher(
                knowledge
            );

        if (

            matcher.find()

        ) {

            String schedule =
                cleanExtractedText(
                    matcher.group(1)
                );

            String company =
                cleanExtractedText(
                    matcher.group(2)
                );

            String title =
                cleanExtractedText(
                    matcher.group(3)
                );

            List<String> sources =
                new List<String>();

            if (

                !String.isBlank(
                    employmentStatus
                )

            ) {

                sources.add(
                    'Applicant Knowledge: Employment Status'
                );

            }

            if (

                !String.isBlank(
                    company
                )

            ) {

                sources.add(
                    'Applicant Knowledge: Employer'
                );

            }

            if (

                !String.isBlank(
                    title
                )

            ) {

                sources.add(
                    'Applicant Knowledge: Job Title'
                );

            }

            if (

                !String.isBlank(
                    schedule
                )

            ) {

                sources.add(
                    'Applicant Knowledge: Employment Schedule'
                );

            }

            String value =
                'I am currently employed';

            if (

                !String.isBlank(
                    schedule
                )

            ) {

                value +=
                    ' ' +
                    schedule;

            }

            value +=
                ' at ' +
                company +
                ' as ' +
                title +
                '.';

            return answerFromSynthesis(
                value,
                'Synthesized employment response from company, title, and employment status',
                sources
            );

        }

        if (

            !String.isBlank(
                employmentStatus
            )

        ) {

            return answerFromSynthesis(
                'My current employment status is ' +
                employmentStatus +
                '.',
                'Synthesized employment response from employment status',
                new List<String>{
                    'Applicant Knowledge: Employment Status'
                }
            );

        }

        return null;

    }

    private static void addSourceValue(

        List<String> values,

        List<String> sources,

        String value,

        String sourceField

    ) {

        if (

            String.isBlank(
                value
            )

        ) {

            return;

        }

        values.add(
            value.trim()
        );

        if (

            !String.isBlank(
                sourceField
            ) &&

            !sources.contains(
                sourceField
            )

        ) {

            sources.add(
                sourceField
            );

        }

    }

    private static List<String> nonBlankValues(

        List<String> values

    ) {

        List<String> nonBlank =
            new List<String>();

        for (

            String value
            : values

        ) {

            if (

                !String.isBlank(
                    value
                )

            ) {

                nonBlank.add(
                    value.trim()
                );

            }

        }

        return nonBlank;

    }

    private static String joinHumanReadable(

        List<String> values

    ) {

        if (

            values == null ||

            values.isEmpty()

        ) {

            return null;

        }

        if (

            values.size() == 1

        ) {

            return values.get(
                0
            );

        }

        List<String> leadingValues =
            new List<String>();

        for (

            Integer i = 0;
            i < values.size() - 1;
            i++

        ) {

            leadingValues.add(
                values.get(
                    i
                )
            );

        }

        return String.join(
            leadingValues,
            ', '
        ) +
        ' and ' +
        values.get(
            values.size() - 1
        );

    }

    private static SemanticAnswer answerFromSynthesis(

        String value,

        String reasoning,

        List<String> sourceFields

    ) {

        if (

            String.isBlank(
                value
            )

        ) {

            return null;

        }

        System.debug(
            LoggingLevel.INFO,
            'SYNTHESIS -> ' +
            reasoning +
            ' | VALUE: ' +
            value +
            ' | SOURCES: ' +
            sourceFields
        );

        return new SemanticAnswer(
            value,
            reasoning,
            sourceFields
        )
            .markAsMerged();

    }

    private static SemanticAnswer answerFromValue(

        String value,

        String reasoning

    ) {

        if (

            String.isBlank(
                value
            )

        ) {

            return null;

        }

        return new SemanticAnswer(
            value,
            reasoning
        );

    }

    private static Boolean questionMeansAny(

        FormQuestion question,

        List<String> phrases

    ) {

        String fingerprint =
            buildQuestionFingerprint(
                question
            );

        for (

            String phrase
            : phrases

        ) {

            if (

                fingerprint.contains(
                    normalizeQuestionText(
                        phrase
                    )
                )

            ) {

                return true;

            }

        }

        return false;

    }

    private static Boolean questionMeansAll(

        FormQuestion question,

        List<String> phrases

    ) {

        String fingerprint =
            buildQuestionFingerprint(
                question
            );

        for (

            String phrase
            : phrases

        ) {

            if (

                !fingerprint.contains(
                    normalizeQuestionText(
                        phrase
                    )
                )

            ) {

                return false;

            }

        }

        return true;

    }

    private static Boolean questionHasOptions(

        FormQuestion question,

        List<String> expectedOptions

    ) {

        if (

            question == null ||

            String.isBlank(
                question.picklistValues
            )

        ) {

            return false;

        }

        Set<String> actualOptions =
            new Set<String>();

        for (

            String rawOption
            : question.picklistValues.split(
                '[,;\\n]'
            )

        ) {

            actualOptions.add(
                normalizeQuestionText(
                    rawOption
                )
            );

        }

        for (

            String expectedOption
            : expectedOptions

        ) {

            if (

                !actualOptions.contains(
                    normalizeQuestionText(
                        expectedOption
                    )
                )

            ) {

                return false;

            }

        }

        return true;

    }

    private static Boolean isCitizenshipStatusQuestion(

        FormQuestion question

    ) {

        if (

            questionMeansAny(
                question,
                new List<String>{
                    'citizenship',
                    'residency',
                    'international student',
                    'domestic student',
                    'visa',
                    'immigration',
                    'resident',
                    'citizen'
                }
            )

        ) {

            return true;

        }

        return questionHasOptions(
            question,
            new List<String>{
                'U.S. Citizen',
                'Permanent Resident',
                'International Student',
                'Other'
            }
        ) &&

        questionMeansAny(
            question,
            new List<String>{
                'status',
                'visa',
                'citizen',
                'resident',
                'residency',
                'immigration',
                'international',
                'domestic'
            }
        );

    }

    private static Boolean isPreferredContactMethodQuestion(

        FormQuestion question

    ) {

        if (

            questionMeansAll(
                question,
                new List<String>{
                    'contact',
                    'method'
                }
            ) ||

            questionMeansAny(
                question,
                new List<String>{
                    'preferred contact',
                    'best way to reach',
                    'how should we contact'
                }
            )

        ) {

            return true;

        }

        return questionHasOptions(
            question,
            new List<String>{
                'Email',
                'Phone',
                'Mail'
            }
        ) &&

        questionMeansAny(
            question,
            new List<String>{
                'contact',
                'communication',
                'communicate',
                'reach',
                'preferred',
                'method',
                'mode'
            }
        );

    }

    private static Boolean isStatementOfPurposeQuestion(

        FormQuestion question

    ) {

        String fingerprint =
            buildQuestionFingerprint(
                question
            );

        return fingerprint.contains(
            'statement of purpose'
        ) ||

        fingerprint.contains(
            'purpose statement'
        ) ||

        fingerprint.contains(
            'academic purpose'
        ) ||

        fingerprint.contains(
            'study purpose'
        );

    }

    private static Boolean isPersonalStatementQuestion(

        FormQuestion question

    ) {

        String fingerprint =
            buildQuestionFingerprint(
                question
            );

        return fingerprint.contains(
            'personal statement'
        ) ||

        fingerprint.contains(
            'personal essay'
        ) ||

        fingerprint.contains(
            'personal motivation'
        ) ||

        fingerprint.contains(
            'motivation statement'
        );

    }

    private static Boolean isChoiceQuestion(

        FormQuestion question

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

    private static String extractPreferredContactMethod(

        String knowledge

    ) {

        String lower =
            safeLower(
                knowledge
            );

        if (

            lower.contains(
                'preferred contact method is email'
            ) ||

            lower.contains(
                'preferred contact method is e mail'
            ) ||

            lower.contains(
                'prefer email'
            )

        ) {

            return 'Email';

        }

        if (

            lower.contains(
                'preferred contact method is phone'
            ) ||

            lower.contains(
                'prefer phone'
            ) ||

            lower.contains(
                'prefer call'
            ) ||

            lower.contains(
                'prefer text'
            )

        ) {

            return 'Phone';

        }

        if (

            lower.contains(
                'preferred contact method is mail'
            ) ||

            lower.contains(
                'prefer mail'
            ) ||

            lower.contains(
                'postal mail'
            )

        ) {

            return 'Mail';

        }

        return null;

    }

    private static String extractProgramDiscoverySource(

        String knowledge

    ) {

        String lower =
            safeLower(
                knowledge
            );

        if (

            lower.contains(
                'search engine'
            ) ||

            lower.contains(
                'google'
            ) ||

            lower.contains(
                'bing'
            ) ||

            lower.contains(
                'online search'
            )

        ) {

            return 'Search Engine';

        }

        if (

            lower.contains(
                'university website'
            ) ||

            lower.contains(
                'school website'
            ) ||

            lower.contains(
                'website'
            )

        ) {

            return 'University Website';

        }

        if (

            lower.contains(
                'social media'
            ) ||

            lower.contains(
                'facebook'
            ) ||

            lower.contains(
                'instagram'
            ) ||

            lower.contains(
                'linkedin'
            )

        ) {

            return 'Social Media';

        }

        if (

            lower.contains(
                'referral'
            ) ||

            lower.contains(
                'friend'
            ) ||

            lower.contains(
                'family'
            )

        ) {

            return 'Referral';

        }

        if (

            lower.contains(
                'education fair'
            ) ||

            lower.contains(
                'college fair'
            ) ||

            lower.contains(
                'career fair'
            )

        ) {

            return 'Education Fair';

        }

        if (

            lower.contains(
                'advertisement'
            ) ||

            lower.contains(
                ' advertising'
            ) ||

            lower.contains(
                ' ad '
            )

        ) {

            return 'Advertisement';

        }

        if (

            lower.contains(
                'conference'
            ) ||

            lower.contains(
                'journal'
            )

        ) {

            return 'Other';

        }

        return null;

    }

    private static String extractProgramApplyingFor(

        String knowledge

    ) {

        String lower =
            safeLower(
                knowledge
            );

        if (

            lower.contains(
                'phd data science'
            )

        ) {

            return 'PhD Data Science';

        }

        if (

            lower.contains(
                'ms cs'
            )

        ) {

            return 'MS CS';

        }

        if (

            lower.contains(
                'mba'
            )

        ) {

            return 'MBA';

        }

        if (

            lower.contains(
                'mph'
            )

        ) {

            return 'MPH';

        }

        if (

            lower.contains(
                'med'
            ) ||

            lower.contains(
                'm ed'
            )

        ) {

            return 'MEd';

        }

        if (

            lower.contains(
                'meng'
            ) ||

            lower.contains(
                'm eng'
            )

        ) {

            return 'MEng';

        }

        return null;

    }

    private static String extractEnrollmentStatus(

        String knowledge

    ) {

        String lower =
            safeLower(
                knowledge
            );

        if (

            lower.contains(
                'full time'
            ) ||

            lower.contains(
                'full-time'
            )

        ) {

            return 'Full-time';

        }

        if (

            lower.contains(
                'part time'
            ) ||

            lower.contains(
                'part-time'
            )

        ) {

            return 'Part-time';

        }

        return null;

    }

    private static String extractSpecialization(

        String knowledge

    ) {

        String lower =
            safeLower(
                knowledge
            );

        if (

            lower.contains(
                'artificial intelligence'
            ) ||

            lower.contains(
                ' ai'
            )

        ) {

            return 'AI';

        }

        if (

            lower.contains(
                'cybersecurity'
            )

        ) {

            return 'Cybersecurity';

        }

        if (

            lower.contains(
                'data science'
            )

        ) {

            return 'Data Science';

        }

        return null;

    }

    private static String extractFieldOfStudy(

        String knowledge

    ) {

        if (

            String.isBlank(
                knowledge
            )

        ) {

            return null;

        }

        Pattern p =
            Pattern.compile(
                '(?i)degree in\\s+([A-Za-z\\s]+?)\\s+from'
            );

        Matcher m =
            p.matcher(
                knowledge
            );

        if (

            m.find()

        ) {

            return m.group(1).trim();

        }

        return null;

    }

    private static String extractHighestEducation(

        String knowledge

    ) {

        String lower =
            safeLower(
                knowledge
            );

        if (

            lower.contains(
                'doctor'
            ) ||

            lower.contains(
                'phd'
            )

        ) {

            return 'Doctoral';

        }

        if (

            lower.contains(
                'master'
            )

        ) {

            return 'Master\'s';

        }

        if (

            lower.contains(
                'bachelor'
            )

        ) {

            return 'Bachelor\'s';

        }

        if (

            lower.contains(
                'associate'
            )

        ) {

            return 'Associate';

        }

        return null;

    }

    private static String extractGreScore(

        String knowledge,

        String section

    ) {

        if (

            String.isBlank(
                knowledge
            )

        ) {

            return null;

        }

        Pattern p =
            Pattern.compile(
                '(?i)gre\\s+' +
                section +
                '(?:itative|al)?\\s+score\\s+is\\s*(\\d{2,3})'
            );

        Matcher m =
            p.matcher(
                knowledge
            );

        if (

            m.find()

        ) {

            return m.group(1);

        }

        return null;

    }

    private static String extractInstitutionCity(

        String knowledge

    ) {

        String lower =
            safeLower(
                knowledge
            );

        if (

            lower.contains(
                'hyderabad'
            )

        ) {

            return 'Hyderabad';

        }

        if (

            lower.contains(
                'bangalore'
            )

        ) {

            return 'Bangalore';

        }

        if (

            lower.contains(
                'chennai'
            )

        ) {

            return 'Chennai';

        }

        return null;

    }

    private static String extractInstitutionCountry(

        String knowledge

    ) {

        String lower =
            safeLower(
                knowledge
            );

        if (

            lower.contains(
                'india'
            )

        ) {

            return 'India';

        }

        if (

            lower.contains(
                'canada'
            )

        ) {

            return 'Canada';

        }

        if (

            lower.contains(
                'united kingdom'
            )

        ) {

            return 'United Kingdom';

        }

        if (

            lower.contains(
                'china'
            )

        ) {

            return 'China';

        }

        if (

            lower.contains(
                'united states'
            ) ||

            lower.contains(
                'usa'
            )

        ) {

            return 'United States';

        }

        return null;

    }

    private static String extractCompetitiveExams(

        String knowledge

    ) {

        if (

            String.isBlank(
                knowledge
            )

        ) {

            return null;

        }

        Pattern p =
            Pattern.compile(
                '(?i)have taken\\s+([A-Za-z\\s,]+?)\\s+examinations'
            );

        Matcher m =
            p.matcher(
                knowledge
            );

        if (

            m.find()

        ) {

            return m.group(1).trim().replace(
                ' and ',
                ', '
            );

        }

        return null;

    }

    private static String safeLower(

        String value

    ) {

        return String.isBlank(
            value
        )
            ? ''
            : value.toLowerCase();

    }

    private static Boolean isFirstNameQuestion(

        FormQuestion question

    ) {

        if (

            isChoiceQuestion(
                question
            )

        ) {

            return false;

        }

        String fingerprint =
            buildQuestionFingerprint(
                question
            );

        return fingerprint.contains(
            'first name'
        ) ||

        fingerprint.contains(
            'given name'
        ) ||

        fingerprint.contains(
            'forename'
        ) ||

        fingerprint.contains(
            'call you'
        ) ||

        fingerprint.contains(
            'preferred name'
        ) ||

        fingerprint.contains(
            'go by'
        ) ||

        fingerprint.contains(
            'called'
        );

    }

    private static Boolean isLastNameQuestion(

        FormQuestion question

    ) {

        if (

            isChoiceQuestion(
                question
            )

        ) {

            return false;

        }

        String fingerprint =
            buildQuestionFingerprint(
                question
            );

        return fingerprint.contains(
            'last name'
        ) ||

        fingerprint.contains(
            'family name'
        ) ||

        fingerprint.contains(
            'surname'
        );

    }

    private static Boolean isEmailQuestion(

        FormQuestion question

    ) {

        if (

            isChoiceQuestion(
                question
            )

        ) {

            return false;

        }

        String fingerprint =
            buildQuestionFingerprint(
                question
            );

        return fingerprint.contains(
            'email'
        ) ||

        fingerprint.contains(
            'e mail'
        ) ||

        fingerprint.contains(
            'electronic mail'
        );

    }

    private static Boolean isPhoneQuestion(

        FormQuestion question

    ) {

        if (

            isChoiceQuestion(
                question
            )

        ) {

            return false;

        }

        String fingerprint =
            buildQuestionFingerprint(
                question
            );

        if (

            fingerprint.contains(
                'contact method'
            ) ||

            fingerprint.contains(
                'preferred contact'
            )

        ) {

            return false;

        }

        return fingerprint.contains(
            'phone'
        ) ||

        fingerprint.contains(
            'mobile'
        ) ||

        fingerprint.contains(
            'telephone'
        ) ||

        fingerprint.contains(
            'cell'
        ) ||

        fingerprint.contains(
            'contact number'
        ) ||

        fingerprint.contains(
            'contact no'
        ) ||

        fingerprint.contains(
            'primary number'
        ) ||

        fingerprint.contains(
            'reachable number'
        );

    }

    private static String buildQuestionFingerprint(

        FormQuestion question

    ) {

        if (

            question == null

        ) {

            return '';

        }

        return normalizeQuestionText(
            firstNonBlank(
                question.questionText,
                ''
            )
        );

    }

    private static String firstNonBlank(

        String preferredValue,

        String fallbackValue

    ) {

        if (

            !String.isBlank(
                preferredValue
            )

        ) {

            return preferredValue;

        }

        return fallbackValue;

    }

    private static void addResultSource(

        DataDiscoveryResult result,

        String sourceField

    ) {

        if (

            result == null ||
            String.isBlank(
                sourceField
            )

        ) {

            return;

        }

        if (

            result.sourceFields == null

        ) {

            result.sourceFields =
                new List<String>();

        }

        if (

            !result.sourceFields.contains(
                sourceField
            )

        ) {

            result.sourceFields.add(
                sourceField
            );

        }

    }

    private static String inferGenericKnowledgeAnswer(

        String questionText,

        String questionType,

        String picklistValues,

        String knowledge

    ) {

        if (

            String.isBlank(
                questionText
            ) ||

            String.isBlank(
                knowledge
            )

        ) {

            return null;

        }

        String explicitChoiceValue =
            extractExplicitChoiceOption(
                questionText,
                questionType,
                picklistValues,
                knowledge
            );

        if (

            !String.isBlank(
                explicitChoiceValue
            )

        ) {

            return explicitChoiceValue;

        }

        FormQuestion genericQuestion =
            new FormQuestion();

        genericQuestion.questionText =
            questionText;

        genericQuestion.questionType =
            questionType;

        genericQuestion.picklistValues =
            picklistValues;

        if (

            isStatementOfPurposeQuestion(
                genericQuestion
            )

        ) {

            return firstNonBlank(
                extractStatementOfPurpose(
                    knowledge
                ),
                buildStatementOfPurpose(
                    knowledge
                )
            );

        }

        if (

            isPersonalStatementQuestion(
                genericQuestion
            )

        ) {

            return firstNonBlank(
                extractPersonalStatement(
                    knowledge
                ),
                buildPersonalStatement(
                    knowledge
                )
            );

        }

        String explicitValue =
            extractGenericLabeledValue(
                questionText,
                knowledge
            );

        if (

            !String.isBlank(
                explicitValue
            )

        ) {

            return normalizeGenericAnswerForQuestionType(
                explicitValue,
                questionType,
                picklistValues
            );

        }

        String yesNoValue =
            inferGenericYesNoAnswer(
                questionText,
                knowledge
            );

        if (

            !String.isBlank(
                yesNoValue
            )

        ) {

            return normalizeGenericAnswerForQuestionType(
                yesNoValue,
                questionType,
                picklistValues
            );

        }

        return null;

    }

    private static String extractExplicitChoiceOption(

        String questionText,

        String questionType,

        String picklistValues,

        String knowledge

    ) {

        if (

            !isChoiceQuestionType(
                questionType,
                picklistValues
            ) ||

            !isAcademicChoiceLabel(
                questionText
            ) ||

            String.isBlank(
                knowledge
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
                    matchGenericAnswerToOption(
                        matcher.group(1),
                        picklistValues
                    );

                if (

                    !String.isBlank(
                        matchedOption
                    )

                ) {

                    System.debug(
                        LoggingLevel.INFO,
                        'UserDiscovery explicit choice match -> QUESTION: ' +
                        questionText +
                        ' | VALUE: ' +
                        matchedOption
                    );

                    return matchedOption;

                }

            }

        }

        return null;

    }

    private static Boolean isChoiceQuestionType(

        String questionType,

        String picklistValues

    ) {

        String type =
            String.isBlank(
                questionType
            )
                ? ''
                : questionType.toLowerCase();

        return type == 'picklist' ||

        type == 'dropdown' ||

        type == 'radio' ||

        !String.isBlank(
            picklistValues
        );

    }

    private static Boolean isAcademicChoiceLabel(

        String questionText

    ) {

        String normalizedQuestion =
            normalizeQuestionText(
                questionText
            );

        return normalizedQuestion.contains(
            'specialization'
        ) ||

        normalizedQuestion.contains(
            'concentration'
        ) ||

        normalizedQuestion.contains(
            'track'
        ) ||

        normalizedQuestion.contains(
            'focus area'
        ) ||

        normalizedQuestion.contains(
            'major'
        ) ||

        normalizedQuestion.contains(
            'course'
        ) ||

        normalizedQuestion.contains(
            'area of study'
        ) ||

        normalizedQuestion.contains(
            'field of study'
        ) ||

        normalizedQuestion.contains(
            'subject'
        ) ||

        normalizedQuestion.contains(
            'discipline'
        );

    }

    private static String extractGenericLabeledValue(

        String questionText,

        String knowledge

    ) {

        List<String> labels =
            buildQuestionLabelAliases(
                questionText
            );

        for (

            String label
            : labels

        ) {

            if (

                String.isBlank(
                    label
                )

            ) {

                continue;

            }

            Matcher matcher =
                Pattern.compile(
                    '(?i)\\b' +
                    escapeRegex(
                        label
                    ) +
                    '\\b\\s*(?:is|are|was|were|:|=|-)\\s*([^.;\\n]+)'
                ).matcher(
                    knowledge
                );

            if (

                matcher.find()

            ) {

                return cleanGenericAnswer(
                    matcher.group(1)
                );

            }

        }

        return null;

    }

    private static String normalizeGenericAnswerForQuestionType(

        String value,

        String questionType,

        String picklistValues

    ) {

        if (

            String.isBlank(
                value
            )

        ) {

            return null;

        }

        String type =
            String.isBlank(
                questionType
            )
                ? ''
                : questionType.toLowerCase();

        if (

            type == 'picklist' ||
            type == 'dropdown' ||
            type == 'radio'

        ) {

            return matchGenericAnswerToOption(
                value,
                picklistValues
            );

        }

        return value;

    }

    private static String matchGenericAnswerToOption(

        String value,

        String picklistValues

    ) {

        if (

            String.isBlank(
                picklistValues
            )

        ) {

            return value;

        }

        String normalizedValue =
            normalizeQuestionText(
                value
            );

        for (

            String rawOption
            : picklistValues.split(
                '[,;\\n]'
            )

        ) {

            String option =
                rawOption.trim();

            String normalizedOption =
                normalizeQuestionText(
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

    private static String inferGenericYesNoAnswer(

        String questionText,

        String knowledge

    ) {

        String normalizedQuestion =
            normalizeQuestionText(
                questionText
            );

        if (

            !(

                normalizedQuestion.startsWith(
                    'have '
                ) ||

                normalizedQuestion.startsWith(
                    'has '
                ) ||

                normalizedQuestion.startsWith(
                    'do '
                ) ||

                normalizedQuestion.startsWith(
                    'does '
                ) ||

                normalizedQuestion.startsWith(
                    'did '
                ) ||

                normalizedQuestion.startsWith(
                    'are '
                ) ||

                normalizedQuestion.startsWith(
                    'is '
                ) ||

                normalizedQuestion.startsWith(
                    'were '
                ) ||

                normalizedQuestion.startsWith(
                    'was '
                )

            )

        ) {

            return null;

        }

        String bestSentence =
            findBestKnowledgeSentence(
                questionText,
                knowledge
            );

        if (

            String.isBlank(
                bestSentence
            )

        ) {

            return null;

        }

        return inferPositiveSentence(
            bestSentence
        )
            ? 'Yes'
            : 'No';

    }

    private static Boolean inferPositiveSentence(

        String sentence

    ) {

        String lowerSentence =
            sentence.toLowerCase();

        return !(

            lowerSentence.contains(
                ' not '
            ) ||

            lowerSentence.contains(
                ' never '
            ) ||

            lowerSentence.contains(
                ' no '
            ) ||

            lowerSentence.contains(
                'none'
            ) ||

            lowerSentence.contains(
                'without'
            )

        );

    }

    private static String findBestKnowledgeSentence(

        String questionText,

        String knowledge

    ) {

        List<String> questionTokens =
            getMeaningfulQuestionTokens(
                questionText
            );

        if (

            questionTokens.isEmpty()

        ) {

            return null;

        }

        if (

            questionTokens.size() < 2

        ) {

            return null;

        }

        String normalizedKnowledge =
            knowledge.replace(
                '\n',
                '. '
            );

        List<String> sentences =
            normalizedKnowledge.split(
                '(?<=[.!?])\\s+'
            );

        Integer bestScore =
            0;

        String bestSentence =
            null;

        for (

            String sentence
            : sentences

        ) {

            String normalizedSentence =
                normalizeQuestionText(
                    sentence
                );

            Integer score =
                0;

            for (

                String token
                : questionTokens

            ) {

                if (

                    normalizedSentence.contains(
                        token
                    )

                ) {

                    score++;

                }

            }

            if (

                score > bestScore

            ) {

                bestScore =
                    score;

                bestSentence =
                    sentence;

            }

        }

        Integer minimumScore =
            2;

        if (

            questionTokens.size() > 4

        ) {

            minimumScore =
                3;

        }

        if (

            questionTokens.size() > 6

        ) {

            minimumScore =
                4;

        }

        return bestScore >= minimumScore
            ? cleanGenericAnswer(
                bestSentence
            )
            : null;

    }

    private static List<String> buildQuestionLabelAliases(

        String questionText

    ) {

        List<String> aliases =
            new List<String>();

        String normalized =
            normalizeQuestionText(
                questionText
            );

        aliases.add(
            normalized
        );

        String compact =
            normalized;

        List<String> leadingWords =
            new List<String>{
                'what is ',
                'what are ',
                'which is ',
                'which are ',
                'please enter ',
                'enter ',
                'select ',
                'choose ',
                'provide ',
                'describe '
            };

        for (

            String leadingWord
            : leadingWords

        ) {

            if (

                compact.startsWith(
                    leadingWord
                )

            ) {

                compact =
                    compact.substring(
                        leadingWord.length()
                    );

            }

        }

        aliases.add(
            compact
        );

        return aliases;

    }

    private static List<String> getMeaningfulQuestionTokens(

        String questionText

    ) {

        List<String> tokens =
            new List<String>();

        for (

            String token
            : normalizeQuestionText(
                questionText
            ).split(
                '\\s+'
            )

        ) {

            if (

                isMeaningfulQuestionToken(
                    token
                ) &&

                !tokens.contains(
                    token
                )

            ) {

                tokens.add(
                    token
                );

            }

        }

        return tokens;

    }

    private static Boolean isMeaningfulQuestionToken(

        String token

    ) {

        if (

            String.isBlank(
                token
            ) ||

            token.length() <= 2

        ) {

            return false;

        }

        Set<String> stopWords =
            new Set<String>{
                'the',
                'and',
                'for',
                'with',
                'your',
                'you',
                'are',
                'was',
                'were',
                'what',
                'which',
                'when',
                'where',
                'have',
                'has',
                'had',
                'did',
                'does',
                'this',
                'that',
                'field',
                'question',
                'please',
                'enter',
                'select',
                'choose',
                'provide',
                'describe'
            };

        return !stopWords.contains(
            token
        );

    }

    private static String normalizeQuestionText(

        String value

    ) {

        if (

            String.isBlank(
                value
            )

        ) {

            return '';

        }

        return value.toLowerCase()
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

    private static String escapeRegex(

        String value

    ) {

        if (

            String.isBlank(
                value
            )

        ) {

            return '';

        }

        String escaped =
            value;

        for (

            String character
            : new List<String>{
                '\\',
                '.',
                '^',
                '$',
                '|',
                '?',
                '*',
                '+',
                '(',
                ')',
                '[',
                ']',
                '{',
                '}'
            }

        ) {

            escaped =
                escaped.replace(
                    character,
                    '\\' +
                    character
                );

        }

        return escaped;

    }

    private static String cleanGenericAnswer(

        String value

    ) {

        String cleaned =
            cleanExtractedText(
                value
            );

        if (

            String.isBlank(
                cleaned
            )

        ) {

            return null;

        }

        if (

            cleaned.length() > 255

        ) {

            cleaned =
                cleaned.left(
                    255
                ).trim();

        }

        return cleaned;

    }

    private static String formatDate(

        Integer year,

        Integer month,

        Integer day

    ) {

        try {

            Date parsedDate =
                Date.newInstance(
                    year,
                    month,
                    day
                );

            return String.valueOf(
                parsedDate
            );

        }

        catch (Exception e) {

            return null;

        }

    }

    private static void addExplanationMetadata(

        DataDiscoveryResult result,

        User usr,

        Contact con

    ) {

        if (

            result == null

        ) {

            return;

        }

        result.selectionType =
            result.isMergedAnswer == true ||
            (
                result.sourceFields != null &&
                result.sourceFields.size() > 1
            )
                ? 'Synthesized from multiple saved fields'
                : 'Direct mapping from saved data';

        result.sourceUpdatedAt =
            findLatestSourceTimestamp(
                result.sourceFields,
                usr,
                con
            );

        if (

            result.alternativeOptions == null

        ) {

            result.alternativeOptions =
                new List<String>();

        }

        if (

            result.alternativeOptions.isEmpty()

        ) {

            result.alternativeOptions.add(
                'No stronger saved-data alternative was found.'
            );

        }

    }

    private static Boolean applyApplicationAnswer(

        FormQuestion question,

        DataDiscoveryResult result,

        Academic_Application__c application

    ) {

        if (

            question == null ||
            result == null ||
            application == null

        ) {

            return false;

        }

        String questionId =
            String.valueOf(
                question.questionId
            )
                .toLowerCase()
                .trim();

        Object value;
        String sourceField;

        if (

            questionId == 'admin_decision_status'

        ) {

            value =
                application.Decision_Status__c;
            sourceField =
                'Academic_Application__c.Decision_Status__c';

        }

        else if (

            questionId == 'admin_admission_granted'

        ) {

            value =
                application.Admission_Granted__c;
            sourceField =
                'Academic_Application__c.Admission_Granted__c';

        }

        else if (

            questionId == 'admin_review_comments'

        ) {

            value =
                application.Admin_Review_Comments__c;
            sourceField =
                'Academic_Application__c.Admin_Review_Comments__c';

        }

        else if (

            questionId == 'admin_approval_comments'

        ) {

            value =
                application.Approval_Decision_Comments__c;
            sourceField =
                'Academic_Application__c.Approval_Decision_Comments__c';

        }

        else if (

            questionId == 'admin_rejection_comments'

        ) {

            value =
                application.Rejection_Comments__c;
            sourceField =
                'Academic_Application__c.Rejection_Comments__c';

        }

        else if (

            questionId == 'admin_reviewer_notes'

        ) {

            value =
                application.Reviewer_Notes__c;
            sourceField =
                'Academic_Application__c.Reviewer_Notes__c';

        }

        else if (

            questionId == 'admin_decision_date'

        ) {

            value =
                application.Decision_Date__c;
            sourceField =
                'Academic_Application__c.Decision_Date__c';

        }

        else {

            return false;

        }

        if (

            value == null ||
            String.isBlank(
                String.valueOf(
                    value
                )
            )

        ) {

            return false;

        }

        result.recommendedValue =
            String.valueOf(
                value
            );

        result.bestMatchConfidence =
            1;

        result.reasoning =
            'Used the selected academic application record for this admin review field.';

        addResultSource(
            result,
            sourceField
        );

        result.sourceUpdatedAt =
            application.LastModifiedDate == null
                ? null
                : application.LastModifiedDate.format();

        result.selectionType =
            'Direct mapping from selected application record';

        result.alternativeOptions.add(
            'No stronger selected-application alternative was found.'
        );

        return true;

    }

    private static String findLatestSourceTimestamp(

        List<String> sourceFields,

        User usr,

        Contact con

    ) {

        Datetime latestTimestamp;

        if (

            sourceFields == null ||
            sourceFields.isEmpty()

        ) {

            latestTimestamp =
                newerDatetime(
                    usr == null ? null : usr.LastModifiedDate,
                    con == null ? null : con.LastModifiedDate
                );

        }

        else {

            for (

                String sourceField
                : sourceFields

            ) {

                String normalizedSource =
                    String.valueOf(
                        sourceField
                    )
                        .toLowerCase();

                if (

                    normalizedSource.contains(
                        'contact.'
                    )

                ) {

                    latestTimestamp =
                        newerDatetime(
                            latestTimestamp,
                            con == null ? null : con.LastModifiedDate
                        );

                }

                if (

                    normalizedSource.contains(
                        'user.'
                    )

                ) {

                    latestTimestamp =
                        newerDatetime(
                            latestTimestamp,
                            usr == null ? null : usr.LastModifiedDate
                        );

                }

            }

        }

        return latestTimestamp == null
            ? null
            : latestTimestamp.format();

    }

    private static Datetime newerDatetime(

        Datetime firstValue,

        Datetime secondValue

    ) {

        if (

            firstValue == null

        ) {

            return secondValue;

        }

        if (

            secondValue == null

        ) {

            return firstValue;

        }

        return secondValue.getTime() > firstValue.getTime()
            ? secondValue
            : firstValue;

    }

}
