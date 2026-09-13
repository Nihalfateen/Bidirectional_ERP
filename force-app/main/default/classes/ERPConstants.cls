public class ERPConstants {
    public static final String DIRECTION_INBOUND = 'Inbound';
    public static final String DIRECTION_OUTBOUND = 'Outbound';

    public static final String ENTITY_ORDER = 'CustomerOrder';
    public static final String ENTITY_INVENTORY = 'InventoryLevel';
    public static final String ENTITY_PRICING = 'PricingData';

    public static final String STATUS_SUCCESS = 'Success';
    public static final String STATUS_FAILED = 'Failed';
    public static final String STATUS_RETRY = 'RetryScheduled';

    public static final String NAMED_CREDENTIAL = 'ERP_Named_Credential';

    public static final Map<String, String> ENTITY_TO_OBJECT = new Map<String, String>{
        ENTITY_ORDER => 'Order',
        ENTITY_INVENTORY => 'Product2',
        ENTITY_PRICING => 'PricebookEntry'
    };

    public static final Map<String, String> ENTITY_TO_EXTERNAL_ID = new Map<String, String>{
        ENTITY_ORDER => 'ERP_Order_Id__c',
        ENTITY_INVENTORY => 'ERP_SKU__c',
        ENTITY_PRICING => 'ERP_Price_Id__c'
    };
}
