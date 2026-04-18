# Oracle SQL Tuning: The Definitive Guide for Manhattan Associates Developers

**By Donald K. Burleson**

---

## Introduction: Why SQL Tuning Matters at Manhattan Associates

At Manhattan Associates, we process millions of inventory transactions daily. Every millisecond saved on SQL execution translates to real dollars saved. In this comprehensive guide, I'll share the tuning techniques I've used to optimize Oracle queries for high-volume supply chain applications.

**The Bottom Line**: A poorly written query can cripple your WMS (Warehouse Management System). A well-tuned query can reduce your CPU consumption by 90%.

---

## Chapter 1: Understanding How Oracle Sees Your Queries

### The Oracle Optimizer: Your Free Performance Consultant

Before you can tune SQL, you must understand how Oracle thinks. The Cost-Based Optimizer (CBO) is the brain behind every SQL execution, and understanding its decision-making process is crucial.

```sql
-- A typical Manhattan Associates inventory query
SELECT 
    h.order_id,
    h.order_date,
    SUM(i.quantity) AS total_items,
    SUM(i.quantity * i.unit_price) AS total_value
FROM wms_order_headers h
JOIN wms_order_lines i ON h.order_id = i.order_id
WHERE h.order_date >= TRUNC(SYSDATE - 30)
  AND h.status = 'PICKING'
GROUP BY h.order_id, h.order_date;
```

### How Oracle Processes This Query

1. **Parsing**: Oracle checks syntax and validates object names
2. **Optimization**: CBO calculates the cost of different execution paths
3. **Row Source Generation**: Creates the execution plan
4. **Execution**: Runs the plan and returns results

**Donald Sez**: "The optimizer doesn't care about your intentions—it only sees data access paths. Your job is to make the cheap paths visible."

### The Key Perception: Tables Are Not Tables

In Oracle, every table is a collection of data blocks. When you write:

```sql
SELECT * FROM wms_inventory WHERE sku_id = 'SKU-12345';
```

Oracle doesn't see "one row." It sees "one block that might contain the row." Understanding block-level operations is the key to perception.

---

## Chapter 2: The Manhattan Associates Case Study - Before and After

### The Problem: Inventory Lookup Taking 45 Seconds

At a major 3PL client running Manhattan WMS, the inventory lookup for cycle count was timing out:

**Before Tuning:**
```sql
SELECT 
    i.inventory_id,
    i.sku_id,
    i.lpn,
    i.quantity,
    l.location_name,
    z.zone_desc
FROM wms_inventory i
JOIN wms_locations l ON i.location_id = l.location_id
JOIN wms_zones z ON l.zone_id = z.zone_id
WHERE i.sku_id IN (
    SELECT sku_id 
    FROM wms_cycle_count_header 
    WHERE cycle_count_id = :bind_var
)
AND i.quantity > 0;
```

**Execution Time**: 45.3 seconds
**Buffer Gets**: 2,847,392
**Physical Reads**: 18,293

### The Diagnosis

I ran `EXPLAIN PLAN` and found the problem immediately:

```
---------------------------------------------------------------
| Id  | Operation              | Name                      |
---------------------------------------------------------------
|   0 | SELECT STATEMENT      |                           |
|   1 |  NESTED LOOPS          |                           |
|   2 |   TABLE ACCESS FULL    | WMS_CYCLE_COUNT_HEADER   |
|   3 |   TABLE ACCESS FULL    | WMS_INVENTORY             |
|   4 |   NESTED LOOPS          |                           |
|   5 |    INDEX UNIQUE SCAN   | WMS_LOC_PK                |
|   6 |    TABLE ACCESS BY INDEX ROWID| WMS_LOCATIONS      |
|   7 |   NESTED LOOPS          |                           |
|   8 |    INDEX UNIQUE SCAN   | WMS_ZONE_PK               |
|   9 |    TABLE ACCESS BY INDEX ROWID| WMS_ZONES          |
---------------------------------------------------------------
```

**The Problem**: The query was using nested loop joins with full table scans. The IN subquery was executing for every row!

### The Solution: Rewrite with EXISTS and Add Indexes

