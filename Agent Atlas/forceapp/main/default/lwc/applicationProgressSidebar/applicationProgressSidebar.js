import { LightningElement, api } from 'lwc';

export default class ApplicationProgressSidebar extends LightningElement {

    @api currentPage = 1;

    @api totalPages = 5;

    @api canAccessAdminPage = false;

    get steps() {

        const steps = [

            {
                id: 1,
                label: 'Personal Information',
                completed: this.currentPage > 1,
                circleClass: this.getClass(1),
                stepClass: this.getStepClass(1)
            },

            {
                id: 2,
                label: 'Contact Information',
                completed: this.currentPage > 2,
                circleClass: this.getClass(2),
                stepClass: this.getStepClass(2)
            },

            {
                id: 3,
                label: 'Educational Background',
                completed: this.currentPage > 3,
                circleClass: this.getClass(3),
                stepClass: this.getStepClass(3)
            },

            {
                id: 4,
                label: 'Program Selection & Academic Interests',
                completed: this.currentPage > 4,
                circleClass: this.getClass(4),
                stepClass: this.getStepClass(4)
            },

            {
                id: 5,
                label: 'Essays & Final Questions',
                completed: false,
                circleClass: this.getClass(5),
                stepClass: this.getStepClass(5)
            }

        ];

        if (Number(this.totalPages) >= 6) {

            steps.push({
                id: 6,
                label: 'Admin View',
                completed: false,
                circleClass: this.getClass(6),
                stepClass: this.getStepClass(6),
                note: this.canAccessAdminPage
                    ? ''
                    : 'Admin only'
            });

        }

        return steps;

    }

    getClass(step) {

        if (
            step === 6 &&
            !this.canAccessAdminPage
        ) {

            return 'progress-circle restricted';

        }

        if (step < this.currentPage) {

            return 'progress-circle completed';

        }

        if (step === this.currentPage) {

            return 'progress-circle current';

        }

        return 'progress-circle pending';

    }

    getStepClass(step) {

        return step === 6 &&
            !this.canAccessAdminPage
                ? 'progress-step restricted-step'
                : 'progress-step';

    }

}
