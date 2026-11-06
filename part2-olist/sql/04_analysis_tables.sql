-- Analysis layer, built from the staging tables only.
--   fct_orders     one row per order, the main table for the analysis
--   dim_products   one row per product
--   dim_sellers    one row per seller
--   dim_customers  one row per person (customer_unique_id)
-- Definitions of every column are in DATA_DICTIONARY.md.

-- name: dim_products
WITH sales AS (
    SELECT product_id,
           COUNT(*) AS items_sold,
           ROUND(SUM(price), 2) AS items_price
    FROM stg_order_items
    GROUP BY product_id
)
SELECT p.product_id,
       COALESCE(t.category, 'unknown') AS category,   -- issue 19
       p.category_pt,
       p.name_length,
       p.description_length,
       p.photo_count,
       p.weight_g,
       p.length_cm,
       p.height_cm,
       p.width_cm,
       COALESCE(s.items_sold, 0) AS items_sold,
       COALESCE(s.items_price, 0) AS items_price
FROM stg_products p
LEFT JOIN stg_category_translation t ON t.category_pt = p.category_pt
LEFT JOIN sales s ON s.product_id = p.product_id;

-- name: fct_orders
-- Each source with several rows per order is reduced to one row per order BEFORE joining,
-- so nothing is double-counted (issue 5).
WITH item_totals AS (
    SELECT i.order_id,
           COUNT(*) AS item_count,
           COUNT(DISTINCT i.product_id) AS product_count,
           COUNT(DISTINCT i.seller_id) AS seller_count,
           MIN(i.seller_id) AS first_seller_id,
           ROUND(SUM(i.price), 2) AS items_price,
           ROUND(SUM(i.freight), 2) AS freight,
           -- A total weight with a missing item in it would be too low, so leave it empty.
           CASE WHEN COUNT(p.weight_g) = COUNT(*) THEN SUM(p.weight_g) END AS total_weight_g
    FROM stg_order_items i
    LEFT JOIN dim_products p ON p.product_id = i.product_id
    GROUP BY i.order_id
),
main_item AS (
    -- The category of an order is the category of its most expensive item.
    SELECT order_id, category
    FROM (
        SELECT i.order_id, p.category,
               ROW_NUMBER() OVER (PARTITION BY i.order_id ORDER BY i.price DESC, i.item_number) AS rn
        FROM stg_order_items i
        JOIN dim_products p ON p.product_id = i.product_id
    )
    WHERE rn = 1
),
payment_totals AS (
    SELECT order_id,
           COUNT(*) AS payment_rows,
           ROUND(SUM(payment_value), 2) AS payment_value
    FROM stg_payments
    GROUP BY order_id
),
latest_review AS (
    -- Keep the latest answer when an order has several reviews (issue 6).
    SELECT order_id, review_id, review_score, answered_at, review_count
    FROM (
        SELECT order_id, review_id, review_score, answered_at,
               COUNT(*) OVER (PARTITION BY order_id) AS review_count,
               ROW_NUMBER() OVER (PARTITION BY order_id ORDER BY answered_at DESC, review_id) AS rn
        FROM stg_reviews
    )
    WHERE rn = 1
),
base AS (
    SELECT o.*,
           c.customer_unique_id,
           c.state AS customer_state,
           c.zip_prefix AS customer_zip,
           i.item_count, i.product_count, i.seller_count, i.items_price, i.freight, i.total_weight_g,
           CASE WHEN i.seller_count = 1 THEN i.first_seller_id END AS seller_id,   -- issue 10
           m.category AS main_category,
           p.payment_rows, p.payment_value,
           r.review_id, r.review_score, r.answered_at AS review_answered_at, r.review_count,
           o.order_status = 'delivered' AND o.delivered_at IS NOT NULL AS is_delivered,
           o.purchased_at >= '2017-01-01' AND o.purchased_at < '2018-09-01' AS in_period,   -- issue 8
           -- Handling dates in an impossible order, or missing, are left out of stage timing (issues 14, 15).
           COALESCE(o.approved_at <= o.handed_to_carrier_at
                AND o.handed_to_carrier_at <= o.delivered_at
                AND o.purchased_at <= o.approved_at, 0) AS has_valid_stage_dates
    FROM stg_orders o
    LEFT JOIN stg_customers c ON c.customer_id = o.customer_id
    LEFT JOIN item_totals i ON i.order_id = o.order_id
    LEFT JOIN main_item m ON m.order_id = o.order_id
    LEFT JOIN payment_totals p ON p.order_id = o.order_id
    LEFT JOIN latest_review r ON r.order_id = o.order_id
)
SELECT b.order_id,
       b.customer_id,
       b.customer_unique_id,
       b.order_status,

       -- dates
       b.purchased_at,
       substr(b.purchased_at, 1, 7) AS purchase_month,
       b.approved_at,
       b.handed_to_carrier_at,
       b.delivered_at,
       b.promised_date,

       -- delivery measures, in whole calendar days (issue 4)
       CAST(julianday(b.promised_date) - julianday(date(b.purchased_at)) AS INTEGER) AS promised_days,
       CAST(julianday(date(b.delivered_at)) - julianday(date(b.purchased_at)) AS INTEGER) AS actual_days,
       CAST(julianday(date(b.delivered_at)) - julianday(b.promised_date) AS INTEGER) AS days_late,   -- negative = early
       CASE WHEN b.delivered_at IS NOT NULL THEN date(b.delivered_at) > b.promised_date END AS is_late,
       CASE WHEN b.delivered_at IS NOT NULL THEN b.delivered_at > b.promised_date END AS is_late_by_timestamp,   -- sensitivity check only

       -- where the time went, in fractional days
       b.has_valid_stage_dates,
       CASE WHEN b.has_valid_stage_dates THEN julianday(b.handed_to_carrier_at) - julianday(b.approved_at) END AS seller_days,
       CASE WHEN b.has_valid_stage_dates THEN julianday(b.delivered_at) - julianday(b.handed_to_carrier_at) END AS carrier_days,

       -- money and basket
       b.item_count,
       b.product_count,
       b.seller_count,
       b.items_price,
       b.freight,
       ROUND(b.items_price + b.freight, 2) AS order_value,
       ROUND(b.freight / (b.items_price + b.freight), 4) AS freight_share,
       b.total_weight_g,
       b.main_category,
       b.payment_rows,
       b.payment_value,

       -- review (latest answer for the order)
       b.review_id,
       b.review_score,
       b.review_answered_at,
       COALESCE(b.review_count, 0) AS review_count,
       CASE WHEN b.delivered_at IS NOT NULL AND b.review_answered_at IS NOT NULL
            THEN date(b.review_answered_at) < date(b.delivered_at) END AS answered_before_delivery,   -- issue 1

       -- where
       b.customer_state,
       b.customer_zip,
       b.seller_id,   -- single-seller orders only
       s.state AS seller_state,
       s.zip_prefix AS seller_zip,
       s.state || '-' || b.customer_state AS route,
       s.state = b.customer_state AS is_same_state,
       -- Straight-line distance between zip prefixes, so approximate. haversine_km is defined in build_tables.py.
       ROUND(haversine_km(gs.lat, gs.lng, gc.lat, gc.lng), 1) AS distance_km,

       -- who is in each analysis
       b.is_delivered,
       b.in_period,
       b.is_delivered AND b.in_period AS in_late_analysis,
       b.is_delivered AND b.in_period AND b.review_score IS NOT NULL AS in_score_analysis,
       b.order_status = 'shipped' AND b.delivered_at IS NULL AS is_shipped_never_delivered   -- issue 3
