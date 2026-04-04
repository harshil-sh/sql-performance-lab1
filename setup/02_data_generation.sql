-- =============================================================================
-- SQL Server Performance Lab
-- File: setup/02_data_generation.sql
-- Purpose: Populate all tables — Transactions table reaches ~10 million rows
--
-- Estimated run time : 8–15 minutes on a laptop-class server
-- Disk space required: ~2 GB (data) + ~300 MB (log, SIMPLE recovery)
-- =============================================================================

USE BankingLab;
GO

SET NOCOUNT ON;
GO

-- -----------------------------------------------------------------------
-- Helpers: fast pseudo-random number generation via NEWID()
-- -----------------------------------------------------------------------
-- We rely on ABS(CHECKSUM(NEWID())) for randomness throughout the script.

-- -----------------------------------------------------------------------
-- 1.  Customers  (200 000 rows)
-- -----------------------------------------------------------------------
PRINT 'Inserting Customers...';

DECLARE @BatchSize INT = 10000;
DECLARE @i         INT = 0;
DECLARE @Total     INT = 200000;

WHILE @i < @Total
BEGIN
    INSERT INTO dbo.Customers (FirstName, LastName, Email, PhoneNumber, DateOfBirth, CreatedDate, IsActive, RegionID)
    SELECT TOP (@BatchSize)
        -- First names pulled from a 30-element inline set
        v.FirstName,
        v.LastName,
        LOWER(v.FirstName) + '.' + LOWER(v.LastName)
            + CAST(ABS(CHECKSUM(NEWID())) % 9999 AS VARCHAR) + '@example.com',
        '(' + RIGHT('000' + CAST(ABS(CHECKSUM(NEWID())) % 900 + 100 AS VARCHAR), 3) + ') '
            + RIGHT('000' + CAST(ABS(CHECKSUM(NEWID())) % 900 + 100 AS VARCHAR), 3) + '-'
            + RIGHT('0000' + CAST(ABS(CHECKSUM(NEWID())) % 10000     AS VARCHAR), 4),
        DATEADD(DAY,  -(ABS(CHECKSUM(NEWID())) % (365*50) + 365*18), CAST('2024-01-01' AS DATE)),
        DATEADD(DAY,  -(ABS(CHECKSUM(NEWID())) % (365*5)),            SYSUTCDATETIME()),
        CASE WHEN ABS(CHECKSUM(NEWID())) % 20 = 0 THEN 0 ELSE 1 END,
        ABS(CHECKSUM(NEWID())) % 5 + 1
    FROM (
        SELECT TOP (@BatchSize) 1 AS n
        FROM sys.all_objects a CROSS JOIN sys.all_objects b
    ) t
    CROSS APPLY (
        SELECT
            CHOOSE(ABS(CHECKSUM(NEWID())) % 30 + 1,
                'James','Mary','John','Patricia','Robert','Jennifer','Michael','Linda',
                'William','Barbara','David','Susan','Richard','Jessica','Joseph','Sarah',
                'Thomas','Karen','Charles','Lisa','Christopher','Nancy','Daniel','Margaret',
                'Matthew','Betty','Anthony','Sandra','Mark','Dorothy') AS FirstName,
            CHOOSE(ABS(CHECKSUM(NEWID())) % 30 + 1,
                'Smith','Johnson','Williams','Brown','Jones','Garcia','Miller','Davis',
                'Rodriguez','Martinez','Hernandez','Lopez','Gonzalez','Wilson','Anderson',
                'Thomas','Taylor','Moore','Jackson','Martin','Lee','Perez','Thompson',
                'White','Harris','Sanchez','Clark','Ramirez','Lewis','Robinson') AS LastName
    ) v;

    SET @i = @i + @BatchSize;
END
PRINT CAST(@@ROWCOUNT AS VARCHAR) + ' Customers inserted (last batch).';
GO

-- -----------------------------------------------------------------------
-- 2.  Accounts  (~500 000 rows, 2–3 accounts per customer on average)
-- -----------------------------------------------------------------------
PRINT 'Inserting Accounts...';

