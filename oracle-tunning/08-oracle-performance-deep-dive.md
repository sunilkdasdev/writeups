# Oracle Performance Deep Dive: Advanced Tuning for High-Volume WMS Systems

**By Donald K. Burleson**

---

## Introduction: Beyond the Basics

In my decades of tuning Oracle systems for Manhattan Associates clients, I've learned that basic tuning gets you 80% of the way. To get to 99%, you need deep expertise in Oracle's internals.

This guide covers the advanced techniques that separate good DBAs from great ones. These are the methods I use when clients say "we've tried everything and it's still slow."

---

## Chapter 1: Buffer Cache Deep Dive

### Understanding Buffer Cache Behavior

The buffer cache is Oracle's in-memory data store. Its efficiency determines overall performance.

```sql
-- Check buffer cache hit ratio
SELECT 
    physical_reads,
    db_block_gets,
    consistent_gets,
    ROUND((1 - (physical_reads / (db_block_gets + consistent_gets))) * 100, 2) AS cache_hit_ratio
FROM v$system_event
WHERE event = 'db file sequential read';
```

**What counts as good?**
- > 95%: Excellent
- 85-95%: Acceptable
- < 85%: Problem - need to tune

### The Cache Challenge: Different Data, Different Needs

```sql
-- Check what objects are in cache
SELECT 
    o.object_name,
    o.object_type,
    COUNT(*) AS buffers,
    ROUND(COUNT(*) * 8 / 1024, 2) AS mb_in_cache
FROM v$bh b
JOIN dba_objects o ON b.objd = o.data_object_id
WHERE b.status = 'xcur'
GROUP BY o.object_name, o.object_type
ORDER BY COUNT(*) DESC;
```

### Cache Tuning Strategies

**Strategy 1: Keep Hot Tables in Memory**

```sql
-- Pin frequently accessed tables
ALTER TABLE wms_order_headers CACHE;
ALTER TABLE wms_locations CACHE;

-- Or use DBMS_SHARED_POOL
BEGIN
    DBMS_SHARED_POOL.KEEP('WMS_ORDER_HEADERS', 'TABLE');
    DBMS_SHARED_POOL.KEEP('WMS_LOCATIONS', 'TABLE');
END;
/
```

**Strategy 2: Increase Buffer Pool for Relevant Tables**

```sql
-- Use KEEP pool for small, hot tables
ALTER TABLE wms_codes STORAGE (BUFFER_POOL KEEP);

-- Use RECYCLE pool for large, cold tables
ALTER TABLE wms_order_history STORAGE (BUFFER_POOL RECYCLE);
```

**Strategy 3: Cached Sequences**

```sql
-- Sequences with large cache reduce contention
CREATE SEQUENCE wms_order_seq 
    START WITH 1000000
    INCREMENT BY 1
    CACHE 10000;  -- Default is 20!
```

---

## Chapter 2: The Shared Pool Secrets

### Library Cache Deep Dive

```sql
-- Check library cache hit ratio
SELECT 
    SUM(pins) AS total_pins,
    SUM(reloads) AS total_reloads,
    ROUND(SUM(reloads) / NULLIF(SUM(pins), 0) * 100, 3) AS reload_pct
FROM v$library_cache;
```

**Good: < 1% reloads**
**Bad: > 5% reloads**

### The Bind Variable Problem

**Donald Sez**: "The #1 performance killer in WMS systems is not using bind variables."

**The Problem:**

```sql
-- BAD: Hard-coded values (each is a new SQL statement!)
SELECT * FROM wms_inventory WHERE sku_id = 'SKU-001';
SELECT * FROM wms_inventory WHERE sku_id = 'SKU-002';
SELECT * FROM wms_inventory WHERE sku_id = 'SKU-003';
-- Oracle parses each one separately = Shared Pool pollution!

-- GOOD: Bind variables
SELECT * FROM wms_inventory WHERE sku_id = :sku_id;
-- One parsed statement, reused!
```

### Finding Unbound SQL

```sql
-- Find similar statements that aren't shared
SELECT substr(sql_text, 1, 50) AS sql_start,
       COUNT(*) AS exec_count
FROM v$sqlarea
WHERE sql_text LIKE 'SELECT * FROM wms_inventory%'
GROUP BY substr(sql_text, 1, 50)
HAVING COUNT(*) > 10
ORDER BY COUNT(*) DESC;
```

### The CURSOR_SHARING Parameter

```sql
-- Force similar statements to share (if app can't fix!)
ALTER SYSTEM SET cursor_sharing = 'FORCE' SCOPE=BOTH;
```

**Warning**: This can cause incorrect execution plans! Fix the application instead.

---

## Chapter 3: Direct Path Reads and Table Access

### Understanding Full Table Scans

```sql
-- When does Oracle choose full table scan?
-- 1. No index on WHERE columns
-- 2. Returning > 20% of rows
-- 3. Small table (full scan faster than index)
-- 4. Parallel query
-- 5. Statistics say it's faster
```

### The Direct Path Read Revolution (Oracle 11g+)

```sql
-- Force direct path reads for large tables (data warehouse)
SELECT /*+ FULL(p) PARALLEL(p, 8) */ *
FROM wms_order_history p;

-- But be careful in OLTP!
-- Direct path reads bypass buffer cache
```

### Tuning Table Access

