-- Two KPI queries used to measure the effect of indexes (see measure_performance.py).
-- They run on the raw tables, as they were written before the clean tables existed.

-- name: seller_kpi
-- Late rate and average score for every seller with at least 100 delivered orders.
-- An order with two sellers counts once for each. Reviews use the latest answer per order.
WITH delivered AS (
    SELECT order_id,
           date(order_delivered_customer_date) > date(order_estimated_delivery_date) AS is_late
    FROM raw_orders
    WHERE order_status = 'delivered' AND order_delivered_customer_date IS NOT NULL
),
order_sellers AS (
    SELECT DISTINCT order_id, seller_id FROM raw_order_items
),
latest_review AS (
    SELECT order_id, score
    FROM (
        SELECT order_id,
               CAST(review_score AS REAL) AS score,
               ROW_NUMBER() OVER (PARTITION BY order_id ORDER BY review_answer_timestamp DESC, review_id) AS rn
        FROM raw_reviews
    )
    WHERE rn = 1
)
SELECT s.seller_id,
       COUNT(*) AS orders,
       ROUND(100.0 * SUM(d.is_late) / COUNT(*), 1) AS late_pct,
       ROUND(AVG(r.score), 2) AS avg_score
FROM delivered d
JOIN order_sellers s ON s.order_id = d.order_id
LEFT JOIN latest_review r ON r.order_id = d.order_id
GROUP BY s.seller_id
HAVING COUNT(*) >= 100
ORDER BY late_pct DESC, s.seller_id;

-- name: seller_drilldown
-- One seller's orders, each with its latest review score, as a dashboard filter would ask for.
-- The review lookup runs once per order, so without an index it scans raw_reviews each time.
SELECT i.order_id,
       COUNT(*) AS items,
       ROUND(SUM(CAST(i.price AS REAL)), 2) AS item_value,
       date(o.order_delivered_customer_date) > date(o.order_estimated_delivery_date) AS is_late,
       (SELECT r.review_score
        FROM raw_reviews r
        WHERE r.order_id = i.order_id
        ORDER BY r.review_answer_timestamp DESC, r.review_id
        LIMIT 1) AS latest_score
FROM raw_order_items i
JOIN raw_orders o ON o.order_id = i.order_id
WHERE i.seller_id = :seller_id
GROUP BY i.order_id
ORDER BY i.order_id;
