-- Databricks on AWS, Azure, and GCP: Genie PAYGO Cost Explorer
-- Run each numbered statement separately in the SQL editor.
-- Default scope: rolling 30 calendar days across all workspaces visible to the account.
-- To scope one workspace, set target_workspace_id in each statement's params CTE.
-- Cost is usage quantity multiplied by the effective list price. It is not an invoice amount
-- and does not include negotiated discounts, credits, taxes, or free/unbilled allowance.
-- identity_metadata.run_as supports user attribution when populated.
-- No customer-visible billing or assistant-events field provides exact Genie Code
-- session/thread cost attribution. Query 7 is explicitly heuristic.
-- Required: SELECT on system.billing.usage and system.billing.list_prices.
-- Queries 6-7 also require SELECT on system.access.assistant_events.
-- Official documentation by cloud:
-- AWS:
-- https://docs.databricks.com/aws/en/genie/budgets#query-genie-usage-and-cost
-- https://docs.databricks.com/aws/en/admin/system-tables/billing
-- https://docs.databricks.com/aws/en/admin/system-tables/assistant
-- Azure:
-- https://learn.microsoft.com/en-us/azure/databricks/genie/budgets#query-genie-usage-and-cost
-- https://learn.microsoft.com/en-us/azure/databricks/admin/system-tables/billing
-- https://learn.microsoft.com/en-us/azure/databricks/admin/system-tables/assistant
-- GCP:
-- https://docs.databricks.com/gcp/en/genie/budgets#query-genie-usage-and-cost
-- https://docs.databricks.com/gcp/en/admin/system-tables/billing
-- https://docs.databricks.com/gcp/en/admin/system-tables/assistant

-- ============================================================================
-- 1. Raw billing records: maximum available system.billing granularity
-- ============================================================================
WITH params AS (
  SELECT
    DATE_SUB(CURRENT_DATE(), 29) AS start_date,
    DATE_ADD(CURRENT_DATE(), 1) AS end_date_exclusive,
    CAST(NULL AS STRING) AS target_workspace_id
)
SELECT
  u.record_id,
  u.usage_start_time,
  u.usage_end_time,
  u.usage_date,
  u.ingestion_date,
  u.account_id,
  u.workspace_id,
  u.identity_metadata.run_as AS user_name,
  u.identity_metadata.created_by,
  u.identity_metadata.owned_by,
  u.identity_metadata.run_by,
  u.usage_metadata.genie.surface AS genie_surface,
  u.usage_metadata.genie.channel AS genie_channel,
  u.usage_metadata.genie.agent_id AS agent_id,
  u.product_features.genie.offering_type AS offering_type,
  u.cloud,
  u.sku_name,
  u.usage_unit,
  u.usage_type,
  u.record_type,
  u.usage_quantity,
  lp.currency_code,
  lp.pricing.effective_list.default AS effective_list_unit_price,
  ROUND(u.usage_quantity * lp.pricing.effective_list.default, 6) AS list_cost
FROM system.billing.usage AS u
CROSS JOIN params AS p
LEFT JOIN system.billing.list_prices AS lp
  ON u.account_id = lp.account_id
  AND u.cloud = lp.cloud
  AND u.sku_name = lp.sku_name
  AND u.usage_unit = lp.usage_unit
  AND u.usage_start_time >= lp.price_start_time
  AND (u.usage_start_time < lp.price_end_time OR lp.price_end_time IS NULL)
WHERE u.billing_origin_product = 'GENIE'
  AND u.usage_date >= p.start_date
  AND u.usage_date < p.end_date_exclusive
  AND (p.target_workspace_id IS NULL OR u.workspace_id = p.target_workspace_id)
ORDER BY u.usage_start_time DESC, list_cost DESC;