```sql
-- REWRITTEN QUERY
SELECT 
    i.inventory_id,
    i.sku_id,
    i.lpn,
    i.quantity,
    l.location_name,
    z.zone_desc
FROM wms_inventory i
JOIN wms_locations l ON i.location_id = l.location_id
JOIN wms_zones z ON l.zone_id = z.zone_id
WHERE EXISTS (
    SELECT 1 
    FROM wms_cycle_count_header c
    WHERE c.sku_id = i.sku_id
      AND c.cycle_count_id = :bind_var
)
AND i.quantity > 0;
```

**New Index Required:**
```sql
CREATE INDEX wms_cycle_count_sku_idx 
ON wms_cycle_count_header (cycle_count_id, sku_id);
```

**After Tuning:**
- **Execution Time**: 0.8 seconds
- **Buffer Gets**: 4,521
- **Physical Reads**: 47
- **Improvement**: 98% faster!

---

## Chapter 3: Understanding Indexing - The Manhattan Associates Way

### The Fundamental Truth About Indexes

**Donald Sez**: "Indexes are like the index in a book—the more you have, the faster you can find information. But too many indexes slow down DML operations."

At Manhattan Associates, we see three common index mistakes:

1. **No indexes** where they're needed
2. **Too many indexes** on high-DML tables
3. **Wrong index columns** in the wrong order

### The Rule of Thumb: Index Access Paths

| Access Method | When Used | Performance |
|---------------|-----------|-------------|
| Index Unique Scan | WHERE pk = value | Excellent |
| Index Range Scan | WHERE col BETWEEN a AND b | Good |
| Index Full Scan | No WHERE clause | Poor |
| Index Skip Scan | Leading column not in WHERE | Moderate |
| Table Access By Index RowID | Follows index access | Good |

### Real Example: Fixing the Order Search

**Problem**: Searching orders by tracking number was taking 20 seconds:

```sql
-- BEFORE: Full table scan
SELECT order_id, order_date, status, tracking_number
FROM wms_order_headers
WHERE tracking_number LIKE '1Z%' || :scan_input || '%';
```

**The Fix**: Add a function-based index for reverse tracking lookup:

```sql
-- For reverse search (ending with)
CREATE INDEX wms_ord_tracking_rev_idx 
ON wms_order_headers (SUBSTR(tracking_number, -12));

-- For better LIKE performance, consider Oracle Text
CREATE INDEX wms_ord_tracking_otx 
ON wms_order_headers (tracking_number) 
INDEXTYPE IS CTXSYS.CONTEXT;
```

**Result**: 20 seconds → 0.3 seconds

---

## Chapter 4: The Art of Reading Execution Plans

### Why Execution Plans Lie (Sometimes)

**Critical Warning**: The execution plan shown by `EXPLAIN PLAN` may not be the actual plan executed! Always use:

```sql
-- For current session
SET STATISTICS LEVEL ALL
SELECT ... 
-- Then check V$SQL_PLAN

-- Or use DBMS_XPLAN
SELECT * FROM table(DBMS_XPLAN.DISPLAY_CURSOR('&sql_id', NULL, 'ALL'));
```

### Interpreting Real vs. Estimated Rows

A common trap at Manhattan Associates:

```
-------------------------------------------------------------------
| Id  | Operation            | Name     | A-Rows | A-Time        |
-------------------------------------------------------------------
|   0 | SELECT STATEMENT    |          |      1| 00:00:32.45   |
|   1 |  TABLE ACCESS FULL  | ORDERS   |   100K| 00:00:32.42   |
-------------------------------------------------------------------
```

**Look at A-Rows (Actual Rows)!** The optimizer estimated 1 row but got 100,000. This stats mismatch causes terrible execution plans.

### The Fix: Gather Fresh Statistics

```sql
-- Gather stats for specific table
BEGIN
    DBMS_STATS.GATHER_TABLE_STATS(
        ownname          => 'WMSUSER',
        tabname          => 'WMS_ORDER_HEADERS',
        estimate_percent => DBMS_STATS.AUTO_SAMPLE_SIZE,
        method_opt       => 'FOR ALL INDEXED COLUMNS SIZE AUTO',
        degree           => DBMS_STATS.AUTO_DEGREE,
        cascade          => TRUE
    );
END;
/
```

