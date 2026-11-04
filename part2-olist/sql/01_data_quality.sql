-- Data-quality checks on the raw Olist tables.
-- These checks only report what is there. Nothing is changed.
-- Missing values and exact duplicate rows are checked for every column by run_checks.py.

-- name: dq01_primary_keys
-- Is each table's expected key really unique?
SELECT 'raw_orders' AS tbl, 'order_id' AS expected_key, COUNT(*) AS row_count, COUNT(DISTINCT order_id) AS distinct_keys, COUNT(*) - COUNT(DISTINCT order_id) AS extra_rows FROM raw_orders
UNION ALL SELECT 'raw_customers', 'customer_id', COUNT(*), COUNT(DISTINCT customer_id), COUNT(*) - COUNT(DISTINCT customer_id) FROM raw_customers
UNION ALL SELECT 'raw_customers', 'customer_unique_id', COUNT(*), COUNT(DISTINCT customer_unique_id), COUNT(*) - COUNT(DISTINCT customer_unique_id) FROM raw_customers
UNION ALL SELECT 'raw_order_items', 'order_id + order_item_id', COUNT(*), COUNT(DISTINCT order_id || '-' || order_item_id), COUNT(*) - COUNT(DISTINCT order_id || '-' || order_item_id) FROM raw_order_items
UNION ALL SELECT 'raw_payments', 'order_id + payment_sequential', COUNT(*), COUNT(DISTINCT order_id || '-' || payment_sequential), COUNT(*) - COUNT(DISTINCT order_id || '-' || payment_sequential) FROM raw_payments
UNION ALL SELECT 'raw_reviews', 'review_id', COUNT(*), COUNT(DISTINCT review_id), COUNT(*) - COUNT(DISTINCT review_id) FROM raw_reviews
UNION ALL SELECT 'raw_reviews', 'order_id', COUNT(*), COUNT(DISTINCT order_id), COUNT(*) - COUNT(DISTINCT order_id) FROM raw_reviews
UNION ALL SELECT 'raw_reviews', 'review_id + order_id', COUNT(*), COUNT(DISTINCT review_id || '-' || order_id), COUNT(*) - COUNT(DISTINCT review_id || '-' || order_id) FROM raw_reviews
UNION ALL SELECT 'raw_products', 'product_id', COUNT(*), COUNT(DISTINCT product_id), COUNT(*) - COUNT(DISTINCT product_id) FROM raw_products
UNION ALL SELECT 'raw_sellers', 'seller_id', COUNT(*), COUNT(DISTINCT seller_id), COUNT(*) - COUNT(DISTINCT seller_id) FROM raw_sellers
UNION ALL SELECT 'raw_geolocation', 'geolocation_zip_code_prefix', COUNT(*), COUNT(DISTINCT geolocation_zip_code_prefix), COUNT(*) - COUNT(DISTINCT geolocation_zip_code_prefix) FROM raw_geolocation
UNION ALL SELECT 'raw_category_translation', 'product_category_name', COUNT(*), COUNT(DISTINCT product_category_name), COUNT(*) - COUNT(DISTINCT product_category_name) FROM raw_category_translation;