-- ============================================================================
-- 2. Hourly paid Genie detail across every supported billing dimension
-- ============================================================================
WITH params AS (
  SELECT
    DATE_SUB(CURRENT_DATE(), 29) AS start_date,
    DATE_ADD(CURRENT_DATE(), 1) AS end_date_exclusive,
    CAST(NULL AS STRING) AS target_workspace_id
),
priced_usage AS (
  SELECT
    u.usage_date,
    DATE_TRUNC('HOUR', u.usage_start_time) AS usage_hour_utc,
    u.account_id,
    u.workspace_id,
    u.identity_metadata.run_as AS attributed_user_name,
    COALESCE(u.identity_metadata.run_as, 'Unattributed') AS user_name,
    CASE
      WHEN u.identity_metadata.run_as IS NULL THEN 'Missing'
      ELSE 'Populated'
    END AS user_attribution_status,
    COALESCE(u.usage_metadata.genie.surface, 'Unknown') AS genie_surface,
    COALESCE(u.usage_metadata.genie.channel, 'Unknown') AS genie_channel,
    COALESCE(u.usage_metadata.genie.agent_id, 'Not available') AS agent_id,
    COALESCE(u.product_features.genie.offering_type, 'Unknown') AS offering_type,
    u.cloud,
    u.sku_name,
    u.usage_unit,
    COALESCE(u.usage_type, 'Unknown') AS usage_type,
    u.record_type,
    COALESCE(lp.currency_code, 'Unknown') AS currency_code,
    CASE WHEN lp.sku_name IS NULL THEN 'Missing price' ELSE 'Priced' END AS price_status,
    u.usage_quantity,
    u.usage_quantity * lp.pricing.effective_list.default AS list_cost
  FROM system.billing.usage AS u
  CROSS JOIN params AS p
  LEFT JOIN system.billing.list_prices AS lp
    ON u.account_id = lp.account_id
    AND u.cloud = lp.cloud
    AND u.sku_name = lp.sku_name
    AND u.usage_unit = lp.usage_unit
    AND u.usage_start_time >= lp.price_start_time
    AND (u.usage_start_time < lp.price_end_time OR lp.price_end_time IS NULL)
  WHERE u.billing_origin_product = 'GENIE'
    AND u.usage_date >= p.start_date
    AND u.usage_date < p.end_date_exclusive
    AND (p.target_workspace_id IS NULL OR u.workspace_id = p.target_workspace_id)
)
SELECT
  usage_date,
  usage_hour_utc,
  account_id,
  workspace_id,
  attributed_user_name,
  user_name,
  user_attribution_status,
  genie_surface,
  genie_channel,
  agent_id,
  offering_type,
  cloud,
  sku_name,
  usage_unit,
  usage_type,
  record_type,
  currency_code,
  price_status,
  COUNT(*) AS billing_records,
  ROUND(SUM(usage_quantity), 6) AS usage_quantity,
  ROUND(SUM(list_cost), 6) AS list_cost
FROM priced_usage
GROUP BY ALL;

