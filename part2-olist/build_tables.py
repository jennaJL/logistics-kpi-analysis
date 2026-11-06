"""Build the clean analysis tables from the raw tables and check them against the raw data.

Usage:
    python build_tables.py [DB_PATH]        (default: data/olist.db)

Order of work:
    sql/03_staging.sql           stg_* tables: clean names and types
    sql/04_analysis_tables.sql   fct_orders, dim_products, dim_sellers, dim_customers
    sql/05_reconciliation.sql    compares them with the raw tables, saved in output/rc*.csv

Each query starts with a line "-- name: <table>". The raw tables are never changed.
Everything runs in one transaction: if a key is not unique or a check fails, the new tables
are not saved. The script can be run again at any time.

Uses only the Python standard library.
"""
import csv
import math
import re
import sqlite3
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
OUT = HERE / "output"

# The column or columns that identify one row. Building a unique index proves each key is unique.
KEYS = {
    "stg_orders": "order_id",
    "stg_order_items": "order_id, item_number",
    "stg_payments": "order_id, payment_number",
    "stg_reviews": "review_id, order_id",
    "stg_customers": "customer_id",
    "stg_sellers": "seller_id",
    "stg_products": "product_id",
    "stg_category_translation": "category_pt",
    "stg_geolocation": "zip_prefix",
    "dim_products": "product_id",
    "fct_orders": "order_id",
    "dim_sellers": "seller_id",
    "dim_customers": "customer_unique_id",
}


def haversine_km(lat1, lng1, lat2, lng2):
    """Straight-line distance over the Earth's surface. Empty if either point is missing."""
    if None in (lat1, lng1, lat2, lng2):
        return None
    p1, p2 = math.radians(lat1), math.radians(lat2)
    dp, dl = p2 - p1, math.radians(lng2 - lng1)
    a = math.sin(dp / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dl / 2) ** 2
    return 6371.0 * 2 * math.asin(math.sqrt(a))


def blocks(filename):
    """Yield (name, query) for each '-- name:' block in a SQL file."""
    text = (HERE / "sql" / filename).read_text(encoding="utf-8")
    for block in re.split(r"^-- name:\s*", text, flags=re.M)[1:]:
        name, _, body = block.partition("\n")
        yield name.strip(), body.strip().rstrip(";")


def build(con, filename):
    for table, query in blocks(filename):
        con.execute(f"DROP TABLE IF EXISTS {table}")
        con.execute(f"CREATE TABLE {table} AS\n{query}")
        con.execute(f"CREATE UNIQUE INDEX ux_{table} ON {table} ({KEYS[table]})")
        rows = con.execute(f"SELECT COUNT(*) FROM {table}").fetchone()[0]
        print(f"{table:28} {rows:>10,} rows")


def save(name, columns, rows):
    with open(OUT / f"{name}.csv", "w", newline="", encoding="utf-8") as f:
        writer = csv.writer(f, lineterminator="\n")
        writer.writerow(columns)
        writer.writerows(rows)


def reconcile(con):
    """Save the check results. Return the checks where expected and actual differ."""
    failed = []
    for name, query in blocks("05_reconciliation.sql"):
        cur = con.execute(query)
        columns = [d[0] for d in cur.description]
        rows = cur.fetchall()
        if name == "rc01_reconciliation":
            # Totals are money, so allow one cent of floating-point rounding.
            results = [r + ("ok" if r[2] is not None and r[3] is not None and abs(r[2] - r[3]) < 0.011 else "FAIL",)
                       for r in rows]
            failed = [r for r in results if r[-1] == "FAIL"]
            save(name, columns + ["result"], results)
            print(f"\n{name}: {len(results) - len(failed)} of {len(results)} checks passed")
        else:
            save(name, columns, rows)
            print(f"\n{name}")
            print(" | ".join(columns))
            for row in rows:
                print(" | ".join("" if v is None else str(v) for v in row))
    return failed


def main(db=None):
    db = Path(db) if db else HERE / "data" / "olist.db"
    if not db.exists():
        sys.exit(f"{db} not found. Run load_data.py first.")
    OUT.mkdir(exist_ok=True)
    con = sqlite3.connect(db, isolation_level=None)
    con.create_function("haversine_km", 4, haversine_km, deterministic=True)
    con.execute("BEGIN")
    try:
        build(con, "03_staging.sql")
        build(con, "04_analysis_tables.sql")
        failed = reconcile(con)
        if failed:
            for r in failed:
                print(f"FAILED  {r[1]}: expected {r[2]}, got {r[3]}")
            raise SystemExit("Checks failed, so the new tables were not saved.")
        con.execute("COMMIT")
    except BaseException:
        con.execute("ROLLBACK")
        raise
    finally:
        con.close()
    print(f"\nSaved the tables to {db}")


if __name__ == "__main__":
    main(*sys.argv[1:])
