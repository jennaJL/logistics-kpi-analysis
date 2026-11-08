"""Step 3: how much does late delivery hurt customers?

Usage:
    python analyze_lateness.py [DB_PATH]        (default: data/olist.db)

1. Runs sql/06_lateness_impact.sql and saves each query to output/li*.csv.
2. Fits regressions of review score and bad review (1-2 stars) on is_late, controlling for
   item count, seller count, order value, purchase month and customer state (issues 7 and 26).
   Each is fitted on all reviews, on reviews answered on/after delivery, and on single-seller,
   single-item orders answered after delivery. Saved to output/li05_regression.csv.

Needs pandas and statsmodels (pip install pandas statsmodels). Reads the database only.
"""
import csv
import re
import sqlite3
import sys
from pathlib import Path

import numpy as np
import pandas as pd
import statsmodels.formula.api as smf

HERE = Path(__file__).resolve().parent
OUT = HERE / "output"
SQL = HERE / "sql" / "06_lateness_impact.sql"


def run_sql(con):
    text = SQL.read_text()
    parts = re.split(r"^-- name: (\w+)\s*$", text, flags=re.M)
    for name, query in zip(parts[1::2], parts[2::2]):
        cur = con.execute(query)
        cols = [d[0] for d in cur.description]
        rows = cur.fetchall()
        with open(OUT / f"{name}.csv", "w", newline="") as f:
            w = csv.writer(f)
            w.writerow(cols)
            w.writerows(rows)
        print(f"\n{name}  ({len(rows)} rows)")
        print(pd.DataFrame(rows, columns=cols).to_string(index=False))


def load_orders(con):
    df = pd.read_sql_query(
        """SELECT order_id, review_score, is_late, days_late, answered_before_delivery,
                  item_count, seller_count, order_value, purchase_month, customer_state
           FROM fct_orders WHERE in_score_analysis = 1""",
        con,
    )
    before = len(df)
    df = df.dropna(subset=["item_count", "seller_count", "order_value"])
    print(f"\nRegression orders: {len(df):,} of {before:,} (dropped {before - len(df)} with no items)")
    df["bad_review"] = (df["review_score"] <= 2).astype(int)
    df["multi_item"] = (df["item_count"] > 1).astype(int)
    df["multi_seller"] = (df["seller_count"] > 1).astype(int)
    df["log_value"] = np.log1p(df["order_value"])
    return df


def fit_models(df):
    samples = {
        "all reviews": df,
        "reviews after delivery": df[df["answered_before_delivery"] == 0],
        "after delivery, 1 seller and 1 item": df[
            (df["answered_before_delivery"] == 0) & (df["item_count"] == 1) & (df["seller_count"] == 1)
        ],
    }
    results = []
    for sample, d in samples.items():
        for outcome, label in [("review_score", "score (1-5)"), ("bad_review", "bad review (share)")]:
            for controls in ["none", "full"]:
                rhs = "is_late"
                if controls == "full":
                    extra = " + log_value + C(purchase_month) + C(customer_state)"
                    if d["multi_item"].nunique() > 1:
                        extra = " + multi_item + multi_seller" + extra
                    rhs += extra
                m = smf.ols(f"{outcome} ~ {rhs}", data=d).fit(cov_type="HC1")
                lo, hi = m.conf_int().loc["is_late"]
                results.append({
                    "sample": sample,
                    "outcome": label,
                    "controls": controls,
                    "orders": int(m.nobs),
                    "late_orders": int(d["is_late"].sum()),
                    "late_effect": round(m.params["is_late"], 3),
                    "ci95_low": round(lo, 3),
                    "ci95_high": round(hi, 3),
                    "p_value": f"{m.pvalues['is_late']:.1e}",
                })
    out = pd.DataFrame(results)
    out.to_csv(OUT / "li05_regression.csv", index=False)
    print("\nli05_regression  (effect of being late; HC1 robust standard errors)")
    print(out.to_string(index=False))


def main():
    db = Path(sys.argv[1]) if len(sys.argv) > 1 else HERE / "data" / "olist.db"
    con = sqlite3.connect(f"file:{db}?mode=ro", uri=True)
    OUT.mkdir(exist_ok=True)
    run_sql(con)
    fit_models(load_orders(con))
    con.close()


if __name__ == "__main__":
    main()
