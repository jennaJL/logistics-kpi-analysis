"""Measure two KPI queries before and after adding indexes.

Usage:
    python measure_performance.py [DB_PATH]       (default: data/olist.db)

Prints each query plan and saves:
    output/perf_results.csv   median time and row count, before and after
    output/perf_plans.txt     the query plans, before and after

The script checks that each query returns identical rows before and after, then
removes the indexes again so the raw tables stay as load_data.py left them.
The slow query takes a while before the indexes are added.

Uses only the Python standard library.
"""
import csv
import re
import sqlite3
import statistics
import sys
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
OUT = HERE / "output"
RUNS = 3

INDEXES = {
    "idx_items_seller_order": "raw_order_items(seller_id, order_id)",
    "idx_orders_order": "raw_orders(order_id)",
    "idx_reviews_order_answer": "raw_reviews(order_id, review_answer_timestamp, review_id)",
}


def load_queries():
    text = (HERE / "sql" / "02_performance_queries.sql").read_text(encoding="utf-8")
    queries = {}
    for block in re.split(r"^-- name:\s*", text, flags=re.M)[1:]:
        name, _, body = block.partition("\n")
        queries[name.strip()] = body.strip().rstrip(";")
    return queries


def measure(con, query, params):
    times = []
    rows = None
    for _ in range(RUNS):
        start = time.perf_counter()
        rows = con.execute(query, params).fetchall()
        times.append((time.perf_counter() - start) * 1000)
    return statistics.median(times), rows


def plan(con, query, params):
    return [r[3] for r in con.execute("EXPLAIN QUERY PLAN " + query, params)]


def db_bytes(con):
    pages = con.execute("PRAGMA page_count").fetchone()[0]
    size = con.execute("PRAGMA page_size").fetchone()[0]
    return pages * size


def drop_indexes(con):
    for name in INDEXES:
        con.execute(f"DROP INDEX IF EXISTS {name}")
    con.commit()


def main(db=None):
    db = Path(db) if db else HERE / "data" / "olist.db"
    if not db.exists():
        sys.exit(f"{db} not found. Run load_data.py first.")
    OUT.mkdir(exist_ok=True)
    con = sqlite3.connect(db)
    drop_indexes(con)
    con.execute("VACUUM")

    # The drilldown uses the seller with the most order items.
    seller = con.execute(
        "SELECT seller_id FROM raw_order_items GROUP BY seller_id ORDER BY COUNT(*) DESC, seller_id LIMIT 1"
    ).fetchone()[0]
    queries = load_queries()
    used = {name: ({"seller_id": seller} if ":seller_id" in q else {}) for name, q in queries.items()}

    results, plans = [], []
    before = {}
    size_before = db_bytes(con)
    for name, q in queries.items():
        print(f"Measuring {name}, no indexes ...", flush=True)
        ms, rows = measure(con, q, used[name])
        before[name] = (ms, rows)
        plans.append((name, "before", plan(con, q, used[name])))

    start = time.perf_counter()
    for name, target in INDEXES.items():
        con.execute(f"CREATE INDEX {name} ON {target}")
    con.commit()
    build_ms = (time.perf_counter() - start) * 1000
    size_after = db_bytes(con)

    for name, q in queries.items():
        print(f"Measuring {name}, with indexes ...", flush=True)
        ms, rows = measure(con, q, used[name])
        plans.append((name, "after", plan(con, q, used[name])))
        if rows != before[name][1]:
            drop_indexes(con)
            sys.exit(f"{name}: results changed after adding indexes")
        results.append((name, len(rows), round(before[name][0], 1), round(ms, 1),
                        round(before[name][0] / ms, 1)))
    drop_indexes(con)
    con.close()

    with open(OUT / "perf_results.csv", "w", newline="", encoding="utf-8") as f:
        writer = csv.writer(f, lineterminator="\n")
        writer.writerow(["query", "rows_returned", "ms_before", "ms_after", "times_faster"])
        writer.writerows(results)
    with open(OUT / "perf_plans.txt", "w", encoding="utf-8") as f:
        f.write(f"SQLite {sqlite3.sqlite_version}\n")
        f.write(f"Drilldown seller: {seller}\n")
        f.write(f"Index build: {build_ms:.0f} ms. Database size: {size_before / 1e6:.1f} MB before, {size_after / 1e6:.1f} MB with indexes.\n")
        for name, when, steps in plans:
            f.write(f"\n{name}, {when} indexes\n")
            f.writelines(f"  {s}\n" for s in steps)

    print((OUT / "perf_plans.txt").read_text(encoding="utf-8"))
    for row in results:
        print(row)
    print("Results were identical before and after. Indexes removed.")


if __name__ == "__main__":
    main(*sys.argv[1:])
