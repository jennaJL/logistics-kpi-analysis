"""Run the data-quality checks and save each result as a CSV in output/.

Usage:
    python run_checks.py [DB_PATH]        (default: data/olist.db)

Each query in sql/01_data_quality.sql starts with a line "-- name: <name>".
Two more checks cover every column of every table, so they are generated here:
    dq00_row_counts_and_duplicates   rows and exact duplicate rows per table
    dq00_missing_values              empty cells per column

Uses only the Python standard library.
"""
import csv
import re
import sqlite3
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
OUT = HERE / "output"


def save(name, columns, rows):
    with open(OUT / f"{name}.csv", "w", newline="", encoding="utf-8") as f:
        writer = csv.writer(f, lineterminator="\n")
        writer.writerow(columns)
        writer.writerows(rows)
    print(f"\n=== {name} ({len(rows)} rows) ===")
    print(" | ".join(columns))
    for row in rows[:30]:
        print(" | ".join("" if v is None else str(v) for v in row))


def table_checks(con):
    tables = [r[0] for r in con.execute(
        "SELECT name FROM sqlite_master WHERE type='table' AND name LIKE 'raw_%' ORDER BY name")]
    counts, missing = [], []
    for t in tables:
        cols = [r[1] for r in con.execute(f'PRAGMA table_info("{t}")')]
        quoted = ", ".join(f'"{c}"' for c in cols)
        total = con.execute(f'SELECT COUNT(*) FROM "{t}"').fetchone()[0]
        distinct = con.execute(f'SELECT COUNT(*) FROM (SELECT DISTINCT {quoted} FROM "{t}")').fetchone()[0]
        counts.append((t, total, total - distinct))
        for c in cols:
            n = con.execute(f'SELECT COUNT(*) FROM "{t}" WHERE "{c}" IS NULL').fetchone()[0]
            if n:
                missing.append((t, c, n, round(100 * n / total, 2)))
    save("dq00_row_counts_and_duplicates", ["tbl", "row_count", "exact_duplicate_rows"], counts)
    save("dq00_missing_values", ["tbl", "column_name", "missing", "missing_pct"], missing)


def main(db=None):
    db = Path(db) if db else HERE / "data" / "olist.db"
    if not db.exists():
        sys.exit(f"{db} not found. Run load_data.py first.")
    OUT.mkdir(exist_ok=True)
    con = sqlite3.connect(db)
    table_checks(con)
    text = (HERE / "sql" / "01_data_quality.sql").read_text(encoding="utf-8")
    for block in re.split(r"^-- name:\s*", text, flags=re.M)[1:]:
        name, _, body = block.partition("\n")
        cur = con.execute(body.strip().rstrip(";"))
        save(name.strip(), [d[0] for d in cur.description], cur.fetchall())
    con.close()


if __name__ == "__main__":
    main(*sys.argv[1:])
