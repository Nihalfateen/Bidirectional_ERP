@IsTest
private class ERPIntegrationServiceTest {
    private class InventoryMock implements HttpCalloutMock {
        public Integer calls = 0;
        public String lastMethod;
        public String lastBody;
        public String lastIdempotencyKey;

        public HttpResponse respond(HttpRequest request) {
            calls++;
            lastMethod = request.getMethod();
            lastBody = request.getBody();
            lastIdempotencyKey = request.getHeader('Idempotency-Key');

            HttpResponse response = new HttpResponse();
            response.setStatusCode(200);
            response.setHeader('Content-Type', 'application/json');
            if (request.getMethod() == 'GET') {
                response.setBody('{"records":[{"sku":"SKU-001","name":"Widget","quantityOnHand":42,"unitCost":9.99}]}');
            } else {
                response.setBody('{"accepted":true}');
            }
            return response;
        }
    }

    @IsTest
    static void pullInventoryUpsertsByExternalId() {
        ERPTriggerDispatcher.disabledForTest = true;
        configureInventoryMetadata();
        Test.setMock(HttpCalloutMock.class, new InventoryMock());

        Test.startTest();
        ERPIntegrationService.SyncResult firstResult = ERPInventoryService.pullFromErp();
        ERPIntegrationService.SyncResult secondResult = ERPInventoryService.pullFromErp();
        Test.stopTest();

        System.assertEquals(1, firstResult.processed, 'First pull should insert one product.');
        System.assertEquals(1, secondResult.processed, 'Second pull should update the same product.');
        System.assertEquals(0, firstResult.failed + secondResult.failed, 'No inbound records should fail.');

        List<Product2> products = [
            SELECT ERP_SKU__c, Name, Quantity_On_Hand__c, ERP_Unit_Cost__c
            FROM Product2
            WHERE ERP_SKU__c = 'SKU-001'
        ];
        System.assertEquals(1, products.size(), 'External ID upsert should prevent duplicates.');
        System.assertEquals('Widget', products[0].Name);
        System.assertEquals(Decimal.valueOf('42'), products[0].Quantity_On_Hand__c);
        System.assertEquals(Decimal.valueOf('9.99'), products[0].ERP_Unit_Cost__c);
    }

    @IsTest
    static void pushInventorySendsMappedPayloadAndIdempotencyKey() {
        ERPTriggerDispatcher.disabledForTest = true;
        configureInventoryMetadata();
        Product2 product = new Product2(
            Name = 'Widget',
            IsActive = true,
            ERP_SKU__c = 'SKU-002',
            Quantity_On_Hand__c = 15,
            ERP_Unit_Cost__c = 12.50
        );
        insert product;

        InventoryMock mock = new InventoryMock();
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        ERPIntegrationService.SyncResult result = ERPInventoryService.pushToErp(new Set<Id>{ product.Id });
        Test.stopTest();

        System.assertEquals(1, result.processed);
        System.assertEquals(0, result.failed);
        System.assertEquals('POST', mock.lastMethod);
        System.assert(mock.lastBody.contains('"sku":"SKU-002"'), 'Payload should include mapped SKU.');
        System.assert(mock.lastBody.contains('"quantityOnHand":15'), 'Payload should include mapped quantity.');
        System.assert(mock.lastIdempotencyKey != null, 'Outbound requests should include an idempotency key.');
    }

    private static void configureInventoryMetadata() {
        ERPIntegrationService.endpointOverrides.clear();
        ERPIntegrationService.mappingOverrides.clear();

        ERPIntegrationService.endpointOverrides.put(
            ERPConstants.ENTITY_INVENTORY + ':' + ERPConstants.DIRECTION_INBOUND,
            endpoint('GET', '/api/v1/inventory')
        );
        ERPIntegrationService.endpointOverrides.put(
            ERPConstants.ENTITY_INVENTORY + ':' + ERPConstants.DIRECTION_OUTBOUND,
            endpoint('POST', '/api/v1/inventory')
        );

        addMapping(ERPConstants.DIRECTION_INBOUND, 'Product2', 'ERP_SKU__c', 'sku', true, true);
        addMapping(ERPConstants.DIRECTION_INBOUND, 'Product2', 'Name', 'name', true, false);
        addMapping(ERPConstants.DIRECTION_INBOUND, 'Product2', 'Quantity_On_Hand__c', 'quantityOnHand', false, false);
        addMapping(ERPConstants.DIRECTION_INBOUND, 'Product2', 'ERP_Unit_Cost__c', 'unitCost', false, false);
        addMapping(ERPConstants.DIRECTION_OUTBOUND, 'Product2', 'ERP_SKU__c', 'sku', false, true);
        addMapping(ERPConstants.DIRECTION_OUTBOUND, 'Product2', 'Quantity_On_Hand__c', 'quantityOnHand', false, false);
    }

    private static ERPIntegrationService.EndpointConfig endpoint(String method, String path) {
        ERPIntegrationService.EndpointConfig config = new ERPIntegrationService.EndpointConfig();
        config.entityType = ERPConstants.ENTITY_INVENTORY;
        config.direction = method == 'GET' ? ERPConstants.DIRECTION_INBOUND : ERPConstants.DIRECTION_OUTBOUND;
        config.httpMethod = method;
        config.path = path;
        config.batchSize = 200;
        config.maxRetries = 2;
        config.timeoutMs = 120000;
        config.enabled = true;
        return config;
    }

    private static void addMapping(String direction, String sobjectApiName, String salesforceField, String erpField, Boolean required, Boolean externalId) {
        ERPIntegrationService.MappingConfig mapping = new ERPIntegrationService.MappingConfig();
        mapping.entityType = ERPConstants.ENTITY_INVENTORY;
        mapping.direction = direction;
        mapping.sobjectApiName = sobjectApiName;
        mapping.salesforceFieldApiName = salesforceField;
        mapping.erpFieldName = erpField;
        mapping.required = required;
        mapping.externalId = externalId;
        ERPIntegrationService.mappingOverrides.add(mapping);
    }
}
