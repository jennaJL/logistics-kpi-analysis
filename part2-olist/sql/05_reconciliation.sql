-- Do the clean tables still match the raw data?
-- Each row compares a number from the new tables ("actual") with the same number worked out
-- directly from the raw tables, or with a fixed rule ("expected"). build_tables.py stops if any differ.

-- name: rc01_reconciliation
-- Row counts
SELECT 'rows' AS check_group, 'stg_orders = raw_orders' AS check_name, (SELECT COUNT(*) FROM raw_orders) AS expected, (SELECT COUNT(*) FROM stg_orders) AS actual
UNION ALL SELECT 'rows', 'stg_order_items = raw_order_items', (SELECT COUNT(*) FROM raw_order_items), (SELECT COUNT(*) FROM stg_order_items)
UNION ALL SELECT 'rows', 'stg_payments = raw_payments', (SELECT COUNT(*) FROM raw_payments), (SELECT COUNT(*) FROM stg_payments)
UNION ALL SELECT 'rows', 'stg_reviews = raw_reviews', (SELECT COUNT(*) FROM raw_reviews), (SELECT COUNT(*) FROM stg_reviews)
UNION ALL SELECT 'rows', 'stg_customers = raw_customers', (SELECT COUNT(*) FROM raw_customers), (SELECT COUNT(*) FROM stg_customers)
UNION ALL SELECT 'rows', 'stg_sellers = raw_sellers', (SELECT COUNT(*) FROM raw_sellers), (SELECT COUNT(*) FROM stg_sellers)
UNION ALL SELECT 'rows', 'stg_products = raw_products', (SELECT COUNT(*) FROM raw_products), (SELECT COUNT(*) FROM stg_products)
UNION ALL SELECT 'rows', 'stg_category_translation = raw + 2 added', (SELECT COUNT(*) + 2 FROM raw_category_translation), (SELECT COUNT(*) FROM stg_category_translation)
UNION ALL SELECT 'rows', 'stg_geolocation = zips with a point inside Brazil', (SELECT COUNT(DISTINCT geolocation_zip_code_prefix) FROM raw_geolocation WHERE CAST(geolocation_lat AS REAL) BETWEEN -33.8 AND 5.3 AND CAST(geolocation_lng AS REAL) BETWEEN -74.0 AND -34.8), (SELECT COUNT(*) FROM stg_geolocation)
UNION ALL SELECT 'rows', 'fct_orders = one row per raw order', (SELECT COUNT(*) FROM raw_orders), (SELECT COUNT(*) FROM fct_orders)
UNION ALL SELECT 'rows', 'dim_products = raw_products', (SELECT COUNT(*) FROM raw_products), (SELECT COUNT(*) FROM dim_products)
UNION ALL SELECT 'rows', 'dim_sellers = raw_sellers', (SELECT COUNT(*) FROM raw_sellers), (SELECT COUNT(*) FROM dim_sellers)
UNION ALL SELECT 'rows', 'dim_customers = distinct people', (SELECT COUNT(DISTINCT customer_unique_id) FROM raw_customers), (SELECT COUNT(*) FROM dim_customers)

