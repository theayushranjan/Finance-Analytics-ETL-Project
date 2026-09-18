-- ================================================================
-- Finance Analytics — MySQL Star Schema
-- Database: finance_analytics
-- Tables: 3 dimensions + 5 fact tables + 8 analytical views
-- ================================================================

CREATE DATABASE IF NOT EXISTS finance_analytics;
USE finance_analytics;

-- ────────────────────────────────────────────────────────────────
-- DIMENSION TABLES
-- ────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS dim_department (
    dept_id    TINYINT      NOT NULL AUTO_INCREMENT,
    dept_name  VARCHAR(50)  NOT NULL,
    PRIMARY KEY (dept_id),
    UNIQUE KEY uq_dept_name (dept_name)
);

CREATE TABLE IF NOT EXISTS dim_currency (
    currency_id   TINYINT     NOT NULL AUTO_INCREMENT,
    currency_code CHAR(3)     NOT NULL,
    PRIMARY KEY (currency_id),
    UNIQUE KEY uq_currency_code (currency_code)
);

CREATE TABLE IF NOT EXISTS dim_date (
    date_id     INT      NOT NULL,
    full_date   DATE     NOT NULL,
    year        SMALLINT NOT NULL,
    quarter     TINYINT  NOT NULL,
    month       TINYINT  NOT NULL,
    month_name  VARCHAR(10) NOT NULL,
    week        TINYINT  NOT NULL,
    day         TINYINT  NOT NULL,
    weekday     VARCHAR(10) NOT NULL,
    is_weekend  TINYINT  NOT NULL DEFAULT 0,
    PRIMARY KEY (date_id),
    INDEX idx_year_month (year, month),
    INDEX idx_full_date  (full_date)
);

-- ────────────────────────────────────────────────────────────────
-- FACT TABLES
-- ────────────────────────────────────────────────────────────────

-- 1. General Ledger (central fact — 2,000 rows)
CREATE TABLE IF NOT EXISTS fact_general_ledger (
    gl_id          VARCHAR(10)  NOT NULL,
    date_id        INT,
    account_number INT,
    account_name   VARCHAR(50),
    debit          DECIMAL(12,2) DEFAULT 0,
    credit         DECIMAL(12,2) DEFAULT 0,
    net_amount     DECIMAL(12,2) DEFAULT 0,   -- credit - debit
    dept_id        TINYINT,
    cost_center    VARCHAR(10),
    description    VARCHAR(100),
    currency_id    TINYINT,
    PRIMARY KEY (gl_id),
    FOREIGN KEY (date_id)     REFERENCES dim_date(date_id),
    FOREIGN KEY (dept_id)     REFERENCES dim_department(dept_id),
    FOREIGN KEY (currency_id) REFERENCES dim_currency(currency_id),
    INDEX idx_gl_date    (date_id),
    INDEX idx_gl_dept    (dept_id),
    INDEX idx_gl_account (account_number)
);

-- 2. Accounts Payable (800 rows)
CREATE TABLE IF NOT EXISTS fact_accounts_payable (
    ap_id           VARCHAR(10)  NOT NULL,
    vendor          VARCHAR(100),
    invoice_date_id INT,
    due_date_id     INT,
    paid_date_id    INT,
    amount          DECIMAL(12,2),
    currency_id     TINYINT,
    status          VARCHAR(20),
    terms           VARCHAR(20),
    days_to_due     SMALLINT,    -- due_date - invoice_date
    is_overdue      TINYINT DEFAULT 0,
    PRIMARY KEY (ap_id),
    FOREIGN KEY (invoice_date_id) REFERENCES dim_date(date_id),
    FOREIGN KEY (due_date_id)     REFERENCES dim_date(date_id),
    FOREIGN KEY (currency_id)     REFERENCES dim_currency(currency_id),
    INDEX idx_ap_status  (status),
    INDEX idx_ap_vendor  (vendor),
    INDEX idx_ap_invoice (invoice_date_id)
);

-- 3. Accounts Receivable (900 rows)
CREATE TABLE IF NOT EXISTS fact_accounts_receivable (
    ar_id             VARCHAR(10)  NOT NULL,
    customer          VARCHAR(100),
    invoice_date_id   INT,
    due_date_id       INT,
    received_date_id  INT,
    amount            DECIMAL(12,2),
    currency_id       TINYINT,
    status            VARCHAR(20),
    terms             VARCHAR(20),
    days_to_due       SMALLINT,
    is_overdue        TINYINT DEFAULT 0,
    PRIMARY KEY (ar_id),
    FOREIGN KEY (invoice_date_id)  REFERENCES dim_date(date_id),
    FOREIGN KEY (due_date_id)      REFERENCES dim_date(date_id),
    FOREIGN KEY (currency_id)      REFERENCES dim_currency(currency_id),
    INDEX idx_ar_status   (status),
    INDEX idx_ar_customer (customer),
    INDEX idx_ar_invoice  (invoice_date_id)
);

