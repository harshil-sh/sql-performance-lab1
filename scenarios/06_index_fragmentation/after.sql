-- =============================================================================
-- SQL Server Performance Lab
-- File: scenarios/06_index_fragmentation/after.sql
-- Scenario: Index Fragmentation — AFTER (REBUILD with FILLFACTOR=85)
--
-- Applies ALTER INDEX … REBUILD WITH (FILLFACTOR=85, ONLINE=ON) to both
-- indexes.  REBUILD is a full reconstruction of the B-tree:
--   • Drops the old index structure and builds a new one from scratch
--   • Re-applies FILLFACTOR (85% here): reserves 15% free space on each
--     leaf page so future inserts have room without splitting
--   • Removes all ghost records (reclaims space from deleted rows)
--   • Rebuilds ALL B-tree levels (leaf + internal nodes)
--   • Updates statistics as a side-effect
--
-- Because page count drops (ghost records removed, fill factor applied),
-- LOGICAL reads also decrease — unlike REORGANIZE which only fixes order.
--
-- Run AFTER: scenarios/06_index_fragmentation/before.sql
--            + scenarios/06_index_fragmentation/optimization.sql
-- =============================================================================

USE BankingLab;
GO

-- -----------------------------------------------------------------------
-- SETUP: if running standalone (skipping optimization.sql), ensure the
--        fragmented table exists first (re-run before.sql).
-- -----------------------------------------------------------------------
IF OBJECT_ID('dbo.FragDemo', 'U') IS NULL
BEGIN
    RAISERROR('FragDemo does not exist. Run before.sql first to create the fragmented table.', 16, 1);
    RETURN;
END
GO

-- -----------------------------------------------------------------------
-- Step 1: Check fragmentation before REBUILD
--         (captures state after REORGANIZE was applied in optimization.sql)
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

-- -----------------------------------------------------------------------
-- Step 2: REBUILD both indexes with FILLFACTOR=85
--
--   FILLFACTOR=85: each leaf page is filled to 85% on rebuild,
--   leaving 15% free for future inserts without triggering a split.
--   Trade-off: slightly more pages → slightly more reads, but far fewer
--   splits over time → index stays healthy longer between maintenance runs.
--
--   ONLINE=ON: other queries can read/write the table during the rebuild.
--              Requires Enterprise Edition (or Developer Edition).
--              On Standard Edition omit ONLINE=ON; a schema-mod lock is
--              taken for the duration of the rebuild.
-- -----------------------------------------------------------------------
PRINT 'Rebuilding IX_FragDemo_AccountID with FILLFACTOR=85...';

ALTER INDEX IX_FragDemo_AccountID ON dbo.FragDemo
    REBUILD WITH (FILLFACTOR = 85, SORT_IN_TEMPDB = ON, ONLINE = ON);

PRINT 'Rebuilding PK_FragDemo (clustered) with FILLFACTOR=85...';

ALTER INDEX PK_FragDemo ON dbo.FragDemo
    REBUILD WITH (FILLFACTOR = 85, SORT_IN_TEMPDB = ON, ONLINE = ON);

PRINT 'REBUILD complete.';
GO

-- -----------------------------------------------------------------------
-- Step 3: Measure fragmentation after REBUILD
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
Expected results after REBUILD:
──────────────────────────────────────────────────────────────
  IndexName                  Type          Pages  FragPct  FillPct
  PK_FragDemo                CLUSTERED     2 201    0.09    85.0   ← page count -37%!
  IX_FragDemo_AccountID      NONCLUSTERED  2 860    0.12    85.0   ← fill factor applied

KEY OBSERVATIONS:
  • FragPct near zero: B-tree rebuilt from scratch in perfect order.
  • PageFillPct = 85.0: FILLFACTOR=85 applied — 15% headroom for future inserts.
  • page_count dropped from 3 521 → 2 201 on CI (-37%):
      Ghost records removed (350 K live rows now packed at 85% fill
      instead of 500 K live+ghost rows spread across fragmented pages).
  • ghost_record_count = 0: all deleted-row tombstones removed.
*/

-- -----------------------------------------------------------------------
-- Step 4: Benchmark scan after REBUILD
--         Both logical AND physical reads improve this time.
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
STATISTICS IO : Table 'FragDemo'. Scan count 1, logical reads  2 201   ← from 3 521!
                                             physical reads     3       ← from 482!

STATISTICS TIME: CPU 61 ms,  elapsed 102 ms   ← from 890 ms

WHAT IMPROVED vs. fragmented baseline:
  Logical reads : 3 521 → 2 201 (-37%)   ← ghost records removed + fill factor
  Physical reads:   482 →     3 (-99%)   ← pages are now physically sequential
  Elapsed time  :   890 → 102 ms (8.7×)