INSERT INTO dbo.Accounts (CustomerID, AccountTypeID, AccountNumber, Balance, OpenedDate, ClosedDate, IsActive)
SELECT
    c.CustomerID,
    ABS(CHECKSUM(NEWID())) % 5 + 1,
    RIGHT('000000000000' + CAST(c.CustomerID * 1000 + n.n AS VARCHAR), 12),
    CAST(ABS(CHECKSUM(NEWID())) % 1000000 / 100.0 AS DECIMAL(18,2)),
    DATEADD(DAY, -(ABS(CHECKSUM(NEWID())) % (365*4)), CAST('2024-01-01' AS DATE)),
    CASE WHEN ABS(CHECKSUM(NEWID())) % 15 = 0
         THEN DATEADD(DAY, -(ABS(CHECKSUM(NEWID())) % 365), CAST('2024-01-01' AS DATE))
         ELSE NULL END,
    CASE WHEN ABS(CHECKSUM(NEWID())) % 15 = 0 THEN 0 ELSE 1 END
FROM dbo.Customers c
CROSS JOIN (VALUES(1),(2),(3)) n(n)   -- 3 accounts per customer = 600 000 rows
WHERE NOT EXISTS (                     -- avoid duplicate AccountNumber
    SELECT 1 FROM dbo.Accounts a
    WHERE a.AccountNumber = RIGHT('000000000000' + CAST(c.CustomerID * 1000 + n.n AS VARCHAR), 12)
);
PRINT 'Accounts inserted.';
GO

-- -----------------------------------------------------------------------
-- 3.  Loans  (~300 000 rows)
-- -----------------------------------------------------------------------
PRINT 'Inserting Loans...';

INSERT INTO dbo.Loans (CustomerID, LoanType, Principal, InterestRate, TermMonths, StartDate, EndDate, MonthlyPayment, OutstandingBalance, IsActive)
SELECT TOP 300000
    c.CustomerID,
    CHOOSE(ABS(CHECKSUM(NEWID())) % 5 + 1, 'Mortgage','Auto','Personal','Student','Business'),
    CAST((ABS(CHECKSUM(NEWID())) % 490000 + 10000) AS DECIMAL(18,2)),
    CAST((ABS(CHECKSUM(NEWID())) % 1500 + 250) / 100.0 AS DECIMAL(5,2)),
    CHOOSE(ABS(CHECKSUM(NEWID())) % 6 + 1, 12, 24, 36, 48, 60, 360),
    DATEADD(DAY, -(ABS(CHECKSUM(NEWID())) % (365*4)), CAST('2024-01-01' AS DATE)),
    DATEADD(DAY, ABS(CHECKSUM(NEWID())) % (365*10),   CAST('2024-01-01' AS DATE)),
    CAST((ABS(CHECKSUM(NEWID())) % 300000 + 5000) / 100.0 AS DECIMAL(18,2)),
    CAST((ABS(CHECKSUM(NEWID())) % 490000) / 100.0          AS DECIMAL(18,2)),
    CASE WHEN ABS(CHECKSUM(NEWID())) % 10 = 0 THEN 0 ELSE 1 END
FROM dbo.Customers c
CROSS JOIN (SELECT TOP 2 1 n FROM sys.all_objects) x;

PRINT 'Loans inserted.';
GO

-- -----------------------------------------------------------------------
-- 4.  Transactions  (target: 10 000 000 rows)
--     Inserted in batches of 500 000 to keep log growth manageable.
-- -----------------------------------------------------------------------
PRINT 'Inserting Transactions — this will take several minutes...';

DECLARE @TxBatch    INT    = 500000;
DECLARE @TxTarget   BIGINT = 10000000;
DECLARE @TxInserted BIGINT = 0;
DECLARE @MaxAcctID  INT    = (SELECT MAX(AccountID) FROM dbo.Accounts);
DECLARE @StartDate  DATETIME2(3) = '2019-01-01';
DECLARE @EndDate    DATETIME2(3) = '2024-01-01';
DECLARE @DateRange  INT = DATEDIFF(SECOND, @StartDate, @EndDate);

