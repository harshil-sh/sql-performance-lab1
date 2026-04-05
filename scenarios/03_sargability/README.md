<<<<<<< HEAD
# Scenario 03: SARGability

## Description

A predicate is **SARGable** (Search ARGument-able) when SQL Server can evaluate it using an index seek. Non-SARGable predicates force index scans even when a perfectly matching index exists. This scenario demonstrates five common non-SARGable patterns and their seek-friendly rewrites, plus a bonus Pattern 6 using a PERSISTED computed column.

## How to Run

1. Run `before.sql` — ensures required indexes exist, then runs all five non-SARGable patterns.
2. Run `optimization.sql` — adds the PERSISTED computed column and index for Pattern 6.
3. Run `after.sql` — runs all five SARGable rewrites plus the computed-column seek.

## Environment

| Setting | Value |
|---------|-------|
| SQL Server version | <!-- e.g. SQL Server 2022 Developer Edition --> |
| Hardware | <!-- e.g. 16-core / 64 GB RAM, NVMe SSD --> |
| Table row count | <!-- e.g. 10,000,000 --> |

## Performance Results

### Before (non-SARGable predicates)

| Pattern | Query Shape | Execution Plan | Logical Reads | Elapsed Time |
|---------|------------|---------------|---------------|--------------|
| 1 — Function wrapping | `YEAR(col) = 2023` | <!-- e.g. Clustered Index Scan --> | <!-- e.g. 105,042 --> | <!-- e.g. 4,018 ms --> |
| 2 — Implicit conversion | `col = '20230615'` (VARCHAR) | <!-- e.g. Clustered Index Scan --> | <!-- e.g. 105,042 --> | <!-- e.g. scan --> |
| 3 — Leading wildcard | `LIKE '%son'` | <!-- e.g. Index Scan --> | <!-- e.g. 681 --> | <!-- e.g. scan --> |
| 4 — Negation | `<> 1` | <!-- e.g. Clustered Index Scan --> | <!-- e.g. 105,042 --> | <!-- e.g. scan --> |
| 5 — OR across columns | `col1 = x OR col2 = y` | <!-- e.g. Clustered Index Scan --> | <!-- e.g. 105,042 --> | <!-- e.g. scan --> |

### After (SARGable rewrites + computed column for Pattern 6)

| Pattern | Rewrite | Execution Plan | Logical Reads | Improvement |
|---------|---------|---------------|---------------|-------------|
| 1 — Range predicate | `col >= '2023-06-01' AND col < '2023-07-01'` | <!-- e.g. Index Seek --> | <!-- e.g. 1,642 --> | <!-- e.g. ~118× --> |
| 2 — Typed literal | `col >= CAST('2023-06-15' AS DATETIME2(3))` | <!-- e.g. Index Seek --> | <!-- e.g. 78 --> | <!-- e.g. >1,000× --> |
| 3 — Trailing wildcard | `LIKE 'Johnson%'` | <!-- e.g. Index Seek --> | <!-- e.g. 4 --> | <!-- e.g. 170× --> |
| 4 — Positive IN list | `IN (2,3,4,5,6)` | <!-- e.g. Index Seek (with selective index) --> | <!-- TODO --> | <!-- TODO --> |
| 5 — UNION ALL | Two seeks via `UNION ALL` | <!-- e.g. Index Seek × 2 --> | <!-- e.g. ~6 --> | <!-- e.g. >17,000× --> |
| 6 — Computed column | `TxYearMonth = 202306` | <!-- e.g. Index Seek --> | <!-- e.g. 1,612 --> | <!-- e.g. ~65× --> |

<!-- SARGability rules of thumb:
  - Never apply a function or expression to the indexed column in WHERE.
  - Apply transformations to the literal/parameter instead.
  - Use typed literals (CAST/CONVERT) to prevent implicit conversions.
  - Replace leading-wildcard LIKE with full-text search or reversed-string columns.
  - Replace OR across different columns with UNION ALL.
  - Use PERSISTED computed columns + indexes for unavoidable function predicates.
-->

## Next Step

See [scenarios/04_window_functions/](../04_window_functions/) for window function performance patterns.
=======
# Scenario: 03 sargability

## Objective
[Add a one-paragraph objective for this scenario.]

## Files
- before.sql
- after.sql
- optimization.sql

## Execution Plan Analysis
### Before
[Paste plan shape, key operators, and bottlenecks.]

### After
[Paste plan shape changes and why they improved performance.]

## Results Table
| Query/Test | Logical Reads (Before) | Logical Reads (After) | CPU Time ms (Before) | CPU Time ms (After) | Notes |
|---|---:|---:|---:|---:|---|
| [Query 1] |  |  |  |  |  |
| [Query 2] |  |  |  |  |  |

## Notes
[Add caveats, assumptions, and environment details.]
>>>>>>> 35ed13f176cabce962f20f6a88667da75306794a
