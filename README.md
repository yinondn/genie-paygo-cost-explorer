# Genie PAYGO Cost Explorer

Use this dashboard to analyze paid Genie usage and estimated list-price cost in Databricks workspaces on AWS, Azure, or GCP.

## Disclaimer

This package is a private initiative. It is not an official Databricks product, feature, or supported solution and is provided as-is. Use is at the customer's own responsibility and risk. The customer must review, test, secure, approve, operate, and monitor it under its own policies before production use.

## Included

- `genie-paygo-cost-explorer.lvdash.json` — the dashboard file to import.
- `customer_genie_cost_explorer.sql` — optional detailed analysis queries.
- `MANIFEST.sha256` — file checksums.

## Requirements

- Permission to create a dashboard.
- Access to an approved SQL warehouse.
- Query access to `system.billing.usage`, `system.billing.list_prices`, and `system.access.assistant_events`.

## Import the dashboard

1. Extract the ZIP locally.
2. Open the **Dashboards** listing page in the Databricks workspace.
3. Click the blue down-caret, then select **Import dashboard from file**.
4. Select `genie-paygo-cost-explorer.lvdash.json` and click **Import dashboard**.
5. Select an approved SQL warehouse if prompted.
6. Refresh and review every page before publishing or sharing the dashboard.

## Important notes

- Results use a rolling 30-day window.
- Cost is an estimated effective list-price amount, not an invoice amount. It excludes negotiated discounts, credits, taxes, and free or unbilled allowance.
- `agent_id` identifies an agent or space when populated; it is not a Genie Code session or thread identifier.
- The user/workspace/hour activity comparison is heuristic and does not provide exact session-level cost attribution.

## Documentation

- Import a dashboard file: [AWS](https://docs.databricks.com/aws/en/dashboards/automate/import-export#import), [Azure](https://learn.microsoft.com/en-us/azure/databricks/dashboards/automate/import-export#import), [GCP](https://docs.databricks.com/gcp/en/dashboards/automate/import-export#import)
- Billing system tables: [AWS](https://docs.databricks.com/aws/en/admin/system-tables/billing), [Azure](https://learn.microsoft.com/en-us/azure/databricks/admin/system-tables/billing), [GCP](https://docs.databricks.com/gcp/en/admin/system-tables/billing)
- Assistant system table: [AWS](https://docs.databricks.com/aws/en/admin/system-tables/assistant), [Azure](https://learn.microsoft.com/en-us/azure/databricks/admin/system-tables/assistant), [GCP](https://docs.databricks.com/gcp/en/admin/system-tables/assistant)
- Share AI/BI dashboards: [AWS](https://docs.databricks.com/aws/en/dashboards/share), [Azure](https://learn.microsoft.com/en-us/azure/databricks/dashboards/share), [GCP](https://docs.databricks.com/gcp/en/dashboards/share)
