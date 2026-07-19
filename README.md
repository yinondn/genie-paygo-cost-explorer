# Genie PAYGO Cost Explorer

This is a production-oriented, import-only package for Databricks workspaces on AWS, Azure, or GCP. It analyzes paid Genie usage and effective list-price cost. Importing the dashboard creates an editable dashboard in the importing user's folder. The package does not contain scripts, change Unity Catalog grants, publish the dashboard, share it, or alter existing resources.

## Disclaimer

This package is a private initiative. It is not an official Databricks product, feature, or supported solution and is provided as-is. Use is at the customer's own responsibility and risk. The customer must review, test, secure, approve, operate, and monitor it under its own policies before production use.

The dashboard includes seven datasets, five pages, and 68 widgets. It breaks down cost by time, workspace, billed identity, Genie product, channel, agent or space ID, offering, SKU, usage unit/type, correction record, currency, and attribution quality. The simplified **Overview** keeps only usage date, Genie surface, channel, workspace, and billed-user filters. The **SKU by product** page retains the detailed filters and billing detail needed for deeper analysis.

## Package contents

- `genie-paygo-cost-explorer.lvdash.json` — the dashboard file to import.
- `customer_genie_cost_explorer.sql` — eight optional, separately runnable analysis queries. The import does not execute this file.
- `MANIFEST.sha256` — checksums for package verification with your approved tooling.

## Production prerequisites

Use an identity that already has all of the following:

- Permission to create a dashboard in its Databricks user folder.
- Access to an existing SQL warehouse and permission to use it.
- Existing query access to `system.billing.usage`, `system.billing.list_prices`, and `system.access.assistant_events`.

This package does not request or modify access. If any prerequisite is missing, stop and use the customer's normal access-request and change-control process.

## Import the dashboard

1. Extract the ZIP locally.
2. In the Databricks workspace, open the **Dashboards** listing page.
3. Click the blue down-caret, then select **Import dashboard from file**.
4. Click **Choose file** and select `genie-paygo-cost-explorer.lvdash.json`.
5. Click **Import dashboard**.

Databricks saves the imported dashboard in the importing user's folder. If the same name already exists there, Databricks appends a number to create a unique name.

## Validate the draft before production release

1. Open the imported draft dashboard.
2. If prompted, select an existing approved SQL warehouse. Do not create a new warehouse for this package.
3. Refresh the dashboard and open all five pages, including **SKU by product**.
4. Confirm that the datasets run without errors and that the results are appropriate for the workspace.
5. Keep the dashboard as a draft until the customer's normal review and change-control checks are complete.
6. Publish and share only after customer approval, using the customer's existing dashboard access model.

If validation fails, delete the imported draft. Because the package does not change grants or other resources, rollback is limited to removing that draft dashboard.

## Data and attribution boundaries

- Results use a rolling 30-day window and read customer-visible system tables.
- Cost is an effective list-price estimate, not an invoice. It excludes negotiated discounts, credits, taxes, and free or unbilled allowance.
- `agent_id` identifies an agent or space when populated; it is not a Genie Code session or thread identifier.
- The user/workspace/hour activity comparison is heuristic and does not provide exact session-level cost attribution.
- If the dashboard is empty, confirm that the Databricks account has paid Genie billing rows in the rolling window and that the importing identity already has access to the required data.

## Official references by cloud

- Import a dashboard file: [AWS](https://docs.databricks.com/aws/en/dashboards/automate/import-export#import), [Azure](https://learn.microsoft.com/en-us/azure/databricks/dashboards/automate/import-export#import), [GCP](https://docs.databricks.com/gcp/en/dashboards/automate/import-export#import)
- Billing system tables: [AWS](https://docs.databricks.com/aws/en/admin/system-tables/billing), [Azure](https://learn.microsoft.com/en-us/azure/databricks/admin/system-tables/billing), [GCP](https://docs.databricks.com/gcp/en/admin/system-tables/billing)
- Assistant system table: [AWS](https://docs.databricks.com/aws/en/admin/system-tables/assistant), [Azure](https://learn.microsoft.com/en-us/azure/databricks/admin/system-tables/assistant), [GCP](https://docs.databricks.com/gcp/en/admin/system-tables/assistant)
- Share AI/BI dashboards: [AWS](https://docs.databricks.com/aws/en/dashboards/share), [Azure](https://learn.microsoft.com/en-us/azure/databricks/dashboards/share), [GCP](https://docs.databricks.com/gcp/en/dashboards/share)
