-- Step 3: how much does late delivery hurt customers?
-- Population: fct_orders where in_score_analysis = 1 (delivered Jan 2017 to Aug 2018, with a review).
-- "Bad review" = 1 or 2 stars. Every query is shown twice: all reviews, and only reviews
-- answered on or after the delivery day (answered_before_delivery = 0), see issue 1.

-- name: li01_score_late_vs_on_time
SELECT CASE WHEN answered_before_delivery = 1 THEN 'before delivery' ELSE 'on/after delivery' END AS review_timing,
       CASE WHEN is_late = 1 THEN 'late' ELSE 'on time' END AS delivery,
       COUNT(*) AS orders,
       ROUND(AVG(review_score), 2) AS avg_score,
       ROUND(100.0 * AVG(review_score <= 2), 1) AS bad_review_pct,
       ROUND(100.0 * AVG(review_score = 5), 1) AS five_star_pct
FROM fct_orders
WHERE in_score_analysis = 1
GROUP BY 1, 2
UNION ALL
SELECT 'all reviews',
       CASE WHEN is_late = 1 THEN 'late' ELSE 'on time' END,
       COUNT(*),
       ROUND(AVG(review_score), 2),
       ROUND(100.0 * AVG(review_score <= 2), 1),
       ROUND(100.0 * AVG(review_score = 5), 1)
FROM fct_orders
WHERE in_score_analysis = 1
GROUP BY 2
ORDER BY 1, 2;

-- name: li02_score_by_days_late
-- Does it get worse the later the parcel is? Early and on-time orders are split too.
WITH banded AS (
    SELECT *,
           CASE WHEN days_late <= -8 THEN '1. 8+ days early'
                WHEN days_late <= -1 THEN '2. 1-7 days early'
                WHEN days_late = 0  THEN '3. on promised day'
                WHEN days_late <= 3 THEN '4. 1-3 days late'
                WHEN days_late <= 7 THEN '5. 4-7 days late'
                WHEN days_late <= 14 THEN '6. 8-14 days late'
                ELSE '7. 15+ days late' END AS band
    FROM fct_orders
    WHERE in_score_analysis = 1
)
SELECT band,
       COUNT(*) AS orders,
       ROUND(AVG(review_score), 2) AS avg_score,
       ROUND(100.0 * AVG(review_score <= 2), 1) AS bad_review_pct,
       SUM(answered_before_delivery = 0) AS orders_after_delivery,
       ROUND(AVG(CASE WHEN answered_before_delivery = 0 THEN review_score END), 2) AS avg_score_after_delivery,
       ROUND(100.0 * AVG(CASE WHEN answered_before_delivery = 0 THEN review_score <= 2 END), 1) AS bad_review_pct_after_delivery
FROM banded
GROUP BY band
ORDER BY band;

-- name: li03_bad_reviews_caused_by_lateness
-- How many bad reviews would disappear if late orders scored like on-time orders?
-- Excess = late bad reviews - late orders * on-time bad-review rate.
WITH rates AS (
    SELECT AVG(CASE WHEN is_late = 0 THEN review_score <= 2 END) AS on_time_bad_rate,
           SUM(is_late) AS late_orders,
           SUM(is_late = 1 AND review_score <= 2) AS late_bad,
           SUM(review_score <= 2) AS all_bad
    FROM fct_orders
    WHERE in_score_analysis = 1
)
SELECT late_orders,
       late_bad,
       ROUND(late_orders * on_time_bad_rate) AS late_bad_expected_if_on_time,
       ROUND(late_bad - late_orders * on_time_bad_rate) AS excess_bad_reviews,
       all_bad,
       ROUND(100.0 * (late_bad - late_orders * on_time_bad_rate) / all_bad, 1) AS excess_pct_of_all_bad
FROM rates;

