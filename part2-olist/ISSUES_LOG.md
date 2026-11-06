# Data issues log

Each row is a problem found in the raw Olist data, and how it is handled. The raw tables are not changed: `build_tables.py` applies the handling when it builds the clean tables. The evidence is in `output/`, under the check named in brackets.

## Issues that affect the main question

| # | Issue | Evidence | Handling |
|---|---|---|---|
| 1 | **Reviews written before delivery.** Many reviews of late orders were answered while the parcel was still on its way, so the score cannot reflect the delivered product. | 64.1% of reviews on late orders (4,110 of 6,409) were answered before delivery, against 0.3% on on-time orders. Average scores: on time 4.29, late and answered after delivery 3.41, late and answered before delivery 1.63. (dq11, dq19) | Keep them and add an `answered_before_delivery` flag. Report the effect with and without them. They still show the cost of waiting, but mixing the groups would hide what is being measured. |
| 2 | **When the survey goes out.** It usually appears 1 day after delivery. If the parcel is late, it often appears about 2 days after the promised date. This is a pattern in the data, not something the source documents. | 85,641 reviews were created 1 day after delivery. Of the 4,777 late-order reviews created before delivery, 3,386 were created 2 days after the promised date. (dq20) | Treat as the likely cause of issue 1 and describe it as an inference. |
| 3 | **Late orders that never arrive are missing from the late rate.** Orders with no delivery date cannot have a days-late figure. | 1,107 orders marked `shipped` have no delivery date. All are past their promised date, with an average score of 2.0. (dq21) | Exclude from days-late figures, report separately, and describe the late rate as a lower limit. |
| 4 | **Two possible definitions of late.** The promised date has no time of day, so a timestamp comparison counts anything delivered on the promised day as late. | All promised dates are at 00:00:00. Late rate is 8.11% by timestamp and 6.77% by calendar day, a difference of 1,292 orders. (dq10) | Late means delivered on a later calendar day than promised. This assumes the promise covers the whole day. Test the other definition as a sensitivity check. |
| 5 | **Joins can double-count.** Orders can have several items, payments and reviews. | 9,803 orders have 2+ items, 2,961 have 2+ payments and 547 have 2+ reviews. Joining items to payments inflates the item total by 4.54%. (dq03, dq04) | Reduce each table to one row per order before joining. Check totals against the raw tables. |
| 6 | **Several reviews for one order.** | 547 orders have 2+ reviews, and 202 of those have different scores. (dq05) | Keep the latest answer for each order. |
| 7 | **The late rate changes sharply over time.** Time could distort any comparison between sellers or regions. | The monthly rate runs from 1.2% (June 2018) to 19.0% (March 2018), among months from 2017 on. (dq18) | Add purchase month as a control in the regression, in addition to the planned controls. |
| 8 | **Thin months at each end of the data.** | Sept to Dec 2016 has 329 orders and no orders in Nov. Sept and Oct 2018 have 20 orders and none delivered. (dq09) | Use orders purchased from January 2017 to August 2018. |
| 9 | **Late orders are more likely to have no review.** | 2.34% of late orders have no review, against 0.55% of on-time orders. (dq24) | Exclude from score analysis and state the gap as a limitation. It is small and unlikely to change the conclusion, but it is not random. |
| 10 | **Orders with more than one seller.** Delivery dates and reviews belong to the order, not to each seller. | 1,278 orders have 2+ sellers, about 1.3%. (dq04) | Rank sellers on single-seller orders only. |
| 26 | **Orders with more items or sellers score lower, even when on time.** The order has only one delivery date, so a multi-seller order may look on time when only part of it has arrived. That reason is an inference and the data cannot confirm it. | On-time orders average 4.36 with one seller and one item, 3.85 with one seller and 2+ items, and 2.87 with 2+ sellers. Late rate is 6.95%, 5.95% and 1.02%. (rc04) | Add item count and seller count as regression controls, and repeat the main result on single-seller, single-item orders. |

## Issues with a smaller or limited effect