-- name: dq02_join_coverage
-- Does each link between tables find a match? Share of unmatched rows in each direction.
WITH checks AS (
    SELECT 'orders -> customers' AS link, COUNT(*) AS row_count, SUM(customer_id NOT IN (SELECT customer_id FROM raw_customers)) AS unmatched FROM raw_orders
    UNION ALL SELECT 'customers -> orders', COUNT(*), SUM(customer_id NOT IN (SELECT customer_id FROM raw_orders)) FROM raw_customers
    UNION ALL SELECT 'items -> orders', COUNT(*), SUM(order_id NOT IN (SELECT order_id FROM raw_orders)) FROM raw_order_items
    UNION ALL SELECT 'items -> products', COUNT(*), SUM(product_id NOT IN (SELECT product_id FROM raw_products)) FROM raw_order_items
    UNION ALL SELECT 'items -> sellers', COUNT(*), SUM(seller_id NOT IN (SELECT seller_id FROM raw_sellers)) FROM raw_order_items
    UNION ALL SELECT 'payments -> orders', COUNT(*), SUM(order_id NOT IN (SELECT order_id FROM raw_orders)) FROM raw_payments
    UNION ALL SELECT 'reviews -> orders', COUNT(*), SUM(order_id NOT IN (SELECT order_id FROM raw_orders)) FROM raw_reviews
    UNION ALL SELECT 'orders -> items', COUNT(*), SUM(order_id NOT IN (SELECT order_id FROM raw_order_items)) FROM raw_orders
    UNION ALL SELECT 'orders -> payments', COUNT(*), SUM(order_id NOT IN (SELECT order_id FROM raw_payments)) FROM raw_orders
    UNION ALL SELECT 'orders -> reviews', COUNT(*), SUM(order_id NOT IN (SELECT order_id FROM raw_reviews)) FROM raw_orders
    UNION ALL SELECT 'delivered orders -> items', COUNT(*), SUM(order_id NOT IN (SELECT order_id FROM raw_order_items)) FROM raw_orders WHERE order_status = 'delivered'
    UNION ALL SELECT 'delivered orders -> reviews', COUNT(*), SUM(order_id NOT IN (SELECT order_id FROM raw_reviews)) FROM raw_orders WHERE order_status = 'delivered'
    UNION ALL SELECT 'customers -> geolocation (zip)', COUNT(*), SUM(customer_zip_code_prefix NOT IN (SELECT geolocation_zip_code_prefix FROM raw_geolocation)) FROM raw_customers
    UNION ALL SELECT 'sellers -> geolocation (zip)', COUNT(*), SUM(seller_zip_code_prefix NOT IN (SELECT geolocation_zip_code_prefix FROM raw_geolocation)) FROM raw_sellers
    UNION ALL SELECT 'products -> category translation', COUNT(*), SUM(product_category_name IS NOT NULL AND product_category_name NOT IN (SELECT product_category_name FROM raw_category_translation)) FROM raw_products
)
SELECT link, row_count, unmatched, ROUND(100.0 * unmatched / row_count, 2) AS unmatched_pct
FROM checks;

-- name: dq03_join_fanout
-- Joining tables with several rows per order repeats rows, which inflates totals.
WITH item_totals AS (
    SELECT SUM(CAST(price AS REAL)) AS true_price FROM raw_order_items
)
SELECT 'items only' AS joined_tables,
       (SELECT COUNT(*) FROM raw_order_items) AS row_count,
       ROUND((SELECT true_price FROM item_totals), 2) AS sum_of_price,
       0.0 AS inflation_pct
UNION ALL
SELECT 'items + payments', COUNT(*), ROUND(SUM(CAST(i.price AS REAL)), 2),
       ROUND(100.0 * (SUM(CAST(i.price AS REAL)) / (SELECT true_price FROM item_totals) - 1), 2)
FROM raw_order_items i JOIN raw_payments p ON p.order_id = i.order_id
UNION ALL
SELECT 'items + reviews', COUNT(*), ROUND(SUM(CAST(i.price AS REAL)), 2),
       ROUND(100.0 * (SUM(CAST(i.price AS REAL)) / (SELECT true_price FROM item_totals) - 1), 2)
FROM raw_order_items i JOIN raw_reviews r ON r.order_id = i.order_id
UNION ALL
SELECT 'items + payments + reviews', COUNT(*), ROUND(SUM(CAST(i.price AS REAL)), 2),
       ROUND(100.0 * (SUM(CAST(i.price AS REAL)) / (SELECT true_price FROM item_totals) - 1), 2)
FROM raw_order_items i JOIN raw_payments p ON p.order_id = i.order_id JOIN raw_reviews r ON r.order_id = i.order_id;

