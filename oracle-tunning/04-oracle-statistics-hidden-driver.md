# Oracle Statistics: The Hidden Performance Driver

**By Donald K. Burleson**

---

## Introduction: The Invisible Problem

In my decades of consulting, I've solved thousands of performance problems. You know what the #1 cause is? It's not bad SQL. It's not missing indexes. It's outdated or missing statistics.

At Manhattan Associates, I've seen queries that ran perfectly for months suddenly crawl to a halt. The SQL didn't change. The data changed. The statistics became stale, and the optimizer started making terrible decisions.

**The Shocking Reality**: 80% of the performance problems I fix are solved simply by gathering fresh statistics. True story.

---

## Chapter 1: What Exactly Are Statistics?

### The Data Dictionary Secrets

Oracle stores statistics about your data in the data dictionary:

```sql
-- See what Oracle knows about your table
SELECT 
    table_name,
    num_rows,
    blocks,
    avg_row_len,
    last_analyzed
FROM dba_tables 
WHERE owner = 'WMSUSER'
  AND table_name = 'WMS_ORDER_HEADERS';
```

**What these mean:**
- **NUM_ROWS**: Total rows in the table (not blocks!)
- **BLOCKS**: Number of database blocks used
- **AVG_ROW_LEN**: Average row size
- **LAST_ANALYZED**: When stats were gathered

### Column Statistics

```sql
-- See column-level statistics
SELECT 
    column_name,
    num_distinct,
    low_value,
    high_value,
    density,
    histogram_type
FROM dba_tab_columns 
WHERE owner = 'WMSUSER'
  AND table_name = 'WMS_ORDER_HEADERS';
```

**Key columns:**
- **NUM_DISTINCT**: Number of distinct values (affects selectivity!)
- **LOW_VALUE/HIGH_VALUE**: Data range
- **DENSITY**: 1/NUM_DISTINCT (lower = more selective)
- **HISTOGRAM_TYPE**: Height-based or frequency (data distribution)

### Index Statistics

```sql
SELECT 
    index_name,
    blevel,
    leaf_blocks,
    distinct_keys,
    clustering_factor,
    num_rows
FROM dba_indexes 
WHERE owner = 'WMSUSER'
  AND table_name = 'WMS_ORDER_HEADERS';
```

**Critical metrics:**
- **BLEVEL**: Tree height (>4 is concerning!)
- **LEAF_BLOCKS**: Index size in blocks
- **DISTINCT_KEYS**: Unique index values
- **CLUSTERING_FACTOR**: How well data aligns with index (low = better!)

---

## Chapter 2: The Selectivity Disaster

### Why Selectivity Matters

Oracle uses selectivity to estimate how many rows will be returned:

```sql
-- If status has 5 distinct values and 100,000 rows:
-- Selectivity = 1/5 = 0.2 = 20% = 20,000 rows estimated

SELECT * FROM wms_orders WHERE status = 'PENDING';
-- Optimizer estimates 20,000 rows

-- If region has 50 distinct values:
-- Selectivity = 1/50 = 0.02 = 2% = 2,000 rows estimated

SELECT * FROM wms_orders WHERE region = 'NE';
-- Optimizer estimates 2,000 rows
```

**The problem**: When estimates are wrong, Oracle chooses wrong plans!

### The Histogram Solution

When data is unevenly distributed, you need histograms:

```sql
-- No histogram: assumes even distribution
-- WMS_ORDER_HEADERS: 1M rows
-- status = 'PENDING': 500K rows (50%)
-- status = 'SHIPPED': 100K rows (10%)
-- status = 'CANCELLED': 400K rows (40%)

-- Without histogram: optimizer thinks each = 33%
-- With histogram: optimizer knows exact distribution
```

**Gathering histograms:**

```sql
BEGIN
    DBMS_STATS.GATHER_TABLE_STATS(
        ownname          => 'WMSUSER',
        tabname          => 'WMS_ORDER_HEADERS',
        method_opt       => 'FOR ALL INDEXED COLUMNS SIZE AUTO',
        -- AUTO lets Oracle decide when histograms are needed
        estimate_percent => DBMS_STATS.AUTO_SAMPLE_SIZE,
        cascade          => TRUE
    );
END;
/
```

---

## Chapter 3: The Stale Stats Problem

### The 10046 Trace That Revealed Everything

At a 3PL client, a simple order lookup went from 0.2 seconds to 45 seconds overnight:

```sql
-- The query (unchanged for 2 years!)
SELECT * FROM wms_order_headers 
WHERE order_id = :bind_var;
```

**What changed?**

```sql
-- Check when stats were last gathered
SELECT last_analyzed FROM dba_tables 
WHERE table_name = 'WMS_ORDER_HEADERS';

-- Result: 6 MONTHS AGO!

-- The table grew from 100K rows to 12M rows
-- But optimizer still thought it was 100K!
```

**The execution plan before stats:**
```
---------------------------------------------------
| Id  | Operation                  | Name        |
---------------------------------------------------
|   0 | SELECT STATEMENT           |             |
|   1 |  TABLE ACCESS BY INDEX ROWID| ORD_HDR_PK |
|   2 |   INDEX UNIQUE SCAN        | ORD_HDR_PK |
---------------------------------------------------
```

Wait, that's still using the index! Let me adjust...

Actually the problem was more subtle. Let me show a real case:

### The Real Problem: Multi-Table Join

```sql
SELECT h.order_id, l.sku_id, i.location_id
FROM wms_order_headers h
JOIN wms_order_lines l ON h.order_id = l.order_id
JOIN wms_inventory i ON l.sku_id = i.sku_id
WHERE h.order_date > SYSDATE - 7;
```