-- ============================================================================
-- 3. Top users, workspaces, agent or space IDs, SKUs, surfaces, and channels
-- ============================================================================
WITH params AS (
  SELECT
    DATE_SUB(CURRENT_DATE(), 29) AS start_date,
    DATE_ADD(CURRENT_DATE(), 1) AS end_date_exclusive,
    CAST(NULL AS STRING) AS target_workspace_id
),
priced_usage AS (
  SELECT
    u.workspace_id,
    u.identity_metadata.run_as AS user_name,
    u.usage_metadata.genie.surface AS genie_surface,
    u.usage_metadata.genie.channel AS genie_channel,
    u.usage_metadata.genie.agent_id AS agent_id,
    u.sku_name,
    u.usage_quantity,
    u.usage_quantity * lp.pricing.effective_list.default AS list_cost
  FROM system.billing.usage AS u
  CROSS JOIN params AS p
  INNER JOIN system.billing.list_prices AS lp
    ON u.account_id = lp.account_id
    AND u.cloud = lp.cloud
    AND u.sku_name = lp.sku_name
    AND u.usage_unit = lp.usage_unit
    AND u.usage_start_time >= lp.price_start_time
    AND (u.usage_start_time < lp.price_end_time OR lp.price_end_time IS NULL)
  WHERE u.billing_origin_product = 'GENIE'
    AND u.usage_date >= p.start_date
    AND u.usage_date < p.end_date_exclusive
    AND (p.target_workspace_id IS NULL OR u.workspace_id = p.target_workspace_id)
),
dimensioned AS (
  SELECT 'User' AS dimension_type, COALESCE(user_name, 'Unattributed') AS dimension_value, usage_quantity, list_cost FROM priced_usage
  UNION ALL
  SELECT 'Workspace', workspace_id, usage_quantity, list_cost FROM priced_usage
  UNION ALL
  SELECT 'Surface', COALESCE(genie_surface, 'Unknown'), usage_quantity, list_cost FROM priced_usage
  UNION ALL
  SELECT 'Channel', COALESCE(genie_channel, 'Unknown'), usage_quantity, list_cost FROM priced_usage
  UNION ALL
  SELECT 'Agent or space ID', agent_id, usage_quantity, list_cost FROM priced_usage WHERE agent_id IS NOT NULL
  UNION ALL
  SELECT 'SKU', sku_name, usage_quantity, list_cost FROM priced_usage
),
aggregated AS (
  SELECT
    dimension_type,
    dimension_value,
    COUNT(*) AS billing_records,
    SUM(usage_quantity) AS usage_quantity,
    SUM(list_cost) AS list_cost
  FROM dimensioned
  GROUP BY dimension_type, dimension_value
),
ranked AS (
  SELECT
    dimension_type,
    dimension_value,
    billing_records,
    usage_quantity,
    list_cost,
    list_cost / NULLIF(SUM(list_cost) OVER (PARTITION BY dimension_type), 0) AS share_of_cost,
    ROW_NUMBER() OVER (
      PARTITION BY dimension_type
      ORDER BY list_cost DESC, dimension_value
    ) AS driver_rank
  FROM aggregated
)
SELECT
  driver_rank,
  MAX(CASE WHEN dimension_type = 'User' THEN dimension_value END) AS top_user,
  ROUND(MAX(CASE WHEN dimension_type = 'User' THEN list_cost END), 6) AS top_user_cost,
  ROUND(MAX(CASE WHEN dimension_type = 'User' THEN share_of_cost END), 6) AS top_user_share,
  MAX(CASE WHEN dimension_type = 'Workspace' THEN dimension_value END) AS top_workspace,
  ROUND(MAX(CASE WHEN dimension_type = 'Workspace' THEN list_cost END), 6) AS top_workspace_cost,
  ROUND(MAX(CASE WHEN dimension_type = 'Workspace' THEN share_of_cost END), 6) AS top_workspace_share,
  MAX(CASE WHEN dimension_type = 'Agent or space ID' THEN dimension_value END) AS top_agent_or_space_id,
  ROUND(MAX(CASE WHEN dimension_type = 'Agent or space ID' THEN list_cost END), 6) AS top_agent_or_space_cost,
  ROUND(MAX(CASE WHEN dimension_type = 'Agent or space ID' THEN share_of_cost END), 6) AS top_agent_or_space_share,
  MAX(CASE WHEN dimension_type = 'SKU' THEN dimension_value END) AS top_sku,
  ROUND(MAX(CASE WHEN dimension_type = 'SKU' THEN list_cost END), 6) AS top_sku_cost,
  MAX(CASE WHEN dimension_type = 'Surface' THEN dimension_value END) AS top_surface,
  ROUND(MAX(CASE WHEN dimension_type = 'Surface' THEN list_cost END), 6) AS top_surface_cost,
  MAX(CASE WHEN dimension_type = 'Channel' THEN dimension_value END) AS top_channel,
  ROUND(MAX(CASE WHEN dimension_type = 'Channel' THEN list_cost END), 6) AS top_channel_cost
FROM ranked
WHERE driver_rank <= 15
GROUP BY driver_rank
ORDER BY driver_rank;