-- name: dq04_rows_per_order
-- How many orders have more than one row in each child table?
SELECT 'items' AS child_table, COUNT(*) AS orders_with_rows, SUM(n > 1) AS orders_with_several, MAX(n) AS max_per_order FROM (SELECT COUNT(*) AS n FROM raw_order_items GROUP BY order_id)
UNION ALL SELECT 'distinct sellers', COUNT(*), SUM(n > 1), MAX(n) FROM (SELECT COUNT(DISTINCT seller_id) AS n FROM raw_order_items GROUP BY order_id)
UNION ALL SELECT 'payments', COUNT(*), SUM(n > 1), MAX(n) FROM (SELECT COUNT(*) AS n FROM raw_payments GROUP BY order_id)
UNION ALL SELECT 'reviews', COUNT(*), SUM(n > 1), MAX(n) FROM (SELECT COUNT(*) AS n FROM raw_reviews GROUP BY order_id);

-- name: dq05_multiple_reviews
-- Orders with several reviews, and review_ids shared by several orders.
SELECT 'orders with 2+ reviews' AS item, COUNT(*) AS n FROM (SELECT order_id FROM raw_reviews GROUP BY order_id HAVING COUNT(*) > 1)
UNION ALL SELECT 'of those, with different scores', COUNT(*) FROM (SELECT order_id FROM raw_reviews GROUP BY order_id HAVING COUNT(*) > 1 AND COUNT(DISTINCT review_score) > 1)
UNION ALL SELECT 'review_ids used on 2+ orders', COUNT(*) FROM (SELECT review_id FROM raw_reviews GROUP BY review_id HAVING COUNT(DISTINCT order_id) > 1)
UNION ALL SELECT 'orders touched by a shared review_id', COUNT(DISTINCT order_id) FROM raw_reviews WHERE review_id IN (SELECT review_id FROM raw_reviews GROUP BY review_id HAVING COUNT(DISTINCT order_id) > 1);

-- name: dq06_status_vs_dates
-- Which milestone dates are filled in for each order status?
SELECT order_status,
       COUNT(*) AS orders,
       SUM(order_approved_at IS NULL) AS no_approved_date,
       SUM(order_delivered_carrier_date IS NULL) AS no_carrier_date,
       SUM(order_delivered_customer_date IS NULL) AS no_customer_date,
       SUM(order_estimated_delivery_date IS NULL) AS no_promised_date
FROM raw_orders
GROUP BY order_status
ORDER BY orders DESC;

-- name: dq07_date_order
-- Do the dates happen in a possible order? Each row is one rule, counted where both dates exist.
WITH d AS (
    SELECT order_status,
           order_purchase_timestamp AS purchased,
           order_approved_at AS approved,
           order_delivered_carrier_date AS carrier,
           order_delivered_customer_date AS delivered,
           order_estimated_delivery_date AS promised
    FROM raw_orders
)
SELECT 'approved before purchase' AS rule, SUM(approved < purchased) AS violations, SUM(approved IS NOT NULL AND purchased IS NOT NULL) AS checked FROM d
UNION ALL SELECT 'handed to carrier before purchase', SUM(carrier < purchased), SUM(carrier IS NOT NULL AND purchased IS NOT NULL) FROM d
UNION ALL SELECT 'handed to carrier before approval', SUM(carrier < approved), SUM(carrier IS NOT NULL AND approved IS NOT NULL) FROM d
UNION ALL SELECT 'delivered before purchase', SUM(delivered < purchased), SUM(delivered IS NOT NULL AND purchased IS NOT NULL) FROM d
UNION ALL SELECT 'delivered before approval', SUM(delivered < approved), SUM(delivered IS NOT NULL AND approved IS NOT NULL) FROM d
UNION ALL SELECT 'delivered before handed to carrier', SUM(delivered < carrier), SUM(delivered IS NOT NULL AND carrier IS NOT NULL) FROM d
UNION ALL SELECT 'promised date before purchase', SUM(promised < purchased), SUM(promised IS NOT NULL AND purchased IS NOT NULL) FROM d;

