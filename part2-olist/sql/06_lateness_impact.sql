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
