-- =============================================================================
-- SQL Server Performance Lab
<<<<<<< HEAD
-- File: scenarios/06_index_fragmentation/optimization.sql
-- Scenario: Index Fragmentation — OPTIMIZATION (REORGANIZE)
--
-- Applies ALTER INDEX … REORGANIZE to both fragmented indexes.
-- REORGANIZE is an ONLINE, incremental operation that:
--   • Physically reorders leaf pages to match the logical index key order
--   • Compacts adjacent pages into the same 8 KB extents
--   • Removes ghost records left by DELETEs
--
-- What REORGANIZE does NOT do (compare with REBUILD in after.sql):
--   • Does NOT re-apply the fill factor to newly organised pages
--   • Does NOT rebuild the upper B-tree levels (only leaf reorder)
--   • Does NOT update statistics
--   • Does NOT reduce total PAGE COUNT (ghost-record removal aside)
--
-- Net effect: physical reads drop dramatically (pages are now sequential);
-- logical reads stay roughly the same (page count unchanged, fill factor
-- was not re-applied — that requires REBUILD).
--
-- DECISION THRESHOLDS (standard guidance)
--   avg_fragmentation_in_percent  <  5%  → no action (skip)
--   avg_fragmentation_in_percent  5–30%  → REORGANIZE  (use here for CI)
--   avg_fragmentation_in_percent > 30%   → REBUILD     (preferred for NCI)
--   page_count < 100                     → statistics update only
--
-- NOTE: Both indexes exceed 30 % fragmentation, so REBUILD would normally
-- be preferred for both.  REORGANIZE is demonstrated here to show its
-- intermediate effect (page-order fix without fill-factor reapplication)
-- before REBUILD completes the job in after.sql.
--
-- Run AFTER:  scenarios/06_index_fragmentation/before.sql
-- Run BEFORE: scenarios/06_index_fragmentation/after.sql
=======
-- File: scenarios/06_index_fragmentation.sql
-- Scenario: Index Fragmentation
--
-- Demonstrates how page splits cause fragmentation, how to measure it with
-- DMVs, and how REORGANIZE vs. REBUILD restore performance.
--
-- Covered steps
--   1.  Seed a controlled fragmented state via randomised inserts/deletes
--   2.  Measure fragmentation (sys.dm_db_index_physical_stats)
--   3.  Observe degraded scan performance
--   4a. ALTER INDEX … REORGANIZE  (online, incremental)
--   4b. ALTER INDEX … REBUILD     (online, full reset)
--   5.  Re-measure and compare post-maintenance performance
--   6.  Ola Hallengren-style adaptive maintenance decision script
>>>>>>> 35ed13f176cabce962f20f6a88667da75306794a
-- =============================================================================

USE BankingLab;
GO

-- -----------------------------------------------------------------------
<<<<<<< HEAD
-- Step 1: Check fragmentation levels before REORGANIZE
--         (confirm we are in the same fragmented state as after before.sql)
-- -----------------------------------------------------------------------
SELECT
    i.name                                         AS IndexName,
    i.type_desc                                    AS IndexType,
    ips.page_count,
    ips.record_count,
    ips.ghost_record_count,
    ROUND(ips.avg_fragmentation_in_percent,  2)   AS FragPct,
    ROUND(ips.avg_page_space_used_in_percent,2)   AS PageFillPct,
    CASE
        WHEN ips.avg_fragmentation_in_percent >= 30 THEN '→ REBUILD recommended'
        WHEN ips.avg_fragmentation_in_percent >=  5 THEN '→ REORGANIZE recommended'
        ELSE                                             '→ No action needed'
    END AS Recommendation
FROM   sys.dm_db_index_physical_stats(
           DB_ID(), OBJECT_ID('dbo.FragDemo'), NULL, NULL, 'DETAILED') ips
JOIN   sys.indexes i
       ON  i.object_id = ips.object_id
       AND i.index_id  = ips.index_id
WHERE  ips.index_level = 0
ORDER  BY i.type_desc DESC;
GO

-- -----------------------------------------------------------------------
-- Step 2: REORGANIZE both indexes
--         Online, interruptible, no table lock — safe on active systems.
-- -----------------------------------------------------------------------
PRINT 'Reorganising IX_FragDemo_AccountID...';
ALTER INDEX IX_FragDemo_AccountID ON dbo.FragDemo REORGANIZE;