FROM base b
LEFT JOIN stg_sellers s ON s.seller_id = b.seller_id
LEFT JOIN stg_geolocation gs ON gs.zip_prefix = s.zip_prefix
LEFT JOIN stg_geolocation gc ON gc.zip_prefix = b.customer_zip;

-- name: dim_sellers
-- Sales columns cover every item the seller sold. Delivery and score columns use only
-- single-seller orders in the analysis period, because those belong clearly to one seller (issue 10).
WITH sales AS (
    SELECT seller_id,
           COUNT(*) AS items_sold,
           COUNT(DISTINCT order_id) AS orders_all,
           ROUND(SUM(price), 2) AS items_price,
           ROUND(SUM(freight), 2) AS freight
    FROM stg_order_items
    GROUP BY seller_id
),
performance AS (
    SELECT seller_id,
           COUNT(*) AS analysis_orders,
           SUM(is_late) AS late_orders,
           ROUND(100.0 * SUM(is_late) / COUNT(*), 2) AS late_pct,
           ROUND(AVG(promised_days), 1) AS avg_promised_days,
           ROUND(AVG(actual_days), 1) AS avg_actual_days,
           COUNT(review_score) AS reviewed_orders,
           ROUND(AVG(review_score), 2) AS avg_review_score,
           ROUND(AVG(CASE WHEN answered_before_delivery = 0 THEN review_score END), 2) AS avg_score_after_delivery
    FROM fct_orders
    WHERE in_late_analysis = 1 AND seller_id IS NOT NULL
    GROUP BY seller_id
)
SELECT s.seller_id,
       s.zip_prefix,
       s.city,
       s.state,
       g.lat,
       g.lng,
       COALESCE(a.items_sold, 0) AS items_sold,
       COALESCE(a.orders_all, 0) AS orders_all,
       COALESCE(a.items_price, 0) AS items_price,
       COALESCE(a.freight, 0) AS freight,
       COALESCE(p.analysis_orders, 0) AS analysis_orders,
       COALESCE(p.late_orders, 0) AS late_orders,
       p.late_pct,
       p.avg_promised_days,
       p.avg_actual_days,
       COALESCE(p.reviewed_orders, 0) AS reviewed_orders,
       p.avg_review_score,
       p.avg_score_after_delivery
