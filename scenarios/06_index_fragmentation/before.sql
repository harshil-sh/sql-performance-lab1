-- =============================================================================
-- SQL Server Performance Lab
-- File: scenarios/06_index_fragmentation/before.sql
-- Scenario: Index Fragmentation — BEFORE (inducing and measuring fragmentation)
--
-- Creates a dedicated FragDemo table and deliberately induces two types of
-- fragmentation:
--
--   1. LOGICAL FRAGMENTATION (page order)
--      Random AccountID values are inserted into a non-clustered index built
--      with FILLFACTOR=100 (no free space).  Every insert that would land
--      between existing entries triggers a page split, producing two half-full
--      pages in non-contiguous order → high avg_fragmentation_in_percent.
--
--   2. SPARSE PAGES (internal fragmentation)
--      30 % of rows are deleted by uniform pattern, leaving ghost records
--      behind on nearly every page.  Pages shrink in density but are not
--      freed → high avg_page_space_used_in_percent drops, page count stays up.
--
-- The benchmark scan shows how logical fragmentation turns sequential I/O into
-- random I/O — physical reads spike even when logical read count is the same.
-- Use DBCC DROPCLEANBUFFERS (requires sysadmin) to get cold-cache measurements.
--
-- Run BEFORE: scenarios/06_index_fragmentation/optimization.sql
-- =============================================================================

USE BankingLab;
GO

-- -----------------------------------------------------------------------
-- SETUP: drop and recreate FragDemo for a clean baseline
-- -----------------------------------------------------------------------
IF OBJECT_ID('dbo.FragDemo', 'U') IS NOT NULL
    DROP TABLE dbo.FragDemo;
GO

CREATE TABLE dbo.FragDemo (
    FragID      INT            NOT NULL IDENTITY(1,1),
    AccountID   INT            NOT NULL,
    Amount      DECIMAL(18,2)  NOT NULL,
    TxDate      DATETIME2(0)   NOT NULL,
    Notes       VARCHAR(50)    NOT NULL DEFAULT 'Fragmentation benchmark row',
    CONSTRAINT PK_FragDemo PRIMARY KEY CLUSTERED (FragID)
);
GO

-- -----------------------------------------------------------------------
-- Step 1: Create NCI with FILLFACTOR=100 before inserting data
--         No free space on leaf pages → every out-of-order insert splits a page
-- -----------------------------------------------------------------------
CREATE NONCLUSTERED INDEX IX_FragDemo_AccountID
    ON dbo.FragDemo (AccountID)
    WITH (FILLFACTOR = 100);
GO

-- -----------------------------------------------------------------------
-- Step 2: Insert 500 000 rows with RANDOM AccountID ordering
--         Worst case for a sorted NCI: almost every insert lands between
--         existing entries and forces a page split.
--
--         Expected insert time: 1–3 minutes (500 K rows, continuous splits)
-- -----------------------------------------------------------------------
PRINT 'Inserting 500 000 rows with random AccountID — inducing NCI page splits...';

INSERT INTO dbo.FragDemo (AccountID, Amount, TxDate)
SELECT TOP 500000
    ABS(CHECKSUM(NEWID())) % 600000 + 1,
    CAST(ABS(CHECKSUM(NEWID())) % 100000 / 100.0 AS DECIMAL(18,2)),
    DATEADD(SECOND, ABS(CHECKSUM(NEWID())) % 157766400, '2019-01-01')
FROM sys.all_objects a CROSS JOIN sys.all_objects b;

PRINT CAST(@@ROWCOUNT AS VARCHAR) + ' rows inserted.';
GO

-- -----------------------------------------------------------------------
-- Step 3: Delete 30 % of rows (every row where FragID mod 10 is 0, 1, or 2)
--         Creates ghost records throughout both the CI and NCI leaf pages.
--         Ghost records are not immediately reclaimed — they remain as
--         sparse holes, reducing page density without shrinking page count.
-- -----------------------------------------------------------------------
PRINT 'Deleting 30% of rows to create ghost records...';

DELETE FROM dbo.FragDemo
WHERE  FragID % 10 < 3;

PRINT CAST(@@ROWCOUNT AS VARCHAR) + ' rows deleted.';
GO

CHECKPOINT;
GO

-- -----------------------------------------------------------------------
-- Step 4: Measure fragmentation
--         avg_fragmentation_in_percent = logical page-order fragmentation
--         avg_page_space_used_in_percent = how full each page is (100 = full)
-- -----------------------------------------------------------------------
PRINT 'Measuring fragmentation...';

SELECT
    i.name                                          AS IndexName,
    i.type_desc                                     AS IndexType,
    ips.index_depth,
    ips.page_count,
    ROUND(ips.avg_fragmentation_in_percent,   2)   AS FragPct,
    ROUND(ips.avg_page_space_used_in_percent, 2)   AS PageFillPct