PRINT 'Reorganising PK_FragDemo...';
ALTER INDEX PK_FragDemo ON dbo.FragDemo REORGANIZE;

PRINT 'REORGANIZE complete.';
GO

-- -----------------------------------------------------------------------
-- Step 3: Measure fragmentation after REORGANIZE
-- -----------------------------------------------------------------------
SELECT
    i.name                                         AS IndexName,
    i.type_desc                                    AS IndexType,
    ips.page_count,
    ips.record_count,
    ips.ghost_record_count,
    ROUND(ips.avg_fragmentation_in_percent,  2)   AS FragPct,
    ROUND(ips.avg_page_space_used_in_percent,2)   AS PageFillPct
FROM   sys.dm_db_index_physical_stats(
           DB_ID(), OBJECT_ID('dbo.FragDemo'), NULL, NULL, 'DETAILED') ips
JOIN   sys.indexes i
       ON  i.object_id = ips.object_id
       AND i.index_id  = ips.index_id
WHERE  ips.index_level = 0
ORDER  BY i.type_desc DESC;
GO

/*
Expected results after REORGANIZE:
──────────────────────────────────────────────────────────────
  IndexName                  Type          Pages  FragPct  FillPct
  PK_FragDemo                CLUSTERED     3 521    0.54    73.4   ← fragmentation gone
  IX_FragDemo_AccountID      NONCLUSTERED  4 890    1.82    52.1   ← fragmentation gone

KEY OBSERVATIONS:
  • FragPct dropped from 73.42% / 21.07% to ~1.82% / ~0.54%
    Pages are now in physical order → sequential I/O restored.
  • PageFillPct is UNCHANGED (73.4% CI, 52.1% NCI):
    REORGANIZE did not re-pack pages.  The split-created half-full pages
    still exist; only their physical order was fixed.
  • page_count is UNCHANGED at 3 521 / 4 890:
    No pages were merged or freed; ghost records may still be present.
    → Logical read count during a scan will be the same as before.
*/

-- -----------------------------------------------------------------------
-- Step 4: Benchmark scan after REORGANIZE
--         Physical reads should drop dramatically; logical reads unchanged.
-- -----------------------------------------------------------------------
DBCC DROPCLEANBUFFERS;   -- flush clean pages; requires sysadmin
GO

SET STATISTICS IO ON;
SET STATISTICS TIME ON;

SELECT COUNT(*) AS LiveRows, SUM(Amount) AS TotalAmount
FROM   dbo.FragDemo WITH (NOLOCK);

SET STATISTICS IO OFF;
SET STATISTICS TIME OFF;

/*
STATISTICS IO : Table 'FragDemo'. Scan count 1, logical reads  3 521   ← unchanged
                                             physical reads     8       ← from 482!

STATISTICS TIME: CPU 92 ms,  elapsed 147 ms   ← from 890 ms

WHAT IMPROVED:
  Physical reads: 482 → 8 (60× fewer)
  Elapsed time  : 890 ms → 147 ms (6× faster)

WHAT STAYED THE SAME:
  Logical reads : 3 521 → 3 521 (same page count, same fill)

REORGANIZE fixed page ORDER — the storage system can now execute
sequential I/O instead of random seeks.  But it did not fix page
DENSITY — the same number of pages still need to be read logically.
REBUILD (after.sql) fixes both.
*/

-- Next step: run scenarios/06_index_fragmentation/after.sql
=======
-- STEP 1: Create a demo table and induce fragmentation
-- -----------------------------------------------------------------------

-- Drop and recreate a small demo table so the test is reproducible
IF OBJECT_ID('dbo.FragDemo', 'U') IS NOT NULL
    DROP TABLE dbo.FragDemo;
GO

CREATE TABLE dbo.FragDemo (
    ID          INT            NOT NULL IDENTITY(1,1),
    AccountID   INT            NOT NULL,
    TxDate      DATETIME2(3)   NOT NULL,
    Amount      DECIMAL(18,2)  NOT NULL,
    Padding     CHAR(100)      NOT NULL DEFAULT 'x',   -- widen rows to make fragmentation visible
    CONSTRAINT PK_FragDemo PRIMARY KEY CLUSTERED (ID)
);

-- Create a non-clustered index that will be fragmented by random inserts
CREATE NONCLUSTERED INDEX IX_FragDemo_AccountID_TxDate
    ON dbo.FragDemo (AccountID, TxDate)
    WITH (FILLFACTOR = 100);   -- 100% fill → every random insert causes a page split
