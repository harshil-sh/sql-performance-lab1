-- =============================================================================
-- SQL Server Performance Lab
-- File: scenarios/06_index_fragmentation/after.sql
-- Scenario: Index Fragmentation - AFTER
--
-- Applies REORGANIZE and REBUILD, then measures fragmentation and performance.
-- =============================================================================

USE BankingLab;
GO

-- Step 1: REORGANIZE (online, incremental)
ALTER INDEX IX_FragDemo_AccountID_TxDate ON dbo.FragDemo REORGANIZE;
ALTER INDEX PK_FragDemo ON dbo.FragDemo REORGANIZE;
GO

SELECT
    i.name AS IndexName,
    ips.avg_fragmentation_in_percent AS FragmentationPct,
    ips.page_count,
    ips.avg_page_space_used_in_percent AS AvgPageFullPct
FROM sys.dm_db_index_physical_stats(DB_ID(), OBJECT_ID('dbo.FragDemo'), NULL, NULL, 'SAMPLED') ips
JOIN sys.indexes i
    ON i.object_id = ips.object_id
   AND i.index_id = ips.index_id
ORDER BY ips.avg_fragmentation_in_percent DESC;
GO

SET STATISTICS IO ON;
SET STATISTICS TIME ON;

SELECT COUNT(*), SUM(Amount)
FROM dbo.FragDemo
WHERE AccountID BETWEEN 1 AND 300000;

SET STATISTICS IO OFF;
SET STATISTICS TIME OFF;
GO

-- Step 2: REBUILD (full reset)
ALTER INDEX ALL ON dbo.FragDemo
    REBUILD WITH (FILLFACTOR = 85, SORT_IN_TEMPDB = ON, ONLINE = ON);
GO

SELECT
    i.name AS IndexName,
    ips.avg_fragmentation_in_percent AS FragmentationPct,
    ips.page_count,
    ips.avg_page_space_used_in_percent AS AvgPageFullPct
FROM sys.dm_db_index_physical_stats(DB_ID(), OBJECT_ID('dbo.FragDemo'), NULL, NULL, 'SAMPLED') ips
JOIN sys.indexes i
    ON i.object_id = ips.object_id
   AND i.index_id = ips.index_id
ORDER BY ips.avg_fragmentation_in_percent DESC;
GO

SET STATISTICS IO ON;
SET STATISTICS TIME ON;

SELECT COUNT(*), SUM(Amount)
FROM dbo.FragDemo
WHERE AccountID BETWEEN 1 AND 300000;

SET STATISTICS IO OFF;
SET STATISTICS TIME OFF;
GO
