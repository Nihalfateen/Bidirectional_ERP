public with sharing class ERPTriggerDispatcher {
    @TestVisible private static Boolean disabledForTest = false;
    private static Boolean isEnqueued = false;

    public static void enqueueOutbound(String entityType, List<SObject> records) {
        if (disabledForTest || isEnqueued || records == null || records.isEmpty()) {
            return;
        }
        Set<Id> ids = new Set<Id>();
        for (SObject record : records) {
            if (record.Id != null) {
                ids.add(record.Id);
            }
        }
        if (!ids.isEmpty()) {
            isEnqueued = true;
            System.enqueueJob(new ERPOutboundQueueable(entityType, ids));
        }
    }
}
