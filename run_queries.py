"""Run every query in sql/*.sql against logistics.db and save each result as a CSV.

Usage:
    python run_queries.py            # uses logistics.db, writes to output/
Each query block in a .sql file starts with a line "-- name: <name>".
The CSVs in output/ are what the Tableau dashboard imports.
"""
import re
import sqlite3
from pathlib import Path

import pandas as pd

ROOT = Path(__file__).parent
OUT = ROOT / "output"


def split_queries(sql_text: str):
    blocks = re.split(r"^-- name:\s*", sql_text, flags=re.M)[1:]
    for block in blocks:
        name, _, body = block.partition("\n")
        yield name.strip(), body.strip().rstrip(";")


def main(db: str = "logistics.db") -> None:
    OUT.mkdir(exist_ok=True)
    con = sqlite3.connect(ROOT / db)
    for sql_file in sorted((ROOT / "sql").glob("*.sql")):
        for name, query in split_queries(sql_file.read_text(encoding="utf-8")):
            df = pd.read_sql(query, con)
            df.to_csv(OUT / f"{name}.csv", index=False)
            print(f"\n=== {name} ({len(df)} rows) ===")
            print(df.head(12).to_string(index=False))
    con.close()


if __name__ == "__main__":
    main()
