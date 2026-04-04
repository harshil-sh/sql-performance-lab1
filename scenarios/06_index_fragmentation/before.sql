-- =============================================================================
-- SQL Server Performance Lab
-- File: scenarios/06_index_fragmentation/before.sql
-- Scenario: Index Fragmentation - BEFORE
--
-- Creates a fragmented test table and captures baseline fragmentation and
-- scan performance prior to maintenance.
-- =============================================================================

USE BankingLab;
GO

IF OBJECT_ID('dbo.FragDemo', 'U') IS NOT NULL
    DROP TABLE dbo.FragDemo;
GO

CREATE TABLE dbo.FragDemo (
    ID INT NOT NULL IDENTITY(1,1),
    AccountID INT NOT NULL,
    TxDate DATETIME2(3) NOT NULL,
    Amount DECIMAL(18,2) NOT NULL,
    Padding CHAR(100) NOT NULL DEFAULT 'x',
    CONSTRAINT PK_FragDemo PRIMARY KEY CLUSTERED (ID)
);

CREATE NONCLUSTERED INDEX IX_FragDemo_AccountID_TxDate
    ON dbo.FragDemo (AccountID, TxDate)
    WITH (FILLFACTOR = 100);
GO

INSERT INTO dbo.FragDemo (AccountID, TxDate, Amount)
SELECT TOP 500000
    ABS(CHECKSUM(NEWID())) % 600000 + 1,
    DATEADD(SECOND, ABS(CHECKSUM(NEWID())) % 157680000, '2019-01-01'),
    CAST((ABS(CHECKSUM(NEWID())) % 1000000 + 1) / 100.0 AS DECIMAL(18,2))
FROM sys.all_objects a CROSS JOIN sys.all_objects b;

DELETE TOP (150000)
FROM dbo.FragDemo
WHERE ID % 3 = 0;
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
