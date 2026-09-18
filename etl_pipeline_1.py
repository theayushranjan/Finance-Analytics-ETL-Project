"""
Finance Analytics ETL Pipeline
================================
Extracts 5 Excel files, transforms them into a clean star schema,
and loads everything into MySQL.

Usage:
    1. pip install -r requirements.txt
    2. Update the CONFIG block below
    3. python etl_pipeline.py
"""

import pandas as pd
import numpy as np
from sqlalchemy import create_engine, text
import logging, sys, os
from datetime import date

# ─────────────────────────────────────────────
# CONFIG  ← update before running
# ─────────────────────────────────────────────
DB_HOST     = "localhost"
DB_PORT     = 3306
DB_USER     = "root"
DB_PASSWORD = "your_password"     # ← change this
DB_NAME     = "finance_analytics"

DATA_DIR = "data"   # folder where your 5 xlsx files live
FILES = {
    "gl": "General-Ledger.xlsx",
    "ap": "Accounts-Payable.xlsx",
    "ar": "Accounts-Receivable.xlsx",
    "bf": "Budget-Forecast.xlsx",
    "ec": "Expense-Claims.xlsx",
}

# ─────────────────────────────────────────────
# LOGGING
# ─────────────────────────────────────────────
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s  %(levelname)-8s  %(message)s",
    handlers=[logging.StreamHandler(sys.stdout)],
)
log = logging.getLogger(__name__)


# ═══════════════════════════════════════════════════════════════
# HELPERS
# ═══════════════════════════════════════════════════════════════

def read_xlsx(key: str) -> pd.DataFrame:
    path = os.path.join(DATA_DIR, FILES[key])
    if not os.path.exists(path):
        log.error(f"File not found: {path}")
        sys.exit(1)
    df = pd.read_excel(path)
    df.columns = df.columns.str.strip()
    log.info(f"[EXTRACT] {key.upper():>2} — {len(df):>5,} rows  ({FILES[key]})")
    return df


def date_to_id(d) -> int | None:
    """Convert a date/datetime to YYYYMMDD integer key."""
    if pd.isnull(d):
        return None
    if hasattr(d, "date"):
        d = d.date()
    return int(d.strftime("%Y%m%d"))


def build_dim_date(date_series_list: list) -> pd.DataFrame:
    """Build a calendar dimension from a list of date Series."""
    all_dates = pd.concat(date_series_list).dropna()
    all_dates = pd.to_datetime(all_dates).dt.normalize().drop_duplicates().sort_values()
    rows = []
    for d in all_dates:
        rows.append({
            "date_id":    int(d.strftime("%Y%m%d")),
            "full_date":  d.date(),
            "year":       d.year,
            "quarter":    d.quarter,
            "month":      d.month,
            "month_name": d.strftime("%B"),
            "week":       int(d.isocalendar()[1]),
            "day":        d.day,
            "weekday":    d.strftime("%A"),
            "is_weekend": 1 if d.weekday() >= 5 else 0,
        })
    return pd.DataFrame(rows).drop_duplicates(subset=["date_id"])


def load_table(df: pd.DataFrame, table: str, engine, pk: str = None) -> None:
    """Write a DataFrame to MySQL, replacing existing data."""
    if df.empty:
        log.warning(f"[LOAD] Skipping empty table: {table}")
        return
    df.to_sql(table, con=engine, if_exists="replace", index=False,
              chunksize=500, method="multi")
    log.info(f"[LOAD] {table:<35} {len(df):>6,} rows ✓")


# ═══════════════════════════════════════════════════════════════
# 1. EXTRACT
# ═══════════════════════════════════════════════════════════════

def extract() -> dict:
    log.info("[EXTRACT] Reading source files …")
    return {k: read_xlsx(k) for k in FILES}


# ═══════════════════════════════════════════════════════════════
# 2. TRANSFORM
# ═══════════════════════════════════════════════════════════════