-- name: dq08_date_ranges_and_format
-- Date ranges, plus how many non-empty values SQLite cannot read as dates.
SELECT 'order_purchase_timestamp' AS field, MIN(order_purchase_timestamp) AS earliest, MAX(order_purchase_timestamp) AS latest, SUM(order_purchase_timestamp IS NOT NULL AND julianday(order_purchase_timestamp) IS NULL) AS unreadable FROM raw_orders
UNION ALL SELECT 'order_approved_at', MIN(order_approved_at), MAX(order_approved_at), SUM(order_approved_at IS NOT NULL AND julianday(order_approved_at) IS NULL) FROM raw_orders
UNION ALL SELECT 'order_delivered_carrier_date', MIN(order_delivered_carrier_date), MAX(order_delivered_carrier_date), SUM(order_delivered_carrier_date IS NOT NULL AND julianday(order_delivered_carrier_date) IS NULL) FROM raw_orders
UNION ALL SELECT 'order_delivered_customer_date', MIN(order_delivered_customer_date), MAX(order_delivered_customer_date), SUM(order_delivered_customer_date IS NOT NULL AND julianday(order_delivered_customer_date) IS NULL) FROM raw_orders
UNION ALL SELECT 'order_estimated_delivery_date', MIN(order_estimated_delivery_date), MAX(order_estimated_delivery_date), SUM(order_estimated_delivery_date IS NOT NULL AND julianday(order_estimated_delivery_date) IS NULL) FROM raw_orders
UNION ALL SELECT 'review_creation_date', MIN(review_creation_date), MAX(review_creation_date), SUM(review_creation_date IS NOT NULL AND julianday(review_creation_date) IS NULL) FROM raw_reviews
UNION ALL SELECT 'review_answer_timestamp', MIN(review_answer_timestamp), MAX(review_answer_timestamp), SUM(review_answer_timestamp IS NOT NULL AND julianday(review_answer_timestamp) IS NULL) FROM raw_reviews
UNION ALL SELECT 'shipping_limit_date', MIN(shipping_limit_date), MAX(shipping_limit_date), SUM(shipping_limit_date IS NOT NULL AND julianday(shipping_limit_date) IS NULL) FROM raw_order_items;

-- name: dq09_monthly_orders
-- Orders per month, to find thin months at the start and end of the data.
SELECT substr(order_purchase_timestamp, 1, 7) AS month,
       COUNT(*) AS orders,
       SUM(order_status = 'delivered') AS delivered,
       ROUND(100.0 * SUM(order_status = 'delivered') / COUNT(*), 1) AS delivered_pct
FROM raw_orders
GROUP BY month
ORDER BY month;

-- name: dq10_late_definition
-- The promised date has no time of day (always 00:00:00), so a plain timestamp comparison
-- calls anything delivered on the promised day late. Compare the two definitions.
SELECT COUNT(*) AS delivered_orders_with_dates,
       SUM(time(order_estimated_delivery_date) <> '00:00:00') AS promised_dates_with_a_time,
       SUM(order_delivered_customer_date > order_estimated_delivery_date) AS late_by_timestamp,
       SUM(date(order_delivered_customer_date) > date(order_estimated_delivery_date)) AS late_by_calendar_day,
       SUM(date(order_delivered_customer_date) = date(order_estimated_delivery_date)) AS delivered_on_promised_day,
       ROUND(100.0 * SUM(order_delivered_customer_date > order_estimated_delivery_date) / COUNT(*), 2) AS late_pct_timestamp,
       ROUND(100.0 * SUM(date(order_delivered_customer_date) > date(order_estimated_delivery_date)) / COUNT(*), 2) AS late_pct_calendar_day
FROM raw_orders
WHERE order_status = 'delivered' AND order_delivered_customer_date IS NOT NULL;

-- name: dq11_review_timing
-- Was the review written after the delivery? A review written earlier cannot reflect the delivery.
-- Compared by calendar day because review_creation_date has no time of day.
WITH j AS (
    SELECT r.review_creation_date AS created,
           r.review_answer_timestamp AS answered,
           o.order_purchase_timestamp AS purchased,
           o.order_delivered_customer_date AS delivered,
           o.order_estimated_delivery_date AS promised
    FROM raw_reviews r
    JOIN raw_orders o ON o.order_id = r.order_id
    WHERE o.order_status = 'delivered' AND o.order_delivered_customer_date IS NOT NULL
),
flagged AS (
    SELECT date(delivered) > date(promised) AS is_late,
           date(created) < date(delivered) AS created_before_delivery,
           date(answered) < date(delivered) AS answered_before_delivery,
           date(created) < date(purchased) AS created_before_purchase
    FROM j
)
SELECT CASE is_late WHEN 1 THEN 'late' ELSE 'on time' END AS delivery,
       COUNT(*) AS reviews,
       SUM(created_before_delivery) AS created_before_delivery,
       ROUND(100.0 * SUM(created_before_delivery) / COUNT(*), 1) AS created_before_delivery_pct,
       SUM(answered_before_delivery) AS answered_before_delivery,
       ROUND(100.0 * SUM(answered_before_delivery) / COUNT(*), 1) AS answered_before_delivery_pct,
       SUM(created_before_purchase) AS created_before_purchase