FROM stg_sellers s
LEFT JOIN stg_geolocation g ON g.zip_prefix = s.zip_prefix
LEFT JOIN sales a ON a.seller_id = s.seller_id
LEFT JOIN performance p ON p.seller_id = s.seller_id;

-- name: dim_customers
-- One row per person. A person can have several addresses, so location comes from their latest order.
WITH latest_address AS (
    SELECT customer_unique_id, zip_prefix, city, state
    FROM (
        SELECT c.customer_unique_id, c.zip_prefix, c.city, c.state,
               ROW_NUMBER() OVER (PARTITION BY c.customer_unique_id
                                  ORDER BY o.purchased_at DESC, o.order_id) AS rn
        FROM stg_customers c
        JOIN stg_orders o ON o.customer_id = c.customer_id
    )
    WHERE rn = 1
),
orders AS (
    SELECT customer_unique_id,
           COUNT(*) AS orders_all,
           MIN(purchased_at) AS first_purchased_at,
           MAX(purchased_at) AS last_purchased_at,
           SUM(in_late_analysis) AS analysis_orders,
           SUM(CASE WHEN in_late_analysis = 1 THEN is_late ELSE 0 END) AS late_orders,
           COUNT(CASE WHEN in_late_analysis = 1 THEN review_score END) AS reviewed_orders,
           ROUND(AVG(CASE WHEN in_late_analysis = 1 THEN review_score END), 2) AS avg_review_score,
           ROUND(SUM(COALESCE(order_value, 0)), 2) AS total_order_value
    FROM fct_orders
    GROUP BY customer_unique_id
)
SELECT o.customer_unique_id,
       a.zip_prefix,
       a.city,
       a.state,
       g.lat,
       g.lng,
       o.orders_all,
       o.orders_all > 1 AS is_repeat_customer,
       o.first_purchased_at,
       o.last_purchased_at,
       o.analysis_orders,
       o.late_orders,
       o.reviewed_orders,
       o.avg_review_score,
       o.total_order_value
FROM orders o
JOIN latest_address a ON a.customer_unique_id = o.customer_unique_id
LEFT JOIN stg_geolocation g ON g.zip_prefix = a.zip_prefix;