def transform(raw: dict) -> dict:
    log.info("[TRANSFORM] Building dimensions …")

    gl = raw["gl"].copy()
    ap = raw["ap"].copy()
    ar = raw["ar"].copy()
    bf = raw["bf"].copy()
    ec = raw["ec"].copy()

    # ── Parse all date columns ───────────────────────────────
    for df, cols in [
        (gl, ["TxnDate"]),
        (ap, ["InvoiceDate", "DueDate", "PaidDate"]),
        (ar, ["InvoiceDate", "DueDate", "ReceivedDate"]),
        (ec, ["SubmitDate", "PayDate"]),
    ]:
        for col in cols:
            if col in df.columns:
                df[col] = pd.to_datetime(df[col], errors="coerce")

    # ── dim_department ───────────────────────────────────────
    depts = sorted(
        set(gl["Dept"].dropna()) |
        set(bf["Dept"].dropna()) |
        set(ec["Dept"].dropna() if "Dept" in ec.columns else [])
    )
    dim_dept = pd.DataFrame({
        "dept_id":   range(1, len(depts) + 1),
        "dept_name": depts,
    })
    dept_map = dict(zip(dim_dept["dept_name"], dim_dept["dept_id"]))
    log.info(f"[TRANSFORM] dim_department  : {len(dim_dept)} rows")

    # ── dim_currency ─────────────────────────────────────────
    currencies = sorted(
        set(gl["Currency"]) | set(ap["Currency"]) |
        set(ar["Currency"]) | set(ec["Currency"])
    )
    dim_currency = pd.DataFrame({
        "currency_id":   range(1, len(currencies) + 1),
        "currency_code": currencies,
    })
    curr_map = dict(zip(dim_currency["currency_code"], dim_currency["currency_id"]))
    log.info(f"[TRANSFORM] dim_currency    : {len(dim_currency)} rows")

    # ── dim_date ─────────────────────────────────────────────
    date_series = [
        gl["TxnDate"],
        ap["InvoiceDate"], ap["DueDate"], ap["PaidDate"],
        ar["InvoiceDate"], ar["DueDate"], ar["ReceivedDate"],
        ec["SubmitDate"], ec["PayDate"],
    ]
    dim_date = build_dim_date(date_series)
    log.info(f"[TRANSFORM] dim_date        : {len(dim_date)} rows")

    log.info("[TRANSFORM] Building fact tables …")

    # ── fact_general_ledger ──────────────────────────────────
    gl["date_id"]     = gl["TxnDate"].apply(date_to_id)
    gl["dept_id"]     = gl["Dept"].map(dept_map)
    gl["currency_id"] = gl["Currency"].map(curr_map)
    gl["net_amount"]  = (gl["Credit"] - gl["Debit"]).round(2)

    fact_gl = gl.rename(columns={
        "GLID": "gl_id", "AccountNumber": "account_number",
        "AccountName": "account_name", "Debit": "debit",
        "Credit": "credit", "CostCenter": "cost_center",
        "Description": "description",
    })[[
        "gl_id", "date_id", "account_number", "account_name",
        "debit", "credit", "net_amount", "dept_id",
        "cost_center", "description", "currency_id",
    ]]
    log.info(f"[TRANSFORM] fact_general_ledger : {len(fact_gl):,} rows")

    # ── fact_accounts_payable ────────────────────────────────
    ap["invoice_date_id"] = ap["InvoiceDate"].apply(date_to_id)
    ap["due_date_id"]     = ap["DueDate"].apply(date_to_id)
    ap["paid_date_id"]    = ap["PaidDate"].apply(date_to_id)
    ap["currency_id"]     = ap["Currency"].map(curr_map)
    ap["days_to_due"]     = (ap["DueDate"] - ap["InvoiceDate"]).dt.days.astype("Int64")
    ap["is_overdue"]      = (
        (ap["Status"] != "Paid") &
        (ap["DueDate"] < pd.Timestamp(date.today()))
    ).astype(int)

    fact_ap = ap.rename(columns={
        "APID": "ap_id", "Vendor": "vendor",
        "Amount": "amount", "Status": "status", "Terms": "terms",
    })[[
        "ap_id", "vendor", "invoice_date_id", "due_date_id", "paid_date_id",
        "amount", "currency_id", "status", "terms", "days_to_due", "is_overdue",
    ]]
    log.info(f"[TRANSFORM] fact_accounts_payable   : {len(fact_ap):,} rows")

    # ── fact_accounts_receivable ─────────────────────────────
    ar["invoice_date_id"]  = ar["InvoiceDate"].apply(date_to_id)
    ar["due_date_id"]      = ar["DueDate"].apply(date_to_id)
    ar["received_date_id"] = ar["ReceivedDate"].apply(date_to_id)
    ar["currency_id"]      = ar["Currency"].map(curr_map)
    ar["days_to_due"]      = (ar["DueDate"] - ar["InvoiceDate"]).dt.days.astype("Int64")
    ar["is_overdue"]       = (
        (ar["Status"] != "Received") &
        (ar["DueDate"] < pd.Timestamp(date.today()))
    ).astype(int)

    fact_ar = ar.rename(columns={
        "ARID": "ar_id", "Customer": "customer",
        "Amount": "amount", "Status": "status", "Terms": "terms",
    })[[
        "ar_id", "customer", "invoice_date_id", "due_date_id", "received_date_id",
        "amount", "currency_id", "status", "terms", "days_to_due", "is_overdue",
    ]]
    log.info(f"[TRANSFORM] fact_accounts_receivable: {len(fact_ar):,} rows")

    # ── fact_budget_forecast ─────────────────────────────────
    bf = bf.drop(columns=["Notes"], errors="ignore")
    bf["dept_id"] = bf["Dept"].map(dept_map)
    bf["variance_pct"] = np.where(
        bf["BudgetUSD"] != 0,
        ((bf["ActualUSD"] - bf["BudgetUSD"]) / bf["BudgetUSD"] * 100).round(2),
        0,
    )

    fact_bf = bf.rename(columns={
        "FiscalYear": "fiscal_year", "Quarter": "quarter",
        "BudgetUSD": "budget_usd", "ForecastUSD": "forecast_usd",
        "ActualUSD": "actual_usd", "VarianceUSD": "variance_usd",
    })[[
        "fiscal_year", "dept_id", "quarter",
        "budget_usd", "forecast_usd", "actual_usd",
        "variance_usd", "variance_pct",
    ]]
    log.info(f"[TRANSFORM] fact_budget_forecast    : {len(fact_bf):,} rows")

    # ── fact_expense_claims ──────────────────────────────────
    ec["submit_date_id"] = ec["SubmitDate"].apply(date_to_id)
    ec["pay_date_id"]    = ec["PayDate"].apply(date_to_id)
    ec["currency_id"]    = ec["Currency"].map(curr_map)

    fact_ec = ec.rename(columns={
        "ClaimID": "claim_id", "EmployeeID": "employee_id",
        "Category": "category", "Description": "description",
        "Amount": "amount", "Status": "status", "ApprovedBy": "approved_by",
    })[[
        "claim_id", "employee_id", "submit_date_id", "pay_date_id",
        "category", "description", "amount", "currency_id",
        "status", "approved_by",
    ]]
    log.info(f"[TRANSFORM] fact_expense_claims     : {len(fact_ec):,} rows")

    return {
        "dim_department":          dim_dept,
        "dim_currency":            dim_currency,
        "dim_date":                dim_date,
        "fact_general_ledger":     fact_gl,
        "fact_accounts_payable":   fact_ap,
        "fact_accounts_receivable":fact_ar,
        "fact_budget_forecast":    fact_bf,
        "fact_expense_claims":     fact_ec,
    }


