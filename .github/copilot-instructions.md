# GitHub Copilot Instructions

## Project Overview

SQL Server Performance Lab — a hands-on reference guide demonstrating six T-SQL performance optimization scenarios against a **10-million-row banking dataset** (`BankingLab` database). Each scenario measures logical reads and elapsed time before and after optimization.

## Setup

```sql
-- Run in sqlcmd or SSMS using :r (in order)
:r setup/01_schema.sql          -- Creates BankingLab database + all tables
:r setup/02_data_generation.sql -- Populates ~10 M rows (~8–15 min on laptop hardware)
```

**Requirements:** SQL Server 2019 or 2022 (Developer/Enterprise), ≥32 GB RAM, ~3 GB free disk.  
**Default data path:** `C:\SQLData\` — edit the `FILENAME` parameters in `01_schema.sql` if your instance uses a different path. Find the instance default with:
```sql
SELECT physical_name FROM sys.master_files WHERE database_id = 1;
```

## Schema

All objects live in the `BankingLab` database under the `dbo` schema:

| Table | Rows | Notes |
|---|---|---|
| `dbo.Transactions` | 10 000 000 | Primary performance target — **no non-clustered indexes at baseline** |
| `dbo.Accounts` | ~600 000 | 3 accounts per customer |
| `dbo.Customers` | 200 000 | |
| `dbo.Loans` | 300 000 | |
| `dbo.TransactionAlerts` | 50 000 | Used for fragmentation scenario |

`Transactions.TransactionID` is the clustered PK (BIGINT IDENTITY). The table intentionally starts with zero non-clustered indexes so each scenario establishes a clean full-scan baseline.

## Scenario Structure

Each scenario under `scenarios/` follows this pattern:

```
scenarios/<NN>_<name>/
  before.sql        -- Drops relevant indexes, runs baseline query with expected scan plan
  optimization.sql  -- Creates recommended indexes / rewrites
  after.sql         -- Re-runs same queries to show improved execution plans
  README.md         -- Problem description + benchmark result table (fill in after running)
```

**Run order within a scenario:** `before.sql` → `optimization.sql` → `after.sql`

Some scenarios also have a flat `scenarios/<NN>_<name>.sql` — earlier single-file versions of the same content.

## Key Conventions

### Benchmarking boilerplate
Every `before.sql` and `after.sql` wraps queries with:
```sql
SET STATISTICS IO ON;
SET STATISTICS TIME ON;
-- ... query ...
SET STATISTICS IO OFF;
SET STATISTICS TIME OFF;
```
Enable actual execution plans with **Ctrl+M** in SSMS before running. Flush the buffer pool between runs:
```sql
DBCC DROPCLEANBUFFERS;  -- requires sysadmin
```

### Index creation standard
All non-clustered indexes in this lab use:
```sql
WITH (FILLFACTOR = 90, SORT_IN_TEMPDB = ON, ONLINE = ON)
```

### Execution plan comments
Each SQL file includes ASCII-art execution plan snapshots inside block comments (`/* ... */`) immediately after the query they describe, showing operator type, estimated vs. actual rows, and logical reads.

### Randomness in data generation
`ABS(CHECKSUM(NEWID()))` is the standard pattern for pseudo-random integers throughout `02_data_generation.sql`.

## Scenarios at a Glance

| # | Scenario | Key technique |
|---|---|---|
| 01 | Missing Indexes | `CREATE NONCLUSTERED INDEX` on `AccountID`, `TransactionDate` |
| 02 | Covering Indexes | `INCLUDE` clause to eliminate Key Lookups |
| 03 | SARGability | Avoid functions on indexed columns; typed literals; `UNION ALL` over `OR` |
| 04 | Window Functions | `ROW_NUMBER()`, `LAG`/`LEAD`, `NTILE`, rolling aggregates — O(n) vs O(n²) |
| 05 | Keyset Pagination | `WHERE (date > @last) OR (date = @last AND id > @lastId)` instead of `OFFSET/FETCH` |
| 06 | Index Fragmentation | `REORGANIZE` (5–30%) vs `REBUILD` (>30%) using `sys.dm_db_index_physical_stats` |

## Useful DMV Queries

```sql
-- Surface missing index recommendations after running baseline queries
SELECT * FROM sys.dm_db_missing_index_details;

-- Check index fragmentation with maintenance action recommendation
SELECT
    OBJECT_NAME(i.object_id) AS TableName,
    i.name AS IndexName,
    ROUND(ips.avg_fragmentation_in_percent, 1) AS FragPct,
    CASE
        WHEN ips.avg_fragmentation_in_percent >= 30 THEN 'ALTER INDEX … REBUILD WITH (FILLFACTOR = 85, ONLINE = ON)'
        WHEN ips.avg_fragmentation_in_percent >=  5 THEN 'ALTER INDEX … REORGANIZE'
        ELSE '-- No action needed'
    END AS Action
FROM sys.dm_db_index_physical_stats(DB_ID(), NULL, NULL, NULL, 'LIMITED') ips
JOIN sys.indexes i ON i.object_id = ips.object_id AND i.index_id = ips.index_id
WHERE OBJECTPROPERTY(i.object_id, 'IsUserTable') = 1
  AND ips.page_count >= 50
ORDER BY FragPct DESC;
```