-- Totals: the same money and counts through every table
UNION ALL SELECT 'totals', 'item price: stg_order_items', (SELECT ROUND(SUM(CAST(price AS REAL)), 2) FROM raw_order_items), (SELECT ROUND(SUM(price), 2) FROM stg_order_items)
UNION ALL SELECT 'totals', 'item price: fct_orders', (SELECT ROUND(SUM(CAST(price AS REAL)), 2) FROM raw_order_items), (SELECT ROUND(SUM(items_price), 2) FROM fct_orders)
UNION ALL SELECT 'totals', 'item price: dim_sellers', (SELECT ROUND(SUM(CAST(price AS REAL)), 2) FROM raw_order_items), (SELECT ROUND(SUM(items_price), 2) FROM dim_sellers)
UNION ALL SELECT 'totals', 'item price: dim_products', (SELECT ROUND(SUM(CAST(price AS REAL)), 2) FROM raw_order_items), (SELECT ROUND(SUM(items_price), 2) FROM dim_products)
UNION ALL SELECT 'totals', 'freight: fct_orders', (SELECT ROUND(SUM(CAST(freight_value AS REAL)), 2) FROM raw_order_items), (SELECT ROUND(SUM(freight), 2) FROM fct_orders)
UNION ALL SELECT 'totals', 'freight: dim_sellers', (SELECT ROUND(SUM(CAST(freight_value AS REAL)), 2) FROM raw_order_items), (SELECT ROUND(SUM(freight), 2) FROM dim_sellers)
UNION ALL SELECT 'totals', 'order value: dim_customers', (SELECT ROUND(SUM(CAST(price AS REAL) + CAST(freight_value AS REAL)), 2) FROM raw_order_items), (SELECT ROUND(SUM(total_order_value), 2) FROM dim_customers)
UNION ALL SELECT 'totals', 'payment value: fct_orders', (SELECT ROUND(SUM(CAST(payment_value AS REAL)), 2) FROM raw_payments), (SELECT ROUND(SUM(payment_value), 2) FROM fct_orders)
UNION ALL SELECT 'totals', 'items: fct_orders', (SELECT COUNT(*) FROM raw_order_items), (SELECT SUM(item_count) FROM fct_orders)
UNION ALL SELECT 'totals', 'items: dim_sellers', (SELECT COUNT(*) FROM raw_order_items), (SELECT SUM(items_sold) FROM dim_sellers)
UNION ALL SELECT 'totals', 'items: dim_products', (SELECT COUNT(*) FROM raw_order_items), (SELECT SUM(items_sold) FROM dim_products)
UNION ALL SELECT 'totals', 'payment rows: fct_orders', (SELECT COUNT(*) FROM raw_payments), (SELECT SUM(payment_rows) FROM fct_orders)
UNION ALL SELECT 'totals', 'review rows: fct_orders', (SELECT COUNT(*) FROM raw_reviews), (SELECT SUM(review_count) FROM fct_orders)
UNION ALL SELECT 'totals', 'orders: dim_customers', (SELECT COUNT(*) FROM raw_orders), (SELECT SUM(orders_all) FROM dim_customers)
UNION ALL SELECT 'totals', 'orders with a review: fct_orders', (SELECT COUNT(DISTINCT order_id) FROM raw_reviews), (SELECT COUNT(review_score) FROM fct_orders)

-- The definitions reproduce the numbers worked out from raw data in the quality checks
UNION ALL SELECT 'definitions', 'delivered orders with a date', (SELECT COUNT(*) FROM raw_orders WHERE order_status = 'delivered' AND order_delivered_customer_date IS NOT NULL), (SELECT SUM(is_delivered) FROM fct_orders)
UNION ALL SELECT 'definitions', 'late by calendar day', (SELECT SUM(date(order_delivered_customer_date) > date(order_estimated_delivery_date)) FROM raw_orders WHERE order_status = 'delivered' AND order_delivered_customer_date IS NOT NULL), (SELECT SUM(is_late) FROM fct_orders WHERE is_delivered = 1)
UNION ALL SELECT 'definitions', 'late by timestamp', (SELECT SUM(order_delivered_customer_date > order_estimated_delivery_date) FROM raw_orders WHERE order_status = 'delivered' AND order_delivered_customer_date IS NOT NULL), (SELECT SUM(is_late_by_timestamp) FROM fct_orders WHERE is_delivered = 1)
UNION ALL SELECT 'definitions', 'shipped, never delivered', (SELECT COUNT(*) FROM raw_orders WHERE order_status = 'shipped' AND order_delivered_customer_date IS NULL), (SELECT SUM(is_shipped_never_delivered) FROM fct_orders)
UNION ALL SELECT 'definitions', 'orders with 2+ sellers', (SELECT COUNT(*) FROM (SELECT order_id FROM raw_order_items GROUP BY order_id HAVING COUNT(DISTINCT seller_id) > 1)), (SELECT COUNT(*) FROM fct_orders WHERE seller_count > 1)
UNION ALL SELECT 'definitions', 'orders with 2+ reviews', (SELECT COUNT(*) FROM (SELECT order_id FROM raw_reviews GROUP BY order_id HAVING COUNT(*) > 1)), (SELECT COUNT(*) FROM fct_orders WHERE review_count > 1)
UNION ALL SELECT 'definitions', 'kept review really is that order''s review and score', (SELECT COUNT(DISTINCT order_id) FROM raw_reviews), (SELECT COUNT(*) FROM fct_orders f JOIN raw_reviews r ON r.order_id = f.order_id AND r.review_id = f.review_id AND CAST(r.review_score AS INTEGER) = f.review_score)
UNION ALL SELECT 'definitions', 'kept review is the latest for its order', (SELECT COUNT(DISTINCT order_id) FROM raw_reviews), (SELECT COUNT(*) FROM fct_orders f JOIN (SELECT order_id, MAX(review_answer_timestamp) AS latest FROM raw_reviews GROUP BY order_id) r ON r.order_id = f.order_id AND r.latest = f.review_answered_at)

