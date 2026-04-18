# Oracle Execution Plans Demystified: Read the Plan, Find the Problem

**By Donald K. Burleson**

---

## Introduction: The Execution Plan Is Your Truth

After three decades of Oracle tuning, I've learned one irrefutable truth: the execution plan never lies. When a query runs slow, the execution plan shows exactly why—every unnecessary table scan, every nested loop, every hash join is captured in black and white.

At Manhattan Associates, I've seen brilliant developers spend weeks trying to "optimize" their SQL, only to discover the problem was revealed in the first 30 seconds of execution plan analysis.

**The Bottom Line**: If you can't read an execution plan, you can't tune SQL. It's that simple.

---

## Chapter 1: How to Actually See What Oracle Does

### The Dangerous Myth: EXPLAIN PLAN

Most developers run EXPLAIN PLAN and think they see the truth. They're usually wrong.

```sql
-- What most people do (INCOMPLETE!)
EXPLAIN PLAN FOR
SELECT order_id, order_date 
FROM wms_order_headers 
WHERE status = 'PENDING';

SELECT * FROM table(DBMS_XPLAN.DISPLAY);
```

This shows what Oracle **might** do. But the actual execution can differ dramatically!

### The Real Way: DBMS_XPLAN.DISPLAY_CURSOR

```sql
-- First, enable statistics collection
ALTER SESSION SET STATISTICS_LEVEL = ALL;

-- Run your query
SELECT order_id, order_date 
FROM wms_order_headers 
WHERE status = 'PENDING';

-- Now see the REAL plan with actual performance metrics
SELECT * FROM table(DBMS_XPLAN.DISPLAY_CURSOR(NULL, NULL, 'ALLSTATS LAST'));
```

**This shows:**
- **A-Rows**: Actual rows returned at each step
- **A-Time**: Actual time spent at each step
- **Buffers**: Actual memory used
- **Reads/Writes**: Physical I/O performed

### Interpreting Real vs. Estimated Rows

This is the #1 execution plan issue I fix at Manhattan Associates:

```
-------------------------------------------------------------------
| Id  | Operation            | Name     | E-Rows | A-Rows | A-Time |
-------------------------------------------------------------------
|   0 | SELECT STATEMENT    |          |      1 |   100K | 00:45  |
|   1 |  TABLE ACCESS FULL  | ORDERS   |      1 |   100K | 00:45  |
-------------------------------------------------------------------
```

**E-Rows (Estimated): 1 row**
**A-Rows (Actual): 100,000 rows**

The optimizer thought it would get 1 row, so it chose a bad plan! This stats problem is the root cause of 80% of the slow queries I see.

---

## Chapter 2: Understanding Join Methods

### Nested Loop Join: The Good, The Bad, The Ugly

A nested loop join works like nested DO loops in programming:

```sql
SELECT /*+ ORDERED */ 
    h.order_id, l.quantity
FROM wms_order_headers h
JOIN wms_order_lines l ON h.order_id = l.order_id
WHERE h.region = 'NE';
```

**How it works:**
1. For each row in the outer table (order_headers)
2. Scan the inner table (order_lines) for matching rows

**Good**: When outer table returns few rows and inner table has index
**Bad**: When outer table returns many rows

**Execution Plan (Good):**
```
-------------------------------------------------------------
| Id  | Operation                      | Name             |
-------------------------------------------------------------
|   0 | SELECT STATEMENT               |                  |
|   1 |  NESTED LOOPS                  |                  |
|   2 |   TABLE ACCESS BY INDEX ROWID | WMS_ORDER_HDR    |
|   3 |    INDEX RANGE SCAN           | ORD_HDR_REGION   |
|   4 |   TABLE ACCESS BY INDEX ROWID | WMS_ORDER_LINES |
|   5 |    INDEX RANGE SCAN           | ORD_LINES_FK     |
-------------------------------------------------------------
```

**Execution Plan (Bad - No Index):**
```
-------------------------------------------------------------
| Id  | Operation            | Name              | Rows   |
-------------------------------------------------------------
|   0 | SELECT STATEMENT    |                   |        |
|   1 |  NESTED LOOPS       |                   |   10M  |
|   2 |   TABLE ACCESS FULL| WMS_ORDER_HDR     |   500K |
|   3 |   TABLE ACCESS FULL| WMS_ORDER_LINES   |    20  |
-------------------------------------------------------------
```

This is doing 500,000 full table scans! Every row from headers scans the entire lines table.

### Hash Join: The Workhorse

Hash joins are efficient for large row sets:

```sql
SELECT h.order_id, l.sku_id
FROM wms_order_headers h
JOIN wms_inventory i ON h.order_id = i.order_id
WHERE h.order_date > SYSDATE - 30;
```

**How it works:**
1. Oracle builds a hash table from the smaller table (in memory)
2. Scans the larger table, probing the hash table for matches

