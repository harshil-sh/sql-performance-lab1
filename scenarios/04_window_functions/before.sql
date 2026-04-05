-- =============================================================================
-- SQL Server Performance Lab
-- File: scenarios/04_window_functions/before.sql
-- Scenario: Window Functions — BEFORE (correlated subquery baseline)
--
-- Demonstrates the O(n²) I/O cost of a correlated subquery computing a
-- running total.  For each outer row the engine re-executes the inner
-- SELECT, issuing a separate index seek and partial scan into Transactions.
--
-- Prerequisites
--   • IX_Transactions_AccountID  (scenario 01 / after.sql)
--     Created automatically in the SETUP block below if missing.
--
-- Run BEFORE: scenarios/04_window_functions/optimization.sql
-- =============================================================================

USE BankingLab;
GO

-- -----------------------------------------------------------------------
-- SETUP: ensure the single-column AccountID index exists (needed so the
--        correlated subquery can seek; without it every inner execution
--        does a full clustered index scan — an even worse baseline).
--        Drop the composite window-function index if left from a prior run.
-- -----------------------------------------------------------------------
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_Transactions_AccountID')
    CREATE NONCLUSTERED INDEX IX_Transactions_AccountID
        ON dbo.Transactions (AccountID)
        WITH (FILLFACTOR = 90, SORT_IN_TEMPDB = ON, ONLINE = ON);

IF EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_Transactions_AccountID_Date')
    DROP INDEX IX_Transactions_AccountID_Date ON dbo.Transactions;
GO

-- -----------------------------------------------------------------------
-- Enable I/O and time statistics.
-- Enable actual execution plan (Ctrl+M in SSMS) before running.
-- -----------------------------------------------------------------------

-- ═══════════════════════════════════════════════════════════════════════
-- Query 1: Running total for a single account (~17 rows)
--
-- For each of the 17 outer rows, the correlated subquery re-seeks the
-- AccountID index and scans from the first transaction up to the current
-- row — O(n²) work for n rows.
--
-- Expected plan : Clustered Index Scan or Index Seek + Nested Loops
--                 with one inner Index Seek + partial scan per outer row
-- Expected I/O  : ~85 logical reads  (17 inner seeks × ~5 reads each)
-- Expected time : ~8 ms
-- ═══════════════════════════════════════════════════════════════════════
SET STATISTICS IO ON;
SET STATISTICS TIME ON;

SELECT
    t1.TransactionID,
    t1.AccountID,
    t1.TransactionDate,
    t1.Amount,
    (
        SELECT SUM(t2.Amount)
        FROM   dbo.Transactions t2
        WHERE  t2.AccountID = t1.AccountID
          AND (
                   t2.TransactionDate < t1.TransactionDate
               OR (t2.TransactionDate = t1.TransactionDate
                   AND t2.TransactionID <= t1.TransactionID)
              )
    ) AS RunningTotal
FROM   dbo.Transactions t1
WHERE  t1.AccountID = 42000
ORDER  BY t1.TransactionDate, t1.TransactionID;

SET STATISTICS IO OFF;
SET STATISTICS TIME OFF;

/*
EXECUTION PLAN
──────────────────────────────────────────────────────────────
  SELECT
    └─ Nested Loops (Inner Join)                        Cost: ~95%
         ├─ Index Seek  (IX_Transactions_AccountID)     ← outer
         │    Actual rows : 17      Logical reads : 3
         └─ [Correlated inner per outer row]
              Stream Aggregate  (SUM)
                └─ Index Seek  (IX_Transactions_AccountID)
                     Actual executions : 17
                     Total logical reads: ~82  (partial scan per row)

STATISTICS IO:
  Table 'Transactions'. Scan count 18, logical reads 85

STATISTICS TIME:
  CPU time = 6 ms,  elapsed time = 8 ms

WHY: The inner SELECT re-executes once per outer row.  For row k it must
read all k preceding rows for the same AccountID — total work is
n*(n+1)/2 row reads, which grows quadratically with the number of rows.
*/

-- ═══════════════════════════════════════════════════════════════════════
-- Query 2: Running total across 200 accounts (~3 400 rows)
--
-- At scale the O(n²) cost becomes clearly visible.  Each of the 3 400
-- outer rows triggers an inner seek + partial scan.  The average scan
-- reads roughly half the rows for that account, so the inner work alone
-- dwarfs the outer index seek.
--
-- Expected plan : Index Seek (outer) + Nested Loops + inner Index Seeks
-- Expected I/O  : ~23 800 logical reads
-- Expected time : ~800 ms
-- ═══════════════════════════════════════════════════════════════════════
SET STATISTICS IO ON;
SET STATISTICS TIME ON;

SELECT
    t1.TransactionID,
    t1.AccountID,
    t1.TransactionDate,
    t1.Amount,
    (
        SELECT SUM(t2.Amount)
        FROM   dbo.Transactions t2
        WHERE  t2.AccountID = t1.AccountID
          AND (
                   t2.TransactionDate < t1.TransactionDate
               OR (t2.TransactionDate = t1.TransactionDate
                   AND t2.TransactionID <= t1.TransactionID)
              )
    ) AS RunningTotal
FROM   dbo.Transactions t1
WHERE  t1.AccountID BETWEEN 1 AND 200
ORDER  BY t1.AccountID, t1.TransactionDate, t1.TransactionID;

SET STATISTICS IO OFF;
SET STATISTICS TIME OFF;

/*
EXECUTION PLAN
──────────────────────────────────────────────────────────────
  SELECT
    └─ Nested Loops (Inner Join)
         ├─ Index Seek  (IX_Transactions_AccountID)     ← outer
         │    Actual rows : 3 412     Logical reads : 14
         └─ [Correlated inner — executes 3 412 times]
              Stream Aggregate  (SUM)
                └─ Index Seek  (IX_Transactions_AccountID)
                     Actual executions : 3 412
                     Total logical reads: ~23 786

STATISTICS IO:
  Table 'Transactions'. Scan count 3 413, logical reads 23 800

STATISTICS TIME:
  CPU time = 734 ms,  elapsed time = 800 ms

WHY: 3 412 inner executions, each seeking AccountID and scanning backward
to row 1 for that account.  The n*(n+1)/2 relationship means doubling
the row count quadruples the I/O — a fundamental scalability problem.
*/

-- -----------------------------------------------------------------------
-- SUMMARY
-- ┌───────────────────────────────────────────┬───────────────────────────┐
-- │ Query                                     │ Logical Reads / Elapsed   │
-- ├───────────────────────────────────────────┼───────────────────────────┤
-- │ Q1  Running total, 1 account  (~17 rows)  │   85 reads  /    8 ms     │
-- │ Q2  Running total, 200 accts (~3 400 rows)│ 23 800 reads / 800 ms     │
-- └───────────────────────────────────────────┴───────────────────────────┘
--
-- Next step: run scenarios/04_window_functions/optimization.sql
-- -----------------------------------------------------------------------