-- Rules that must hold: each row counts the rows that break a rule, so expected is 0
UNION ALL SELECT 'rules', 'days_late = actual_days - promised_days', 0, (SELECT COUNT(*) FROM fct_orders WHERE days_late <> actual_days - promised_days)
UNION ALL SELECT 'rules', 'is_late agrees with days_late', 0, (SELECT COUNT(*) FROM fct_orders WHERE delivered_at IS NOT NULL AND is_late <> (days_late > 0))
UNION ALL SELECT 'rules', 'no delivery before purchase', 0, (SELECT COUNT(*) FROM fct_orders WHERE actual_days < 0)
UNION ALL SELECT 'rules', 'no negative stage times', 0, (SELECT COUNT(*) FROM fct_orders WHERE seller_days < 0 OR carrier_days < 0)
UNION ALL SELECT 'rules', 'late analysis: all delivered, in period, with measures', 0, (SELECT COUNT(*) FROM fct_orders WHERE in_late_analysis = 1 AND (order_status <> 'delivered' OR days_late IS NULL OR is_late IS NULL OR purchased_at < '2017-01-01' OR purchased_at >= '2018-09-01'))
UNION ALL SELECT 'rules', 'score analysis: all have a score', 0, (SELECT COUNT(*) FROM fct_orders WHERE in_score_analysis = 1 AND (review_score IS NULL OR answered_before_delivery IS NULL))
UNION ALL SELECT 'rules', 'seller_id filled only on single-seller orders', 0, (SELECT COUNT(*) FROM fct_orders WHERE (seller_count = 1) <> (seller_id IS NOT NULL) AND seller_count IS NOT NULL)
UNION ALL SELECT 'rules', 'every late-analysis order has items and a category', 0, (SELECT COUNT(*) FROM fct_orders WHERE in_late_analysis = 1 AND (item_count IS NULL OR main_category IS NULL))
UNION ALL SELECT 'rules', 'fct_orders.seller_id exists in dim_sellers', 0, (SELECT COUNT(*) FROM fct_orders WHERE seller_id IS NOT NULL AND seller_id NOT IN (SELECT seller_id FROM dim_sellers))
UNION ALL SELECT 'rules', 'fct_orders.customer_unique_id exists in dim_customers', 0, (SELECT COUNT(*) FROM fct_orders WHERE customer_unique_id IS NULL OR customer_unique_id NOT IN (SELECT customer_unique_id FROM dim_customers))
UNION ALL SELECT 'rules', 'every item product exists in dim_products', 0, (SELECT COUNT(*) FROM stg_order_items WHERE product_id NOT IN (SELECT product_id FROM dim_products))
UNION ALL SELECT 'rules', 'distances are possible within Brazil (0 to 5,000 km)', 0, (SELECT COUNT(*) FROM fct_orders WHERE distance_km < 0 OR distance_km > 5000)
UNION ALL SELECT 'rules', 'no untranslated category', 0, (SELECT COUNT(*) FROM dim_products WHERE category IS NULL OR (category_pt IS NOT NULL AND category = 'unknown'))
UNION ALL SELECT 'rules', 'price is stored as a number', 0, (SELECT COUNT(*) FROM stg_order_items WHERE typeof(price) <> 'real')
UNION ALL SELECT 'rules', 'review score is stored as a whole number from 1 to 5', 0, (SELECT COUNT(*) FROM stg_reviews WHERE typeof(review_score) <> 'integer' OR review_score NOT BETWEEN 1 AND 5);