FROM flagged
GROUP BY is_late;

-- name: dq12_review_scores
-- Are all scores valid, and how are they spread?
SELECT review_score, COUNT(*) AS reviews, ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1) AS pct
FROM raw_reviews
GROUP BY review_score
ORDER BY review_score;

-- name: dq13_money_values
-- Impossible or suspicious amounts.
SELECT 'item price <= 0' AS item, COUNT(*) AS n FROM raw_order_items WHERE CAST(price AS REAL) <= 0
UNION ALL SELECT 'freight < 0', COUNT(*) FROM raw_order_items WHERE CAST(freight_value AS REAL) < 0
UNION ALL SELECT 'freight = 0', COUNT(*) FROM raw_order_items WHERE CAST(freight_value AS REAL) = 0
UNION ALL SELECT 'freight above item price', COUNT(*) FROM raw_order_items WHERE CAST(freight_value AS REAL) > CAST(price AS REAL)
UNION ALL SELECT 'payment value = 0', COUNT(*) FROM raw_payments WHERE CAST(payment_value AS REAL) = 0
UNION ALL SELECT 'payment value < 0', COUNT(*) FROM raw_payments WHERE CAST(payment_value AS REAL) < 0
UNION ALL SELECT 'payment type not_defined', COUNT(*) FROM raw_payments WHERE payment_type = 'not_defined'
UNION ALL SELECT 'installments = 0', COUNT(*) FROM raw_payments WHERE CAST(payment_installments AS INTEGER) = 0;

-- name: dq14_items_vs_payments
-- For each order with both, does price + freight equal the amount paid?
WITH items AS (
    SELECT order_id, SUM(CAST(price AS REAL) + CAST(freight_value AS REAL)) AS item_total
    FROM raw_order_items GROUP BY order_id
),
pay AS (
    SELECT order_id, SUM(CAST(payment_value AS REAL)) AS paid
    FROM raw_payments GROUP BY order_id
),
diff AS (
    SELECT paid - item_total AS d, item_total FROM items JOIN pay USING (order_id)
)
SELECT COUNT(*) AS orders_compared,
       SUM(ABS(d) <= 0.05) AS match_within_5_cents,
       SUM(d > 0.05) AS paid_more_than_items,
       SUM(d < -0.05) AS paid_less_than_items,
       SUM(ABS(d) > 0.05 AND ABS(d) / item_total > 0.05) AS differ_by_more_than_5_pct,
       ROUND(SUM(item_total), 2) AS total_items_and_freight,
       ROUND(SUM(item_total + d), 2) AS total_paid,
       ROUND(SUM(d), 2) AS total_difference,
       ROUND(MIN(d), 2) AS biggest_underpayment,
       ROUND(MAX(d), 2) AS biggest_overpayment
FROM diff;

-- name: dq15_product_gaps
-- Gaps in product fields, the controls planned for the regression.
SELECT 'products, total' AS item, COUNT(*) AS n FROM raw_products
UNION ALL SELECT 'no category', COUNT(*) FROM raw_products WHERE product_category_name IS NULL
UNION ALL SELECT 'no weight or dimensions', COUNT(*) FROM raw_products WHERE product_weight_g IS NULL OR product_length_cm IS NULL OR product_height_cm IS NULL OR product_width_cm IS NULL
UNION ALL SELECT 'weight = 0', COUNT(*) FROM raw_products WHERE CAST(product_weight_g AS REAL) = 0
UNION ALL SELECT 'order items on a product with no category', COUNT(*) FROM raw_order_items WHERE product_id IN (SELECT product_id FROM raw_products WHERE product_category_name IS NULL)
UNION ALL SELECT 'category with no English translation: ' || product_category_name, COUNT(*) FROM raw_products WHERE product_category_name IS NOT NULL AND product_category_name NOT IN (SELECT product_category_name FROM raw_category_translation) GROUP BY product_category_name;

