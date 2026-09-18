# Finance Analytics ETL Pipeline & Power BI Dashboard

![MySQL](https://img.shields.io/badge/MySQL-8.0-4479A1?style=for-the-badge&logo=mysql&logoColor=white)
![Python](https://img.shields.io/badge/Python-3.9+-3776AB?style=for-the-badge&logo=python&logoColor=white)
![Power BI](https://img.shields.io/badge/Power%20BI-Dashboard-F2C811?style=for-the-badge&logo=powerbi&logoColor=black)
![Pandas](https://img.shields.io/badge/Pandas-2.0-150458?style=for-the-badge&logo=pandas&logoColor=white)

A end-to-end **Finance Analytics** project built with a Python ETL pipeline, MySQL star schema, and an interactive Power BI dashboard — covering General Ledger, Accounts Payable, Accounts Receivable, Budget Forecasting, and Expense Claims.

---

## Dashboard Preview

### P&L Overview
> Revenue trends by department, total costs, and net position across 2023–2025

### Budget VS Actual
> Quarterly budget vs actual spend by department with variance analysis

### Cash Flow
> Monthly receivables vs payables with AP status breakdown

### Expense Claims
> Employee expense breakdown by category and approval status

>

---

##  Architecture

```
┌─────────────────────────────────────────────────────┐
│                   DATA SOURCES                      │
│  General   Accounts  Accounts  Budget   Expense     │
│  Ledger    Payable   Receivable Forecast Claims      │
│  .xlsx     .xlsx     .xlsx      .xlsx    .xlsx       │
└────────────────────┬────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────┐
│              ETL PIPELINE (Python)                  │
│                                                     │
│  EXTRACT          TRANSFORM           LOAD          │
│  pandas           Clean & model    SQLAlchemy        │
│  read_excel()     Star schema      → MySQL           │
└────────────────────┬────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────┐
│           MySQL DATABASE (finance_analytics)        │
│                                                     │
│  Dimensions          Facts                          │
│  ├── dim_date        ├── fact_general_ledger         │
│  ├── dim_department  ├── fact_accounts_payable       │
│  └── dim_currency    ├── fact_accounts_receivable    │
│                      ├── fact_budget_forecast        │
│                      └── fact_expense_claims         │
└────────────────────┬────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────┐
│              POWER BI DASHBOARD                     │
│  ├── P&L Overview                                   │
│  ├── Budget VS Actual                               │
│  ├── Cash Flow                                      │
│  └── Expense Claims                                 │
└─────────────────────────────────────────────────────┘
```

---

## Repository Structure

```
finance-analytics-etl/
│
├── sql/
│   ├── schema.sql                    # Database DDL — all tables & views
│   └── finance_analytics_data.sql   # Full INSERT statements (all 4,748 rows)
│
├── etl_pipeline.py                  # Python ETL script
├── requirements.txt                 # Python dependencies
├── screenshots/                     # Power BI dashboard screenshots
└── README.md
```

---

## Database Schema

### Star Schema Design

```
                    dim_date
                       │
   dim_department ──────┼───── fact_general_ledger ───── dim_currency
                        │
                        ├───── fact_accounts_payable
                        │
                        ├───── fact_accounts_receivable
                        │
                        ├───── fact_budget_forecast
                        │
                        └───── fact_expense_claims
```

### Tables

| Table | Rows | Description |
|-------|------|-------------|
| `dim_department` | 6 | Finance, HR, IT, Marketing, Operations, Sales |
| `dim_currency` | 5 | AUD, CAD, EUR, GBP, USD |
| `dim_date` | 949 | Full calendar — year, quarter, month, week, weekday |
| `fact_general_ledger` | 2,000 | Journal entries with debit, credit, net amount |
| `fact_accounts_payable` | 800 | Vendor invoices with ageing and overdue flags |
| `fact_accounts_receivable` | 900 | Customer invoices with collection status |
| `fact_budget_forecast` | 48 | Quarterly budget vs actual by department |
| `fact_expense_claims` | 1,000 | Employee claims with approval workflow |
| **Total** | **4,748** | |

### Analytical Views (Power BI ready)

| View | Purpose |
|------|---------|
| `vw_pl_by_dept_month` | P&L breakdown by department and month |
| `vw_budget_vs_actual` | Budget vs forecast vs actual with variance % |
| `vw_ap_ageing` | AP ageing buckets (0–30, 31–60, 61–90, 90+ days) |
| `vw_ar_collection` | AR collection rate per customer |
| `vw_expense_summary` | Expense claims by category and status |
| `vw_cashflow_summary` | Monthly receivables vs payables |
| `vw_top_vendors` | Top vendors by total spend |
| `vw_employee_expenses` | Employee expense leaderboard |

---

## Setup & Installation

### Prerequisites
- Python 3.9+
- MySQL 8.0+
- MySQL Connector/NET (for Power BI)
- Power BI Desktop (free)

### 1. Clone the repository
```bash
git clone https://github.com/yourusername/finance-analytics-etl.git
cd finance-analytics-etl
```

### 2. Install Python dependencies
```bash
pip install -r requirements.txt
```

### 3. Set up MySQL database
```bash
# Create schema (tables + views)
mysql -u root -p < sql/schema.sql

# Load all data
mysql -u root -p < sql/finance_analytics_data.sql
```

### 4. Verify data loaded correctly
```sql
USE finance_analytics;

SELECT 'dim_department'            AS table_name, COUNT(*) AS total FROM dim_department
UNION ALL SELECT 'dim_currency',                  COUNT(*) FROM dim_currency
UNION ALL SELECT 'dim_date',                      COUNT(*) FROM dim_date
UNION ALL SELECT 'fact_general_ledger',            COUNT(*) FROM fact_general_ledger
UNION ALL SELECT 'fact_accounts_payable',          COUNT(*) FROM fact_accounts_payable
UNION ALL SELECT 'fact_accounts_receivable',       COUNT(*) FROM fact_accounts_receivable
UNION ALL SELECT 'fact_budget_forecast',           COUNT(*) FROM fact_budget_forecast
UNION ALL SELECT 'fact_expense_claims',            COUNT(*) FROM fact_expense_claims;
```

### 5. Connect Power BI
1. Open Power BI Desktop
2. Get Data → MySQL database
3. Server: `localhost` | Database: `finance_analytics`
4. Load all `dim_*`, `fact_*` tables

---

## ETL Pipeline

The Python ETL script (`etl_pipeline.py`) handles the full pipeline:

### Extract
- Reads all 5 `.xlsx` source files using `pandas.read_excel()`
- Validates file existence before processing

### Transform
| Step | Detail |
|------|--------|
| Date parsing | All date columns converted to datetime → YYYYMMDD integer keys |
| Null handling | Open invoice dates kept as NULL (expected for unpaid items) |
| Derived columns | `net_amount`, `days_to_due`, `is_overdue`, `variance_pct` |
| Dimension extraction | Departments & currencies deduplicated into lookup tables |
| Calendar table | `dim_date` built from all date columns across all 5 files |
| Notes column | Dropped from Budget Forecast (100% empty) |

### Load
- Writes to MySQL using SQLAlchemy
- Disables FK checks during bulk load for performance
- Processes tables in dependency order (dimensions first, facts second)

---

## Power BI Dashboard

### DAX Measures Used

```dax
Net Cash Flow =
    SUM(Fact_accounts_receivable[amount]) -
    SUM(Fact_accounts_payable[amount])

Total Revenue =
    CALCULATE(SUM(Fact_general_ledger[credit]),
              Fact_general_ledger[account_name] = "Sales Revenue")

Budget Variance % =
    DIVIDE(SUM(Fact_budget_forecast[variance_usd]),
           SUM(Fact_budget_forecast[budget_usd])) * 100
```

### Dashboard Pages

| Page | Key Visuals | Key Insight |
|------|------------|-------------|
| P&L Overview | Line chart, bar chart, KPI cards | 1.97M revenue, 763K net position |
| Budget VS Actual | Clustered column, variance table | Marketing 31.97% over budget |
| Cash Flow | Column chart, donut chart | 1.51M positive net cash flow |
| Expense Claims | Bar chart, donut, employee table | Supplies largest category (21.31%) |

---

## Tech Stack

| Layer | Technology |
|-------|-----------|
| Language | Python 3.9+ |
| Data Processing | pandas, numpy |
| Database | MySQL 8.0 |
| ORM / Loader | SQLAlchemy + mysql-connector-python |
| Visualisation | Microsoft Power BI Desktop |
| Version Control | Git / GitHub |

---

## Data Source

**Finance & Accounting Sample Datasets** — 5 fully synthetic, audit-ready Excel workbooks  
Source: [Excelx.com — Free Finance & Accounting Sample Data](https://excelx.com/practice-data/finance-accounting/)  
License: Free for practice and portfolio use

---


Abel Okpanachi
- GitHub: https://github.com/Youngboss45
- LinkedIn: https://www.linkedin.com/in/abel-okpanachi-170404277/

---

*Built as a portfolio project demonstrating a complete data engineering workflow — from raw Excel files to an interactive financial dashboard.*
