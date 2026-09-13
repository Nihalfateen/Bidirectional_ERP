trigger ERPOrderTrigger on Order (after insert, after update) {
    List<SObject> records = new List<SObject>();
    for (Order record : Trigger.new) {
        records.add(record);
    }
    ERPTriggerDispatcher.enqueueOutbound(ERPConstants.ENTITY_ORDER, records);
}