-- name: dq16_geolocation
-- The geolocation table has many rows per zip, and some points outside Brazil.
-- The box is Brazil's approximate extent: lat -33.8 to 5.3, lng -74 to -34.8.
SELECT COUNT(*) AS row_count,
       COUNT(DISTINCT geolocation_zip_code_prefix) AS distinct_zips,
       ROUND(1.0 * COUNT(*) / COUNT(DISTINCT geolocation_zip_code_prefix), 1) AS avg_rows_per_zip,
       SUM(CAST(geolocation_lat AS REAL) NOT BETWEEN -33.8 AND 5.3 OR CAST(geolocation_lng AS REAL) NOT BETWEEN -74.0 AND -34.8) AS rows_outside_brazil
FROM raw_geolocation;

-- name: dq17_zips_with_several_places
-- Zip prefixes linked to more than one state or city spelling.
SELECT 'zips in 2+ states' AS item, COUNT(*) AS n FROM (SELECT geolocation_zip_code_prefix FROM raw_geolocation GROUP BY 1 HAVING COUNT(DISTINCT geolocation_state) > 1)
UNION ALL SELECT 'zips with 2+ city spellings', COUNT(*) FROM (SELECT geolocation_zip_code_prefix FROM raw_geolocation GROUP BY 1 HAVING COUNT(DISTINCT geolocation_city) > 1);

-- name: dq18_late_rate_by_month
-- Late rate per purchase month, to check it is not driven by one period.
SELECT substr(order_purchase_timestamp, 1, 7) AS month,
       COUNT(*) AS delivered_orders,
       ROUND(100.0 * SUM(date(order_delivered_customer_date) > date(order_estimated_delivery_date)) / COUNT(*), 1) AS late_pct
FROM raw_orders
WHERE order_status = 'delivered' AND order_delivered_customer_date IS NOT NULL
GROUP BY month
ORDER BY month;

-- name: dq19_review_score_by_timing
-- Average score depends on whether the customer answered before the parcel arrived.
WITH j AS (
    SELECT CAST(r.review_score AS INTEGER) AS score,
           date(o.order_delivered_customer_date) > date(o.order_estimated_delivery_date) AS is_late,
           date(r.review_answer_timestamp) < date(o.order_delivered_customer_date) AS answered_before_delivery
    FROM raw_reviews r
    JOIN raw_orders o ON o.order_id = r.order_id
    WHERE o.order_status = 'delivered' AND o.order_delivered_customer_date IS NOT NULL
)
SELECT CASE is_late WHEN 1 THEN 'late' ELSE 'on time' END AS delivery,
       CASE answered_before_delivery WHEN 1 THEN 'before delivery' ELSE 'on or after delivery day' END AS answered,
       COUNT(*) AS reviews,
       ROUND(AVG(score), 2) AS avg_score,
       ROUND(100.0 * SUM(score <= 2) / COUNT(*), 1) AS score_1_or_2_pct
FROM j
GROUP BY is_late, answered_before_delivery
ORDER BY is_late, answered_before_delivery;

-- name: dq20_survey_timing
-- When is the survey created, relative to delivery and to the promised date?
-- Measured in calendar days. Only the most common gaps are listed.
SELECT * FROM (
    SELECT 'all delivered: survey minus delivery' AS measure,
           CAST(julianday(date(r.review_creation_date)) - julianday(date(o.order_delivered_customer_date)) AS INTEGER) AS days,
           COUNT(*) AS reviews
    FROM raw_reviews r JOIN raw_orders o ON o.order_id = r.order_id
    WHERE o.order_status = 'delivered' AND o.order_delivered_customer_date IS NOT NULL
    GROUP BY days ORDER BY reviews DESC LIMIT 3
)
UNION ALL
SELECT * FROM (
    SELECT 'late, survey before delivery: survey minus promised date',
           CAST(julianday(date(r.review_creation_date)) - julianday(date(o.order_estimated_delivery_date)) AS INTEGER) AS days,
           COUNT(*) AS reviews
    FROM raw_reviews r JOIN raw_orders o ON o.order_id = r.order_id
    WHERE o.order_status = 'delivered' AND o.order_delivered_customer_date IS NOT NULL
      AND date(o.order_delivered_customer_date) > date(o.order_estimated_delivery_date)
      AND date(r.review_creation_date) < date(o.order_delivered_customer_date)
    GROUP BY days ORDER BY reviews DESC LIMIT 3
);