-- name: li04_late_rate_and_impact_by_state
-- Where to act first: customer states with 1,000+ reviewed orders, ranked by excess bad reviews.
WITH by_state AS (
    SELECT customer_state,
           COUNT(*) AS orders,
           SUM(is_late) AS late_orders,
           AVG(CASE WHEN is_late = 0 THEN review_score <= 2 END) AS on_time_bad_rate,
           AVG(CASE WHEN is_late = 1 THEN review_score <= 2 END) AS late_bad_rate
    FROM fct_orders
    WHERE in_score_analysis = 1
    GROUP BY customer_state
    HAVING COUNT(*) >= 1000
)
SELECT customer_state,
       orders,
       late_orders,
       ROUND(100.0 * late_orders / orders, 1) AS late_pct,
       ROUND(100.0 * on_time_bad_rate, 1) AS on_time_bad_pct,
       ROUND(100.0 * late_bad_rate, 1) AS late_bad_pct,
       ROUND(late_orders * (late_bad_rate - on_time_bad_rate)) AS excess_bad_reviews,
       RANK() OVER (ORDER BY late_orders * (late_bad_rate - on_time_bad_rate) DESC) AS impact_rank
FROM by_state
ORDER BY impact_rank;

-- name: li08_late_rate_by_seller
-- Which sellers cause the most late orders? Single-seller orders only (seller_id is empty on
-- multi-seller orders, issue 10). Sellers with 100+ orders in the late analysis, ranked by
-- excess late orders = late orders - orders * overall late rate.
WITH overall AS (
    SELECT AVG(is_late) AS late_rate
    FROM fct_orders
    WHERE in_late_analysis = 1 AND seller_id IS NOT NULL
),
by_seller AS (
    SELECT seller_id,
           MAX(seller_state) AS seller_state,
           COUNT(*) AS orders,
           SUM(is_late) AS late_orders,
           AVG(CASE WHEN is_late = 1 THEN days_late END) AS avg_days_late_when_late,
           AVG(promised_days) AS avg_promised_days,
           AVG(actual_days) AS avg_actual_days,
           AVG(CASE WHEN in_score_analysis = 1 THEN review_score END) AS avg_score
    FROM fct_orders
    WHERE in_late_analysis = 1 AND seller_id IS NOT NULL
    GROUP BY seller_id
    HAVING COUNT(*) >= 100
)
SELECT SUBSTR(b.seller_id, 1, 8) AS seller,
       b.seller_state,
       b.orders,
       b.late_orders,
       ROUND(100.0 * b.late_orders / b.orders, 1) AS late_pct,
       ROUND(b.late_orders - b.orders * o.late_rate) AS excess_late_orders,
       ROUND(b.avg_days_late_when_late, 1) AS avg_days_late_when_late,
       ROUND(b.avg_promised_days, 1) AS avg_promised_days,
       ROUND(b.avg_actual_days, 1) AS avg_actual_days,
       ROUND(b.avg_score, 2) AS avg_score,
       RANK() OVER (ORDER BY b.late_orders - b.orders * o.late_rate DESC) AS problem_rank
FROM by_seller b CROSS JOIN overall o
ORDER BY problem_rank;

-- name: li09_late_rate_by_promise
-- Promise accuracy: how long was the promise, how long did delivery take, and how often was
-- the promise broken? days_early = promised_days - actual_days (negative = late).
WITH banded AS (
    SELECT *,
           CASE WHEN promised_days <= 14 THEN '1. up to 14 days'
                WHEN promised_days <= 21 THEN '2. 15-21 days'
                WHEN promised_days <= 28 THEN '3. 22-28 days'
                WHEN promised_days <= 35 THEN '4. 29-35 days'
                ELSE '5. 36+ days' END AS promise_band
    FROM fct_orders
    WHERE in_late_analysis = 1
)
SELECT promise_band,
       COUNT(*) AS orders,
       ROUND(AVG(promised_days), 1) AS avg_promised_days,
       ROUND(AVG(actual_days), 1) AS avg_actual_days,
       ROUND(AVG(promised_days - actual_days), 1) AS avg_days_early,
       ROUND(100.0 * AVG(is_late), 1) AS late_pct,
       ROUND(AVG(CASE WHEN in_score_analysis = 1 THEN review_score END), 2) AS avg_score
FROM banded
GROUP BY promise_band
ORDER BY promise_band;
