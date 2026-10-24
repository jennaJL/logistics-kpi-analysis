-- Logistics KPIs. Canceled / suspected-fraud orders are excluded (they never ship).
-- Definitions:
--   on-time rate = share of shipped orders with delivery_status 'Shipping on time' or 'Advance shipping'
--   late rate    = share of shipped orders with late_flag = 1
--   delay        = days_real - days_scheduled (calendar days; positive = late)

-- name: kpi01_overview
SELECT COUNT(*)                                             AS shipped_orders,
       ROUND(100.0 * SUM(late_flag = 0) / COUNT(*), 1)      AS on_time_pct,
       ROUND(100.0 * SUM(late_flag = 1) / COUNT(*), 1)      AS late_pct,
       ROUND(AVG(days_real), 2)                             AS avg_days_real,
       ROUND(AVG(days_scheduled), 2)                        AS avg_days_promised,
       ROUND(AVG(CASE WHEN late_flag = 1
                      THEN days_real - days_scheduled END), 2) AS avg_delay_when_late
FROM shipments
WHERE delivery_status <> 'Shipping canceled';

-- name: kpi02_by_shipping_mode
-- The core question: does each service level keep its promise?
SELECT shipping_mode,
       days_scheduled                                        AS promised_days,
       ROUND(AVG(days_real), 2)                              AS avg_actual_days,
       COUNT(*)                                              AS orders,
       ROUND(100.0 * SUM(late_flag) / COUNT(*), 1)           AS late_pct,
       ROUND(AVG(days_real - days_scheduled), 2)             AS avg_delay_days
FROM shipments
WHERE delivery_status <> 'Shipping canceled'
GROUP BY shipping_mode, days_scheduled
ORDER BY promised_days;

-- name: kpi03_monthly_trend
-- Monthly volume and late rate, with a 3-month rolling average to smooth noise.
WITH monthly AS (
    SELECT substr(order_date, 1, 7)                  AS month,
           COUNT(*)                                  AS orders,
           ROUND(100.0 * SUM(late_flag) / COUNT(*), 1) AS late_pct
    FROM shipments
    WHERE delivery_status <> 'Shipping canceled'
    GROUP BY month
)
SELECT month,
       orders,
       late_pct,
       ROUND(AVG(late_pct) OVER (ORDER BY month ROWS BETWEEN 2 PRECEDING AND CURRENT ROW), 1)
           AS late_pct_rolling_3m
FROM monthly
ORDER BY month;

-- name: kpi04_by_market
SELECT market,
       COUNT(*)                                    AS orders,
       ROUND(100.0 * SUM(late_flag) / COUNT(*), 1) AS late_pct,
       ROUND(AVG(days_real - days_scheduled), 2)   AS avg_delay_days
FROM shipments
WHERE delivery_status <> 'Shipping canceled'
GROUP BY market
ORDER BY late_pct DESC;

-- name: kpi05_mode_by_market
-- Late rate per mode within each market (for a heatmap / matrix visual).
-- If the mode effect is the same everywhere, the fix is the service-level design, not a region.
SELECT market,
       shipping_mode,
       COUNT(*)                                    AS orders,
       ROUND(100.0 * SUM(late_flag) / COUNT(*), 1) AS late_pct
FROM shipments
WHERE delivery_status <> 'Shipping canceled'
GROUP BY market, shipping_mode
ORDER BY market, shipping_mode;

-- name: kpi06_worst_regions
-- Regions ranked by late rate (minimum 500 orders so small regions do not top the list by chance).
SELECT order_region,
       market,
       orders,
       late_pct,
       RANK() OVER (ORDER BY late_pct DESC) AS late_rank
FROM (
    SELECT order_region,
           MIN(market)                                 AS market,
           COUNT(*)                                    AS orders,
           ROUND(100.0 * SUM(late_flag) / COUNT(*), 1) AS late_pct
    FROM shipments
    WHERE delivery_status <> 'Shipping canceled'
    GROUP BY order_region
    HAVING COUNT(*) >= 500
)
ORDER BY late_rank;

-- name: kpi07_delay_distribution
-- How late is "late"? Orders by delay in days, per mode.
SELECT shipping_mode,
       days_real - days_scheduled AS delay_days,
       COUNT(*)                   AS orders,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (PARTITION BY shipping_mode), 1) AS pct_within_mode
FROM shipments
WHERE delivery_status <> 'Shipping canceled'
GROUP BY shipping_mode, delay_days
ORDER BY shipping_mode, delay_days;

-- name: kpi08_revenue_on_late_orders
-- Revenue tied to late deliveries: where a fix protects the most customer value.
SELECT shipping_mode,
       ROUND(SUM(revenue), 0)                                   AS revenue,
       ROUND(SUM(CASE WHEN late_flag = 1 THEN revenue END), 0)  AS revenue_late,
       ROUND(100.0 * SUM(CASE WHEN late_flag = 1 THEN revenue END) / SUM(revenue), 1)
                                                                AS pct_revenue_late
FROM shipments
WHERE delivery_status <> 'Shipping canceled'
GROUP BY shipping_mode
ORDER BY revenue_late DESC;