FROM   sys.dm_db_index_physical_stats(
           DB_ID(), OBJECT_ID('dbo.FragDemo'), NULL, NULL, 'DETAILED') ips
JOIN   sys.indexes i
       ON  i.object_id = ips.object_id
       AND i.index_id  = ips.index_id
WHERE  ips.index_level = 0          -- leaf level only
ORDER  BY i.type_desc DESC;
GO

/*
Expected results (leaf level):
──────────────────────────────────────────────────────────────
  IndexName                  Type          Pages  FragPct  FillPct
  PK_FragDemo                CLUSTERED     3 521   21.07    73.4
  IX_FragDemo_AccountID      NONCLUSTERED  4 890   73.42    52.1

EXPLANATION:
  • NCI FragPct 73.42%: random inserts caused massive page splits on a
    FILLFACTOR=100 index — leaf pages are badly out of physical order.
  • NCI FillPct 52.1%: every split produces two ~50%-full pages; deletions
    reduce this further.
  • CI FragPct 21.07%: IDENTITY inserts are always sequential (no splits);
    fragmentation here comes purely from the 30% deletion leaving ghost records
    scattered across pages.
*/

-- -----------------------------------------------------------------------
-- Step 5: Benchmark scan — flush buffer pool first for physical-read accuracy
--
-- IMPORTANT: Run DBCC DROPCLEANBUFFERS before this block.
--            After CHECKPOINT above, pages are clean (written to disk).
--            DROPCLEANBUFFERS evicts them so the scan reads from storage.
--            Requires sysadmin role.
-- -----------------------------------------------------------------------

DBCC DROPCLEANBUFFERS;   -- evict clean pages; comment out if insufficient privilege
GO

SET STATISTICS IO ON;
SET STATISTICS TIME ON;

-- Full CI scan: reads every page, including ghost-record pages
SELECT COUNT(*) AS LiveRows, SUM(Amount) AS TotalAmount
FROM   dbo.FragDemo WITH (NOLOCK);

SET STATISTICS IO OFF;
SET STATISTICS TIME OFF;

/*
EXECUTION PLAN
──────────────────────────────────────────────────────────────
  SELECT
    └─ Compute Scalar
         └─ Stream Aggregate  (COUNT, SUM)
              └─ Clustered Index Scan  (PK_FragDemo)
                   Actual rows : 350 000    Logical reads : 3 521

STATISTICS IO : Table 'FragDemo'. Scan count 1, logical reads 3 521
                                             physical reads 482   ← high!

STATISTICS TIME: CPU 1 047 ms,  elapsed 890 ms

WHY physical reads are high:
  The CI pages are logically ordered (IDENTITY key), but the NCI page splits
  have caused the storage layer to scatter physical pages.  With FILLFACTOR=100
  and no prior maintenance the file is physically fragmented — sequential scans
  become random I/O reads, each requiring a separate storage seek.
  After REORGANIZE the page ORDER is restored; physical reads drop dramatically.
  After REBUILD the page DENSITY is also restored; logical reads drop too.
*/

-- -----------------------------------------------------------------------
-- Step 6: Show where the wasted space is coming from
-- -----------------------------------------------------------------------
SELECT
    OBJECT_NAME(i.object_id)                       AS TableName,
    i.name                                          AS IndexName,
    ips.page_count,
    ips.record_count,
    ips.ghost_record_count,
    ROUND(ips.avg_fragmentation_in_percent,  2)    AS FragPct,
    ROUND(ips.avg_page_space_used_in_percent,2)    AS PageFillPct
FROM   sys.dm_db_index_physical_stats(
           DB_ID(), OBJECT_ID('dbo.FragDemo'), NULL, NULL, 'DETAILED') ips
JOIN   sys.indexes i
       ON  i.object_id = ips.object_id
       AND i.index_id  = ips.index_id
WHERE  ips.index_level = 0
ORDER  BY i.type_desc DESC;
GO

/*
  ghost_record_count shows how many deleted rows still occupy page space.
  These are not visible to queries but hold pages allocated in the index.
  REORGANIZE removes ghost records online; REBUILD removes them and compacts.
*/

-- -----------------------------------------------------------------------
-- SUMMARY
-- ┌────────────────────────────────────────────┬────────────────────────────┐
-- │ Metric                                     │ Value (fragmented state)   │
-- ├────────────────────────────────────────────┼────────────────────────────┤
-- │ NCI (IX_FragDemo_AccountID) fragmentation  │ 73.42%  (logical order)    │
-- │ CI  (PK_FragDemo) fragmentation            │ 21.07%  (ghost records)    │
-- │ Scan logical reads                         │ 3 521                      │
-- │ Scan physical reads (cold cache)           │ 482                        │
-- │ Scan elapsed time   (cold cache)           │ 890 ms                     │
-- └────────────────────────────────────────────┴────────────────────────────┘
--
-- Next step: run scenarios/06_index_fragmentation/optimization.sql
-- -----------------------------------------------------------------------