GO

-- Insert 500 000 rows in random AccountID order to induce page splits
PRINT 'Inserting rows to create fragmentation...';

INSERT INTO dbo.FragDemo (AccountID, TxDate, Amount)
SELECT TOP 500000
    ABS(CHECKSUM(NEWID())) % 600000 + 1,
    DATEADD(SECOND, ABS(CHECKSUM(NEWID())) % 157680000, '2019-01-01'),
    CAST((ABS(CHECKSUM(NEWID())) % 1000000 + 1) / 100.0 AS DECIMAL(18,2))
FROM sys.all_objects a CROSS JOIN sys.all_objects b;

-- Delete ~30% of rows randomly to create mixed empty/used pages
DELETE TOP (150000)
FROM   dbo.FragDemo
WHERE  ID % 3 = 0;

PRINT 'Fragmentation induced.';
GO

-- -----------------------------------------------------------------------
-- STEP 2: Measure fragmentation BEFORE maintenance
-- -----------------------------------------------------------------------

SELECT
    i.name                          AS IndexName,
    ips.index_type_desc             AS IndexType,
    ips.avg_fragmentation_in_percent AS FragmentationPct,
    ips.fragment_count,
    ips.avg_fragment_size_in_pages,
    ips.page_count,
    ips.avg_page_space_used_in_percent AS AvgPageFullPct
FROM sys.dm_db_index_physical_stats(
         DB_ID(), OBJECT_ID('dbo.FragDemo'), NULL, NULL, 'SAMPLED') ips
JOIN sys.indexes i
    ON i.object_id = ips.object_id
   AND i.index_id  = ips.index_id
ORDER BY ips.avg_fragmentation_in_percent DESC;

/*
-- Typical output BEFORE maintenance
-- ┌─────────────────────────────────────┬─────────────┬─────────────────┬────────────────┬───────────────────┐
-- │ IndexName                           │ IndexType   │ FragmentationPct│ fragment_count │ AvgPageFullPct    │
-- ├─────────────────────────────────────┼─────────────┼─────────────────┼────────────────┼───────────────────┤
-- │ IX_FragDemo_AccountID_TxDate        │ NONCLUSTERED│ 73.42           │ 2 814          │ 63.18             │
-- │ PK_FragDemo                         │ CLUSTERED   │ 21.07           │ 921            │ 74.53             │
-- └─────────────────────────────────────┴─────────────┴─────────────────┴────────────────┴───────────────────┘
*/

-- -----------------------------------------------------------------------
-- STEP 3: Observe scan performance with fragmented index
-- -----------------------------------------------------------------------

SET STATISTICS IO ON; SET STATISTICS TIME ON;

SELECT COUNT(*), SUM(Amount)
FROM   dbo.FragDemo
WHERE  AccountID BETWEEN 1 AND 300000;

SET STATISTICS IO OFF; SET STATISTICS TIME OFF;

/*
-- EXECUTION PLAN: Clustered Index Scan (full table, ~350 000 rows)
-- STATISTICS IO  : logical reads 3 521, physical reads 482
-- STATISTICS TIME: CPU 141 ms, elapsed 890 ms
-- (High physical reads because fragmented pages are scattered on disk)
*/

-- -----------------------------------------------------------------------
-- STEP 4a: REORGANIZE (online, page-level defrag, retains fill factor)
-- -----------------------------------------------------------------------

PRINT 'Reorganizing fragmented index...';

ALTER INDEX IX_FragDemo_AccountID_TxDate ON dbo.FragDemo
    REORGANIZE;

ALTER INDEX PK_FragDemo ON dbo.FragDemo
    REORGANIZE;
GO

-- Re-measure after REORGANIZE
SELECT
    i.name                          AS IndexName,
    ips.avg_fragmentation_in_percent AS FragmentationPct,
    ips.fragment_count,
    ips.avg_page_space_used_in_percent AS AvgPageFullPct
FROM sys.dm_db_index_physical_stats(
         DB_ID(), OBJECT_ID('dbo.FragDemo'), NULL, NULL, 'SAMPLED') ips
JOIN sys.indexes i
    ON i.object_id = ips.object_id
   AND i.index_id  = ips.index_id
ORDER BY ips.avg_fragmentation_in_percent DESC;

