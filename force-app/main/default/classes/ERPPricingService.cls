public with sharing class ERPPricingService {
    public static ERPIntegrationService.SyncResult pullFromErp() {
        return ERPIntegrationService.pullAndUpsert(ERPConstants.ENTITY_PRICING);
    }

    public static ERPIntegrationService.SyncResult pushToErp(Set<Id> pricebookEntryIds) {
        return ERPIntegrationService.pushRecords(ERPConstants.ENTITY_PRICING, pricebookEntryIds);
    }
}