-- ============================================================================
-- 4. Daily trends with prior-day and rolling seven-day baselines
-- ============================================================================
WITH params AS (
  SELECT
    DATE_SUB(CURRENT_DATE(), 29) AS output_start_date,
    DATE_SUB(CURRENT_DATE(), 36) AS scan_start_date,
    DATE_ADD(CURRENT_DATE(), 1) AS end_date_exclusive,
    CAST(NULL AS STRING) AS target_workspace_id
),
daily AS (
  SELECT
    u.usage_date,
    COALESCE(u.usage_metadata.genie.surface, 'Unknown') AS genie_surface,
    COALESCE(u.usage_metadata.genie.channel, 'Unknown') AS genie_channel,
    COUNT(*) AS billing_records,
    COUNT(DISTINCT u.workspace_id) AS distinct_workspaces,
    COUNT(DISTINCT u.identity_metadata.run_as) AS distinct_users,
    SUM(u.usage_quantity) AS usage_quantity,
    SUM(u.usage_quantity * lp.pricing.effective_list.default) AS list_cost
  FROM system.billing.usage AS u
  CROSS JOIN params AS p
  INNER JOIN system.billing.list_prices AS lp
    ON u.account_id = lp.account_id
    AND u.cloud = lp.cloud
    AND u.sku_name = lp.sku_name
    AND u.usage_unit = lp.usage_unit
    AND u.usage_start_time >= lp.price_start_time
    AND (u.usage_start_time < lp.price_end_time OR lp.price_end_time IS NULL)
  WHERE u.billing_origin_product = 'GENIE'
    AND u.usage_date >= p.scan_start_date
    AND u.usage_date < p.end_date_exclusive
    AND (p.target_workspace_id IS NULL OR u.workspace_id = p.target_workspace_id)
  GROUP BY ALL
),
with_baselines AS (
  SELECT
    d.usage_date,
    d.genie_surface,
    d.genie_channel,
    d.billing_records,
    d.distinct_workspaces,
    d.distinct_users,
    d.usage_quantity,
    d.list_cost,
    prior_day.list_cost AS prior_day_cost,
    COALESCE(SUM(prior_7d.list_cost), 0) / 7 AS prior_7d_avg_cost
  FROM daily AS d
  LEFT JOIN daily AS prior_day
    ON prior_day.genie_surface = d.genie_surface
    AND prior_day.genie_channel = d.genie_channel
    AND prior_day.usage_date = DATE_SUB(d.usage_date, 1)
  LEFT JOIN daily AS prior_7d
    ON prior_7d.genie_surface = d.genie_surface
    AND prior_7d.genie_channel = d.genie_channel
    AND prior_7d.usage_date >= DATE_SUB(d.usage_date, 7)
    AND prior_7d.usage_date < d.usage_date
  GROUP BY
    d.usage_date,
    d.genie_surface,
    d.genie_channel,
    d.billing_records,
    d.distinct_workspaces,
    d.distinct_users,
    d.usage_quantity,
    d.list_cost,
    prior_day.list_cost
)
SELECT
  usage_date,
  genie_surface,
  genie_channel,
  billing_records,
  distinct_workspaces,
  distinct_users,
  ROUND(usage_quantity, 6) AS usage_quantity,
  ROUND(list_cost, 6) AS list_cost,
  ROUND(prior_day_cost, 6) AS prior_day_cost,
  ROUND(prior_7d_avg_cost, 6) AS prior_7d_avg_cost,
  ROUND((list_cost - prior_7d_avg_cost) / NULLIF(prior_7d_avg_cost, 0), 6) AS variance_vs_prior_7d
FROM with_baselines
CROSS JOIN params AS p
WHERE usage_date >= p.output_start_date
  AND usage_date < p.end_date_exclusive;

