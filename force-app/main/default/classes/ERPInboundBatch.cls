public with sharing class ERPInboundBatch implements Database.Batchable<String>, Database.AllowsCallouts, Database.Stateful {
    private final List<String> entityTypes;
    private Integer processed = 0;
    private Integer failed = 0;

    public ERPInboundBatch() {
        this(new List<String>{
            ERPConstants.ENTITY_ORDER,
            ERPConstants.ENTITY_INVENTORY,
            ERPConstants.ENTITY_PRICING
        });
    }

    public ERPInboundBatch(List<String> entityTypes) {
        this.entityTypes = entityTypes == null ? new List<String>() : entityTypes;
    }

    public Iterable<String> start(Database.BatchableContext context) {
        return entityTypes;
    }

    public void execute(Database.BatchableContext context, List<String> scope) {
        for (String entityType : scope) {
            try {
                ERPIntegrationService.SyncResult result = ERPIntegrationService.pullAndUpsert(entityType);
                processed += result.processed;
                failed += result.failed;
            } catch (Exception ex) {
                failed++;
                ERPIntegrationLogger.log(
                    entityType,
                    ERPConstants.DIRECTION_INBOUND,
                    ERPConstants.STATUS_FAILED,
                    null,
                    null,
                    ex.getMessage(),
                    0,
                    null
                );
            }
        }
    }

    public void finish(Database.BatchableContext context) {
        ERPIntegrationLogger.logResult('All', ERPConstants.DIRECTION_INBOUND, failed == 0 ? ERPConstants.STATUS_SUCCESS : ERPConstants.STATUS_FAILED, processed, failed);
    }
}
