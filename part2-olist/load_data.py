"""Load the 9 raw Olist CSVs into a SQLite database, exactly as they are.

Usage:
    python load_data.py [RAW_DIR] [DB_PATH]

Defaults:
    RAW_DIR  ../../olist-raw/archive   (outside the repo)
    DB_PATH  data/olist.db             (git-ignored)

Every table is called raw_<name> and every column is stored as TEXT, so nothing
is cleaned, converted or dropped here. Empty cells become NULL. Types and clean
names come in the next layer. No secondary indexes are added. The script stops
if a table's row count does not match its CSV.

Uses only the Python standard library.
"""
import csv
import sqlite3
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent

TABLES = {
    "raw_customers": "olist_customers_dataset.csv",
    "raw_geolocation": "olist_geolocation_dataset.csv",
    "raw_order_items": "olist_order_items_dataset.csv",
    "raw_payments": "olist_order_payments_dataset.csv",
    "raw_reviews": "olist_order_reviews_dataset.csv",
    "raw_orders": "olist_orders_dataset.csv",
    "raw_products": "olist_products_dataset.csv",
    "raw_sellers": "olist_sellers_dataset.csv",
    "raw_category_translation": "product_category_name_translation.csv",
}

csv.field_size_limit(10_000_000)


def load_table(con, table, path):
    # utf-8-sig removes the invisible BOM at the start of the translation file.
    with open(path, encoding="utf-8-sig", newline="") as f:
        reader = csv.reader(f)
        header = next(reader)
        columns = ", ".join(f'"{c}" TEXT' for c in header)
        marks = ", ".join("?" for _ in header)
        con.execute(f'CREATE TABLE "{table}" ({columns})')
        csv_rows = 0
        batch = []
        for row in reader:
            if len(row) != len(header):
                sys.exit(f"{path.name}, row {csv_rows + 2}: expected {len(header)} fields, got {len(row)}")
            batch.append([v if v != "" else None for v in row])
            csv_rows += 1
            if len(batch) == 50_000:
                con.executemany(f'INSERT INTO "{table}" VALUES ({marks})', batch)
                batch.clear()
        con.executemany(f'INSERT INTO "{table}" VALUES ({marks})', batch)
    db_rows = con.execute(f'SELECT COUNT(*) FROM "{table}"').fetchone()[0]
    if db_rows != csv_rows:
        sys.exit(f"{table}: CSV has {csv_rows} rows but the table has {db_rows}")
    return db_rows


def main(raw_dir=None, db_path=None):
    raw_dir = Path(raw_dir) if raw_dir else HERE.parent.parent / "olist-raw" / "archive"
    db_path = Path(db_path) if db_path else HERE / "data" / "olist.db"
    db_path.parent.mkdir(parents=True, exist_ok=True)
    db_path.unlink(missing_ok=True)

    con = sqlite3.connect(db_path)
    for table, filename in TABLES.items():
        print(f"{table:28} {load_table(con, table, raw_dir / filename):>10,} rows")
    con.commit()
    con.close()
    print(f"Saved to {db_path}")


if __name__ == "__main__":
    main(*sys.argv[1:])
