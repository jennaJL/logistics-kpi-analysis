# Part 2: Does late delivery hurt customers? (Olist)

## Question

Does late delivery hurt customers, how much, and where should the business act first?

## Data

[Brazilian E-Commerce Public Dataset by Olist](https://www.kaggle.com/datasets/olistbr/brazilian-ecommerce), provided by Olist on Kaggle under [CC BY-NC-SA 4.0](https://creativecommons.org/licenses/by-nc-sa/4.0/). It has about 100,000 real, anonymised orders from 2016 to 2018.

The raw files are not stored in this repo.

## Status

The data is loaded and checked, and the clean tables are built. The analysis of late delivery comes next.

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

## How to run

Python 3 is all you need. The 9 CSVs go in a folder outside the repo.

```bash
cd part2-olist
python3 load_data.py path/to/csv/folder    # creates data/olist.db (git-ignored)
python3 run_checks.py                      # writes output/dq*.csv
python3 build_tables.py                    # adds the clean tables, writes output/rc*.csv
python3 measure_performance.py             # writes output/perf_*
```

## Files

```
load_data.py                   CSV -> SQLite, unchanged, all columns as text
run_checks.py                  runs the checks and saves the results
build_tables.py                builds the clean tables and checks them against raw
measure_performance.py         times the queries with and without indexes
sql/01_data_quality.sql        data-quality checks
sql/02_performance_queries.sql the two queries that were timed
sql/03_staging.sql             staging tables
sql/04_analysis_tables.sql     order, seller, customer and product tables
sql/05_reconciliation.sql      checks against the raw data
DATA_DICTIONARY.md             every table, column and metric definition
ISSUES_LOG.md                  every problem found and how it is handled
output/                        results of the checks and timings
```