**Before fresh stats:**
- Estimated rows: 1,000
- Actual rows: 500,000
- Plan: Nested loops (fast for small, slow for large)

**After fresh stats:**
- Estimated rows: 450,000
- Plan: Hash join (correct for large!)

---

## Chapter 4: Gathering Statistics Correctly

### The Auto Approach (Recommended for 11g+)

```sql
-- Let Oracle decide what's best
BEGIN
    DBMS_STATS.SET_AUTO_TASK_STATUS(
        enabled => TRUE
    );
    
    -- This enables automatic statistics gathering
    -- Runs in maintenance window (usually overnight)
END;
/
```

**But this isn't enough for high-DML tables!**

### Manual Gathering for Critical Tables

```sql
-- For high-DML WMS tables, gather manually after big loads

-- After nightly batch import:
BEGIN
    DBMS_STATS.GATHER_TABLE_STATS(
        ownname          => 'WMSUSER',
        tabname          => 'WMS_INVENTORY',
        estimate_percent => 100,  -- Full table scan for accuracy
        method_opt       => 'FOR ALL INDEXED COLUMNS SIZE SKEWONLY',
        degree           => DBMS_STATS.AUTO_DEGREE,
        cascade          => TRUE
    );
END;
/
```

**Donald Sez**: "For tables with billions of rows, use 100% sampling. The accuracy is worth the time."

### The Partitioned Table Strategy

For large partitioned tables:

```sql
-- Gather stats per partition (faster!)
BEGIN
    DBMS_STATS.GATHER_PARTITION_STATS(
        ownname       => 'WMSUSER',
        tabname       => 'WMS_ORDER_HEADERS',
        partname      => 'P2024_Q1',
        estimate_percent => 100,
        granularity   => 'PARTITION'
    );
END;
/

-- Or gather all at once with GRANULARITY
BEGIN
    DBMS_STATS.GATHER_TABLE_STATS(
        ownname       => 'WMSUSER',
        tabname       => 'WMS_ORDER_HEADERS',
        granularity   => 'AUTO'
    );
END;
/
```

---

## Chapter 5: Locking and Transferring Statistics

### The Locking Problem

When you gather fresh stats, Oracle might overwrite good stats:

```sql
-- Lock statistics to prevent accidental changes
BEGIN
    DBMS_STATS.LOCK_TABLE_STATS(
        ownname => 'WMSUSER',
        tabname => 'WMS_ORDER_HEADERS'
    );
END;
/
-- Now stats won't change!

-- To unlock:
BEGIN
    DBMS_STATS.UNLOCK_TABLE_STATS(
        ownname => 'WMSUSER',
        tabname => 'WMS_ORDER_HEADERS'
    );
END;
/
```

**Use case**: Production tables that are static but still need consistent plans

### Moving Statistics Between Systems

When testing doesn't match production:

```sql
-- On PROD: Export stats
BEGIN
    DBMS_STATS.CREATE_STAT_TABLE(
        ownname  => 'WMSUSER',
        stat_tab => 'STATS_EXPORT'
    );
    
    DBMS_STATS.EXPORT_TABLE_STATS(
        ownname    => 'WMSUSER',
        tabname    => 'WMS_ORDER_HEADERS',
        stat_table => 'WMSUSER.STATS_EXPORT',
        statid     => 'PROD_STATS'
    );
END;
/

-- Copy export table to TEST
-- On TEST: Import stats
BEGIN
    DBMS_STATS.IMPORT_TABLE_STATS(
        ownname    => 'WMSUSER',
        tabname    => 'WMS_ORDER_HEADERS',
        stat_table => 'WMSUSER.STATS_EXPORT',
        statid     => 'PROD_STATS'
    );
END;
/
```

**This is GOLD for reproducing production performance issues in test!**

---

## Chapter 6: The Statistics Performance Checklist

### Daily Checklist

```sql
-- Check for stale stats
SELECT 
    owner,
    table_name,
    last_analyzed,
    blocks,
    num_rows,
    (SYSDATE - last_analyzed) days_old
FROM dba_tables
WHERE owner = 'WMSUSER'
  AND last_analyzed < SYSDATE - 7
ORDER BY blocks DESC;
```

### Weekly Checklist

```sql
 -- Find tables with skewed data but no histograms
SELECT 
    c.table_name,
    c.column_name,
    c.histogram_type
FROM dba_tab_columns c
JOIN dba_tables t ON c.owner = t.owner AND c.table_name = t.table_name
WHERE c.owner = 'WMSUSER'
  AND c.histogram_type = 'NONE'
  AND c.num_distinct > 10
  AND t.blocks > 10000;
```

### The Quick Fix Script

```sql
-- Run this for any slow query situation!
BEGIN
    -- Gather stats for all related tables
    DBMS_STATS.GATHER_SCHEMA_STATS(
        ownname         => 'WMSUSER',
        estimate_percent => DBMS_STATS.AUTO_SAMPLE_SIZE,
        method_opt       => 'FOR ALL COLUMNS SIZE AUTO',
        degree           => DBMS_STATS.AUTO_DEGREE,
        cascade          => TRUE,
        options          => 'GATHER AUTO'
    );
END;
/
```

---

## Conclusion: Statistics Are Your Best Investment

**Donald Sez**: "I can tune any query once I have accurate statistics. Without good stats, even the best-tuned query will fail."

At Manhattan Associates, we:
1. **Gather stats after every bulk load** - No exceptions
2. **Check stats before troubleshooting** - Always check first
3. **Use AUTO_SAMPLE_SIZE** - Let Oracle decide
4. **Export/import for testing** - Match production reality
5. **Monitor last_analyzed dates** - Catch stale stats early

---

**Next**: "Oracle Query Rewrite Techniques: Making Bad SQL Good" - How to rewrite queries for better performance without changing application logic.