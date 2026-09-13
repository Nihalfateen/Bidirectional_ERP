trigger ERPProductTrigger on Product2 (after insert, after update) {
    List<SObject> records = new List<SObject>();
    for (Product2 record : Trigger.new) {
        records.add(record);
    }
    ERPTriggerDispatcher.enqueueOutbound(ERPConstants.ENTITY_INVENTORY, records);
}
