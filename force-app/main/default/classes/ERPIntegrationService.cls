public with sharing class ERPIntegrationService {
    public class EndpointConfig {
        public String developerName;
        public String entityType;
        public String direction;
        public String httpMethod;
        public String path;
        public Integer batchSize;
        public Integer maxRetries;
        public Integer timeoutMs;
        public Boolean enabled;
    }

    public class MappingConfig {
        public String entityType;
        public String direction;
        public String sobjectApiName;
        public String salesforceFieldApiName;
        public String erpFieldName;
        public Boolean required;
        public Boolean externalId;
    }

    public class SyncResult {
        public Integer processed = 0;
        public Integer failed = 0;
        public List<String> errors = new List<String>();
    }

    @TestVisible private static Map<String, EndpointConfig> endpointOverrides = new Map<String, EndpointConfig>();
    @TestVisible private static List<MappingConfig> mappingOverrides = new List<MappingConfig>();

    public static HttpResponse send(EndpointConfig endpointConfig, Object requestBody, String idempotencyKey) {
        if (endpointConfig == null || !endpointConfig.enabled) {
            throw new ERPIntegrationException('ERP endpoint is not configured or is disabled.');
        }

        HttpRequest request = new HttpRequest();
        request.setEndpoint('callout:' + ERPConstants.NAMED_CREDENTIAL + normalizePath(endpointConfig.path));
        request.setMethod(endpointConfig.httpMethod);
        request.setTimeout(endpointConfig.timeoutMs == null ? 120000 : endpointConfig.timeoutMs);
        request.setHeader('Content-Type', 'application/json');
        request.setHeader('Accept', 'application/json');
        if (!String.isBlank(idempotencyKey)) {
            request.setHeader('Idempotency-Key', idempotencyKey);
        }
        if (requestBody != null) {
            request.setBody(JSON.serialize(requestBody));
        }

        HttpResponse response = new Http().send(request);
        if (response.getStatusCode() < 200 || response.getStatusCode() >= 300) {
            throw new ERPIntegrationException(
                'ERP request failed with status ' + response.getStatusCode() + ': ' + response.getBody()
            );
        }
        return response;
    }

    public static SyncResult pullAndUpsert(String entityType) {
        EndpointConfig endpointConfig = getEndpoint(entityType, ERPConstants.DIRECTION_INBOUND);
        SyncResult totalResult = new SyncResult();
        Integer pageSize = endpointConfig.batchSize == null || endpointConfig.batchSize <= 0 ? 200 : endpointConfig.batchSize;
        Integer offset = 0;
        Boolean hasMoreRecords = true;

        while (hasMoreRecords) {
            EndpointConfig pageConfig = copyEndpoint(endpointConfig);
            pageConfig.path = appendPagination(pageConfig.path, pageSize, offset);
            HttpResponse response = send(pageConfig, null, null);
            List<Map<String, Object>> records = extractRecordList(response.getBody());
            SyncResult pageResult = upsertInboundRecords(entityType, records);
            totalResult.processed += pageResult.processed;
            totalResult.failed += pageResult.failed;
            totalResult.errors.addAll(pageResult.errors);

            hasMoreRecords = records.size() == pageSize && Limits.getCallouts() < Limits.getLimitCallouts();
            offset += pageSize;
        }

        ERPIntegrationLogger.logResult(entityType, ERPConstants.DIRECTION_INBOUND, ERPConstants.STATUS_SUCCESS, totalResult.processed, totalResult.failed);
        return totalResult;
    }

    public static SyncResult upsertInboundRecords(String entityType, List<Map<String, Object>> erpRecords) {
        SyncResult result = new SyncResult();
        if (erpRecords == null || erpRecords.isEmpty()) {
            return result;
        }

        String objectApiName = ERPConstants.ENTITY_TO_OBJECT.get(entityType);
        String externalIdField = ERPConstants.ENTITY_TO_EXTERNAL_ID.get(entityType);
        if (String.isBlank(objectApiName) || String.isBlank(externalIdField)) {
            throw new ERPIntegrationException('Unsupported ERP entity: ' + entityType);
        }

        Schema.SObjectType objectType = Schema.getGlobalDescribe().get(objectApiName);
        Schema.DescribeSObjectResult objectDescribe = objectType.getDescribe();
        if (!objectDescribe.isCreateable() || !objectDescribe.isUpdateable()) {
            throw new ERPIntegrationException('Insufficient object permissions for ' + objectApiName);
        }

        Map<String, MappingConfig> mappingsByErpField = getMappings(entityType, ERPConstants.DIRECTION_INBOUND);
        Map<String, Schema.SObjectField> fieldMap = objectDescribe.fields.getMap();
        List<SObject> recordsToUpsert = new List<SObject>();

        for (Map<String, Object> erpRecord : erpRecords) {
            SObject target = objectType.newSObject();
            for (String erpField : mappingsByErpField.keySet()) {
                MappingConfig mapping = mappingsByErpField.get(erpField);
                if (!fieldMap.containsKey(mapping.salesforceFieldApiName)) {
                    continue;
                }
                Object value = erpRecord.get(erpField);
                if (mapping.required && value == null) {
                    result.failed++;
                    result.errors.add('Missing required ERP field ' + erpField + ' for ' + entityType);
                    continue;
                }
                if (value != null) {
                    target.put(mapping.salesforceFieldApiName, coerceValue(value, fieldMap.get(mapping.salesforceFieldApiName)));
                }
            }
            if (target.get(externalIdField) == null) {
                result.failed++;
                result.errors.add('Missing external ID ' + externalIdField + ' for ' + entityType);
                continue;
            }
            recordsToUpsert.add(target);
        }

        if (recordsToUpsert.isEmpty()) {
            return result;
        }

        SObjectAccessDecision accessDecision = Security.stripInaccessible(AccessType.UPSERTABLE, recordsToUpsert);
        Schema.SObjectField externalFieldToken = fieldMap.get(externalIdField);
        Database.UpsertResult[] upsertResults = Database.upsert(accessDecision.getRecords(), externalFieldToken, false);

        for (Database.UpsertResult upsertResult : upsertResults) {
            if (upsertResult.isSuccess()) {
                result.processed++;
            } else {
                result.failed++;
                result.errors.add(formatErrors(upsertResult.getErrors()));
            }
        }
        return result;
    }

    public static SyncResult pushRecords(String entityType, Set<Id> recordIds) {
        SyncResult result = new SyncResult();
        if (recordIds == null || recordIds.isEmpty()) {
            return result;
        }

        EndpointConfig endpointConfig = getEndpoint(entityType, ERPConstants.DIRECTION_OUTBOUND);
        String objectApiName = ERPConstants.ENTITY_TO_OBJECT.get(entityType);
        Schema.DescribeSObjectResult objectDescribe = Schema.getGlobalDescribe().get(objectApiName).getDescribe();
        if (!objectDescribe.isAccessible()) {
            throw new ERPIntegrationException('Insufficient read access for ' + objectApiName);
        }

        Map<String, MappingConfig> mappingsBySalesforceField = getMappingsBySalesforceField(entityType, ERPConstants.DIRECTION_OUTBOUND);
        Set<String> fieldNames = new Set<String>{ 'Id', 'SystemModstamp' };
        fieldNames.addAll(mappingsBySalesforceField.keySet());
        String query = 'SELECT ' + String.join(new List<String>(fieldNames), ',') +
            ' FROM ' + objectApiName +
            ' WHERE Id IN :recordIds';
        List<SObject> records = Database.query(query);
        SObjectAccessDecision accessDecision = Security.stripInaccessible(AccessType.READABLE, records);

        for (SObject record : accessDecision.getRecords()) {
            Map<String, Object> payload = toErpPayload(record, mappingsBySalesforceField);
            String idempotencyKey = entityType + '-' + String.valueOf(record.get('Id')) + '-' + String.valueOf(record.get('SystemModstamp'));
            try {
                HttpResponse response = send(endpointConfig, payload, idempotencyKey);
                result.processed++;
                ERPIntegrationLogger.log(
                    entityType,
                    ERPConstants.DIRECTION_OUTBOUND,
                    ERPConstants.STATUS_SUCCESS,
                    JSON.serialize(payload),
                    response.getBody(),
                    null,
                    0,
                    (Id) record.get('Id')
                );
            } catch (Exception ex) {
                result.failed++;
                result.errors.add(ex.getMessage());
                ERPIntegrationLogger.log(
                    entityType,
                    ERPConstants.DIRECTION_OUTBOUND,
                    ERPConstants.STATUS_FAILED,
                    JSON.serialize(payload),
                    null,
                    ex.getMessage(),
                    0,
                    (Id) record.get('Id')
                );
            }
        }
        return result;
    }

    public static EndpointConfig getEndpoint(String entityType, String direction) {
        String key = entityType + ':' + direction;
        if (endpointOverrides.containsKey(key)) {
            return endpointOverrides.get(key);
        }

        List<ERP_Endpoint__mdt> rows = [
            SELECT DeveloperName, Entity_Type__c, Direction__c, HTTP_Method__c, Path__c,
                   Batch_Size__c, Max_Retries__c, Timeout_Milliseconds__c, Enabled__c
            FROM ERP_Endpoint__mdt
            WHERE Entity_Type__c = :entityType
            AND Direction__c = :direction
            AND Enabled__c = true
            LIMIT 1
        ];
        if (rows.isEmpty()) {
            throw new ERPIntegrationException('Missing ERP endpoint metadata for ' + entityType + ' ' + direction);
        }
        ERP_Endpoint__mdt row = rows[0];
        EndpointConfig config = new EndpointConfig();
        config.developerName = row.DeveloperName;
        config.entityType = row.Entity_Type__c;
        config.direction = row.Direction__c;
        config.httpMethod = row.HTTP_Method__c;
        config.path = row.Path__c;
        config.batchSize = row.Batch_Size__c == null ? 200 : Integer.valueOf(row.Batch_Size__c);
        config.maxRetries = row.Max_Retries__c == null ? 3 : Integer.valueOf(row.Max_Retries__c);
        config.timeoutMs = row.Timeout_Milliseconds__c == null ? 120000 : Integer.valueOf(row.Timeout_Milliseconds__c);
        config.enabled = row.Enabled__c;
        return config;
    }

    private static Map<String, MappingConfig> getMappings(String entityType, String direction) {
        Map<String, MappingConfig> mappingsByErpField = new Map<String, MappingConfig>();
        for (MappingConfig mapping : getMappingList(entityType, direction)) {
            mappingsByErpField.put(mapping.erpFieldName, mapping);
        }
        return mappingsByErpField;
    }

    private static Map<String, MappingConfig> getMappingsBySalesforceField(String entityType, String direction) {
        Map<String, MappingConfig> mappingsBySalesforceField = new Map<String, MappingConfig>();
        for (MappingConfig mapping : getMappingList(entityType, direction)) {
            mappingsBySalesforceField.put(mapping.salesforceFieldApiName, mapping);
        }
        return mappingsBySalesforceField;
    }

    private static List<MappingConfig> getMappingList(String entityType, String direction) {
        if (!mappingOverrides.isEmpty()) {
            List<MappingConfig> filtered = new List<MappingConfig>();
            for (MappingConfig mapping : mappingOverrides) {
                if (mapping.entityType == entityType && mapping.direction == direction) {
                    filtered.add(mapping);
                }
            }
            return filtered;
        }

        List<MappingConfig> mappings = new List<MappingConfig>();
        for (ERP_Field_Mapping__mdt row : [
            SELECT Entity_Type__c, Direction__c, SObject_API_Name__c, Salesforce_Field_API_Name__c,
                   ERP_Field_Name__c, Required__c, External_Id__c
            FROM ERP_Field_Mapping__mdt
            WHERE Entity_Type__c = :entityType
            AND Direction__c = :direction
            ORDER BY Sort_Order__c ASC
        ]) {
            MappingConfig mapping = new MappingConfig();
            mapping.entityType = row.Entity_Type__c;
            mapping.direction = row.Direction__c;
            mapping.sobjectApiName = row.SObject_API_Name__c;
            mapping.salesforceFieldApiName = row.Salesforce_Field_API_Name__c;
            mapping.erpFieldName = row.ERP_Field_Name__c;
            mapping.required = row.Required__c;
            mapping.externalId = row.External_Id__c;
            mappings.add(mapping);
        }
        return mappings;
    }

    private static List<Map<String, Object>> extractRecordList(String responseBody) {
        List<Map<String, Object>> records = new List<Map<String, Object>>();
        if (String.isBlank(responseBody)) {
            return records;
        }
        Object parsed = JSON.deserializeUntyped(responseBody);
        Object source = parsed;
        if (parsed instanceof Map<String, Object>) {
            Map<String, Object> envelope = (Map<String, Object>) parsed;
            if (envelope.containsKey('records')) {
                source = envelope.get('records');
            } else if (envelope.containsKey('data')) {
                source = envelope.get('data');
            } else if (envelope.containsKey('items')) {
                source = envelope.get('items');
            }
        }
        if (source instanceof List<Object>) {
            for (Object item : (List<Object>) source) {
                if (item instanceof Map<String, Object>) {
                    records.add((Map<String, Object>) item);
                }
            }
        }
        return records;
    }

    private static Map<String, Object> toErpPayload(SObject record, Map<String, MappingConfig> mappingsBySalesforceField) {
        Map<String, Object> payload = new Map<String, Object>();
        for (String fieldName : mappingsBySalesforceField.keySet()) {
            MappingConfig mapping = mappingsBySalesforceField.get(fieldName);
            payload.put(mapping.erpFieldName, record.get(fieldName));
        }
        return payload;
    }

    private static Object coerceValue(Object value, Schema.SObjectField fieldToken) {
        Schema.DisplayType fieldType = fieldToken.getDescribe().getType();
        if (value == null) {
            return null;
        }
        if (fieldType == Schema.DisplayType.Date) {
            return value instanceof Date ? value : Date.valueOf(String.valueOf(value));
        }
        if (fieldType == Schema.DisplayType.DateTime) {
            return value instanceof Datetime ? value : Datetime.valueOfGmt(String.valueOf(value).replace('T', ' ').replace('Z', ''));
        }
        if (fieldType == Schema.DisplayType.Currency || fieldType == Schema.DisplayType.Double || fieldType == Schema.DisplayType.Percent) {
            return Decimal.valueOf(String.valueOf(value));
        }
        if (fieldType == Schema.DisplayType.Integer) {
            return Integer.valueOf(String.valueOf(value));
        }
        if (fieldType == Schema.DisplayType.Boolean) {
            return Boolean.valueOf(String.valueOf(value));
        }
        return value;
    }

    private static String normalizePath(String path) {
        if (String.isBlank(path)) {
            return '';
        }
        return path.startsWith('/') ? path : '/' + path;
    }

    private static EndpointConfig copyEndpoint(EndpointConfig source) {
        EndpointConfig copy = new EndpointConfig();
        copy.developerName = source.developerName;
        copy.entityType = source.entityType;
        copy.direction = source.direction;
        copy.httpMethod = source.httpMethod;
        copy.path = source.path;
        copy.batchSize = source.batchSize;
        copy.maxRetries = source.maxRetries;
        copy.timeoutMs = source.timeoutMs;
        copy.enabled = source.enabled;
        return copy;
    }

    private static String appendPagination(String path, Integer limitSize, Integer offset) {
        String separator = String.isBlank(path) || !path.contains('?') ? '?' : '&';
        return path + separator + 'limit=' + limitSize + '&offset=' + offset;
    }

    private static String formatErrors(Database.Error[] errors) {
        List<String> messages = new List<String>();
        for (Database.Error error : errors) {
            messages.add(error.getStatusCode() + ': ' + error.getMessage());
        }
        return String.join(messages, '; ');
    }
}
