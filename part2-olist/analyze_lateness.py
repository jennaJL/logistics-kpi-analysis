"""Step 3: how much does late delivery hurt customers?

Usage:
    python analyze_lateness.py [DB_PATH]        (default: data/olist.db)

1. Runs sql/06_lateness_impact.sql and saves each query to output/li*.csv.
2. Fits regressions of review score and bad review (1-2 stars) on is_late, controlling for
   item count, seller count, order value, purchase month and customer state (issues 7 and 26).
   Each is fitted on all reviews, on reviews answered on/after delivery, and on single-seller,
   single-item orders answered after delivery. Saved to output/li05_regression.csv.
3. Bootstrap 95% intervals for the late vs on-time gap in average score and bad-review share
   (10,000 resamples, seed 42). Saved to output/li06_bootstrap.csv.
4. Regressions with the task's controls: item price, freight, seller-customer distance and
   product category, plus month, customer state and multi-item. Single-seller orders only,
   because distance exists only for them (issue 10). Saved to output/li07_regression_controls.csv.

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


def bootstrap(df, reps=10_000, seed=42):
    """Resample orders with replacement within the late and on-time groups.

    A review score takes only five values, so resampling n orders is the same as drawing the
    counts of 1-5 stars from a multinomial with the group's observed shares. This gives the
    exact bootstrap distribution, and is fast enough for 10,000 resamples.
    """
    rng = np.random.default_rng(seed)
    stars = np.arange(1, 6)
    rows = []
    samples = {"all reviews": df, "reviews after delivery": df[df["answered_before_delivery"] == 0]}
    for sample, d in samples.items():
        means, bads = {}, {}
        point = {}
        for late in (0, 1):
            g = d.loc[d["is_late"] == late, "review_score"].astype(int)
            n = len(g)
            p = g.value_counts().reindex(stars, fill_value=0).to_numpy() / n
            draws = rng.multinomial(n, p, size=reps)  # reps x 5 star counts
            means[late] = draws @ stars / n
            bads[late] = draws[:, :2].sum(axis=1) / n
            point[late] = (g.mean(), (g <= 2).mean(), n)
        for metric, diff, est in [
            ("avg score (late - on time)", means[1] - means[0], point[1][0] - point[0][0]),
            ("bad review share (late - on time)", bads[1] - bads[0], point[1][1] - point[0][1]),
        ]:
            lo, hi = np.percentile(diff, [2.5, 97.5])
            rows.append({
                "sample": sample, "metric": metric,
                "on_time_orders": point[0][2], "late_orders": point[1][2],
                "on_time": round(point[0][0] if "score" in metric else point[0][1], 3),
                "late": round(point[1][0] if "score" in metric else point[1][1], 3),
                "difference": round(est, 3), "ci95_low": round(lo, 3), "ci95_high": round(hi, 3),
                "resamples": reps,
            })
    out = pd.DataFrame(rows)
    out.to_csv(OUT / "li06_bootstrap.csv", index=False)
    print("\nli06_bootstrap  (percentile intervals, 10,000 resamples)")
    print(out.to_string(index=False))


def load_controls(con):
    df = pd.read_sql_query(
        """SELECT order_id, review_score, is_late, answered_before_delivery, item_count,
                  items_price, freight, distance_km, main_category, purchase_month, customer_state
           FROM fct_orders
           WHERE in_score_analysis = 1 AND seller_count = 1""",
        con,
    )
    before = len(df)
    df = df.dropna(subset=["items_price", "freight", "distance_km"])
    print(f"\nControl-regression orders: {len(df):,} of {before:,} single-seller orders "
          f"(dropped {before - len(df)} with no distance, issue 23)")
    df["bad_review"] = (df["review_score"] <= 2).astype(int)
    df["multi_item"] = (df["item_count"] > 1).astype(int)
    df["log_price"] = np.log1p(df["items_price"])
    df["log_freight"] = np.log1p(df["freight"])
    df["log_distance"] = np.log1p(df["distance_km"])
    # Categories with fewer than 300 orders are pooled, so each category effect is estimable.
    counts = df["main_category"].value_counts()
    df["category"] = df["main_category"].where(df["main_category"].map(counts) >= 300, "other (small)")
    return df


def fit_control_models(df):
    specs = {
        "none": "is_late",
        "price, freight, distance": "is_late + log_price + log_freight + log_distance",
        "full": ("is_late + log_price + log_freight + log_distance + C(category)"
                 " + multi_item + C(purchase_month) + C(customer_state)"),
    }
    samples = {"all reviews": df, "reviews after delivery": df[df["answered_before_delivery"] == 0]}
    results = []
    for sample, d in samples.items():
        for outcome, label in [("review_score", "score (1-5)"), ("bad_review", "bad review (share)")]:
            for name, rhs in specs.items():
                m = smf.ols(f"{outcome} ~ {rhs}", data=d).fit(cov_type="HC1")
                lo, hi = m.conf_int().loc["is_late"]
                results.append({
                    "sample": sample, "outcome": label, "controls": name,
                    "orders": int(m.nobs), "late_orders": int(d["is_late"].sum()),
                    "late_effect": round(m.params["is_late"], 3),
                    "ci95_low": round(lo, 3), "ci95_high": round(hi, 3),
                    "p_value": f"{m.pvalues['is_late']:.1e}",
                })
    out = pd.DataFrame(results)
    out.to_csv(OUT / "li07_regression_controls.csv", index=False)
    print("\nli07_regression_controls  (effect of being late; HC1 robust standard errors)")
    print(out.to_string(index=False))
    # Are the controls related to lateness? If not, they cannot confound it.
    print("\nLate rate by distance quartile (single-seller orders):")
    print(df.groupby(pd.qcut(df["distance_km"], 4), observed=True)["is_late"].mean().round(3).to_string())


def main():
    db = Path(sys.argv[1]) if len(sys.argv) > 1 else HERE / "data" / "olist.db"
    con = sqlite3.connect(f"file:{db}?mode=ro", uri=True)
    OUT.mkdir(exist_ok=True)
    run_sql(con)
    orders = load_orders(con)
    fit_models(orders)
    bootstrap(orders)
    fit_control_models(load_controls(con))
    con.close()


if __name__ == "__main__":
    main()
