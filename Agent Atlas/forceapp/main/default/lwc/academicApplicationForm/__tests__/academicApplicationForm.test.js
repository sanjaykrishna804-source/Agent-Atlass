import { createElement } from '@lwc/engine-dom';

import AcademicApplicationForm
    from 'c/academicApplicationForm';

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

// MOCK APEX METHODS

jest.mock(
    '@salesforce/apex/AcademicFormController.loadFormConfiguration',

    () => {
        return {
            default: jest.fn()
        };
    },

    { virtual: true }
);

jest.mock(
    '@salesforce/apex/AcademicFormController.canUseAdminApplicationContext',

    () => {
        return {
            default: jest.fn()
        };
    },

    { virtual: true }
);

jest.mock(
    '@salesforce/apex/AcademicFormController.canAccessAcademicApplication',

    () => {
        return {
            default: jest.fn()
        };
    },

    { virtual: true }
);

jest.mock(
    '@salesforce/apex/AcademicFormController.loadFormDraft',

    () => {
        return {
            default: jest.fn()
        };
    },

    { virtual: true }
);

jest.mock(
    '@salesforce/apex/AcademicFormController.loadFormSubmission',

    () => {
        return {
            default: jest.fn()
        };
    },

    { virtual: true }
);

jest.mock(
    '@salesforce/apex/AcademicFormController.saveFormDraft',

    () => {
        return {
            default: jest.fn()
        };
    },

    { virtual: true }
);

jest.mock(
    '@salesforce/apex/AcademicFormController.submitForm',

    () => {
        return {
            default: jest.fn()
        };
    },

    { virtual: true }
);

jest.mock(
    '@salesforce/apex/AIFormFillLogger.logChatDecision',

    () => {
        return {
            default: jest.fn()
        };
    },

    { virtual: true }
);

describe('c-academic-application-form', () => {

    beforeEach(() => {

        canUseAdminApplicationContext.mockResolvedValue(false);
        canAccessAcademicApplication.mockResolvedValue(false);
        loadFormSubmission.mockResolvedValue(null);

    });

    afterEach(() => {

        while (document.body.firstChild) {

            document.body.removeChild(
                document.body.firstChild
            );

        }

        jest.clearAllMocks();

    });

    // HELPER FUNCTION

    async function flushPromises() {

        return new Promise((resolve) =>
            setTimeout(resolve, 0)
        );

    }

    // TEST 1

    it(
        'loads metadata configuration and shows fresh form when no draft exists',

        async () => {

            const mockConfig = [

                {
                    Question_Id__c: 'Q01',
                    Question_Label__c: 'First Name',
                    Question_Type__c: 'text',
                    Page_Number__c: 1,
                    Display_Order__c: 1
                },

                {
                    Question_Id__c: 'Q11',
                    Question_Label__c: 'Major Choice',
                    Question_Type__c: 'picklist',
                    Page_Number__c: 2,
                    Display_Order__c: 1
                }

            ];

            loadFormConfiguration.mockResolvedValue(
                mockConfig
            );

            loadFormDraft.mockResolvedValue(null);

            const element = createElement(
                'c-academic-application-form',
                {
                    is: AcademicApplicationForm
                }
            );

            document.body.appendChild(element);

            await flushPromises();

            const progressIndicator =
                element.shadowRoot.querySelector(
                    'c-form-progress'
                );

            expect(progressIndicator)
                .not.toBeNull();

            expect(progressIndicator.currentPage)
                .toBe(1);

            const modalPrompt =
                element.shadowRoot.querySelector(
                    '.slds-modal'
                );

            expect(modalPrompt)
                .toBeNull();

        }
    );

    // TEST 2

    it(
        'detects incomplete drafts and displays the resume prompt modal',

        async () => {

            const mockDraft = {

                Id: 'a00xx000000DraftID',

                Current_Page__c: 3,

                Last_Saved__c:
                    '2026-05-18T12:00:00.000Z',

                Form_Responses__r: [

                    {
                        Question_Id__c: 'Q01',
                        Response_Value__c:
                            'Test Applicant'
                    }

                ]

            };

            loadFormConfiguration
                .mockResolvedValue([]);

            loadFormDraft
                .mockResolvedValue(mockDraft);

            const element = createElement(
                'c-academic-application-form',
                {
                    is: AcademicApplicationForm
                }
            );

            document.body.appendChild(element);

            await flushPromises();

            const modalPrompt =
                element.shadowRoot.querySelector(
                    'section.slds-modal'
                );

            expect(modalPrompt)
                .not.toBeNull();

            const resumeBtn =
                element.shadowRoot.querySelector(
                    'lightning-button[label="Resume Application"]'
                );

            resumeBtn.click();

            await flushPromises();

            expect(
                element.shadowRoot
                    .querySelector('c-form-progress')
                    .currentPage
            ).toBe(3);

        }
    );

    // TEST 3

    it(
        'triggers a save tracking update when auto-save request fires',

        async () => {

            loadFormConfiguration
                .mockResolvedValue([]);

            loadFormDraft
                .mockResolvedValue(null);

            saveFormDraft.mockResolvedValue({

                submissionId:
                    'a00xx000000SaveID'

            });

            const element = createElement(
                'c-academic-application-form',
                {
                    is: AcademicApplicationForm
                }
            );

            document.body.appendChild(element);

            await flushPromises();

            const autoSaveService =
                element.shadowRoot.querySelector(
                    'c-form-auto-save'
                );

            autoSaveService.dispatchEvent(

                new CustomEvent(
                    'autosaverequest',

                    {
                        detail: {
                            trigger:
                                'Timer Interval Execution'
                        }
                    }
                )

            );

            await flushPromises();

            expect(saveFormDraft)
                .toHaveBeenCalledTimes(1);

        }
    );

    // TEST 4

    it(
        'blocks navigation forwarding if validation fails on final submit step',

        async () => {

            loadFormConfiguration
                .mockResolvedValue([]);

            loadFormDraft
                .mockResolvedValue(null);

            const element = createElement(
                'c-academic-application-form',
                {
                    is: AcademicApplicationForm
                }
            );

            document.body.appendChild(element);

            await flushPromises();

            const progressIndicator =
                element.shadowRoot.querySelector(
                    'c-form-progress'
                );

            progressIndicator.dispatchEvent(

                new CustomEvent(
                    'pagejump',

                    {
                        detail: {
                            page: 5
                        }
                    }
                )

            );

            await flushPromises();

            const mockFormPage =
                element.shadowRoot.querySelector(
                    'c-form-page'
                );

            mockFormPage.validateAllFields =
                jest.fn().mockReturnValue(false);

            const submitBtn =
                element.shadowRoot.querySelector(
                    'button.btn-submit'
                );

            expect(submitBtn)
                .not.toBeNull();

            submitBtn.click();

            await flushPromises();

            expect(submitForm)
                .not.toHaveBeenCalled();

        }
    );

});
