# Oracle Hints: The Complete Guide to Query Optimization

**By Donald K. Burleson**

---

## Introduction: Hints Are a Double-Edged Sword

In my decades of Oracle consulting, I've seen hints used brilliantly and catastrophically. Hints are powerful directives that override the optimizer's decisions—but they come with risks.

At Manhattan Associates, we use hints sparingly and always with a plan to fix the underlying problem. Hints should be a temporary fix, not a permanent crutch.

**The Golden Rule**: Use hints only when you've proven the optimizer is wrong and you understand why.

---

## Chapter 1: Understanding Hint Syntax

### The Basics

```sql
-- Single hint
SELECT /*+ FULL(wms_orders) */ * FROM wms_orders WHERE order_id = 123;

-- Multiple hints
SELECT /*+ FULL(wms_orders) INDEX(wms_ord_lines ord_lines_pk) */ 
    * 
FROM wms_orders o
JOIN wms_order_lines l ON o.order_id = l.order_id
WHERE o.order_date > SYSDATE - 7;
```

### Hint Errors Are Silent

```sql
-- This hint is IGNORED but no error is thrown!
SELECT /*+ FULL(wms_orders) */ * 
FROM wms_orders 
WHERE order_id = 123;
-- If order_id has an index, it's used anyway!
-- Check v$sql_plan to see if hints are applied!
```

**Always verify hint usage:**

```sql
SELECT sql_id, sql_text 
FROM v$sql 
WHERE sql_text LIKE '%wms_orders%';

SELECT * FROM table(DBMS_XPLAN.DISPLAY_CURSOR('&sql_id', NULL, 'HINT'));
```

---

## Chapter 2: Access Path Hints

### FULL: Force Full Table Scan

```sql
-- Force full scan even if index exists
SELECT /*+ FULL(wms_inventory) */ *
FROM wms_inventory
WHERE quantity > 0;  -- 90% of rows, full scan is correct
```

### INDEX: Force Index Usage

```sql
-- Force specific index
SELECT /*+ INDEX(wms_orders wms_ord_status_idx) */ *
FROM wms_orders
WHERE status = 'PENDING';

-- Force index range scan
SELECT /*+ INDEX(wms_orders wms_ord_date_idx) */ *
FROM wms_orders
WHERE order_date > SYSDATE - 30;
```

### NO_INDEX: Disable Index

```sql
-- Disable an index that optimizer wrongly chooses
SELECT /*+ NO_INDEX(wms_orders wms_ord_status_idx) */ *
FROM wms_orders
WHERE status || '' = 'PENDING';  -- Hack to force full scan
```

### INDEX_FFS: Index Fast Full Scan

```sql
-- Use index fast full scan (multi-block read)
SELECT /*+ INDEX_FFS(wms_inventory wms_inv_sku_idx) */ sku_id, quantity
FROM wms_inventory
WHERE sku_id LIKE 'SKU%';
```

---

## Chapter 3: Join Order Hints

### ORDERED: Force Written Join Order

```sql
-- Force join order as written
SELECT /*+ ORDERED */
    o.order_id,
    l.sku_id,
    i.location_id
FROM wms_order_headers o
JOIN wms_order_lines l ON o.order_id = l.order_id
JOIN wms_inventory i ON l.sku_id = i.sku_id
WHERE o.order_date > SYSDATE - 7;
```

**When to use**: When you know the optimal join order and optimizer is choosing wrong.

### LEADING: Set First Table in Join

```sql
-- Set specific first table
SELECT /*+ LEADING(o l i) */
    o.order_id,
    l.sku_id,
    i.location_id
FROM wms_order_headers o
JOIN wms_order_lines l ON o.order_id = l.order_id
JOIN wms_inventory i ON l.sku_id = i.sku_id;
```

---

## Chapter 4: Join Method Hints

### USE_NL: Force Nested Loops

