public with sharing class ERPOrderService {
    public static ERPIntegrationService.SyncResult pullFromErp() {
        return ERPIntegrationService.pullAndUpsert(ERPConstants.ENTITY_ORDER);
    }

    public static ERPIntegrationService.SyncResult pushToErp(Set<Id> orderIds) {
        return ERPIntegrationService.pushRecords(ERPConstants.ENTITY_ORDER, orderIds);
    }
}