-- name: dq21_orders_never_marked_delivered
-- Orders with no delivery date. Are they past their promise, and how did customers score them?
-- "Past promise" compares with the last delivery date in the data, 2018-10-17.
WITH scores AS (
    SELECT order_id, AVG(CAST(review_score AS REAL)) AS score
    FROM raw_reviews GROUP BY order_id
)
SELECT o.order_status,
       COUNT(*) AS orders,
       SUM(date(o.order_estimated_delivery_date) < '2018-10-17') AS past_promise,
       COUNT(s.order_id) AS orders_with_review,
       ROUND(AVG(s.score), 2) AS avg_score
FROM raw_orders o
LEFT JOIN scores s ON s.order_id = o.order_id
WHERE o.order_delivered_customer_date IS NULL
GROUP BY o.order_status
ORDER BY orders DESC;

-- name: dq22_shared_review_ids
-- When one review_id covers several orders, is it the same customer and the same answer?
WITH shared AS (
    SELECT review_id FROM raw_reviews GROUP BY review_id HAVING COUNT(DISTINCT order_id) > 1
),
per_review AS (
    SELECT r.review_id,
           COUNT(DISTINCT c.customer_unique_id) AS customers,
           COUNT(DISTINCT r.review_score) AS scores,
           COUNT(DISTINCT r.review_answer_timestamp) AS answer_times
    FROM raw_reviews r
    JOIN shared USING (review_id)
    JOIN raw_orders o ON o.order_id = r.order_id
    JOIN raw_customers c ON c.customer_id = o.customer_id
    GROUP BY r.review_id
)
SELECT COUNT(*) AS shared_review_ids,
       SUM(customers = 1) AS same_customer,
       SUM(scores = 1) AS same_score,
       SUM(answer_times = 1) AS same_answer_time
FROM per_review;

-- name: dq23_shipping_limit_years
-- Items by year of the seller's shipping deadline. Orders end in 2018.
SELECT substr(shipping_limit_date, 1, 4) AS year, COUNT(*) AS items
FROM raw_order_items
GROUP BY year
ORDER BY year;

-- name: dq24_missing_reviews_by_lateness
-- Are late orders more likely to have no review at all?
SELECT CASE WHEN date(o.order_delivered_customer_date) > date(o.order_estimated_delivery_date) THEN 'late' ELSE 'on time' END AS delivery,
       COUNT(*) AS orders,
       SUM(o.order_id NOT IN (SELECT order_id FROM raw_reviews)) AS no_review,
       ROUND(100.0 * SUM(o.order_id NOT IN (SELECT order_id FROM raw_reviews)) / COUNT(*), 2) AS no_review_pct
FROM raw_orders o
WHERE o.order_status = 'delivered' AND o.order_delivered_customer_date IS NOT NULL
GROUP BY delivery;

-- name: dq25_analysis_population
-- How many orders are left for the main analysis, and how far ahead is the promise set?
SELECT COUNT(*) AS delivered_with_date,
       SUM(order_id IN (SELECT order_id FROM raw_reviews)) AS and_with_review,
       ROUND(AVG(julianday(date(order_estimated_delivery_date)) - julianday(date(order_purchase_timestamp))), 1) AS avg_days_promised,
       ROUND(AVG(julianday(order_delivered_customer_date) - julianday(order_purchase_timestamp)), 1) AS avg_days_actual
FROM raw_orders
WHERE order_status = 'delivered' AND order_delivered_customer_date IS NOT NULL;
