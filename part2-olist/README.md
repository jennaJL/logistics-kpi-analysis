# Part 2: Does late delivery hurt customers? (Olist)

## Question

Does late delivery hurt customers, how much, and where should the business act first?

## Data

[Brazilian E-Commerce Public Dataset by Olist](https://www.kaggle.com/datasets/olistbr/brazilian-ecommerce), provided by Olist on Kaggle under [CC BY-NC-SA 4.0](https://creativecommons.org/licenses/by-nc-sa/4.0/). It has about 100,000 real, anonymised orders from 2016 to 2018.

The raw files are not stored in this repo.

## Status

Step 1 of the analysis is done: the data is loaded and checked. The clean tables and the analysis of late delivery come next.

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

## How to run

Python 3 is all you need. The 9 CSVs go in a folder outside the repo.

```bash
cd part2-olist
python3 load_data.py path/to/csv/folder    # creates data/olist.db (git-ignored)
python3 run_checks.py                      # writes output/dq*.csv
python3 measure_performance.py             # writes output/perf_*
```

## Files

```
load_data.py                   CSV -> SQLite, unchanged, all columns as text
run_checks.py                  runs the checks and saves the results
measure_performance.py         times the queries with and without indexes
sql/01_data_quality.sql        data-quality checks
sql/02_performance_queries.sql the two queries that were timed
ISSUES_LOG.md                  every problem found and how it is handled
output/                        results of the checks and timings
```
