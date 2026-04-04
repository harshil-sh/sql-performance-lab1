-- =============================================================================
-- SQL Server Performance Lab
-- File: setup/01_schema.sql
-- Purpose: Create the BankingLab database and all supporting tables
-- =============================================================================

USE master;
GO

-- -----------------------------------------------------------------------
-- 1.  Create the database
-- -----------------------------------------------------------------------
IF DB_ID('BankingLab') IS NOT NULL
BEGIN
    ALTER DATABASE BankingLab SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE BankingLab;
END
GO

-- NOTE: Update the FILENAME paths below to match a directory that exists on
--       your server (e.g. the instance's default data/log directories).
--       To find the default paths run:
--         SELECT physical_name FROM sys.master_files WHERE database_id = 1;
--       On Linux / containers use forward slashes, e.g. '/var/opt/mssql/data/'.
CREATE DATABASE BankingLab
ON PRIMARY (
    NAME       = N'BankingLab_data',
    FILENAME   = N'C:\SQLData\BankingLab_data.mdf',
    SIZE       = 4096 MB,
    MAXSIZE    = UNLIMITED,
    FILEGROWTH = 512 MB
)
LOG ON (
    NAME       = N'BankingLab_log',
    FILENAME   = N'C:\SQLData\BankingLab_log.ldf',
    SIZE       = 1024 MB,
    MAXSIZE    = UNLIMITED,
    FILEGROWTH = 256 MB
);
GO

ALTER DATABASE BankingLab SET RECOVERY SIMPLE;
GO

USE BankingLab;
GO

-- -----------------------------------------------------------------------
-- 2.  Reference / lookup tables
-- -----------------------------------------------------------------------

CREATE TABLE dbo.AccountType (
    AccountTypeID   TINYINT      NOT NULL,
    TypeName        VARCHAR(20)  NOT NULL,
    CONSTRAINT PK_AccountType PRIMARY KEY (AccountTypeID)
);

INSERT INTO dbo.AccountType VALUES
    (1, 'Checking'),
    (2, 'Savings'),
    (3, 'Money Market'),
    (4, 'CD'),
    (5, 'Investment');
GO

CREATE TABLE dbo.TransactionType (
    TransactionTypeID   TINYINT      NOT NULL,
    TypeName            VARCHAR(30)  NOT NULL,
    CONSTRAINT PK_TransactionType PRIMARY KEY (TransactionTypeID)
);

INSERT INTO dbo.TransactionType VALUES
    (1, 'Deposit'),
    (2, 'Withdrawal'),
    (3, 'Transfer'),
    (4, 'Fee'),
    (5, 'Interest'),
    (6, 'Adjustment');
GO

CREATE TABLE dbo.BranchRegion (
    RegionID    TINYINT      NOT NULL,
    RegionName  VARCHAR(20)  NOT NULL,
    CONSTRAINT PK_BranchRegion PRIMARY KEY (RegionID)
);

INSERT INTO dbo.BranchRegion VALUES
    (1, 'Northeast'),
    (2, 'Southeast'),
    (3, 'Midwest'),
    (4, 'Southwest'),
    (5, 'West');
GO

-- -----------------------------------------------------------------------
-- 3.  Customers
-- -----------------------------------------------------------------------
CREATE TABLE dbo.Customers (
    CustomerID    INT           NOT NULL IDENTITY(1,1),
    FirstName     VARCHAR(50)   NOT NULL,
    LastName      VARCHAR(50)   NOT NULL,
    Email         VARCHAR(100)  NOT NULL,
    PhoneNumber   VARCHAR(20)   NULL,
    DateOfBirth   DATE          NOT NULL,
    CreatedDate   DATETIME2(0)  NOT NULL DEFAULT SYSUTCDATETIME(),
    IsActive      BIT           NOT NULL DEFAULT 1,
    RegionID      TINYINT       NOT NULL,
    CONSTRAINT PK_Customers     PRIMARY KEY CLUSTERED (CustomerID),
    CONSTRAINT FK_Customers_Region
        FOREIGN KEY (RegionID) REFERENCES dbo.BranchRegion (RegionID)
);
GO

-- -----------------------------------------------------------------------
-- 4.  Accounts
-- -----------------------------------------------------------------------
CREATE TABLE dbo.Accounts (
    AccountID     INT            NOT NULL IDENTITY(1,1),
    CustomerID    INT            NOT NULL,
    AccountTypeID TINYINT        NOT NULL,
    AccountNumber CHAR(12)       NOT NULL,
    Balance       DECIMAL(18,2)  NOT NULL DEFAULT 0,
    OpenedDate    DATE           NOT NULL,
    ClosedDate    DATE           NULL,
    IsActive      BIT            NOT NULL DEFAULT 1,
    CONSTRAINT PK_Accounts PRIMARY KEY CLUSTERED (AccountID),
    CONSTRAINT UQ_AccountNumber UNIQUE (AccountNumber),
    CONSTRAINT FK_Accounts_Customer
        FOREIGN KEY (CustomerID)   REFERENCES dbo.Customers   (CustomerID),
    CONSTRAINT FK_Accounts_Type
        FOREIGN KEY (AccountTypeID) REFERENCES dbo.AccountType (AccountTypeID)
);
GO

-- -----------------------------------------------------------------------
-- 5.  Transactions  (10 million rows — no non-clustered indexes yet)
-- -----------------------------------------------------------------------
CREATE TABLE dbo.Transactions (
    TransactionID     BIGINT         NOT NULL IDENTITY(1,1),
    AccountID         INT            NOT NULL,
    TransactionTypeID TINYINT        NOT NULL,
    Amount            DECIMAL(18,2)  NOT NULL,
    BalanceAfter      DECIMAL(18,2)  NOT NULL,
    TransactionDate   DATETIME2(3)   NOT NULL,
    Description       VARCHAR(200)   NULL,
    ReferenceNumber   CHAR(16)       NOT NULL,
    IsReversed        BIT            NOT NULL DEFAULT 0,
    CONSTRAINT PK_Transactions PRIMARY KEY CLUSTERED (TransactionID),
    CONSTRAINT FK_Transactions_Account
        FOREIGN KEY (AccountID)         REFERENCES dbo.Accounts        (AccountID),
    CONSTRAINT FK_Transactions_Type
        FOREIGN KEY (TransactionTypeID) REFERENCES dbo.TransactionType (TransactionTypeID)
);
GO

-- -----------------------------------------------------------------------
-- 6.  Loans
-- -----------------------------------------------------------------------
CREATE TABLE dbo.Loans (
    LoanID          INT            NOT NULL IDENTITY(1,1),
    CustomerID      INT            NOT NULL,
    LoanType        VARCHAR(30)    NOT NULL,
    Principal       DECIMAL(18,2)  NOT NULL,
    InterestRate    DECIMAL(5,2)   NOT NULL,
    TermMonths      SMALLINT       NOT NULL,
    StartDate       DATE           NOT NULL,
    EndDate         DATE           NOT NULL,
    MonthlyPayment  DECIMAL(18,2)  NOT NULL,
    OutstandingBalance DECIMAL(18,2) NOT NULL,
    IsActive        BIT            NOT NULL DEFAULT 1,
    CONSTRAINT PK_Loans PRIMARY KEY CLUSTERED (LoanID),
    CONSTRAINT FK_Loans_Customer
        FOREIGN KEY (CustomerID) REFERENCES dbo.Customers (CustomerID)
);
GO

-- -----------------------------------------------------------------------
-- 7.  Alerts / notifications table (used for fragmentation demo)
-- -----------------------------------------------------------------------
CREATE TABLE dbo.TransactionAlerts (
    AlertID         BIGINT        NOT NULL IDENTITY(1,1),
    TransactionID   BIGINT        NOT NULL,
    AlertType       VARCHAR(30)   NOT NULL,
    AlertMessage    VARCHAR(500)  NOT NULL,
    CreatedDate     DATETIME2(0)  NOT NULL DEFAULT SYSUTCDATETIME(),
    IsRead          BIT           NOT NULL DEFAULT 0,
    CONSTRAINT PK_TransactionAlerts PRIMARY KEY CLUSTERED (AlertID),
    CONSTRAINT FK_Alerts_Transaction
        FOREIGN KEY (TransactionID) REFERENCES dbo.Transactions (TransactionID)
);
GO

PRINT 'Schema created successfully.';
GO
