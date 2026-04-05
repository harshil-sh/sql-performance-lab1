# Scenario 04: Window Functions — SUM OVER vs Correlated Subquery

## Description

Demonstrates the O(n²) I/O cost of a correlated subquery computing a running total and shows how `SUM() OVER (PARTITION BY … ORDER BY … ROWS UNBOUNDED PRECEDING)` replaces it with a single O(n) streaming pass. A composite non-clustered index eliminates the Sort operator from the window function plan, making the after-state both read- and CPU-efficient.

## How to Run

1. Run `before.sql` — ensures the bare `IX_Transactions_AccountID` index exists, drops the composite window index, and executes both baseline queries using correlated subqueries.
2. Run `optimization.sql` — creates `IX_Transactions_AccountID_Date` on `(AccountID, TransactionDate, TransactionID) INCLUDE (Amount)`.
3. Run `after.sql` — re-runs the same queries rewritten with `SUM() OVER` to show the improved execution plans.

## Environment

| Setting | Value |
|---------|-------|
| SQL Server version | <!-- e.g. SQL Server 2022 Developer Edition --> |
| Hardware | <!-- e.g. 16-core / 64 GB RAM, NVMe SSD --> |
| Table row count | <!-- e.g. 10,000,000 --> |

## Performance Results

### Before (correlated subquery)

| Query | Execution Plan | Logical Reads | Elapsed Time |
|-------|---------------|---------------|--------------|
| Q1 — running total, `AccountID = 42000` (~17 rows) | <!-- e.g. Index Seek + Nested Loops × 17 inner seeks --> | <!-- e.g. 85 --> | <!-- e.g. 8 ms --> |
| Q2 — running total, `AccountID BETWEEN 1 AND 200` (~3,400 rows) | <!-- e.g. Index Seek + 3,412 correlated inner seeks --> | <!-- e.g. 23,800 --> | <!-- e.g. 800 ms --> |

### After (`SUM() OVER` + `IX_Transactions_AccountID_Date`)

| Query | Execution Plan | Logical Reads | Elapsed Time |
|-------|---------------|---------------|--------------|
| Q1 — running total, `AccountID = 42000` (~17 rows) | <!-- e.g. Index Seek → Window Spool (no Sort) --> | <!-- e.g. 3 --> | <!-- e.g. 0 ms --> |
| Q2 — running total, `AccountID BETWEEN 1 AND 200` (~3,400 rows) | <!-- e.g. Index Seek range → Window Spool (no Sort) --> | <!-- e.g. 85 --> | <!-- e.g. 2 ms --> |

### Summary

| Query | Before reads | After reads | Improvement |
|-------|-------------|------------|-------------|
| Q1 (~17 rows) | <!-- TODO --> | <!-- TODO --> | <!-- e.g. ~28× --> |
| Q2 (~3,400 rows) | <!-- TODO --> | <!-- TODO --> | <!-- e.g. ~280× --> |

### Index Storage Trade-off

| Index | Role | Estimated Size |
|-------|------|---------------|
| `IX_Transactions_AccountID` (key only) | Subquery inner seeks | <!-- e.g. ~80 MB --> |
| `IX_Transactions_AccountID_Date` (3-col key + Amount INCLUDE) | Window function sort elimination + covering | <!-- e.g. ~320 MB --> |

<!-- Key observations:
  - Correlated subquery: for n rows the inner SELECT re-executes n times, each reading 1…n rows → total I/O grows as n*(n+1)/2.
  - SUM() OVER streams forward once through an ordered index; the accumulator is updated in memory per row — O(n) total.
  - Without the composite index the window function still works but requires a blocking Sort operator (~30% of plan cost).
  - Match the index key columns exactly to (PARTITION BY, ORDER BY) to eliminate Sort from every window query on this partition shape.
-->

## Next Step

See [scenarios/05_keyset_pagination/](../05_keyset_pagination/) to learn how to replace `OFFSET/FETCH` with keyset pagination for deep-page performance.
