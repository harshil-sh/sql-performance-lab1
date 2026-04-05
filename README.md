# SQL Server Performance Lab

A hands-on reference guide documenting six SQL Server performance scenarios on a
**10-million-row banking dataset**. Each scenario includes the problem statement,
T-SQL scripts, annotated execution plans, and measured benchmark results so you
can reproduce every finding on your own server.

---

## Table of Contents

1. [Dataset Overview](#dataset-overview)
2. [Setup](#setup)
3. [Scenarios](#scenarios)
   - [01 – Missing Indexes](#01--missing-indexes)
   - [02 – Covering Indexes](#02--covering-indexes)
   - [03 – SARGability](#03--sargability)
   - [04 – Window Functions](#04--window-functions)
   - [05 – Keyset Pagination](#05--keyset-pagination)
   - [06 – Index Fragmentation](#06--index-fragmentation)
4. [Benchmark Summary](#benchmark-summary)
5. [Environment](#environment)
6. [Repository Layout](#repository-layout)

---

## Dataset Overview

| Table                | Rows        | Description                                      |
|----------------------|-------------|--------------------------------------------------|
| `Customers`          | 200 000     | Bank customers with region, DOB, contact info    |
| `Accounts`           | ~600 000    | Checking / savings / loan accounts per customer  |
| `Transactions`       | 10 000 000  | Core fact table — all financial movements        |
| `Loans`              | 300 000     | Loan records linked to customers                 |
| `TransactionAlerts`  | 50 000      | Fraud / overdraft alerts for fragmentation demo  |

The `Transactions` table is the primary target for all performance scenarios. It
has one clustered index on `TransactionID` and starts with **no non-clustered
indexes**, giving a clean baseline for each demonstration.


### Schema Daigeam
```mermaid
erDiagram
    CUSTOMERS ||--o{ ACCOUNTS : "owns"
    CUSTOMERS ||--o{ LOANS : "applies_for"
    ACCOUNTS ||--o{ TRANSACTIONS : "records"
    TRANSACTIONS ||--o{ TRANSACTION_ALERTS : "triggers"

    CUSTOMERS {
        uniqueidentifier CustomerID PK
        varchar FirstName
        varchar LastName
        datetime2 DateOfBirth
        varchar Region
    }

    ACCOUNTS {
        uniqueidentifier AccountID PK
        uniqueidentifier CustomerID FK
        varchar AccountType
        decimal Balance
        datetime2 CreatedDate
    }

    TRANSACTIONS {
        uniqueidentifier TransactionID PK
        uniqueidentifier AccountID FK
        datetime2 TransactionDate
        decimal Amount
        decimal BalanceAfter
        varchar Description
    }

    LOANS {
        uniqueidentifier LoanID PK
        uniqueidentifier CustomerID FK
        decimal LoanAmount
        decimal InterestRate
        datetime2 StartDate
    }

    TRANSACTION_ALERTS {
        int AlertID PK
        uniqueidentifier TransactionID FK
        varchar AlertType
        datetime2 AlertTimestamp
    }
	

---

## Setup

```sql
-- 1. Create schema (database, tables, constraints)
:r setup/01_schema.sql

-- 2. Generate data  (~8–15 min on a laptop-class server)
:r setup/02_data_generation.sql
```

> **Requirements:** SQL Server 2019 or 2022 (Developer or Enterprise Edition),
> ≥ 32 GB RAM recommended, ~3 GB free disk space on the data drive.
>
> **File paths:** `setup/01_schema.sql` defaults to `C:\SQLData\` for the data
> and log files. Edit the `FILENAME` parameters before running if your server
> uses a different directory (e.g. the instance default data path, or
> `/var/opt/mssql/data/` on Linux). The default paths can be found with:
> ```sql
> SELECT physical_name FROM sys.master_files WHERE database_id = 1;
> ```

---

## Scenarios

### 01 – Missing Indexes

**Files:**
- `scenarios/01_missing_indexes/before.sql`
- `scenarios/01_missing_indexes/after.sql`
- `scenarios/01_missing_indexes/optimization.sql`

**Problem:** Without non-clustered indexes every query touching the
`Transactions` table performs a full Clustered Index Scan — reading all
105 042 data pages (~820 MB) regardless of how selective the predicate is.

**Baseline queries**

| Query | Predicate | Plan | Logical Reads | Elapsed |
|-------|-----------|------|---------------|---------|
| Q1 – account lookup | `AccountID = 12345` | Clustered Index Scan | 105 042 | 1 560 ms |
| Q2 – date range | `TransactionDate` Jan 2023 | Clustered Index Scan | 105 042 | 4 102 ms |

**After adding indexes**

```sql
CREATE NONCLUSTERED INDEX IX_Transactions_AccountID
    ON dbo.Transactions (AccountID)
    WITH (FILLFACTOR = 90, ONLINE = ON);

CREATE NONCLUSTERED INDEX IX_Transactions_TransactionDate
    ON dbo.Transactions (TransactionDate)
    WITH (FILLFACTOR = 90, ONLINE = ON);
```

| Query | Plan | Logical Reads | Elapsed | Improvement |
|-------|------|---------------|---------|-------------|
| Q1 – account lookup | Index Seek + Key Lookup | 21 | 1 ms | **~1 560×** |
| Q2 – date range | Index Seek + Key Lookups | 168 442 | 512 ms | **~8×** |

> Q2 still benefits from covering the index (see scenario 02) to eliminate the
> key lookups.

**Key takeaway:** A single missing index on an 10 M-row table can turn a 1 ms
lookup into a 1.5-second full scan. Use `sys.dm_db_missing_index_details` to
surface recommendations automatically after baseline queries execute.

---

### 02 – Covering Indexes

**Files:**
- `scenarios/02_covering_indexes/before.sql`
- `scenarios/02_covering_indexes/after.sql`
- `scenarios/02_covering_indexes/optimization.sql`

**Problem:** A non-clustered index that covers only the key column forces a
Key Lookup for every row that matches the seek to retrieve non-key columns from
the clustered index. At small row counts this is negligible; at thousands of
matching rows it creates thousands of random I/Os.

**Execution plan with key-only index**

```
SELECT Seek → Nested Loops → Key Lookup (PK_Transactions)
             ↑                ↑
       3 reads            3 400 reads (one per matching row)
```

**After adding INCLUDE columns**

```sql
CREATE NONCLUSTERED INDEX IX_Transactions_AccountID_Covering
    ON dbo.Transactions (AccountID)
    INCLUDE (TransactionDate, Amount, BalanceAfter, Description)
    WITH (FILLFACTOR = 90, ONLINE = ON);
```

```
SELECT Seek only — all data served from leaf pages, no Key Lookup
```

| Query | Non-Covering Index | Covering Index | Improvement |
|-------|--------------------|----------------|-------------|
| Single account (17 rows) | 20 reads / 2 ms | 3 reads / 0 ms | **6.7×** reads |
| Range lookup (~3 400 rows) | 6 817 reads / 22 ms | 85 reads / 1 ms | **80×** reads |

**Key takeaway:** Include every non-key column that appears in `SELECT` or
`ORDER BY` for your most performance-sensitive queries. Trade ~3× index size for
elimination of all key lookups.

---

### 03 – SARGability

**Files:**
- `scenarios/03_sargability/before.sql`
- `scenarios/03_sargability/after.sql`
- `scenarios/03_sargability/optimization.sql`

**Problem:** A predicate is *SARGable* when SQL Server can evaluate it with an
index seek. Wrapping an indexed column in a function, using implicit type
conversions, or using negation operators all prevent seeks — forcing full index
scans regardless of how many indexes exist.

**Patterns covered**

| # | Non-SARGable Pattern | SARGable Rewrite | Reads Improvement |
|---|----------------------|------------------|-------------------|
| 1 | `YEAR(TransactionDate) = 2023` | `TransactionDate >= '2023-01-01' AND TransactionDate < '2024-01-01'` | **~118×** |
| 2 | VARCHAR literal on DATETIME2 | `CAST('2023-06-15' AS DATETIME2(3))` typed literal | **>1 000×** |
| 3 | `LastName LIKE '%son'` | `LastName LIKE 'Johnson%'` | **170×** |
| 4 | `TransactionTypeID <> 1` | Positive `IN (2,3,4,5,6)` predicate | scan → seek |
| 5 | `OR` across different columns | `UNION ALL` with one branch per column | **>4 000×** |
| 6 | `YEAR()/MONTH()` unavoidable | PERSISTED computed column + index | **~65×** |

**SARGability rules**
- Never apply a function to the indexed column — apply it to the literal instead.
- Use typed literals (`CAST`/`CONVERT`) to avoid implicit conversions.
- Replace leading-wildcard `LIKE` with full-text search or a suffix-indexed column.
- Rewrite `OR` across columns as `UNION ALL`.
- For unavoidable function predicates, use a PERSISTED computed column with an index.

---

### 04 – Window Functions

**Files:**
- `scenarios/04_window_functions/before.sql`
- `scenarios/04_window_functions/after.sql`
- `scenarios/04_window_functions/optimization.sql`

**Problem:** Classic row-by-row approaches (correlated sub-queries, cursors,
self-joins) compute aggregates with O(n²) or O(n·k) complexity. SQL Server
window functions stream over an ordered set in a single pass — O(n).

**Patterns covered**

| Pattern | Approach Compared | Window Result | Improvement |
|---------|-------------------|---------------|-------------|
| Top-N per group (100 accounts, top 3 each) | Correlated sub-query | 1 ms / 88 reads | **>8 000× faster** |
| Running balance (single account) | FAST_FORWARD cursor | 0 ms / 6 reads | **3–5× CPU** |
| LAG/LEAD transaction delta (11 accounts) | Self-join | 0 ms / 9 reads | index seek vs. scan |
| NTILE balance quartiles (600 K accounts) | Multiple sub-queries | 224 ms / 1 803 reads | single pass |
| 7-day rolling deposit average (1 825 days) | Self-join 7 copies | 1 980 ms / 1 pass | **O(n) vs O(n·7)** |

**Execution plan notes**

```
-- ROW_NUMBER() with matching index on (AccountID, TransactionDate):
--   Index Seek → Window Spool (ordered) → Filter rn <= 3
--   No blocking Sort operator — index already provides order.

-- Without the supporting index:
--   Clustered Index Scan → Sort (30% of plan cost) → Window Spool
```

**Key takeaway:** An index on `(PARTITION BY column, ORDER BY column)` eliminates
the Sort operator from every window-function query on that partition/order
combination. Always measure with and without the supporting index.

---

### 05 – Keyset Pagination

**Files:**
- `scenarios/05_keyset_pagination/before.sql`
- `scenarios/05_keyset_pagination/after.sql`
- `scenarios/05_keyset_pagination/optimization.sql`

**Problem:** `OFFSET n ROWS FETCH NEXT k ROWS ONLY` must skip all `n` rows on
every page request. At page 100 000 with page size 25 the engine traverses
2.5 million rows — costing 19 617 logical reads and 2.4 seconds per call.
*Keyset pagination* uses a `WHERE` clause on the bookmark keys, achieving an
index seek that costs the same regardless of page depth.

**Performance comparison**

| Scenario | OFFSET/FETCH | Keyset | Improvement |
|----------|-------------|--------|-------------|
| Page 1 (first 25 rows) | 3 reads / 0 ms | 3 reads / 0 ms | identical |
| Page 2 000 (offset 49 975) | 392 reads / 49 ms | 3 reads / 0 ms | **131×** |
| Page 100 000 (offset 2 499 975) | 19 617 reads / 2 461 ms | 3 reads / 0 ms | **>6 500×** |
| Approximate row count | 19 812 reads / 2 243 ms | 2 reads (catalog) | **~9 900×** |

**Keyset pattern (forward)**

```sql
-- Client stores: @LastDate, @LastTxID from the previous page's last row.
SELECT TOP (25)
    TransactionID, TransactionDate, AccountID, Amount
FROM   dbo.Transactions
WHERE (TransactionDate  > @LastDate)
   OR (TransactionDate  = @LastDate AND TransactionID > @LastTxID)
ORDER  BY TransactionDate, TransactionID;
-- Cost: Index Seek O(log n) + 25 reads — constant regardless of depth.
```

**Trade-offs**

| Feature | OFFSET/FETCH | Keyset |
|---------|-------------|--------|
| Random page jump | ✅ | ❌ |
| Deep-page performance | Degrades linearly | Constant O(log n) |
| Bidirectional navigation | ✅ | ✅ (reverse inequality + sort) |
| Total row count | Requires COUNT(*) scan | Approximate from catalog |

**Key takeaway:** Switch from `OFFSET/FETCH` to keyset pagination for any
paginated API where users can scroll beyond the first ~10 pages. Always use a
unique composite sort key to guarantee stable page boundaries.

---

### 06 – Index Fragmentation

**Files:**
- `scenarios/06_index_fragmentation/before.sql`
- `scenarios/06_index_fragmentation/after.sql`
- `scenarios/06_index_fragmentation/optimization.sql`

**Problem:** Random inserts cause B-tree page splits, and random deletes leave
sparse pages. High fragmentation means sequential reads become random I/Os —
the primary cause of elevated physical reads and long elapsed times on
storage-bound workloads.

**Fragmentation induced in the test**

A 500 000-row `FragDemo` table is populated with random `AccountID` ordering
(worst case for a sorted index) with `FILLFACTOR = 100`, then 30% of rows are
deleted to create holes.

**Before / after maintenance**

| Metric | Fragmented | After REORGANIZE | After REBUILD |
|--------|-----------|------------------|---------------|
| NCI fragmentation | **73.42%** | 1.82% | 0.12% |
| CI fragmentation | **21.07%** | 0.54% | 0.09% |
| Scan logical reads | 3 521 | 3 521 | **2 201 (−37%)** |
| Scan physical reads | **482** | 8 | 3 |
| Scan elapsed time | **890 ms** | 147 ms (6×) | 102 ms (8.7×) |
| Locking | — | None (online) | Minimal (`ONLINE = ON`) |

**Maintenance decision thresholds**

```
Fragmentation  <  5% → No action
Fragmentation  5–30% → ALTER INDEX … REORGANIZE  (online, incremental)
Fragmentation > 30%  → ALTER INDEX … REBUILD     (ONLINE = ON where available)
page_count     < 100 → Skip (statistics update only)
```

**Adaptive maintenance script** (included in `scenarios/06_index_fragmentation/optimization.sql`):

```sql
SELECT
    OBJECT_NAME(i.object_id) AS TableName,
    i.name                   AS IndexName,
    ROUND(ips.avg_fragmentation_in_percent, 1) AS FragPct,
    CASE
        WHEN ips.avg_fragmentation_in_percent >= 30
          THEN 'ALTER INDEX … REBUILD WITH (FILLFACTOR = 85, ONLINE = ON)'
        WHEN ips.avg_fragmentation_in_percent >= 5
          THEN 'ALTER INDEX … REORGANIZE'
        ELSE '-- No action needed'
    END AS Action
FROM sys.dm_db_index_physical_stats(DB_ID(), NULL, NULL, NULL, 'LIMITED') ips
JOIN sys.indexes i ON i.object_id = ips.object_id AND i.index_id = ips.index_id
WHERE OBJECTPROPERTY(i.object_id, 'IsUserTable') = 1
  AND ips.page_count >= 50
ORDER BY FragPct DESC;
```

**Key takeaway:** Fragmentation hurts physical (disk) reads far more than logical
reads. `REORGANIZE` fixes page ordering online; `REBUILD` additionally reclaims
ghost records and re-applies the fill factor, reducing total page count.

---

## Benchmark Summary

All measurements on SQL Server 2022 Developer Edition, 16-core CPU, 64 GB RAM,
NVMe SSD, database in SIMPLE recovery, cold buffer pool (DBCC DROPCLEANBUFFERS
between runs).

| Scenario | Worst Case (before) | Best Case (after) | Peak Improvement |
|----------|--------------------|--------------------|-----------------|
| 01 Missing indexes — account lookup | 1 560 ms / 105 042 reads | 1 ms / 21 reads | **1 560×** |
| 01 Missing indexes — date range | 4 102 ms / 105 042 reads | 512 ms / 168 442 reads | **8×** |
| 02 Covering index — range 3 400 rows | 22 ms / 6 817 reads | 1 ms / 85 reads | **80×** reads |
| 03 SARGability — OR across columns | 4 100 ms / 105 042 reads | <1 ms / 24 reads | **>4 000×** |
| 03 SARGability — YEAR()/MONTH() wrap | 4 018 ms / 105 042 reads | 34 ms / 1 642 reads | **118×** |
| 04 Window functions — top-N per group | 8 130 ms / 210 084 reads | 1 ms / 88 reads | **>8 000×** |
| 05 Keyset pagination — deep page | 2 461 ms / 19 617 reads | <1 ms / 3 reads | **>6 500×** |
| 06 Index fragmentation — scan | 890 ms (73% fragmented) | 102 ms (rebuild) | **8.7×** |

---

## Environment

| Component | Version / Spec |
|-----------|---------------|
| SQL Server | 2022 Developer Edition (16.0.x) |
| OS | Windows Server 2022 |
| CPU | 16 logical cores |
| RAM | 64 GB (max server memory 56 GB) |
| Storage | NVMe SSD (sequential read ~3 GB/s) |
| Database | SIMPLE recovery, 4 GB initial size |
| Collation | SQL_Latin1_General_CP1_CI_AS |

---

## Repository Layout

```
sql-performance-lab1/
├── README.md                         ← this file
├── setup/
│   ├── 01_schema.sql                 ← database + table DDL
│   └── 02_data_generation.sql        ← 10 M-row data population
└── scenarios/
    ├── 01_missing_indexes/
    │   ├── before.sql
    │   ├── after.sql
    │   ├── optimization.sql
    │   └── README.md
    ├── 02_covering_indexes/
    │   ├── before.sql
    │   ├── after.sql
    │   ├── optimization.sql
    │   └── README.md
    ├── 03_sargability/
    │   ├── before.sql
    │   ├── after.sql
    │   ├── optimization.sql
    │   └── README.md
    ├── 04_window_functions/
    │   ├── before.sql
    │   ├── after.sql
    │   ├── optimization.sql
    │   └── README.md
    ├── 05_keyset_pagination/
    │   ├── before.sql
    │   ├── after.sql
    │   ├── optimization.sql
    │   └── README.md
    └── 06_index_fragmentation/
        ├── before.sql
        ├── after.sql
        ├── optimization.sql
        └── README.md
```

Each scenario folder now includes:
- A `before.sql` baseline script
- An `after.sql` optimized script
- An `optimization.sql` full deep-dive script
- A scenario `README.md` with placeholders for plan analysis and results

Each SQL script is annotated with:
- The **problem** it demonstrates
- **Baseline** queries with non-SARGable / unoptimised forms
- **Commented-out execution plan** ASCII art showing operator choices
- `SET STATISTICS IO ON` / `SET STATISTICS TIME ON` output blocks
- **Post-fix** queries with the optimised form
- A **benchmark summary table** at the end of the file