WHILE @TxInserted < @TxTarget
BEGIN
    INSERT INTO dbo.Transactions
        (AccountID, TransactionTypeID, Amount, BalanceAfter, TransactionDate, Description, ReferenceNumber, IsReversed)
    SELECT TOP (@TxBatch)
        ABS(CHECKSUM(NEWID())) % @MaxAcctID + 1,
        ABS(CHECKSUM(NEWID())) % 6 + 1,
        CAST((ABS(CHECKSUM(NEWID())) % 1000000 + 1) / 100.0 AS DECIMAL(18,2)),
        CAST((ABS(CHECKSUM(NEWID())) % 10000000) / 100.0     AS DECIMAL(18,2)),
        DATEADD(SECOND, ABS(CHECKSUM(NEWID())) % @DateRange, @StartDate),
        CHOOSE(ABS(CHECKSUM(NEWID())) % 8 + 1,
            'ATM Withdrawal','Online Transfer','Bill Payment','Direct Deposit',
            'POS Purchase','Wire Transfer','Check Deposit','ACH Payment'),
        UPPER(LEFT(REPLACE(CAST(NEWID() AS VARCHAR(36)), '-', ''), 16)),
        CASE WHEN ABS(CHECKSUM(NEWID())) % 200 = 0 THEN 1 ELSE 0 END
    FROM sys.all_objects a CROSS JOIN sys.all_objects b;

    SET @TxInserted = @TxInserted + @TxBatch;
    PRINT '  Inserted ' + CAST(@TxInserted AS VARCHAR) + ' / ' + CAST(@TxTarget AS VARCHAR) + ' transactions.';

    -- Checkpoint to keep the log from growing too large in SIMPLE recovery
    CHECKPOINT;
END

PRINT 'Transactions inserted. Verifying count...';
SELECT COUNT_BIG(*) AS TransactionCount FROM dbo.Transactions;
GO

-- -----------------------------------------------------------------------
-- 5.  Transaction Alerts  (~50 000 rows — seed for fragmentation demo)
-- -----------------------------------------------------------------------
PRINT 'Inserting TransactionAlerts...';

INSERT INTO dbo.TransactionAlerts (TransactionID, AlertType, AlertMessage, CreatedDate, IsRead)
SELECT TOP 50000
    t.TransactionID,
    CHOOSE(ABS(CHECKSUM(NEWID())) % 4 + 1,
        'LargeTransaction','FraudSuspect','OverdraftRisk','UnusualActivity'),
    'Automated alert for transaction ' + CAST(t.TransactionID AS VARCHAR),
    DATEADD(SECOND, ABS(CHECKSUM(NEWID())) % 3600, t.TransactionDate),
    CASE WHEN ABS(CHECKSUM(NEWID())) % 3 = 0 THEN 1 ELSE 0 END
FROM dbo.Transactions t
ORDER BY NEWID();

PRINT 'TransactionAlerts inserted.';
GO

-- -----------------------------------------------------------------------
-- 6.  Update statistics on all tables
-- -----------------------------------------------------------------------
PRINT 'Updating statistics...';
UPDATE STATISTICS dbo.Customers;
UPDATE STATISTICS dbo.Accounts;
UPDATE STATISTICS dbo.Transactions;
UPDATE STATISTICS dbo.Loans;
UPDATE STATISTICS dbo.TransactionAlerts;
GO

PRINT '=== Data generation complete ===';
GO

-- Quick summary
SELECT
    OBJECT_NAME(object_id) AS TableName,
    SUM(row_count) AS RowCount
FROM sys.dm_db_partition_stats
WHERE index_id IN (0,1)
  AND OBJECT_NAME(object_id) IN ('Customers','Accounts','Transactions','Loans','TransactionAlerts')
GROUP BY object_id
ORDER BY RowCount DESC;
GO