# ═══════════════════════════════════════════════════════════════
# 3. LOAD
# ═══════════════════════════════════════════════════════════════

def load(tables: dict, engine) -> None:
    log.info("[LOAD] Writing to MySQL …")

    # Disable FK checks during bulk load, re-enable after
    with engine.connect() as conn:
        conn.execute(text("SET FOREIGN_KEY_CHECKS = 0"))
        conn.commit()

    load_order = [
        "dim_department",
        "dim_currency",
        "dim_date",
        "fact_general_ledger",
        "fact_accounts_payable",
        "fact_accounts_receivable",
        "fact_budget_forecast",
        "fact_expense_claims",
    ]
    for name in load_order:
        load_table(tables[name], name, engine)

    with engine.connect() as conn:
        conn.execute(text("SET FOREIGN_KEY_CHECKS = 1"))
        conn.commit()


# ═══════════════════════════════════════════════════════════════
# MAIN
# ═══════════════════════════════════════════════════════════════

def main():
    log.info("=" * 58)
    log.info("   FINANCE ANALYTICS ETL PIPELINE")
    log.info("=" * 58)

    conn_str = (
        f"mysql+mysqlconnector://{DB_USER}:{DB_PASSWORD}"
        f"@{DB_HOST}:{DB_PORT}/{DB_NAME}"
    )
    log.info(f"[DB] Connecting → {DB_HOST}:{DB_PORT}/{DB_NAME}")
    engine = create_engine(conn_str, echo=False)

    raw    = extract()
    tables = transform(raw)
    load(tables, engine)

    log.info("=" * 58)
    log.info("   ETL COMPLETE ✓  —  8 tables loaded")
    log.info("=" * 58)


if __name__ == "__main__":
    main()
