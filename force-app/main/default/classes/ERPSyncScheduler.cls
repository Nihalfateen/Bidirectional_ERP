global with sharing class ERPSyncScheduler implements Schedulable {
    global void execute(SchedulableContext context) {
        Database.executeBatch(new ERPInboundBatch(), 1);
    }
}
