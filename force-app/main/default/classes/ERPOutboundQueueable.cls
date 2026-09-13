public with sharing class ERPOutboundQueueable implements Queueable, Database.AllowsCallouts {
    private final String entityType;
    private final Set<Id> recordIds;
    private final Integer attemptNumber;

    public ERPOutboundQueueable(String entityType, Set<Id> recordIds) {
        this(entityType, recordIds, 0);
    }

    public ERPOutboundQueueable(String entityType, Set<Id> recordIds, Integer attemptNumber) {
        this.entityType = entityType;
        this.recordIds = recordIds == null ? new Set<Id>() : new Set<Id>(recordIds);
        this.attemptNumber = attemptNumber == null ? 0 : attemptNumber;
    }

    public void execute(QueueableContext context) {
        ERPIntegrationService.EndpointConfig endpointConfig = ERPIntegrationService.getEndpoint(entityType, ERPConstants.DIRECTION_OUTBOUND);
        try {
            ERPIntegrationService.SyncResult result = ERPIntegrationService.pushRecords(entityType, recordIds);
            if (result.failed > 0 && attemptNumber < endpointConfig.maxRetries) {
                ERPIntegrationLogger.logResult(entityType, ERPConstants.DIRECTION_OUTBOUND, ERPConstants.STATUS_RETRY, result.processed, result.failed);
                System.enqueueJob(new ERPOutboundQueueable(entityType, recordIds, attemptNumber + 1));
            }
        } catch (Exception ex) {
            ERPIntegrationLogger.log(
                entityType,
                ERPConstants.DIRECTION_OUTBOUND,
                ERPConstants.STATUS_FAILED,
                null,
                null,
                ex.getMessage(),
                attemptNumber,
                null
            );
            if (attemptNumber < endpointConfig.maxRetries) {
                System.enqueueJob(new ERPOutboundQueueable(entityType, recordIds, attemptNumber + 1));
            }
        }
    }
}