-- name: rc02_analysis_population
-- How many orders each filter leaves, from all orders to the groups used in the analysis.
SELECT 1 AS step, 'All orders' AS filter, COUNT(*) AS orders FROM fct_orders
UNION ALL SELECT 2, 'Status delivered, with a delivery date', SUM(is_delivered) FROM fct_orders
UNION ALL SELECT 3, 'and purchased Jan 2017 to Aug 2018: late analysis', SUM(in_late_analysis) FROM fct_orders
UNION ALL SELECT 4, 'and with a review: score analysis', SUM(in_score_analysis) FROM fct_orders
UNION ALL SELECT 5, 'and answered on or after delivery day', SUM(in_score_analysis = 1 AND answered_before_delivery = 0) FROM fct_orders
UNION ALL SELECT 6, 'Late analysis: single-seller orders', SUM(in_late_analysis = 1 AND seller_id IS NOT NULL) FROM fct_orders
UNION ALL SELECT 7, 'Late analysis: single-seller, with a distance', SUM(in_late_analysis = 1 AND distance_km IS NOT NULL) FROM fct_orders
UNION ALL SELECT 8, 'Late analysis: with valid stage dates', SUM(in_late_analysis = 1 AND has_valid_stage_dates = 1) FROM fct_orders
UNION ALL SELECT 9, 'Shipped, never delivered, in period (reported separately)', SUM(is_shipped_never_delivered = 1 AND in_period = 1) FROM fct_orders
ORDER BY step;

-- name: rc03_review_groups
-- The three review groups in the final population. Each order counts once, with its latest review.
SELECT CASE is_late WHEN 1 THEN 'late' ELSE 'on time' END AS delivery,
       CASE answered_before_delivery WHEN 1 THEN 'before delivery' ELSE 'on or after delivery day' END AS answered,
       COUNT(*) AS orders,
       ROUND(AVG(review_score), 2) AS avg_score
FROM fct_orders
WHERE in_score_analysis = 1
GROUP BY is_late, answered_before_delivery
ORDER BY is_late, answered_before_delivery;

-- name: rc04_score_by_basket
-- Late rate and score by basket type, in the late analysis (issue 26).
SELECT CASE WHEN seller_count > 1 THEN '2+ sellers'
            WHEN item_count > 1 THEN 'one seller, 2+ items'
            ELSE 'one seller, one item' END AS basket,
       COUNT(*) AS orders,
       SUM(is_late) AS late_orders,
       ROUND(100.0 * SUM(is_late) / COUNT(*), 2) AS late_pct,
       ROUND(AVG(promised_days), 1) AS avg_promised_days,
       ROUND(AVG(actual_days), 1) AS avg_actual_days,
       ROUND(AVG(review_score), 2) AS avg_score,
       ROUND(AVG(CASE WHEN is_late = 0 THEN review_score END), 2) AS avg_score_on_time
FROM fct_orders
WHERE in_late_analysis = 1
GROUP BY basket
ORDER BY avg_score_on_time DESC;