-- 4. Budget Forecast (48 rows)
CREATE TABLE IF NOT EXISTS fact_budget_forecast (
    forecast_id   INT          NOT NULL AUTO_INCREMENT,
    fiscal_year   SMALLINT,
    dept_id       TINYINT,
    quarter       TINYINT,
    budget_usd    DECIMAL(14,2),
    forecast_usd  DECIMAL(14,2),
    actual_usd    DECIMAL(14,2),
    variance_usd  DECIMAL(14,2),
    variance_pct  DECIMAL(7,2),   -- (actual - budget) / budget * 100
    PRIMARY KEY (forecast_id),
    FOREIGN KEY (dept_id) REFERENCES dim_department(dept_id),
    UNIQUE KEY uq_dept_yr_qtr (dept_id, fiscal_year, quarter),
    INDEX idx_bf_year    (fiscal_year),
    INDEX idx_bf_dept    (dept_id)
);

-- 5. Expense Claims (1,000 rows)
CREATE TABLE IF NOT EXISTS fact_expense_claims (
    claim_id      VARCHAR(10)  NOT NULL,
    employee_id   VARCHAR(10),
    submit_date_id INT,
    pay_date_id   INT,
    category      VARCHAR(30),
    description   VARCHAR(100),
    amount        DECIMAL(10,2),
    currency_id   TINYINT,
    status        VARCHAR(20),
    approved_by   VARCHAR(20),
    PRIMARY KEY (claim_id),
    FOREIGN KEY (submit_date_id) REFERENCES dim_date(date_id),
    FOREIGN KEY (currency_id)    REFERENCES dim_currency(currency_id),
    INDEX idx_ec_status   (status),
    INDEX idx_ec_employee (employee_id),
    INDEX idx_ec_category (category),
    INDEX idx_ec_date     (submit_date_id)
);

-- ────────────────────────────────────────────────────────────────
-- ANALYTICAL VIEWS  (ready for Power BI)
-- ────────────────────────────────────────────────────────────────

-- 1. P&L Summary by Department & Month
CREATE OR REPLACE VIEW vw_pl_by_dept_month AS
SELECT
    d.year,
    d.month,
    d.month_name,
    d.quarter,
    dp.dept_name,
    ROUND(SUM(CASE WHEN g.account_name = 'Sales Revenue' THEN g.credit ELSE 0 END), 2) AS revenue,
    ROUND(SUM(CASE WHEN g.account_name = 'Online Sales'  THEN g.credit ELSE 0 END), 2) AS online_sales,
    ROUND(SUM(CASE WHEN g.account_name = 'COGS'          THEN g.debit  ELSE 0 END), 2) AS cogs,
    ROUND(SUM(CASE WHEN g.account_name = 'Payroll Expense' THEN g.debit ELSE 0 END), 2) AS payroll,
    ROUND(SUM(CASE WHEN g.account_name = 'Travel Expense'  THEN g.debit ELSE 0 END), 2) AS travel_expense,
    ROUND(SUM(g.credit) - SUM(g.debit), 2) AS net_position
FROM fact_general_ledger g
JOIN dim_date       d  ON g.date_id  = d.date_id
JOIN dim_department dp ON g.dept_id  = dp.dept_id
GROUP BY d.year, d.month, d.month_name, d.quarter, dp.dept_name
ORDER BY d.year, d.month, dp.dept_name;

-- 2. Budget vs Actual by Department & Quarter
CREATE OR REPLACE VIEW vw_budget_vs_actual AS
SELECT
    bf.fiscal_year,
    bf.quarter,
    dp.dept_name,
    ROUND(bf.budget_usd, 2)   AS budget,
    ROUND(bf.forecast_usd, 2) AS forecast,
    ROUND(bf.actual_usd, 2)   AS actual,
    ROUND(bf.variance_usd, 2) AS variance,
    ROUND(bf.variance_pct, 2) AS variance_pct
FROM fact_budget_forecast bf
JOIN dim_department dp ON bf.dept_id = dp.dept_id
ORDER BY bf.fiscal_year, bf.quarter, dp.dept_name;

-- 3. AP Ageing (open invoices bucketed by overdue days)
CREATE OR REPLACE VIEW vw_ap_ageing AS
SELECT
    ap.vendor,
    c.currency_code,
    ap.status,
    COUNT(*)                                                   AS invoice_count,
    ROUND(SUM(ap.amount), 2)                                   AS total_amount,
    ROUND(SUM(CASE WHEN ap.days_to_due BETWEEN 0  AND 30  THEN ap.amount ELSE 0 END), 2) AS current_0_30,
    ROUND(SUM(CASE WHEN ap.days_to_due BETWEEN 31 AND 60  THEN ap.amount ELSE 0 END), 2) AS overdue_31_60,
    ROUND(SUM(CASE WHEN ap.days_to_due BETWEEN 61 AND 90  THEN ap.amount ELSE 0 END), 2) AS overdue_61_90,
    ROUND(SUM(CASE WHEN ap.days_to_due > 90               THEN ap.amount ELSE 0 END), 2) AS overdue_90_plus
