-- =============================================================================
-- SQL Server Performance Lab
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
-- =============================================================================

USE BankingLab;
GO

-- -----------------------------------------------------------------------
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