-- ============================================================================
-- 5. User, agent-ID, and price metadata coverage by workspace and day
-- ============================================================================
WITH params AS (
  SELECT
    DATE_SUB(CURRENT_DATE(), 29) AS start_date,
    DATE_ADD(CURRENT_DATE(), 1) AS end_date_exclusive,
    CAST(NULL AS STRING) AS target_workspace_id
),
quality AS (
  SELECT
    u.usage_date,
    u.workspace_id,
    COALESCE(u.usage_metadata.genie.surface, 'Unknown') AS genie_surface,
    COALESCE(u.usage_metadata.genie.channel, 'Unknown') AS genie_channel,
    COUNT(*) AS billing_records,
    COUNT_IF(u.identity_metadata.run_as IS NOT NULL) AS records_with_user,
    COUNT_IF(u.identity_metadata.run_as IS NULL) AS records_without_user,
    COUNT_IF(u.usage_metadata.genie.agent_id IS NOT NULL) AS records_with_agent_id,
    COUNT_IF(lp.sku_name IS NOT NULL) AS records_with_price,
    COUNT(DISTINCT u.identity_metadata.run_as) AS distinct_users,
    COUNT(DISTINCT u.usage_metadata.genie.agent_id) AS distinct_agent_ids,
    SUM(u.usage_quantity * lp.pricing.effective_list.default) AS list_cost,
    SUM(
      CASE
        WHEN u.identity_metadata.run_as IS NULL
        THEN u.usage_quantity * lp.pricing.effective_list.default
        ELSE 0
      END
    ) AS unattributed_list_cost
  FROM system.billing.usage AS u
  CROSS JOIN params AS p
  LEFT JOIN system.billing.list_prices AS lp
    ON u.account_id = lp.account_id
    AND u.cloud = lp.cloud
    AND u.sku_name = lp.sku_name
    AND u.usage_unit = lp.usage_unit
    AND u.usage_start_time >= lp.price_start_time
    AND (u.usage_start_time < lp.price_end_time OR lp.price_end_time IS NULL)
  WHERE u.billing_origin_product = 'GENIE'
    AND u.usage_date >= p.start_date
    AND u.usage_date < p.end_date_exclusive
    AND (p.target_workspace_id IS NULL OR u.workspace_id = p.target_workspace_id)
  GROUP BY ALL
)
SELECT
  usage_date,
  workspace_id,
  genie_surface,
  genie_channel,
  billing_records,
  records_with_user,
  records_without_user,
  records_with_agent_id,
  records_with_price,
  distinct_users,
  distinct_agent_ids,
  ROUND(records_with_user / NULLIF(billing_records, 0), 6) AS user_coverage_ratio,
  ROUND(records_with_agent_id / NULLIF(billing_records, 0), 6) AS agent_id_coverage_ratio,
  ROUND(records_with_price / NULLIF(billing_records, 0), 6) AS price_coverage_ratio,
  ROUND(list_cost, 6) AS list_cost,
  ROUND(unattributed_list_cost, 6) AS unattributed_list_cost
FROM quality;

-- ============================================================================
-- 6. Genie Code assistant activity by user, workspace, and hour
-- ============================================================================
WITH params AS (
  SELECT
    DATE_SUB(CURRENT_DATE(), 29) AS start_date,
    DATE_ADD(CURRENT_DATE(), 1) AS end_date_exclusive,
    CAST(NULL AS STRING) AS target_workspace_id
)
SELECT
  a.event_date,
  DATE_TRUNC('HOUR', a.event_time) AS event_hour_utc,
  a.account_id,
  a.workspace_id,
  a.initiated_by AS user_name,
  COALESCE(a.user_agent, 'Unknown') AS user_agent,
  COUNT(*) AS assistant_events
FROM system.access.assistant_events AS a
CROSS JOIN params AS p
WHERE a.event_date >= p.start_date
  AND a.event_date < p.end_date_exclusive
  AND (p.target_workspace_id IS NULL OR a.workspace_id = p.target_workspace_id)
GROUP BY ALL;

-- ============================================================================
-- 7. Heuristic Genie Code billing and activity context by user/workspace/hour
-- ============================================================================
WITH params AS (
  SELECT
    DATE_SUB(CURRENT_DATE(), 29) AS start_date,
    DATE_ADD(CURRENT_DATE(), 1) AS end_date_exclusive,
    CAST(NULL AS STRING) AS target_workspace_id
),
code_cost AS (
  SELECT
    DATE_TRUNC('HOUR', u.usage_start_time) AS activity_hour_utc,
    u.workspace_id,
    u.identity_metadata.run_as AS user_name,
    COUNT(*) AS billing_records,
    SUM(u.usage_quantity) AS usage_quantity,
    SUM(u.usage_quantity * lp.pricing.effective_list.default) AS list_cost
  FROM system.billing.usage AS u
  CROSS JOIN params AS p
  INNER JOIN system.billing.list_prices AS lp
    ON u.account_id = lp.account_id
    AND u.cloud = lp.cloud
    AND u.sku_name = lp.sku_name
    AND u.usage_unit = lp.usage_unit
    AND u.usage_start_time >= lp.price_start_time
    AND (u.usage_start_time < lp.price_end_time OR lp.price_end_time IS NULL)
  WHERE u.billing_origin_product = 'GENIE'
    AND u.usage_metadata.genie.surface = 'GENIE_CODE'
    AND u.usage_date >= p.start_date
    AND u.usage_date < p.end_date_exclusive
    AND (p.target_workspace_id IS NULL OR u.workspace_id = p.target_workspace_id)
  GROUP BY ALL
),
events AS (
  SELECT
    DATE_TRUNC('HOUR', a.event_time) AS activity_hour_utc,
    a.workspace_id,
    a.initiated_by AS user_name,
    COUNT(*) AS assistant_events
  FROM system.access.assistant_events AS a
  CROSS JOIN params AS p
  WHERE a.event_date >= p.start_date
    AND a.event_date < p.end_date_exclusive
    AND (p.target_workspace_id IS NULL OR a.workspace_id = p.target_workspace_id)
  GROUP BY ALL
)
SELECT
  COALESCE(c.activity_hour_utc, e.activity_hour_utc) AS activity_hour_utc,
  COALESCE(c.workspace_id, e.workspace_id) AS workspace_id,
  COALESCE(c.user_name, e.user_name) AS user_name,
  COALESCE(c.billing_records, 0) AS billing_records,
  ROUND(COALESCE(c.usage_quantity, 0), 6) AS usage_quantity,
  ROUND(COALESCE(c.list_cost, 0), 6) AS list_cost,
  COALESCE(e.assistant_events, 0) AS assistant_events,
  'Heuristic user/workspace/hour context only - not session attribution' AS attribution_limit