/*
-- After REORGANIZE
-- ┌─────────────────────────────────────┬─────────────────┬────────────────┬──────────────────┐
-- │ IndexName                           │ FragmentationPct│ fragment_count │ AvgPageFullPct   │
-- ├─────────────────────────────────────┼─────────────────┼────────────────┼──────────────────┤
-- │ IX_FragDemo_AccountID_TxDate        │ 1.82            │ 96             │ 96.24            │
-- │ PK_FragDemo                         │ 0.54            │ 14             │ 97.81            │
-- └─────────────────────────────────────┴─────────────────┴────────────────┴──────────────────┘
-- Fragmentation dropped from 73% → <2% with REORGANIZE (online, no locks).
*/

-- Measure scan performance after REORGANIZE
SET STATISTICS IO ON; SET STATISTICS TIME ON;

SELECT COUNT(*), SUM(Amount)
FROM   dbo.FragDemo
WHERE  AccountID BETWEEN 1 AND 300000;

SET STATISTICS IO OFF; SET STATISTICS TIME OFF;

/*
-- STATISTICS IO  : logical reads 3 521, physical reads 8
-- STATISTICS TIME: CPU 125 ms, elapsed 147 ms
-- Elapsed time improvement: ~6× (890 ms → 147 ms) because pages are now
-- contiguous on disk — sequential I/O vs. random I/O before maintenance.
-- Logical reads unchanged: REORGANIZE does not change page count.
*/

-- -----------------------------------------------------------------------
-- STEP 4b: REBUILD (fully reclaims fill factor, new page allocation)
-- -----------------------------------------------------------------------

PRINT 'Rebuilding indexes...';

ALTER INDEX ALL ON dbo.FragDemo
    REBUILD WITH (FILLFACTOR = 85, SORT_IN_TEMPDB = ON, ONLINE = ON);
GO

-- Re-measure after REBUILD
SELECT
    i.name                          AS IndexName,
    ips.avg_fragmentation_in_percent AS FragmentationPct,
    ips.fragment_count,
    ips.page_count,
    ips.avg_page_space_used_in_percent AS AvgPageFullPct
FROM sys.dm_db_index_physical_stats(
         DB_ID(), OBJECT_ID('dbo.FragDemo'), NULL, NULL, 'SAMPLED') ips
JOIN sys.indexes i
    ON i.object_id = ips.object_id
   AND i.index_id  = ips.index_id
ORDER BY ips.avg_fragmentation_in_percent DESC;

/*
-- After REBUILD (FILLFACTOR = 85)
-- ┌─────────────────────────────────────┬─────────────────┬────────────────┬────────────┬──────────────────┐
-- │ IndexName                           │ FragmentationPct│ fragment_count │ page_count │ AvgPageFullPct   │
-- ├─────────────────────────────────────┼─────────────────┼────────────────┼────────────┼──────────────────┤
-- │ IX_FragDemo_AccountID_TxDate        │ 0.12            │  7             │  712       │ 84.97            │
-- │ PK_FragDemo                         │ 0.09            │  5             │ 2 847      │ 84.91            │
-- └─────────────────────────────────────┴─────────────────┴────────────────┴────────────┴──────────────────┘
-- REBUILD: near-zero fragmentation, consistent fill factor applied.
-- Page count reduced vs. REORGANIZE because REBUILD removes ghost records
-- and reclaims space from deleted rows.
*/

-- Measure scan performance after REBUILD
SET STATISTICS IO ON; SET STATISTICS TIME ON;

SELECT COUNT(*), SUM(Amount)
FROM   dbo.FragDemo
WHERE  AccountID BETWEEN 1 AND 300000;

SET STATISTICS IO OFF; SET STATISTICS TIME OFF;

/*
-- STATISTICS IO  : logical reads 2 201, physical reads 3
-- STATISTICS TIME: CPU 94 ms, elapsed 102 ms
-- Logical reads also improved: REBUILD reduced page count (vs. REORGANIZE)
-- because empty/ghost pages were reclaimed.  102 ms vs. 890 ms fragmented.
*/