| # | Issue | Evidence | Handling |
|---|---|---|---|
| 11 | **One review_id on several orders.** | 789 review_ids cover 1,412 orders. In all 789, it is the same customer, score and answer time. (dq05, dq22) | Not an error: one answer covers several orders. Use `review_id + order_id` as the key, and allow for repeat customers when calculating intervals. |
| 12 | **Delivered orders with a missing delivery date.** | 8 orders. (dq06) | Exclude. |
| 13 | **Canceled orders with a delivery date.** | 6 orders. (dq06) | Exclude. The analysis uses `delivered` orders only. |
| 14 | **Impossible order of handling dates.** | Handed to carrier before approval: 1,359. Before purchase: 166. Delivered before approval: 61. Delivered before handed to carrier: 23. (dq07) | Purchase, delivery and promised dates are not affected, so the late rate stands. Exclude these orders from any stage-by-stage timing. |
| 15 | **Delivered orders with missing handling dates.** | No approval date: 14. No carrier date: 2. (dq06) | Keep. Exclude from stage-by-stage timing only. |
| 16 | **Orders with no items.** | 775 orders, none with status `delivered`. (dq02) | No effect on delivered orders. |
| 17 | **Amount paid differs from price plus freight.** The cause is not in the data. | 98,405 of 98,665 orders match within 5 cents, and 216 differ by more than 5%. (dq14) | Use item price and freight for order value. Payments are not used for value. |
| 18 | **Odd payment rows.** | Value of 0: 9. Type `not_defined`: 3. Installments of 0: 2. One order has no payment row. (dq13, dq02) | No effect, because payments are not used for value. |
| 19 | **Missing product details.** | 610 products have no category (1,603 order items). 2 have no size or weight, and 4 have a weight of 0. (dq15) | Label the category `unknown`. Treat missing or zero size and weight as missing. |
| 20 | **Categories with no English name.** | `pc_gamer` and `portateis_cozinha_e_preparadores_de_alimentos`, 13 products. (dq15) | Add the two translations in the clean tables. |
| 21 | **Misspelled column names.** | `product_name_lenght` and `product_description_lenght`. | Correct in the clean tables. |
| 22 | **Geolocation is not one row per zip.** | 1,000,163 rows for 19,015 zip prefixes, with 261,831 exact duplicates. 47 rows fall outside Brazil's approximate limits, 8 zips appear in 2+ states and 8,556 have 2+ city spellings. (dq00, dq16, dq17) | Build one point per zip from the median of the rows inside the limits. Take state from the customer and seller tables. Distances are approximate because only zip prefixes are available. |
| 23 | **Zips not found in geolocation.** | 278 customers and 7 sellers. (dq02) | Leave distance empty for these. |
| 24 | **Seller deadlines in 2020.** | 4 items have a `shipping_limit_date` in 2020, while orders end in 2018. (dq23) | This field is not used. Exclude these 4 values if it is used later. |
| 25 | **customer_id is not a person.** | One `customer_id` per order: 99,441 ids for 96,096 `customer_unique_id` values. (dq01) | Use `customer_unique_id` to identify a customer. |

## Checks that passed

- All 9 tables loaded with row counts matching their CSVs.
- No missing values in any key column. (dq00)
- `order_id`, `customer_id`, `product_id` and `seller_id` are unique in their own tables, as are order item and payment keys. (dq01)
- Every item, payment and review links to an existing order, and every item to an existing product and seller. (dq02)
- No delivery before purchase, approval before purchase, or promised date before purchase. (dq07)
- All dates are readable. (dq08)
- All review scores are 1 to 5. (dq12)
- No negative or zero item prices, and no negative freight or payments. (dq13)
- Many review comments are empty (88.3% of titles, 58.7% of messages), which is expected because they are optional. Scores are complete. (dq00)

## Numbers for the analysis

- Delivered orders with a delivery date: 96,470. Of these, 95,824 have a review, before applying the date range in issue 8. (dq25)
- On average, the promised date is 24.4 days after purchase and actual delivery takes 12.6 days. Part of the low late rate may come from these long promises, which the analysis should examine. (dq25)