```
-------------------------------------------------
| Id  | Operation         | Name                |
-------------------------------------------------
|   0 | SELECT STATEMENT  |                    |
|   1 |  HASH JOIN        |                    |
|   2 |   TABLE ACCESS FULL| WMS_ORDER_HDR     |
|   3 |   TABLE ACCESS FULL| WMS_INVENTORY     |
-------------------------------------------------
```

**Good for**: Large tables, no useful index, equi-join
**The catch**: Needs enough memory for the hash table

### Merge Join: The Sorted Approach

```sql
SELECT /*+ USE_MERGE(h l) */ 
    h.order_id, l.sku_id
FROM wms_order_headers h
JOIN wms_order_lines l ON h.order_id = l.order_id
WHERE h.status = 'COMPLETE';
```

**How it works:**
1. Both inputs are sorted by join key
2. Merge sorted streams together

**Good for**: Already-sorted data, large sets
**The catch**: Sorts can be expensive

---

## Chapter 3: Access Methods - What's Really Happening

### TABLE ACCESS FULL: The Big Red Flag

When you see this, ask yourself: "Should I be scanning every row?"

```sql
-- This might be acceptable
SELECT * FROM wms_inventory WHERE quantity > 0;  -- 90% of rows

-- This is usually BAD
SELECT * FROM wms_inventory WHERE sku_id = 'SKU-123';
```

**The fix**: Create an index

```sql
CREATE INDEX wms_inv_sku_idx ON wms_inventory(sku_id);

-- Plan now shows:
-- INDEX RANGE SCAN on wms_inv_sku_idx
-- TABLE ACCESS BY INDEX ROWID
```

### INDEX UNIQUE SCAN: Perfect for PK Lookups

```sql
SELECT * FROM wms_order_headers WHERE order_id = 12345;
```

```
---------------------------------------------
| Id  | Operation                   | Name |
---------------------------------------------
|   0 | SELECT STATEMENT            |      |
|   1 |  TABLE ACCESS BY INDEX ROWID|      |
|   2 |   INDEX UNIQUE SCAN         | PK   |
---------------------------------------------
```

This is optimal! Single row, single I/O.

### INDEX RANGE SCAN: The Sweet Spot

```sql
SELECT * FROM wms_orders WHERE order_date BETWEEN '01-JAN-24' AND '31-MAR-24';
```

```
-----------------------------------------------
| Id  | Operation               | Name         |
-----------------------------------------------
|   0 | SELECT STATEMENT        |              |
|   1 |  INDEX RANGE SCAN       | ORD_DATE_IDX |
-----------------------------------------------
```

This scans only the relevant index leaf blocks—not the whole index.

### INDEX FULL SCAN: When It's Actually Good

```sql
-- No WHERE clause, but need order
SELECT status, COUNT(*) FROM wms_orders GROUP BY status;
```

```
-------------------------------------------------
| Id  | Operation           | Name              |
-------------------------------------------------
|   0 | SELECT STATEMENT    |                   |
|   1 |  SORT GROUP BY     |                   |
|   2 |   INDEX FULL SCAN  | ORD_STATUS_IDX    |
-------------------------------------------------
```

This reads the entire index (which is smaller than the table) in sorted order!

---

## Chapter 4: Real-World Case Study - The 30-Second Inventory Report

### The Problem

At a major retail client, their inventory valuation report took 30+ minutes:

```sql
SELECT 
    i.sku_id,
    s.sku_desc,
    i.location_id,
    l.location_name,
    SUM(i.quantity) AS total_qty,
    SUM(i.quantity * i.unit_cost) AS total_value
FROM wms_inventory i
JOIN wms_sku s ON i.sku_id = s.sku_id
JOIN wms_locations l ON i.location_id = l.location_id
WHERE i.quantity > 0
  AND l.location_type IN ('PICK', 'BULK', 'STAGE')
GROUP BY 
    i.sku_id, s.sku_desc, i.location_id, l.location_name;
```

### The Execution Plan (Before)

```
----------------------------------------------------------------------------
| Id  | Operation                 | Name           | A-Time   | Buffers |
----------------------------------------------------------------------------
|   0 | SELECT STATEMENT          |                | 31:45.23 |  4.2M   |
|   1 |  HASH GROUP BY            |                | 31:45.21 |  4.2M   |
|   2 |   HASH JOIN               |                | 02:12.45 |  4.2M   |
|   3 |    TABLE ACCESS FULL      | WMS_INVENTORY  | 00:32.12 |  1.8M   |
|   4 |    HASH JOIN              |                | 01:15.33 |  2.4M   |
|   5 |     TABLE ACCESS FULL     | WMS_SKU        | 00:05.21 |   450   |
|   6 |     TABLE ACCESS FULL     | WMS_LOCATIONS  | 00:02.11 |   289   |
----------------------------------------------------------------------------
```

**Problems identified:**
1. Full table scan on wms_inventory (12 million rows)
2. No indexes on join predicates
3. Hash join forcing full table scans

### The Fix

**Step 1: Add proper indexes**

```sql
CREATE INDEX wms_inv_loc_qty_idx 
ON wms_inventory(location_id, quantity, sku_id, unit_cost);

CREATE INDEX wms_loc_type_idx 
ON wms_locations(location_type, location_id);
```

