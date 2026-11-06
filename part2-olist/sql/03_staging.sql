-- Staging layer: one clean table for each raw table.
-- Clean names and real types, and small fixes listed in ISSUES_LOG.md. No rows are dropped,
-- except in stg_geolocation, which reduces many rows per zip to one point.
-- Each query is a plain SELECT. build_tables.py saves it as a table with the given name.
-- SQLite has no date type, so dates stay as ISO text, which sorts and compares correctly.

-- name: stg_orders
SELECT order_id,
       customer_id,
       order_status,
       order_purchase_timestamp      AS purchased_at,
       order_approved_at             AS approved_at,
       order_delivered_carrier_date  AS handed_to_carrier_at,
       order_delivered_customer_date AS delivered_at,
       date(order_estimated_delivery_date) AS promised_date   -- always 00:00:00 in the raw data (issue 4)
FROM raw_orders;

-- name: stg_order_items
SELECT order_id,
       CAST(order_item_id AS INTEGER) AS item_number,
       product_id,
       seller_id,
       CASE WHEN shipping_limit_date < '2019' THEN shipping_limit_date END AS shipping_limit_at,  -- issue 24
       CAST(price AS REAL)         AS price,
       CAST(freight_value AS REAL) AS freight
FROM raw_order_items;

-- name: stg_payments
SELECT order_id,
       CAST(payment_sequential AS INTEGER)   AS payment_number,
       payment_type,
       CAST(payment_installments AS INTEGER) AS installments,
       CAST(payment_value AS REAL)           AS payment_value
FROM raw_payments;

-- name: stg_reviews
SELECT review_id,
       order_id,
       CAST(review_score AS INTEGER) AS review_score,
       review_comment_title          AS comment_title,
       review_comment_message        AS comment_message,
       date(review_creation_date)    AS survey_created_date,
       review_answer_timestamp       AS answered_at
FROM raw_reviews;

-- name: stg_customers
SELECT customer_id,                                    -- one per order, not a person (issue 25)
       customer_unique_id,                             -- the person
       customer_zip_code_prefix AS zip_prefix,
       customer_city            AS city,
       customer_state           AS state
FROM raw_customers;

-- name: stg_sellers
SELECT seller_id,
       seller_zip_code_prefix AS zip_prefix,
       seller_city            AS city,
       seller_state           AS state
FROM raw_sellers;

-- name: stg_products
SELECT product_id,
       product_category_name                          AS category_pt,
       CAST(product_name_lenght AS INTEGER)           AS name_length,         -- spelling fixed (issue 21)
       CAST(product_description_lenght AS INTEGER)    AS description_length,  -- spelling fixed (issue 21)
       CAST(product_photos_qty AS INTEGER)            AS photo_count,
       NULLIF(CAST(product_weight_g AS REAL), 0)      AS weight_g,            -- 0 means missing (issue 19)
       NULLIF(CAST(product_length_cm AS REAL), 0)     AS length_cm,
       NULLIF(CAST(product_height_cm AS REAL), 0)     AS height_cm,
       NULLIF(CAST(product_width_cm AS REAL), 0)      AS width_cm
FROM raw_products;

-- name: stg_category_translation
-- The raw table plus the two categories it leaves out (issue 20).
SELECT product_category_name AS category_pt,
       product_category_name_english AS category
FROM raw_category_translation
UNION ALL SELECT 'pc_gamer', 'pc_gamer'
UNION ALL SELECT 'portateis_cozinha_e_preparadores_de_alimentos', 'portable_kitchen_and_food_preparers';

-- name: stg_geolocation
-- One point per zip prefix: the median latitude and longitude of the rows inside Brazil (issue 22).
-- SQLite has no MEDIAN, so number the rows in order and average the middle one or two.
-- For n rows, (n + 1) / 2 and (n + 2) / 2 are the same row when n is odd and the middle two when even.
WITH inside_brazil AS (
    SELECT geolocation_zip_code_prefix AS zip_prefix,
           CAST(geolocation_lat AS REAL) AS lat,
           CAST(geolocation_lng AS REAL) AS lng
    FROM raw_geolocation
    WHERE CAST(geolocation_lat AS REAL) BETWEEN -33.8 AND 5.3
      AND CAST(geolocation_lng AS REAL) BETWEEN -74.0 AND -34.8
),
ranked AS (
    SELECT zip_prefix, lat, lng,
           ROW_NUMBER() OVER (PARTITION BY zip_prefix ORDER BY lat) AS lat_rank,
           ROW_NUMBER() OVER (PARTITION BY zip_prefix ORDER BY lng) AS lng_rank,
           COUNT(*)     OVER (PARTITION BY zip_prefix)              AS n
    FROM inside_brazil
),
median_lat AS (
    SELECT zip_prefix, AVG(lat) AS lat, MAX(n) AS source_rows
    FROM ranked
    WHERE lat_rank IN ((n + 1) / 2, (n + 2) / 2)
    GROUP BY zip_prefix
),
median_lng AS (
    SELECT zip_prefix, AVG(lng) AS lng
    FROM ranked
    WHERE lng_rank IN ((n + 1) / 2, (n + 2) / 2)
    GROUP BY zip_prefix
)
SELECT a.zip_prefix, a.lat, b.lng, a.source_rows
FROM median_lat a
JOIN median_lng b ON b.zip_prefix = a.zip_prefix;