WHAT IMPROVED vs. REORGANIZE only (after optimization.sql):
  Logical reads : 3 521 → 2 201 (-37%)   ← REORGANIZE left these unchanged
  Physical reads:     8 →     3           ← already low after REORGANIZE
  Elapsed time  :   147 →  102 ms         ← further improvement

REBUILD vs. REORGANIZE comparison:
  REORGANIZE: fixes page ORDER  → physical reads recover  (482 → 8)
  REBUILD   : fixes page ORDER  → physical reads recover  (482 → 3)
            + fixes page DENSITY → logical reads recover  (3521 → 2201)
            + re-applies FILLFACTOR → future split resistance restored
            + removes ghost records → storage reclaimed
*/

-- -----------------------------------------------------------------------
-- Step 5: Full before / after benchmark summary
-- -----------------------------------------------------------------------

-- ┌──────────────────────────────────┬───────────────┬──────────────────┬───────────────┐
-- │ Metric                           │ Fragmented    │ After REORGANIZE │ After REBUILD │
-- ├──────────────────────────────────┼───────────────┼──────────────────┼───────────────┤
-- │ NCI avg_fragmentation_in_percent │ 73.42%        │ 1.82%            │ 0.12%         │
-- │ CI  avg_fragmentation_in_percent │ 21.07%        │ 0.54%            │ 0.09%         │
-- │ CI  page_count                   │ 3 521         │ 3 521 (same)     │ 2 201 (-37%)  │
-- │ Scan logical reads               │ 3 521         │ 3 521 (same)     │ 2 201 (-37%)  │
-- │ Scan physical reads (cold cache) │ 482           │ 8    (60×)       │ 3    (161×)   │
-- │ Scan elapsed time   (cold cache) │ 890 ms        │ 147 ms (6×)      │ 102 ms (8.7×) │
-- └──────────────────────────────────┴───────────────┴──────────────────┴───────────────┘

-- -----------------------------------------------------------------------
-- Step 6: Adaptive maintenance script — applies to ALL user tables
--         Run this periodically (e.g. nightly maintenance window) to
--         identify and fix fragmented indexes across the entire database.
-- -----------------------------------------------------------------------
SELECT
    OBJECT_NAME(i.object_id)                        AS TableName,
    i.name                                           AS IndexName,
    ips.page_count,
    ROUND(ips.avg_fragmentation_in_percent, 1)       AS FragPct,
    CASE
        WHEN ips.page_count < 100
          THEN 'UPDATE STATISTICS ' + OBJECT_NAME(i.object_id)
               + ' — page count too low for index maintenance'
        WHEN ips.avg_fragmentation_in_percent >= 30
          THEN 'ALTER INDEX [' + i.name + '] ON ['
               + OBJECT_NAME(i.object_id)
               + '] REBUILD WITH (FILLFACTOR = 85, ONLINE = ON)'
        WHEN ips.avg_fragmentation_in_percent >= 5
          THEN 'ALTER INDEX [' + i.name + '] ON ['
               + OBJECT_NAME(i.object_id) + '] REORGANIZE'
        ELSE  '-- No action needed'
    END AS MaintenanceAction
FROM   sys.dm_db_index_physical_stats(
           DB_ID(), NULL, NULL, NULL, 'LIMITED') ips
JOIN   sys.indexes i
       ON  i.object_id = ips.object_id
       AND i.index_id  = ips.index_id
WHERE  OBJECTPROPERTY(i.object_id, 'IsUserTable') = 1
  AND  ips.index_level = 0
ORDER  BY FragPct DESC;
GO

/*
Run this query after any bulk INSERT/DELETE/UPDATE workload to assess
maintenance needs.  Copy the MaintenanceAction column output and execute
the statements in order of descending FragPct.

DECISION THRESHOLDS:
  page_count  < 100  → statistics update only (index too small to matter)
  FragPct  <  5%     → no action (overhead of maintenance exceeds benefit)
  FragPct  5–30%     → REORGANIZE (online, low locking, incremental)
  FragPct  > 30%     → REBUILD    (ONLINE=ON on Enterprise; schema lock on Standard)
*/

-- -----------------------------------------------------------------------
-- Key takeaways
--   • FILLFACTOR=100 (no free space) maximises space efficiency at build
--     time but guarantees splits on the first out-of-order insert.
--     For write-heavy tables, FILLFACTOR 80–90 is a common starting point.
--   • REORGANIZE is safe on 24×7 systems — fully online, can be interrupted.
--     It fixes page ORDER but not page DENSITY.
--   • REBUILD delivers the complete fix: order, density, fill factor, ghost
--     records, and statistics.  Use ONLINE=ON to minimise locking impact
--     (Enterprise / Developer Edition required).
--   • Fragmentation hurts physical (disk) I/O far more than logical I/O —
--     the most visible effect is on storage-bound workloads and cold-cache
--     scenarios (e.g. morning after a nightly batch).
-- -----------------------------------------------------------------------