**Step 2: Rewrite to use index access**

```sql
SELECT 
    i.sku_id,
    s.sku_desc,
    i.location_id,
    l.location_name,
    SUM(i.quantity) AS total_qty,
    SUM(i.quantity * i.unit_cost) AS total_value
FROM wms_inventory i
JOIN wms_locations l ON i.location_id = l.location_id
JOIN wms_sku s ON i.sku_id = s.sku_id
WHERE i.quantity > 0
  AND l.location_type IN ('PICK', 'BULK', 'STAGE')
GROUP BY 
    i.sku_id, s.sku_desc, i.location_id, l.location_name;
```

### The Execution Plan (After)

```
---------------------------------------------------------------------------
| Id  | Operation                       | Name              | A-Time | Buf |
---------------------------------------------------------------------------
|   0 | SELECT STATEMENT                |                   | 00:02.34|  45K |
|   1 |  HASH GROUP BY                  |                   | 00:02.34|  45K |
|   2 |   HASH JOIN                     |                   | 00:01.89|  45K |
|   3 |    INDEX FAST FULL SCAN         | WMS_INV_LOC_QTY   | 00:00.45|  32K |
|   4 |    HASH JOIN                    |                   | 00:01.12|  13K |
|   5 |     TABLE ACCESS BY INDEX ROWID | WMS_LOCATIONS    | 00:00.02|   12 |
|   6 |      INDEX RANGE SCAN           | WMS_LOC_TYPE     | 00:00.01|    4 |
|   7 |     TABLE ACCESS FULL           | WMS_SKU          | 00:00.89|  450 |
---------------------------------------------------------------------------
```

**Result**: 31 minutes → 2.3 seconds! **99.9% improvement**

---

## Chapter 5: Common Plan Problems and Fixes

### Problem 1: Cartesian Product

**Symptom**: Unexplained high row counts

```
|   3 |        MERGE JOIN CARTESIAN     |                 |
```

**Cause**: Forgot to join two tables

```sql
-- BROKEN: Cartesian!
SELECT h.*, l.* 
FROM wms_order_headers h, wms_order_lines l
WHERE h.status = 'PENDING';  -- No join to l!

-- FIXED: Proper join
SELECT h.*, l.* 
FROM wms_order_headers h
JOIN wms_order_lines l ON h.order_id = l.order_id
WHERE h.status = 'PENDING';
```

### Problem 2: Filter Predicates in Wrong Order

**Symptom**: Too many rows processed early

```
|   2 |   TABLE ACCESS FULL            | WMS_ORDERS      |
|   3 |    TABLE ACCESS BY INDEX ROWID | WMS_ORDER_LINES |
|   4 |     INDEX RANGE SCAN           | ORD_LINES_FK    |
```

The line table is accessed BEFORE filtering the header!

**Fix**: Put filter on header table first in WHERE

### Problem 3: Remote Queries

**Symptom**: Query goes across database link

```
|   2 |   REMOTE | WMS_ORDERS@LINK |  |  | 
```

**Fix**: Consider materialized view or copying data locally

### Problem 4: Excessive Sorts

**Symptom**: Sort operations dominate time

```
|   2 |  SORT ORDER BY                 |                |
|   4 |   SORT JOIN                   |                |
```

**Fix**: Create index on ORDER BY columns

---

## Chapter 6: Using Hints to Fix Plans

### When Hints Are Appropriate

**Donald Sez**: "Hints are like medicine—when used correctly, they cure the patient. When overused, they create dependencies that haunt you forever."

Use hints only when:
1. Statistics are accurate but optimizer still chooses wrong
2. Application has fixed SQL that cannot be changed
3. You've proven the hint improves performance

### Common Hints

```sql
/*+ FULL(table) */              -- Force full table scan
/*+ INDEX(table index) */       -- Force index use
/*+ USE_NL(table1 table2) */    -- Force nested loop
/*+ USE_HASH(table1 table2) */  -- Force hash join
/*+ ORDERED */                  -- Force join order as written
/*+ PARALLEL(8) */             -- Force parallelism
/*+ LEADING(t1 t2) */          -- Set first table in join
```

### The Safe Hint Approach

```sql
-- Start with a hint to fix the immediate problem
SELECT /*+ FULL(wms_inventory) */ *
FROM wms_inventory
WHERE quantity > 1000;

-- Then work on the real fix: add proper index
CREATE INDEX wms_inv_qty_idx ON wms_inventory(quantity);
```

---

## Conclusion: Plan Reading Is a Skill

**Donald Sez**: "The execution plan is a map of what Oracle does. Learn to read it like a GPS—it tells you exactly where the performance went."

At Manhattan Associates, we follow this process:
1. Run query with ALLSTATS to get actual performance
2. Identify operations with high A-Time or Buffers
3. Ask "Why?" at each step
4. Fix root cause (stats, indexes, rewrite) not symptoms

---

**Next**: "Oracle Statistics: The Hidden Performance Driver" - Why outdated statistics cause 90% of performance problems and how to fix them.