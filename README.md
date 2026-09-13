# Salesforce-External ERP Integration

Bidirectional REST integration package for synchronizing customer orders, inventory levels, and pricing data between Salesforce and a legacy ERP.

## Architecture

- **Named Credential**: `ERP_Named_Credential` stores the ERP base URL and authentication outside Apex. The included metadata is a deployable placeholder; configure the real authentication protocol or External Credential in the target org.
- **Custom Metadata**:
  - `ERP_Endpoint__mdt` controls endpoint paths, direction, entity type, batch size, retry settings, and enablement.
  - `ERP_Field_Mapping__mdt` maps ERP JSON fields to Salesforce object fields.
- **Apex services**:
  - `ERPIntegrationService` handles REST callouts, JSON mapping, CRUD/FLS checks, idempotent upserts, and retry scheduling.
  - `ERPOrderService`, `ERPInventoryService`, and `ERPPricingService` contain entity-specific sync logic.
  - `ERPIntegrationLogger` writes monitoring records for failures and outcomes.
- **Async processing**:
  - `ERPOutboundQueueable` supports near real-time push from Salesforce to ERP.
  - `ERPInboundBatch` handles high-volume inbound pulls through configurable `limit`/`offset` pagination.
  - `ERPSyncScheduler` runs scheduled synchronization.

## Deployment Notes

1. Create/update the `ERP_Named_Credential` metadata with the real ERP endpoint and auth provider.
2. Deploy source with Salesforce CLI.
3. Adjust custom metadata records for ERP endpoint paths and field mappings.
4. Schedule the sync:

```apex
System.schedule('ERP Hourly Sync', '0 0 * * * ?', new ERPSyncScheduler());
```

## Idempotency

Records are matched using external ID fields:

- `Order.ERP_Order_Id__c`
- `Product2.ERP_SKU__c`
- `PricebookEntry.ERP_Price_Id__c`

The integration uses upsert where possible and outbound idempotency keys to avoid duplicate creation during retries.