FROM fact_accounts_payable ap
JOIN dim_currency c ON ap.currency_id = c.currency_id
WHERE ap.status != 'Paid'
GROUP BY ap.vendor, c.currency_code, ap.status
ORDER BY total_amount DESC;

-- 4. AR Collection Performance
CREATE OR REPLACE VIEW vw_ar_collection AS
SELECT
    ar.customer,
    c.currency_code,
    ar.status,
    COUNT(*)                   AS invoice_count,
    ROUND(SUM(ar.amount), 2)   AS total_invoiced,
    ROUND(SUM(CASE WHEN ar.status = 'Received' THEN ar.amount ELSE 0 END), 2) AS collected,
    ROUND(SUM(CASE WHEN ar.status != 'Received' THEN ar.amount ELSE 0 END), 2) AS outstanding,
    ROUND(AVG(ar.days_to_due), 1) AS avg_days_to_due
FROM fact_accounts_receivable ar
JOIN dim_currency c ON ar.currency_id = c.currency_id
GROUP BY ar.customer, c.currency_code, ar.status
ORDER BY outstanding DESC;

-- 5. Expense Claims by Category & Status
CREATE OR REPLACE VIEW vw_expense_summary AS
SELECT
    ec.category,
    ec.status,
    c.currency_code,
    COUNT(*)                   AS claim_count,
    ROUND(SUM(ec.amount), 2)   AS total_amount,
    ROUND(AVG(ec.amount), 2)   AS avg_claim,
    ROUND(MAX(ec.amount), 2)   AS max_claim
FROM fact_expense_claims ec
JOIN dim_currency c ON ec.currency_id = c.currency_id
GROUP BY ec.category, ec.status, c.currency_code
ORDER BY total_amount DESC;

-- 6. Cash Flow Summary (AP vs AR by month)
CREATE OR REPLACE VIEW vw_cashflow_summary AS
SELECT
    d.year,
    d.month,
    d.month_name,
    ROUND(SUM(ar.amount), 2) AS receivables,
    ROUND(SUM(ap.amount), 2) AS payables,
    ROUND(SUM(ar.amount) - SUM(ap.amount), 2) AS net_cashflow
FROM dim_date d
LEFT JOIN fact_accounts_receivable ar ON ar.invoice_date_id = d.date_id
LEFT JOIN fact_accounts_payable    ap ON ap.invoice_date_id = d.date_id
GROUP BY d.year, d.month, d.month_name
HAVING receivables IS NOT NULL OR payables IS NOT NULL
ORDER BY d.year, d.month;

-- 7. Top Vendors by Spend (AP)
CREATE OR REPLACE VIEW vw_top_vendors AS
SELECT
    ap.vendor,
    COUNT(*)                  AS invoice_count,
    ROUND(SUM(ap.amount), 2)  AS total_spend,
    ROUND(AVG(ap.amount), 2)  AS avg_invoice,
    SUM(CASE WHEN ap.status = 'Paid'    THEN 1 ELSE 0 END) AS paid_count,
    SUM(CASE WHEN ap.status = 'Open'    THEN 1 ELSE 0 END) AS open_count,
    SUM(CASE WHEN ap.status = 'Partial' THEN 1 ELSE 0 END) AS partial_count
FROM fact_accounts_payable ap
GROUP BY ap.vendor
ORDER BY total_spend DESC;

-- 8. Employee Expense Leaderboard
CREATE OR REPLACE VIEW vw_employee_expenses AS
SELECT
    ec.employee_id,
    ec.approved_by,
    COUNT(*)                  AS total_claims,
    ROUND(SUM(ec.amount), 2)  AS total_spend,
    ROUND(AVG(ec.amount), 2)  AS avg_claim,
    SUM(CASE WHEN ec.status = 'Paid'      THEN 1 ELSE 0 END) AS paid,
    SUM(CASE WHEN ec.status = 'Approved'  THEN 1 ELSE 0 END) AS approved,
    SUM(CASE WHEN ec.status = 'Submitted' THEN 1 ELSE 0 END) AS pending,
    SUM(CASE WHEN ec.status = 'Rejected'  THEN 1 ELSE 0 END) AS rejected
FROM fact_expense_claims ec
GROUP BY ec.employee_id, ec.approved_by
ORDER BY total_spend DESC;
