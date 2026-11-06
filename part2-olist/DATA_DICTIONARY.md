# Data dictionary

The tables are built by `build_tables.py` from the raw tables, which are never changed. Issue numbers refer to [`ISSUES_LOG.md`](ISSUES_LOG.md).

## How the tables fit together

`fct_orders` is the centre. It links to `dim_customers` through `customer_unique_id` and to `dim_sellers` through `seller_id`. An order's items are in `stg_order_items`, which links to `fct_orders` through `order_id` and to `dim_products` through `product_id`.

| Table | One row per | Rows | Key | Use it for |
|---|---|---|---|---|
| `fct_orders` | order | 99,441 | `order_id` | The main analysis table |
| `dim_sellers` | seller | 3,095 | `seller_id` | Seller comparisons |
| `dim_customers` | person | 96,096 | `customer_unique_id` | Repeat customers, customer location |
| `dim_products` | product | 32,951 | `product_id` | Category and size |
| `stg_*` | one per raw table | | see `KEYS` in `build_tables.py` | Item-level or payment-level questions |

`fct_orders` keeps every order, so its totals match the raw data. **Use the flags below to choose the orders for each analysis.**

## Who is in each analysis

| Flag | Meaning | Orders |
|---|---|---|
| `is_delivered` | Status is `delivered` and there is a delivery date (issues 12, 13) | 96,470 |
| `in_period` | Purchased from January 2017 to August 2018 (issue 8) | |
| `in_late_analysis` | `is_delivered` and `in_period`. Use for the late rate | 96,203 |
| `in_score_analysis` | `in_late_analysis` with a review. Use for review scores | 95,560 |
| `is_shipped_never_delivered` | Status is `shipped` with no delivery date. Report separately (issue 3) | 1,107 (1,097 in period) |

The full count at each filter is in `output/rc02_analysis_population.csv`.

## `fct_orders` columns

**Delivery**

| Column | Definition |
|---|---|
| `purchased_at`, `approved_at`, `handed_to_carrier_at`, `delivered_at` | Timestamps from the raw order |
| `promised_date` | Date promised to the customer. It has no time of day (issue 4) |
| `purchase_month` | `YYYY-MM`, for the time control (issue 7) |
| `promised_days` | Calendar days from purchase to promised date |
| `actual_days` | Calendar days from purchase to delivery. Empty if not delivered |
| `days_late` | Calendar days from promised date to delivery, so `actual_days - promised_days`. Negative means early |
| `is_late` | 1 if delivered on a later calendar day than promised. **This is the project's definition of late** |
| `is_late_by_timestamp` | 1 if the delivery timestamp is after midnight at the start of the promised date. For the sensitivity check only |
| `has_valid_stage_dates` | 1 if all dates exist and run in order: purchase, approval, carrier, delivery (issues 14, 15) |
| `seller_days` | Days from approval to handover to the carrier, with decimals. Only when `has_valid_stage_dates` is 1 |
| `carrier_days` | Days from handover to delivery, with decimals. Only when `has_valid_stage_dates` is 1 |

**Money and basket**

| Column | Definition |
|---|---|
| `item_count`, `product_count`, `seller_count` | Items, distinct products and distinct sellers. Empty for the 775 orders with no items |
| `items_price` | Sum of item prices |
| `freight` | Sum of item freight |
| `order_value` | `items_price + freight`. Payments are not used for value (issue 17) |
| `freight_share` | `freight / order_value` |
| `total_weight_g` | Sum of item weights. Empty if any item's weight is missing |
| `main_category` | English category of the most expensive item, `unknown` if the product has none (issue 19). On a tie, the lower item number |
| `payment_rows`, `payment_value` | Number of payment rows and total paid. For reconciliation only |

**Review**

| Column | Definition |
|---|---|
| `review_id`, `review_score`, `review_answered_at` | The order's latest answered review (issue 6) |
| `review_count` | How many reviews the order has in the raw data |
| `answered_before_delivery` | 1 if the review was answered on an earlier calendar day than delivery (issue 1) |

**Location**

| Column | Definition |
|---|---|
| `customer_id`, `customer_unique_id` | The per-order id and the id of the person (issue 25) |
| `customer_state`, `customer_zip` | Address on this order |
| `seller_id`, `seller_state`, `seller_zip` | Filled only on single-seller orders (issue 10) |
| `route` | `seller_state-customer_state`, for example `SP-RJ`. Single-seller orders only |
| `is_same_state` | 1 if seller and customer are in the same state. Single-seller orders only |
| `distance_km` | Straight-line distance between the two zip prefixes, so approximate (issue 22). Single-seller orders only |

## `dim_sellers`

Location: `zip_prefix`, `city`, `state`, `lat`, `lng`.

Sales cover every item the seller sold, in any status: `items_sold`, `orders_all`, `items_price`, `freight`.

Performance covers single-seller orders in `in_late_analysis` only (issue 10): `analysis_orders`, `late_orders`, `late_pct`, `avg_promised_days`, `avg_actual_days`, `reviewed_orders`, `avg_review_score`, and `avg_score_after_delivery`, which leaves out reviews answered before delivery.

Check `analysis_orders` before comparing sellers: 2,925 sellers have at least one order, but only 201 have 100 or more.

## `dim_customers`

Location comes from the person's latest order, because a person can have several addresses: `zip_prefix`, `city`, `state`, `lat`, `lng`.

Orders: `orders_all`, `is_repeat_customer` (2+ orders, 2,997 people), `first_purchased_at`, `last_purchased_at`, `total_order_value`.

Analysis: `analysis_orders`, `late_orders`, `reviewed_orders`, `avg_review_score`.

Orders from repeat customers are not independent, so use `customer_unique_id` when calculating intervals (issue 11).

## `dim_products`

`category` (English, or `unknown`), `category_pt`, `name_length`, `description_length`, `photo_count`, `weight_g`, `length_cm`, `height_cm`, `width_cm`, `items_sold`, `items_price`. A weight or size of 0 is stored as empty (issue 19).

## Staging tables

`stg_orders`, `stg_order_items`, `stg_payments`, `stg_reviews`, `stg_customers`, `stg_sellers` and `stg_products` have the same rows as their raw tables, with clean names and types.

- `stg_category_translation` is the raw table plus 2 missing translations (issue 20).
- `stg_geolocation` has one point per zip prefix: the median latitude and longitude of the rows inside Brazil. It has 19,010 of the 19,015 zips, because 5 have no point inside Brazil. Those 5 zips and the zips missing from the raw table leave `distance_km` empty, for 279 customer ids and 7 sellers (issue 23).
