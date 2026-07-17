# Genie PAYGO Cost Explorer

Customer-shareable Azure Databricks assets for analyzing paid Genie usage and effective list-price cost.

## Contents

- `dashboard/genie-paygo-cost-explorer.lvdash.json` — importable AI/BI dashboard with seven datasets, five pages, and 74 widgets.
- `sql/customer_genie_cost_explorer.sql` — eight optional, separately runnable analysis queries.

The dashboard covers cost by time, workspace, billed identity, Genie product, channel, agent or space ID, offering, SKU, usage unit/type, correction record, currency, and attribution quality. The **SKU by product** page provides detailed SKU billing by Genie product.

## Prerequisites

The importing identity must already have:

- Permission to create a dashboard in its Azure Databricks user folder.
- Access to an existing SQL warehouse and permission to use it.
- Query access to `system.billing.usage`, `system.billing.list_prices`, and `system.access.assistant_events`.

These assets do not create warehouses, modify grants, publish dashboards, or change sharing settings.

## Import the dashboard

1. Download `dashboard/genie-paygo-cost-explorer.lvdash.json`. Do not upload the repository ZIP.
2. In Azure Databricks, open the **Dashboards** listing page.
3. Click the blue down-caret and select **Import dashboard from file**.
4. Choose `genie-paygo-cost-explorer.lvdash.json`, then click **Import dashboard**.
5. If prompted, select an existing approved SQL warehouse.
6. Validate all five pages while the dashboard remains a draft.
7. Publish and share only after the customer's normal change-control review.

Official instructions: https://learn.microsoft.com/en-us/azure/databricks/dashboards/automate/import-export#import

## Data boundaries

- Results use a rolling 30-day window and customer-visible system tables.
- Cost is an effective list-price estimate, not an invoice. It excludes negotiated discounts, credits, taxes, and free or unbilled allowance.
- `agent_id` identifies an agent or space when populated; it is not a Genie Code session or thread identifier.
- The user/workspace/hour activity comparison is heuristic and does not provide exact session-level cost attribution.

The repository contains no customer data, customer identifiers, credentials, deployment scripts, or permission-changing SQL.