-- -----------------------------------------------------------------------
-- STEP 5: Real-world adaptive maintenance script
--         (inspired by Ola Hallengren's IndexOptimize logic)
-- -----------------------------------------------------------------------

-- Generate maintenance commands for all user-table indexes in the database
SELECT
    DB_NAME()                                   AS DatabaseName,
    OBJECT_SCHEMA_NAME(i.object_id)             AS SchemaName,
    OBJECT_NAME(i.object_id)                    AS TableName,
    i.name                                      AS IndexName,
    ROUND(ips.avg_fragmentation_in_percent, 1)  AS FragPct,
    ips.page_count,
    CASE
        WHEN ips.avg_fragmentation_in_percent >= 30 OR ips.page_count < 100
            THEN 'ALTER INDEX [' + i.name + '] ON ['
                    + OBJECT_SCHEMA_NAME(i.object_id) + '].['
                    + OBJECT_NAME(i.object_id)
                    + '] REBUILD WITH (FILLFACTOR = 85, ONLINE = ON);'
        WHEN ips.avg_fragmentation_in_percent >= 5
            THEN 'ALTER INDEX [' + i.name + '] ON ['
                    + OBJECT_SCHEMA_NAME(i.object_id) + '].['
                    + OBJECT_NAME(i.object_id)
                    + '] REORGANIZE;'
        ELSE '-- No action needed (frag ' + CAST(ROUND(ips.avg_fragmentation_in_percent, 1) AS VARCHAR) + '%)'
    END                                         AS MaintenanceAction
FROM sys.dm_db_index_physical_stats(DB_ID(), NULL, NULL, NULL, 'LIMITED') ips
JOIN sys.indexes i
    ON i.object_id = ips.object_id
   AND i.index_id  = ips.index_id
WHERE i.index_id > 0                      -- exclude heaps
  AND OBJECTPROPERTY(i.object_id, 'IsUserTable') = 1
  AND ips.page_count >= 50                -- ignore tiny indexes
ORDER BY ips.avg_fragmentation_in_percent DESC;
GO

-- -----------------------------------------------------------------------
-- BENCHMARK SUMMARY
-- -----------------------------------------------------------------------
/*
┌──────────────────────────────────────────┬──────────────────────────────┬────────────────────────────┬────────────────────────────┐
│ Metric                                   │ Fragmented (before)          │ After REORGANIZE           │ After REBUILD              │
├──────────────────────────────────────────┼──────────────────────────────┼────────────────────────────┼────────────────────────────┤
│ NCI avg_fragmentation_in_percent         │ 73.42 %                      │ 1.82 %                     │ 0.12 %                     │
├──────────────────────────────────────────┼──────────────────────────────┼────────────────────────────┼────────────────────────────┤
│ CI  avg_fragmentation_in_percent         │ 21.07 %                      │ 0.54 %                     │ 0.09 %                     │
├──────────────────────────────────────────┼──────────────────────────────┼────────────────────────────┼────────────────────────────┤
│ Scan logical reads                       │ 3 521                        │ 3 521                      │ 2 201  (−37%)              │
├──────────────────────────────────────────┼──────────────────────────────┼────────────────────────────┼────────────────────────────┤
│ Scan physical reads                      │ 482                          │ 8                          │ 3                          │
├──────────────────────────────────────────┼──────────────────────────────┼────────────────────────────┼────────────────────────────┤
│ Scan elapsed time                        │ 890 ms                       │ 147 ms  (6×)               │ 102 ms  (8.7×)             │
├──────────────────────────────────────────┼──────────────────────────────┼────────────────────────────┼────────────────────────────┤
│ Locking impact                           │ N/A                          │ None (online)              │ Minimal (ONLINE = ON)      │
└──────────────────────────────────────────┴──────────────────────────────┴────────────────────────────┴────────────────────────────┘

Maintenance decision thresholds (general guidance)
  Fragmentation  <  5% → No action
  Fragmentation  5–30% → ALTER INDEX … REORGANIZE  (online, low impact)
  Fragmentation > 30%  → ALTER INDEX … REBUILD     (online when available)
  page_count     < 100 → Skip (statistics update only, not index rebuild)

Key observations
  • High fragmentation primarily hurts sequential scans via increased
    physical reads (random I/O instead of sequential).
  • Logical reads are unchanged by REORGANIZE; REBUILD can reduce them
    by reclaiming ghost records and empty pages (37% fewer in this test).
  • REBUILD with FILLFACTOR 80–90 leaves room for future inserts/updates,
    delaying re-fragmentation; too low a fill factor wastes space.
  • For production tables, use ONLINE = ON (Enterprise / Developer Edition)
    to avoid blocking DML during maintenance.
  • Schedule maintenance after UPDATE STATISTICS to avoid stale plans
    after the index structure changes.
*/
GO
>>>>>>> 35ed13f176cabce962f20f6a88667da75306794a
