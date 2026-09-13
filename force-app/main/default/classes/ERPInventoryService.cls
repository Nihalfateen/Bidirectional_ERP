public with sharing class ERPInventoryService {
    public static ERPIntegrationService.SyncResult pullFromErp() {
        return ERPIntegrationService.pullAndUpsert(ERPConstants.ENTITY_INVENTORY);
    }

    public static ERPIntegrationService.SyncResult pushToErp(Set<Id> productIds) {
        return ERPIntegrationService.pushRecords(ERPConstants.ENTITY_INVENTORY, productIds);
    }
}
