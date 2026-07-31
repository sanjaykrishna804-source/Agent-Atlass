import { LightningElement, api }
from 'lwc';

export default class AiProgressIndicator
    extends LightningElement {

    @api isLoading = false;

    @api statusMessage =
        'Processing...';

}