```sql
-- Use nested loops for indexed lookups
SELECT /*+ ORDERED USE_NL(l i) */
    o.order_id,
    l.sku_id,
    i.location_id
FROM wms_order_headers o
JOIN wms_order_lines l ON o.order_id = l.order_id
JOIN wms_inventory i ON l.sku_id = i.sku_id
WHERE o.order_date > SYSDATE - 7;
```

**Best for**: Small result sets, indexed joins

### USE_HASH: Force Hash Join

```sql
-- Use hash join for large sets
SELECT /*+ USE_HASH(l i) */
    l.sku_id,
    SUM(l.quantity)
FROM wms_order_lines l
JOIN wms_inventory i ON l.sku_id = i.sku_id
GROUP BY l.sku_id;
```

**Best for**: Large tables, equi-joins, no useful indexes

### USE_MERGE: Force Sort-Merge Join

```sql
-- Use merge join
SELECT /*+ USE_MERGE(o l) */
    o.order_id,
    l.sku_id
FROM wms_order_headers o
JOIN wms_order_lines l ON o.order_id = l.order_id
WHERE o.status = 'COMPLETED';
```

**Best for**: Already sorted data, non-equi joins

---

## Chapter 5: Parallel Execution Hints

### PARALLEL: Enable Parallelism

```sql
-- Force parallel query with specific degree
SELECT /*+ PARALLEL(8) */
    region,
    SUM(total_value)
FROM wms_order_headers
WHERE order_date >= TRUNC(SYSDATE, 'MM')
GROUP BY region;

-- Parallel on specific table
SELECT /*+ PARALLEL(wms_order_headers, 8) */
    *
FROM wms_order_headers;
```

### PARALLEL_INDEX: Parallel Index Scan

```sql
-- Parallel index range scan
SELECT /*+ PARALLEL_INDEX(wms_inventory wms_inv_loc_idx, 8) */
    *
FROM wms_inventory
WHERE location_id LIKE 'PICK%';
```

---

## Chapter 6: The Manhattan Associates Hint Strategy

### Our Hint Guidelines

1. **Document the hint** - Why was it added?
2. **Plan to remove** - Fix the real problem
3. **Test thoroughly** - Hints can regress
4. **Monitor usage** - Track hint effectiveness

### Common Hint Patterns We Use

```sql
-- Pattern 1: Force index when optimizer misses
SELECT /*+ INDEX(wms_ord_date_idx) */
    *
FROM wms_order_headers
WHERE order_date BETWEEN SYSDATE - 30 AND SYSDATE;

-- Pattern 2: Parallel for reports
SELECT /*+ PARALLEL(8) FULL(h) */
    h.region,
    SUM(l.quantity * l.unit_price) AS total
FROM wms_order_headers h
JOIN wms_order_lines l ON h.order_id = l.order_id
WHERE h.order_date >= TRUNC(SYSDATE, 'YYYY')
GROUP BY h.region;

-- Pattern 3: Ordered join for known good order
SELECT /*+ ORDERED */
    *
FROM wms_order_headers h
JOIN wms_order_lines l ON h.order_id = l.order_id
JOIN wms_inventory i ON l.sku_id = i.sku_id
JOIN wms_locations loc ON i.location_id = loc.location_id
WHERE h.order_date > SYSDATE - 7;
```

---

## Conclusion: Use Hints Wisely

**Donald Sez**: "Hints are a powerful tool for experienced DBAs, but they're also a dangerous shortcut. Use them to fix immediate problems, but always work on the root cause."

At Manhattan Associates:
1. **Verify hints work** - Check v$sql_plan
2. **Document why** - Future DBAs will thank you
3. **Remove when fixed** - Don't make hints permanent
4. **Prefer statistics** - Often hints aren't needed with good stats

---

**Next**: "Oracle Partitioning: The Complete Guide for High-Volume WMS Tables" - Range, list, hash, and composite partitioning strategies.