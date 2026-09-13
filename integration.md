# Salesforce-External ERP Integration Design

## Architecture Summary

The integration is implemented on the Lightning Platform using Apex REST callouts, Named Credentials, Custom Metadata Types, Batch Apex, Queueable Apex, and Scheduled Apex.

Salesforce is the integration runtime. It pulls ERP data on a schedule and pushes Salesforce-originated changes through asynchronous queueable jobs. Configuration is metadata-driven so endpoint paths, batch sizes, retry counts, and field mappings can change without Apex edits.

## Main Components

| Component | Purpose |
| --- | --- |
| `ERPIntegrationService` | Shared HTTP, mapping, pagination, CRUD/FLS, upsert, and payload logic |
| `ERPOrderService` | Customer order sync facade |
| `ERPInventoryService` | Inventory sync facade |
| `ERPPricingService` | Pricing sync facade |
| `ERPInboundBatch` | Scheduled high-volume inbound sync processor |
| `ERPOutboundQueueable` | Near real-time outbound callout processor with retry support |
| `ERPSyncScheduler` | Scheduled Apex entry point |
| `ERPTriggerDispatcher` | Trigger-safe queueing helper |
| `ERPIntegrationLogger` | Writes sync outcomes and failures to `ERP_Integration_Log__c` |

## Authentication

All outbound REST requests use the `ERP_Named_Credential` Named Credential.

The included metadata uses `NoAuthentication` as a deployable placeholder. In the target org, update the Named Credential or connect it to an External Credential/Auth Provider according to the ERP security model.

No usernames, passwords, tokens, or secrets should be stored in Apex or custom metadata.

## Configuration Metadata

### `ERP_Endpoint__mdt`

Controls endpoint behavior by entity and direction.

Fields:

- `Entity_Type__c`
- `Direction__c`
- `HTTP_Method__c`
- `Path__c`
- `Batch_Size__c`
- `Max_Retries__c`
- `Timeout_Milliseconds__c`
- `Enabled__c`

Starter endpoint records are included for:

- `CustomerOrder` inbound and outbound
- `InventoryLevel` inbound and outbound
- `PricingData` inbound and outbound

### `ERP_Field_Mapping__mdt`

Maps ERP JSON fields to Salesforce fields.

Fields:

- `Entity_Type__c`
- `Direction__c`
- `SObject_API_Name__c`
- `Salesforce_Field_API_Name__c`
- `ERP_Field_Name__c`
- `Required__c`
- `External_Id__c`
- `Sort_Order__c`

## Data Mapping

### Customer Orders

Salesforce object: `Order`

External ID: `ERP_Order_Id__c`

| ERP Field | Salesforce Field |
| --- | --- |
| `orderId` | `ERP_Order_Id__c` |
| `salesforceAccountId` | `AccountId` |
| `orderDate` | `EffectiveDate` |
| `status` | `Status` |
| `totalAmount` | `ERP_Total_Amount__c` |

### Inventory Levels

Salesforce object: `Product2`

External ID: `ERP_SKU__c`

| ERP Field | Salesforce Field |
| --- | --- |
| `sku` | `ERP_SKU__c` |
| `name` | `Name` |
| `quantityOnHand` | `Quantity_On_Hand__c` |
| `unitCost` | `ERP_Unit_Cost__c` |

### Pricing Data

Salesforce object: `PricebookEntry`

External ID: `ERP_Price_Id__c`

| ERP Field | Salesforce Field |
| --- | --- |
| `priceId` | `ERP_Price_Id__c` |
| `salesforcePricebookId` | `Pricebook2Id` |
| `salesforceProductId` | `Product2Id` |
| `unitPrice` | `UnitPrice` |
| `active` | `IsActive` |

## Inbound Sync Flow

1. `ERPSyncScheduler` starts `ERPInboundBatch`.
2. `ERPInboundBatch` processes customer orders, inventory levels, and pricing data.
3. `ERPIntegrationService` loads enabled inbound endpoint metadata.
4. The service calls the ERP using the Named Credential.
5. Responses are read from `records`, `data`, `items`, or a root JSON list.
6. Records are mapped through `ERP_Field_Mapping__mdt`.
7. Salesforce records are upserted by external ID.
8. Results and failures are written to `ERP_Integration_Log__c`.

Inbound calls use `limit` and `offset` pagination based on endpoint `Batch_Size__c`.

## Outbound Sync Flow

1. Salesforce trigger fires after insert or update.
2. `ERPTriggerDispatcher` enqueues `ERPOutboundQueueable`.
3. The queueable loads outbound endpoint and field mapping metadata.
4. Salesforce records are queried in bulk with only mapped fields.
5. CRUD/FLS is enforced before serialization.
6. The mapped JSON payload is sent to ERP.
7. An idempotency key is included in the request header.
8. Successes and failures are logged.
9. Failed outbound jobs are retried until `Max_Retries__c` is reached.

## Duplicate Prevention

Inbound duplicate prevention is handled through Salesforce external ID upserts:

- `Order.ERP_Order_Id__c`
- `Product2.ERP_SKU__c`
- `PricebookEntry.ERP_Price_Id__c`

Outbound duplicate prevention is supported through the `Idempotency-Key` request header:

```text
<EntityType>-<SalesforceRecordId>-<SystemModstamp>
```

The ERP should store or honor this key to avoid duplicate writes during retries.

## Error Handling

The integration uses partial success processing where possible.

Logged data includes:

- Entity type
- Sync direction
- Status
- Request body
- Response body
- Error message
- Retry count
- Related Salesforce record ID
- Timestamp

HTTP status codes outside the `2xx` range are treated as failures.

## Governor Limit Strategy

- Batch Apex splits scheduled inbound processing.
- Queueable Apex performs callouts outside trigger transactions.
- SOQL queries include only mapped fields.
- Inbound pagination limits response size.
- DML uses bulk `Database.upsert` with partial success.
- CRUD and FLS checks run once per object operation path.

## Deployment Checklist

1. Deploy the Salesforce DX source.
2. Configure `ERP_Named_Credential` with the real ERP base URL and authentication.
3. Confirm custom metadata endpoint paths match the ERP API.
4. Confirm field mappings match the final ERP JSON contract.
5. Assign user/profile access to custom fields and `ERP_Integration_Log__c`.
6. Run Apex tests in the target org.
7. Schedule `ERPSyncScheduler`.
8. Monitor `ERP_Integration_Log__c` after the first scheduled run.

## Scheduling Example

```apex
System.schedule('ERP Hourly Sync', '0 0 * * * ?', new ERPSyncScheduler());
```

## Operational Notes

- Disable individual endpoint records with `Enabled__c` during ERP maintenance.
- Tune `Batch_Size__c` based on ERP response time and Salesforce callout limits.
- Add new field mappings through `ERP_Field_Mapping__mdt`; avoid editing Apex for mapping-only changes.
- Review failed `ERP_Integration_Log__c` records daily during rollout.