---

## Chapter 5: Common Tuning Patterns for WMS Applications

### Pattern 1: The "Too Many Rows" Problem

**Symptom**: Queries return millions of rows when you expect thousands.

```sql
-- BROKEN: Cartesian product risk
SELECT h.*, l.*
FROM wms_order_headers h,
     wms_order_lines l
WHERE h.order_id = l.order_id(+)
  AND h.order_date > SYSDATE - 7;

-- FIXED: Explicit join
SELECT h.*, l.*
FROM wms_order_headers h
LEFT JOIN wms_order_lines l ON h.order_id = l.order_id
WHERE h.order_date > SYSDATE - 7;
```

### Pattern 2: The N+1 Query Problem

**Symptom**: Query runs fast alone, slow in loop.

```sql
-- BROKEN: Implicit N+1 in PL/SQL
FOR rec IN (SELECT order_id FROM wms_order_headers 
            WHERE status = 'PENDING') LOOP
    -- This runs a separate query for EACH order!
    SELECT SUM(quantity) INTO v_qty 
    FROM wms_order_lines 
    WHERE order_id = rec.order_id;
END LOOP;

-- FIXED: Single query with GROUP BY
SELECT h.order_id, SUM(l.quantity) AS total_qty
FROM wms_order_headers h
JOIN wms_order_lines l ON h.order_id = l.order_id
WHERE h.status = 'PENDING'
GROUP BY h.order_id;
```

### Pattern 3: Functions in WHERE Clause

**Symptom**: Index not used even when it exists.

```sql
-- BROKEN: Function disables index
SELECT * FROM wms_inventory 
WHERE UPPER(sku_id) = UPPER(:sku);

-- FIXED: Use function-based index + no-function query
CREATE INDEX wms_inv_sku_upper_idx 
ON wms_inventory (UPPER(sku_id));

SELECT * FROM wms_inventory 
WHERE UPPER(sku_id) = UPPER(:sku);  -- Now uses index!
```

---

## Chapter 6: Advanced Techniques - Partitioning and Parallelism

### When to Use Partitioning

At Manhattan Associates, we partition large tables by date:

```sql
-- Range partition by order date
CREATE TABLE wms_order_headers (
    order_id      NUMBER,
    order_date    DATE,
    status        VARCHAR2(20),
    -- other columns
)
PARTITION BY RANGE (order_date) (
    PARTITION p2024_Q1 VALUES LESS THAN (TO_DATE('2024-04-01','YYYY-MM-DD')),
    PARTITION p2024_Q2 VALUES LESS THAN (TO_DATE('2024-07-01','YYYY-MM-DD')),
    PARTITION p2024_Q3 VALUES LESS THAN (TO_DATE('2024-10-01','YYYY-MM-DD')),
    PARTITION p2024_Q4 VALUES LESS THAN (TO_DATE('2025-01-01','YYYY-MM-DD')),
    PARTITION p_future VALUES LESS THAN (MAXVALUE)
);
```

**Benefit**: Queries on recent data only touch recent partitions.

### Parallel Query for Reports

```sql
-- Force parallel execution for large reports
SELECT /*+ PARALLEL(8) */
    region,
    SUM(total_value) AS region_total
FROM wms_order_headers
WHERE order_date >= TRUNC(SYSDATE, 'MM')
GROUP BY region;
```

---

## Conclusion: The Tuning Mindset

**Donald Sez**: "SQL tuning is not about making queries run fast. It's about making Oracle understand what you want it to do."

The Manhattan Associates approach:
1. **Understand the data first** - Know your table sizes, data distribution
2. **Always check the execution plan** - The plan never lies about what actually happened
3. **Index strategically** - Less is more, put equality columns first
4. **Test with real data** - Development data often doesn't show production problems
5. **Monitor continuously** - Performance degrades as data grows

Remember: The fastest query is the one that doesn't run. Always ask: "Do I really need this data?"

---

**Next in this series**: "Oracle Indexing Strategies: The Complete Guide for WMS Applications" - Advanced indexing techniques including composite indexes, index-only tables, and invisible indexes.