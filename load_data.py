"""Load the DataCo supply-chain CSV into a SQLite database.

Usage:
    python load_data.py path/to/DataCoSupplyChainDataset.csv   (original, latin-1)
    python load_data.py path/to/supply_chain_clean.csv.gz       (cleaned mirror)

Creates logistics.db with:
    order_items  one row per order line (raw grain of the dataset)
    shipments    view, one row per order (the grain used for logistics KPIs)

Customer names, e-mail, password and street columns are dropped on load:
they are not needed for the analysis.
"""
import sqlite3
import sys
from pathlib import Path

import pandas as pd

DROP = ["Customer Email", "Customer Fname", "Customer Lname", "Customer Password",
        "Customer Street", "Product Image", "Product Description", "Order Zipcode"]

RENAME = {
    "Type": "payment_type",
    "Days for shipping (real)": "days_real",
    "Days for shipment (scheduled)": "days_scheduled",
    "Delivery Status": "delivery_status",
    "Late_delivery_risk": "late_flag",
    "Category Name": "category",
    "Department Name": "department",
    "Customer Country": "customer_country",
    "Customer Segment": "customer_segment",
    "Customer Id": "customer_id",
    "Market": "market",
    "Order Region": "order_region",
    "Order Country": "order_country",
    "Order City": "order_city",
    "order date (DateOrders)": "order_date",
    "shipping date (DateOrders)": "shipping_date",
    "Order Id": "order_id",
    "Order Item Id": "order_item_id",
    "Order Item Quantity": "quantity",
    "Sales": "sales",
    "Order Item Total": "item_total",
    "Order Profit Per Order": "profit",
    "Order Status": "order_status",
    "Product Name": "product_name",
    "Shipping Mode": "shipping_mode",
}


def main(src: str, db: str = "logistics.db") -> None:
    enc = "latin-1" if src.lower().endswith(".csv") else None
    df = pd.read_csv(src, encoding=enc)
    df = df.drop(columns=[c for c in DROP if c in df.columns])
    df = df[list(RENAME)].rename(columns=RENAME)
    for col in ("order_date", "shipping_date"):
        df[col] = pd.to_datetime(df[col], format="%m/%d/%Y %H:%M").dt.strftime("%Y-%m-%d %H:%M")
    df["product_name"] = df["product_name"].str.strip()

    Path(db).unlink(missing_ok=True)
    con = sqlite3.connect(db)
    df.to_sql("order_items", con, index=False)
    con.executescript("""
        CREATE INDEX idx_order ON order_items(order_id);
        CREATE VIEW shipments AS
        SELECT order_id,
               MIN(order_date)       AS order_date,
               MIN(shipping_date)    AS shipping_date,
               MIN(shipping_mode)    AS shipping_mode,
               MIN(market)           AS market,
               MIN(order_region)     AS order_region,
               MIN(order_country)    AS order_country,
               MIN(delivery_status)  AS delivery_status,
               MIN(order_status)     AS order_status,
               MAX(late_flag)        AS late_flag,
               MIN(days_real)        AS days_real,
               MIN(days_scheduled)   AS days_scheduled,
               COUNT(*)              AS lines,
               SUM(quantity)         AS units,
               ROUND(SUM(item_total), 2) AS revenue
        FROM order_items
        GROUP BY order_id;
    """)
    con.commit()
    n_items = con.execute("SELECT COUNT(*) FROM order_items").fetchone()[0]
    n_orders = con.execute("SELECT COUNT(*) FROM shipments").fetchone()[0]
    print(f"Loaded {n_items:,} order lines / {n_orders:,} orders into {db}")
    con.close()


if __name__ == "__main__":
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    main(*sys.argv[1:])
