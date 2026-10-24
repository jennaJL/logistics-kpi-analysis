-- Data-quality checks, run before any KPI is trusted.
-- Each block starts with "-- name:"; run_queries.py saves each result to output/<name>.csv.
-- Grain: order_items = one row per order line; shipments = one row per order.

-- name: dq01_row_counts
-- How many lines and orders, and over which period.
SELECT (SELECT COUNT(*) FROM order_items)          AS order_lines,
       (SELECT COUNT(*) FROM shipments)            AS orders,
       (SELECT MIN(order_date) FROM shipments)     AS first_order,
       (SELECT MAX(order_date) FROM shipments)     AS last_order;

-- name: dq02_duplicate_lines
-- Every order line should appear once.
SELECT COUNT(*) AS duplicated_order_item_ids
FROM (SELECT order_item_id FROM order_items GROUP BY order_item_id HAVING COUNT(*) > 1);

-- name: dq03_missing_key_fields
-- Fields the KPIs depend on must never be empty.
SELECT SUM(order_id IS NULL)        AS missing_order_id,
       SUM(order_date IS NULL)      AS missing_order_date,
       SUM(shipping_date IS NULL)   AS missing_shipping_date,
       SUM(shipping_mode IS NULL)   AS missing_shipping_mode,
       SUM(delivery_status IS NULL) AS missing_delivery_status,
       SUM(market IS NULL)          AS missing_market
FROM order_items;

-- name: dq04_order_level_consistency
-- Lines of the same order must agree on mode, status and dates,
-- otherwise rolling them up to one shipment per order is not safe.
SELECT COUNT(*) AS orders_with_conflicting_lines
FROM (
    SELECT order_id
    FROM order_items
    GROUP BY order_id
    HAVING COUNT(DISTINCT shipping_mode) > 1
        OR COUNT(DISTINCT delivery_status) > 1
        OR COUNT(DISTINCT order_date) > 1
        OR COUNT(DISTINCT shipping_date) > 1
);

-- name: dq05_late_flag_vs_status
-- The late flag should be 1 exactly when the status says "Late delivery".
SELECT delivery_status,
       late_flag,
       COUNT(*) AS orders,
       CASE WHEN (delivery_status = 'Late delivery') = (late_flag = 1)
            THEN 'consistent' ELSE 'CHECK' END AS result
FROM shipments
GROUP BY delivery_status, late_flag
ORDER BY delivery_status;

-- name: dq06_days_real_definition
-- Is "days_real" counted in 24-hour periods or in calendar days?
-- Compare it with both measures computed from the two timestamps.
SELECT SUM(days_real <> CAST(julianday(shipping_date) - julianday(order_date) AS INTEGER))
           AS mismatches_24h_periods,
       SUM(days_real <> CAST(julianday(date(shipping_date)) - julianday(date(order_date)) AS INTEGER))
           AS mismatches_calendar_days,
       COUNT(*) AS orders
FROM shipments;

-- name: dq07_impossible_values
-- Values that cannot be right in a logistics table.
SELECT SUM(shipping_date < order_date) AS shipped_before_ordered,
       SUM(days_real < 0)              AS negative_days_real,
       SUM(days_scheduled < 0)         AS negative_days_scheduled,
       SUM(units <= 0)                 AS orders_without_units,
       SUM(revenue < 0)                AS negative_revenue
FROM shipments;

-- name: dq08_scheduled_days_per_mode
-- Each shipping mode should have one fixed promised lead time.
SELECT shipping_mode,
       COUNT(DISTINCT days_scheduled) AS distinct_promises,
       MIN(days_scheduled)            AS promised_days,
       COUNT(*)                       AS orders
FROM shipments
GROUP BY shipping_mode
ORDER BY promised_days;

-- name: dq09_canceled_share
-- Canceled and suspected-fraud orders never ship; they are excluded from delivery KPIs.
SELECT delivery_status,
       COUNT(*) AS orders,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1) AS pct_of_orders
FROM shipments
GROUP BY delivery_status
ORDER BY orders DESC;