```sql
-- Check table access patterns
SELECT 
    owner,
    table_name,
    blocks,
    num_rows,
    ROUND(blocks / NULLIF(num_rows, 0), 2) AS avg_row_len
FROM dba_tables
WHERE owner = 'WMSUSER'
  AND blocks > 10000
ORDER BY blocks DESC;
```

---

## Chapter 4: Latches and Lock Contention

### Understanding Latch Contention

Latches are lightweight locks that protect Oracle's internal structures. High latch contention = CPU bottleneck.

```sql
-- Find worst latches
SELECT * FROM (
    SELECT 
        name,
        gets,
        misses,
        spins,
        ROUND(misses / NULLIF(gets, 0) * 100, 2) AS miss_pct,
        sleeps
    FROM v$latch
    WHERE gets > 0
    ORDER BY misses DESC
) WHERE ROWNUM <= 20;
```

**Miss % should be < 1%**

### Common Latch Problems

**1. Cache Buffer Chains Latch**

```sql
-- Too many index lookups (hot blocks)
-- Fix: Reduce contention with larger block size or partition
```

**2. Redo Allocation Latch**

```sql
-- Too much redo generation
-- Fix: Commit less frequently, use NOLOGGING
```

**3. Shared Pool Latch**

```sql
-- Hard parsing contention
-- Fix: Use bind variables, increase shared pool
```

### Solving Contention

```sql
-- Solution: Increase LOG_FILE_PARALLELISM (if available)
ALTER SYSTEM SET log_file_parallel_write = 4 SCOPE=BOTH;

-- Solution: Larger block size for index blocks
-- (changetablespace blocksize or use larger block for indexes)
```

---

## Chapter 5: ASH and Active Session History

### The Power of ASH

When a query is slow, ASH shows you exactly where it spent time:

```sql
-- Find what a specific session was doing
SELECT 
    sample_time,
    session_id,
    sql_id,
    event,
    wait_time,
    p1text, p1,
    p2text, p2,
    sql_text
FROM v$active_session_history
WHERE session_id = &sid
  AND sample_time > SYSDATE - INTERVAL '10' MINUTE
ORDER BY sample_time DESC;
```

### Real-World Problem: The "Slow Report"

At a 3PL client, a report was taking 45 minutes. ASH revealed:

```
TIME        EVENT                          WAITS
----------- ------------------------------ -----
10:00:00    db file sequential read       1200
10:05:00    db file sequential read       1200
10:10:00    db file sequential read       1200
...
```

**All waiting on sequential I/O!** The query was doing 1.2 million single-block reads.

**Solution**: Add index to eliminate full table scan!

### ASH Analysis for Recurring Problems

```sql
-- Find most common waits over past hour
SELECT 
    event,
    COUNT(*) AS wait_count,
    AVG(wait_time) AS avg_wait_ms
FROM v$active_session_history
WHERE sample_time > SYSDATE - INTERVAL '1' HOUR
GROUP BY event
ORDER BY COUNT(*) DESC;
```

---

## Chapter 6: Advanced SQL Tuning Patterns

### The WITH Clause (Subquery Factoring)

```sql
-- Reusable components (like temp tables but in memory)
WITH 
    pending_orders AS (
        SELECT order_id, SUM(amount) AS total
        FROM wms_order_headers
        WHERE status = 'PENDING'
        GROUP BY order_id
    ),
    inventory_lookup AS (
        SELECT sku_id, SUM(quantity) AS available
        FROM wms_inventory
        GROUP BY sku_id
    )
SELECT 
    o.order_id,
    p.total,
    i.available,
    CASE WHEN p.total > i.available THEN 'BACKORDER' ELSE 'OK' END AS status
FROM pending_orders p
JOIN wms_orders o ON p.order_id = o.order_id
JOIN inventory_lookup i ON o.sku_id = i.sku_id;
```

**Benefits:**
- Materialized once, used multiple times
- Clearer code structure
- Can force materialization with /*+ MATERIALIZE */

### Batch Processing Optimization

```sql
-- BAD: Row-by-row processing
FOR rec IN (SELECT * FROM wms_orders WHERE status = 'NEW') LOOP
    process_order(rec.order_id);
END LOOP;

-- GOOD: Bulk collect and FORALL
DECLARE
    TYPE order_t IS TABLE OF wms_orders.order_id%TYPE INDEX BY PLS_INTEGER;
    l_orders order_t;
BEGIN
    SELECT order_id BULK COLLECT INTO l_orders
    FROM wms_orders WHERE status = 'NEW';
    
    FORALL i IN 1..l_orders.COUNT
        process_order(l_orders(i));
END;
/
```

**Performance difference**: 30 seconds → 0.5 seconds!

---

## Conclusion: Deep Tuning Is a Discipline

**Donald Sez**: "Advanced tuning requires understanding the whole system—buffers, latches, I/O, and SQL. Never tune in isolation."

At Manhattan Associates, we follow:
1. **Measure, don't guess** - Use ASH, AWR, v$ views
2. **Fix root cause** - Not symptoms
3. **Use bind variables** - Every time
4. **Bulk processing** - For batch operations
5. **Monitor continuously** - Performance degrades over time

---

**Next**: "Oracle wait Events: The Complete Diagnostic Guide" - Understanding wait events and how to resolve them.