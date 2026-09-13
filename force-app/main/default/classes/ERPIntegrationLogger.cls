public with sharing class ERPIntegrationLogger {
    public static void log(
        String entityType,
        String direction,
        String status,
        String requestBody,
        String responseBody,
        String errorMessage,
        Integer retryCount,
        Id relatedRecordId
    ) {
        if (!Schema.sObjectType.ERP_Integration_Log__c.isCreateable()) {
            System.debug(LoggingLevel.ERROR, 'ERP log skipped because user lacks create access: ' + errorMessage);
            return;
        }

        ERP_Integration_Log__c entry = new ERP_Integration_Log__c(
            Entity_Type__c = entityType,
            Direction__c = direction,
            Status__c = status,
            Request_Body__c = truncateLongText(requestBody),
            Response_Body__c = truncateLongText(responseBody),
            Error_Message__c = truncateLongText(errorMessage),
            Retry_Count__c = retryCount,
            Related_Record_Id__c = relatedRecordId,
            Occurred_At__c = System.now()
        );

        SObjectAccessDecision accessDecision = Security.stripInaccessible(
            AccessType.CREATABLE,
            new List<SObject>{ entry }
        );
        insert accessDecision.getRecords();
    }

    public static void logResult(String entityType, String direction, String status, Integer processed, Integer failed) {
        log(
            entityType,
            direction,
            status,
            null,
            'processed=' + processed + '; failed=' + failed,
            failed > 0 ? String.valueOf(failed) + ' record(s) failed' : null,
            0,
            null
        );
    }

    private static String truncateLongText(String value) {
        if (String.isBlank(value)) {
            return value;
        }
        return value.length() > 32768 ? value.substring(0, 32768) : value;
    }
}