FROM code_cost AS c
FULL OUTER JOIN events AS e
  ON c.activity_hour_utc = e.activity_hour_utc
  AND c.workspace_id = e.workspace_id
  AND c.user_name = e.user_name;

-- ============================================================================
-- 8. Detailed SKU billing by Genie product, workspace, and day
-- ============================================================================
WITH params AS (
  SELECT
    DATE_SUB(CURRENT_DATE(), 29) AS start_date,
    DATE_ADD(CURRENT_DATE(), 1) AS end_date_exclusive,
    CAST(NULL AS STRING) AS target_workspace_id
),
priced_usage AS (
  SELECT
    u.usage_date,
    u.account_id,
    u.workspace_id,
    u.identity_metadata.run_as AS attributed_user_name,
    COALESCE(u.usage_metadata.genie.surface, 'Unknown') AS genie_product,
    COALESCE(u.usage_metadata.genie.channel, 'Unknown') AS genie_channel,
    COALESCE(u.product_features.genie.offering_type, 'Unknown') AS offering_type,
    u.sku_name,
    u.usage_unit,
    COALESCE(u.usage_type, 'Unknown') AS usage_type,
    u.record_type,
    COALESCE(lp.currency_code, 'Unknown') AS currency_code,
    CASE WHEN lp.sku_name IS NULL THEN 'Missing price' ELSE 'Priced' END AS price_status,
    u.usage_quantity,
    u.usage_quantity * lp.pricing.effective_list.default AS list_cost
  FROM system.billing.usage AS u
  CROSS JOIN params AS p
  LEFT JOIN system.billing.list_prices AS lp
    ON u.account_id = lp.account_id
    AND u.cloud = lp.cloud
    AND u.sku_name = lp.sku_name
    AND u.usage_unit = lp.usage_unit
    AND u.usage_start_time >= lp.price_start_time
    AND (u.usage_start_time < lp.price_end_time OR lp.price_end_time IS NULL)
  WHERE u.billing_origin_product = 'GENIE'
    AND u.usage_date >= p.start_date
    AND u.usage_date < p.end_date_exclusive
    AND (p.target_workspace_id IS NULL OR u.workspace_id = p.target_workspace_id)
)
SELECT
  usage_date,
  account_id,
  workspace_id,
  genie_product,
  genie_channel,
  offering_type,
  sku_name,
  usage_unit,
  usage_type,
  record_type,
  currency_code,
  price_status,
  COUNT(*) AS billing_records,
  COUNT(DISTINCT attributed_user_name) AS distinct_billed_users,
  ROUND(SUM(usage_quantity), 6) AS usage_quantity,
  ROUND(SUM(list_cost), 6) AS list_cost,
  ROUND(SUM(list_cost) / NULLIF(SUM(usage_quantity), 0), 6) AS effective_unit_price
FROM priced_usage
GROUP BY ALL;
