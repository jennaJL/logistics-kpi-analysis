# Part 2: Does late delivery hurt customers? (Olist)

## Question

Does late delivery hurt customers, how much, and where should the business act first?

## Data

[Brazilian E-Commerce Public Dataset by Olist](https://www.kaggle.com/datasets/olistbr/brazilian-ecommerce), provided by Olist on Kaggle under [CC BY-NC-SA 4.0](https://creativecommons.org/licenses/by-nc-sa/4.0/). It has about 100,000 real, anonymised orders from 2016 to 2018.

The raw files are not stored in this repo.

## Status

The data is loaded and checked, the clean tables are built, and the lateness analysis is done: late delivery clearly hurts review scores, with bootstrap intervals and controls (see below). The Tableau dashboard comes next.

## Data quality

Full results are in [`ISSUES_LOG.md`](ISSUES_LOG.md) and `output/dq*.csv`.

The dates the main question depends on are sound: no order is delivered before it was purchased, and every promised date is readable. The checks also changed how the analysis has to be done:

- **Most reviews of late orders were answered before the parcel arrived** (64.1%). These scores cannot reflect the delivered product, so results will be shown with and without them.
- **Joining items to payments inflates revenue by 4.5%**, because one order can have several rows in each table. Each table is reduced to one row per order before joining.
- **The late rate depends on the definition:** 8.11% by timestamp and 6.77% by calendar day. The promised date has no time of day, so this project uses calendar days.
- **The late rate leaves out 1,107 orders marked shipped that never show a delivery date.** All are past their promised date and they average a score of 2.0, so the rate is a lower limit.

## SQL performance

`measure_performance.py` runs two KPI queries with and without indexes, using the median of 3 runs. It stops if an index changes the results.

| Query | What it does | No indexes | With indexes | Plan change |
|---|---|---|---|---|
| `seller_drilldown` | One seller's 1,854 orders, with the latest review of each | 17,265 ms | 24 ms | `SCAN` to `SEARCH` on items and reviews |
| `seller_kpi` | Late rate and score for all 210 large sellers | 976 ms | 1,142 ms | No useful change |

Three indexes were tested: `raw_order_items(seller_id, order_id)`, `raw_orders(order_id)` and `raw_reviews(order_id, review_answer_timestamp, review_id)`.

**Why the drilldown improved:** its review lookup runs once per order. Without an index, SQLite reads all 99,224 reviews 1,854 times. With an index, it goes straight to the matching rows.

**Why the seller KPI did not:** it needs almost every row, so there is little to skip. SQLite also already builds a temporary index for these joins, shown as `AUTOMATIC COVERING INDEX` in the plan. A small difference like this one is within normal timing variation, so this is no gain rather than a real slowdown.

**The cost:** the indexes took 0.3 seconds to build and added 21.9 MB (16%) to the database. Each insert would also have more to update, so an index should be added for a query that needs it.

Timings come from one machine (SQLite 3.37.2 in a Linux virtual machine on a MacBook Air) and will vary. The full plans are in `output/perf_plans.txt`.

## Clean tables

`build_tables.py` builds a clean layer on top of the raw tables, which stay unchanged:

- **`stg_*`:** one table per raw table, with clean names and types.
- **`fct_orders`:** one row per order, with promised days, actual days, days late, freight and review score. Each source is reduced to one row per order before joining, which avoids the 4.5% inflation above.
- **`dim_sellers`, `dim_customers`, `dim_products`:** one row per seller, person and product.

Every column and metric is defined in [`DATA_DICTIONARY.md`](DATA_DICTIONARY.md).

| Population | Orders |
|---|---|
| All orders | 99,441 |
| Delivered, with a delivery date | 96,470 |
| Purchased January 2017 to August 2018: **late analysis** | 96,203 |
| With a review: **score analysis** | 95,560 |

In the late analysis, 6,531 orders are late (6.79%). 1,097 more in the same period were marked shipped and never delivered, and are reported separately.

**Reconciliation:** 51 automated checks compare the new tables with the raw data, including row counts, price, freight and payment totals, and the rule that each kept review is the order's latest. Results are in `output/rc01_reconciliation.csv`. If a key is not unique or a check fails, the build stops and saves nothing.

**One new finding for the analysis:** orders with more items or sellers score lower even when on time (4.36 with one seller and one item, 2.87 with 2+ sellers). Item and seller counts are now planned regression controls (issue 26 in the log).

## Does late delivery hurt customers?

Yes, and by a lot. Results come from `analyze_lateness.py`, which runs `sql/06_lateness_impact.sql`, the bootstrap and the regressions. Population: the 95,560 orders in the score analysis. A **bad review** is 1 or 2 stars.

| Reviews | Delivery | Orders | Avg. score | Bad reviews | 5 stars |
|---|---|---|---|---|---|
| All | On time | 89,182 | 4.29 | 9.2% | 62.3% |
| All | Late | 6,378 | 2.27 | 62.4% | 16.5% |
| Answered after delivery | On time | 89,031 | 4.29 | 9.2% | 62.3% |
| Answered after delivery | Late | 2,294 | 3.41 | 28.3% | 35.5% |

**The effect holds with controls.** In a regression with item count, seller count, order value, purchase month and customer state (robust standard errors), a late order scores **1.98 stars lower** on all reviews (95% CI 1.94 to 2.02). On reviews answered after delivery it is **0.87 stars lower** (0.80 to 0.93) and 19 percentage points more likely to be a bad review. Single-seller, single-item orders give the same result (0.87 stars), so issue 26 does not explain it. Results: `output/li05_regression.csv`.

**Two numbers, because they measure different things.** All reviews include customers who wrote while still waiting (issue 1), so 1.98 is the full cost of lateness on the score. 0.87 is the cost among customers who already had the parcel, so it is the conservative figure.

**It gets worse the later the parcel is** (`output/li02_score_by_days_late.csv`):

| Days late | Orders | Avg. score | Bad reviews |
|---|---|---|---|
| 8+ days early | 70,673 | 4.32 | 9.0% |
| 1–7 days early | 17,229 | 4.20 | 10.2% |
| On the promised day | 1,280 | 4.03 | 12.4% |
| 1–3 days late | 1,851 | 3.29 | 32.1% |
| 4–7 days late | 1,748 | 2.10 | 67.7% |
| 8–14 days late | 1,446 | 1.67 | 80.2% |
| 15+ days late | 1,333 | 1.72 | 78.3% |

Even 1–3 days late more than triples the bad-review rate of on-time orders (9.2%), so small delays matter.

**Size of the problem:** late orders are 6.7% of reviewed orders but give 3,981 of the 12,228 bad reviews. If they scored like on-time orders, about **3,391 bad reviews (28% of all) would not exist** (`output/li03_bad_reviews_caused_by_lateness.csv`). Counting only the effect on reviews answered after delivery, it is still about 1,200 (10%).

**Where to act first** (`output/li04_late_rate_and_impact_by_state.csv`): **Rio de Janeiro (RJ)** has the most excess bad reviews (905), because 12.0% of its orders are late, against 4.4% in São Paulo. São Paulo comes second (815) because of its volume. Bahia (11.9% late) and Ceará (13.7%) also have high late rates.

**The gap is not a sampling accident** (`output/li06_bootstrap.csv`). With 10,000 bootstrap resamples of orders, the 95% interval for the score gap is −2.06 to −1.98 stars on all reviews and −0.94 to −0.81 on reviews answered after delivery. The bad-review gap is +52 to +54 points and +17 to +21 points. A score takes only five values, so each resample draws the star counts from a multinomial, which is the same as resampling orders and much faster.

**Price, freight, distance and category do not explain it** (`output/li07_regression_controls.csv`). These controls need the seller's location, so this model uses the 93,832 single-seller orders with a known distance. Lateness is related to distance: 4.5% of orders under 184 km are late, against 8.9% over 800 km. But adding the controls barely moves the effect:

| Reviews | Controls | Effect on score | 95% CI | Effect on bad reviews |
|---|---|---|---|---|
| All | None | −2.04 | −2.08 to −2.00 | +53.7 pts |
| All | Price, freight, distance | −2.02 | −2.06 to −1.98 | +53.4 pts |
| All | + category, items, month, state | −1.98 | −2.02 to −1.94 | +52.5 pts |
| After delivery | None | −0.89 | −0.96 to −0.83 | +19.5 pts |
| After delivery | Price, freight, distance | −0.88 | −0.95 to −0.82 | +19.3 pts |
| After delivery | + category, items, month, state | −0.86 | −0.93 to −0.80 | +19.1 pts |

Categories with fewer than 300 orders are pooled as "other". Price, freight and distance are log-transformed.

**Sellers differ more than chance allows** (`output/li08_late_rate_by_seller.csv`). Among the 201 sellers with 100+ single-seller orders, late rates run from 0% to 19.1% (median 5.8%). The spread is about 4.5 times what random variation would give (chi-square 912 on 200 degrees of freedom). The problem is still spread out: the 10 worst sellers account for 312 late orders above the average rate, about 5% of all 6,531 late orders. So seller follow-up helps, but it will not fix lateness alone. Two sellers stand out on rate rather than volume: `06a2c3af` (MA, 19.1% late) and `88460e8e` (PR, 18.5% late, average score 3.51). 17 of the 20 worst sellers are in São Paulo, which mostly reflects where sellers are.

**Promises are long, and length is not accuracy** (`output/li09_late_rate_by_promise.csv`). On average a parcel arrives 11 days before the promised date. The longest promises (36+ days) are broken least often (3.6% late) but still arrive 24 days early, and their average score is the lowest (4.06 against 4.32 for promises up to 14 days). Long promises are also long-distance orders, so this table does not show that shorter promises would raise scores. It does show that the promise is a poor estimate of the actual delivery time, which is the point to test next.

**Limits:** this is observational data, so lateness is not randomly assigned. The bootstrap shows the gap is not noise, and the controls show it is not explained by price, freight, distance, category, basket size, month or state. The steady rise with days late also fits a causal reading. Still, unmeasured problems with the same orders (a damaged product, a poor seller, a lost parcel) could add to the effect, so the numbers are associations, not proven causes. The models are OLS and linear probability models, chosen so the effect reads in stars and percentage points. Seller and distance results use single-seller orders only (issue 10).

## How to run

Python 3 is all you need, plus pandas and statsmodels for `analyze_lateness.py`. The 9 CSVs go in a folder outside the repo.

```bash
cd part2-olist
python3 load_data.py path/to/csv/folder    # creates data/olist.db (git-ignored)
python3 run_checks.py                      # writes output/dq*.csv
python3 build_tables.py                    # adds the clean tables, writes output/rc*.csv
python3 analyze_lateness.py                # writes output/li*.csv (needs pandas, statsmodels)
python3 measure_performance.py             # writes output/perf_*
```

## Files

```
load_data.py                   CSV -> SQLite, unchanged, all columns as text
run_checks.py                  runs the checks and saves the results
build_tables.py                builds the clean tables and checks them against raw
analyze_lateness.py            measures how much late delivery hurts review scores
measure_performance.py         times the queries with and without indexes
sql/01_data_quality.sql        data-quality checks
sql/02_performance_queries.sql the two queries that were timed
sql/03_staging.sql             staging tables
sql/04_analysis_tables.sql     order, seller, customer and product tables
sql/05_reconciliation.sql      checks against the raw data
sql/06_lateness_impact.sql     late vs on-time scores, days late, impact by state, sellers, promises
DATA_DICTIONARY.md             every table, column and metric definition
ISSUES_LOG.md                  every problem found and how it is handled
output/                        results of the checks and timings
```
