trigger ERPPricebookEntryTrigger on PricebookEntry (after insert, after update) {
    List<SObject> records = new List<SObject>();
    for (PricebookEntry record : Trigger.new) {
        records.add(record);
    }
    ERPTriggerDispatcher.enqueueOutbound(ERPConstants.ENTITY_PRICING, records);
}
