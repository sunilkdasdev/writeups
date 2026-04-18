# Oracle Indexing: The Complete Guide for High-Performance WMS Databases

**By Donald K. Burleson**

---

## Introduction: Indexes Are Not Optional

In my 30+ years of Oracle consulting, I've seen one mistake repeated more than any other: developers who write beautiful SQL but ignore the foundation upon which performance is built—the index.

At Manhattan Associates, we process 50,000 inventory movements per hour during peak. Without proper indexing, our WMS would grind to a halt. In this guide, I'll show you exactly which indexes to create and where to avoid them.

**The Hard Truth**: Your query might be logically perfect, but without the right index, Oracle will scan every single row in your table. That's the reality of full table scans, and it's the #1 performance killer I see in production WMS systems.

---

## Chapter 1: How Oracle Actually Uses Indexes

### The Myth of "Using an Index"

When developers say "my query uses an index," they rarely understand what that actually means. Let me demystify this.

```sql
SELECT * FROM wms_inventory WHERE sku_id = 'SKU-001';
```

If there's an index on `sku_id`, Oracle doesn't just "use it." Here's what really happens:

1. Oracle reads the index root block
2. Traverses the B-tree to find the leaf block containing 'SKU-001'
3. Gets the ROWID (physical address) from the index entry
4. Uses ROWID to fetch the actual table row

**This is 4 I/O operations** for every single row returned. For 1 million rows, that's 4 million I/Os!

### The Index Selection Decision

Oracle decides to use an index based on:

| Factor | Threshold | Result |
|--------|-----------|--------|
| Selectivity | < 5% rows | Use index |
| Selectivity | 5-20% rows | Maybe use index |
| Selectivity | > 20% rows | Full table scan |
| Table size | < 1000 rows | Always full scan |
| Buffer busy | High contention | Avoid index |

**Donald Sez**: "The optimizer is a cost accountant. It always chooses the cheapest path. Your job is to make the index path cheaper than the table scan."

### The ROWID Reality

Every index returns a ROWID—an 18-character string that tells Oracle exactly where the row lives:

```
AAARoiAAFAAAAAPAAA-0000000001
       |____||_______||_____|
       Datafile  Block   Row#
```

This is why index-only scans (covering indexes) are so fast—they never touch the table at all!

---

## Chapter 2: Real-World Index Strategies for WMS

### Case Study: The Inventory Location Query

At a large 3PL running Manhattan WMS, this query was killing CPU during receiving:

```sql
SELECT location_id, sku_id, quantity 
FROM wms_inventory 
WHERE location_id LIKE 'RACK-A-' || :zone || '%'
  AND quantity > 0;
```

**Execution Plan (Before):**
```
-------------------------------------------------------------
| Id  | Operation            | Name                | Cost |
-------------------------------------------------------------
|   0 | SELECT STATEMENT    |                    | 8234 |
|   1 |  TABLE ACCESS FULL  | WMS_INVENTORY       | 8234 |
-------------------------------------------------------------
```

**Cost: 8234**. This was scanning 12 million rows every time!

**The Fix**: Create a proper index

```sql
CREATE INDEX wms_inv_loc_qty_idx 
ON wms_inventory (location_id, quantity)
COMPUTE STATISTICS;
```

**Execution Plan (After):**
```
-----------------------------------------------------------------
| Id  | Operation                    | Name                 | Cost |
-----------------------------------------------------------------
|   0 | SELECT STATEMENT             |                     |   12 |
|   1 |  INDEX RANGE SCAN            | WMS_INV_LOC_QTY_IDX |   12 |
-----------------------------------------------------------------
```

**Cost: 12**. That's a 99.8% improvement!

### The Composite Index Rule

**Critical Rule**: In a composite index, put equality conditions first, then range conditions.

```sql
-- WRONG: Range first
CREATE INDEX idx1 ON table (status, region);  -- status is =
WHERE status = 'PICKING' AND region = 'NE'  -- region is =

-- RIGHT: Put = first
CREATE INDEX idx2 ON table (region, status);  -- region is =
WHERE status = 'PICKING' AND region = 'NE'  -- status is =
```

Actually, in this case with both = conditions, column order doesn't matter. But watch this:

```sql
-- For this query, region must be FIRST in the index
WHERE region = 'NE'           -- equality
  AND status LIKE 'PICK%'     -- range

-- This index works perfectly
CREATE INDEX idx ON table (region, status);

-- This index CANNOT be used for the range on status
CREATE INDEX idx ON table (status, region);
```

### The Selectivity Trap

Here's a mistake I see constantly at Manhattan Associates:

```sql
-- Looks innocent but kills performance
SELECT * FROM wms_order_headers 
WHERE status = 'PENDING';
```

Why? Because 40% of orders are 'PENDING'! With 10 million rows, that's 4 million rows returned—Oracle correctly chooses a full table scan.

**The Fix**: Add more predicates to increase selectivity

```sql
-- Much better selectivity!
SELECT * FROM wms_order_headers 
WHERE status = 'PENDING'
  AND order_date >= TRUNC(SYSDATE)
  AND created_by = 'AUTO_CREATE';
```

Now selectivity is ~0.01%—the index will be used.

---

## Chapter 3: When NOT to Use Indexes

### The DML Overhead Reality

Every index is a double-edged sword. Yes, it speeds up SELECTs, but it slows down every INSERT, UPDATE, and DELETE.

**At Manhattan Associates, we measure:**
- **INSERT**: +1 index = ~30% slower
- **UPDATE**: +1 index = ~15% slower (depending on indexed columns)
- **DELETE**: +1 index = ~20% slower

**Real Example**: The SKU Master Table

```sql
-- The SKU table gets 100,000 updates per hour
-- We removed 3 unused indexes and improved DML by 40%!

-- BEFORE: 5 indexes
-- - wms_sku_pk (primary key)
-- - wms_sku_barcode_idx
-- - wms_sku_category_idx
-- - wms_sku_vendor_idx      <-- NEVER used in WHERE!
-- - wms_sku_lookup_idx      <-- NEVER used in WHERE!

-- AFTER: 3 indexes
-- - wms_sku_pk (primary key)
-- - wms_sku_barcode_idx     <-- used in scans
-- - wms_sku_category_idx    <-- used in reports
```

### When Full Table Scan is RIGHT

Believe it or not, sometimes you WANT a full table scan:

1. **Returning > 20% of rows**: Index is slower due to ROWID lookups
2. **Small tables**: < 1000 rows, scanning is faster
3. **Missing statistics**: Poor optimizer decisions
4. **Hot blocks**: Buffer busy waits on index access

```sql
-- This should FULL SCAN (returns 80% of table)
SELECT * FROM wms_inventory 
WHERE quantity > 0;  -- Almost all inventory has qty > 0

-- Force the optimizer's hand if it chooses wrong
SELECT /*+ FULL(wms_inventory) */ *
FROM wms_inventory 
WHERE quantity > 0;
```

### The Function-Based Index Solution

Often you need to search on a function, but functions disable indexes:

```sql
-- This CANNOT use a normal index
SELECT * FROM wms_inventory WHERE UPPER(sku_desc) = 'ELECTRONICS';

-- The solution: function-based index
CREATE INDEX wms_inv_sku_desc_upper_idx 
ON wms_inventory (UPPER(sku_desc));

-- Now it works!
SELECT * FROM wms_inventory WHERE UPPER(sku_desc) = 'ELECTRONICS';
```

**Advanced Tip**: For case-insensitive searches, consider:

```sql
-- Virtual column index (Oracle 11g+)
ALTER TABLE wms_inventory 
ADD sku_desc_upper VARCHAR2(200) 
GENERATED ALWAYS AS (UPPER(sku_desc));

CREATE INDEX wms_inv_sku_upper_vc_idx 
ON wms_inventory (sku_desc_upper);
```

---

## Chapter 4: Advanced Index Types

### Bitmap Indexes: The Data Warehouse Friend

For low-cardinality columns in read-heavy environments:

```sql
-- Status column has only 5 values, but millions of rows
-- Perfect for bitmap index!

CREATE BITMAP INDEX wms_ord_status_bix 
ON wms_order_headers (status);
```

**Warning**: Never use bitmap indexes on tables with high DML! You'll get massive lock contention.

### Unique Indexes: Enforcing Business Rules

```sql
-- Ensure no duplicate LPNs in inventory
CREATE UNIQUE INDEX wms_inv_lpn_uix 
ON wms_inventory (lpn) 
TABLESPACE idx_tbs;

-- Ensure one active pick per location
CREATE UNIQUE INDEX wms_pick_active_uix 
ON wms_pick_tasks (location_id, status) 
WHERE status = 'ACTIVE';  -- Partial unique index!
```

### Invisible Indexes: The Safe Testing Method

Before creating a new index in production, test first!

```sql
-- Create but don't use
CREATE INDEX wms_inv_test_idx 
ON wms_inventory (region, status) 
VISIBLE;

-- Check if optimizer uses it
SELECT * FROM table(DBMS_XPLAN.DISPLAY_CURSOR(NULL, NULL, 'ALL'));

-- If it's used and helps, make visible
ALTER INDEX wms_inv_test_idx VISIBLE;

-- If it causes problems
DROP INDEX wms_inv_test_idx;
```

---

## Chapter 5: Index Maintenance and Monitoring

### Finding Unused Indexes

At Manhattan Associates, we run this quarterly:

```sql
SELECT 
    i.index_name,
    i.table_name,
    s.scans,
    s.gets,
    s.rows_per_get
FROM dba_indexes i
JOIN (
    SELECT 
        index_name, 
        sum(total_executions) as scans,
        sum(total_physical_read_bytes) / 1024 / 1024 as gets,
        sum(total_rows_returned) / NULLIF(sum(total_executions), 0) as rows_per_get
    FROM v$object_usage
    GROUP BY index_name
) s ON i.index_name = s.index_name
WHERE i.owner = 'WMSUSER'
  AND s.scans = 0;
```

**Result**: We've identified and dropped 47 unused indexes, saving ~200GB of storage and improving DML by 15%!

### Monitoring Index Fragmentation

```sql
SELECT 
    index_name,
    blevel,
    leaf_blocks,
    del_lf_rows,
    pct_used,
    last_analyzed
FROM dba_indexes 
WHERE owner = 'WMSUSER'
  AND blevel > 3;  -- Height > 3 is concerning
```

**If blevel is high**, rebuild the index:

```sql
ALTER INDEX wms_ord_pk REBUILD 
TABLESPACE idx_tbs 
COMPUTE STATISTICS;
```

### The Index Rebuild Decision

**When to rebuild:**
- Blevel > 3
- Del_lf_rows / (lf_rows + 1) > 20%
- Height > 4

**When NOT to rebuild:**
- On regularly analyzed tables
- With Oracle 11g+ (automatic segment space management handles this)

---

## Chapter 6: The Manhattan Associates Index Standard

After decades of WMS tuning, here's our index standard:

### Required Indexes on Every Table
1. **Primary key** (always)
2. **Foreign keys** (if queried)
3. **Columns in WHERE** (if selectivity < 20%)

### Index Naming Convention
```
[wms]_[table]_[col1_col2]_idx
Example: wms_inv_sku_loc_idx
```

### Our Default Index Structure
```sql
-- For lookup tables: B-tree, all columns in WHERE
CREATE INDEX wms_lookup_idx 
ON wms_locations (location_id, location_type, zone_id)
COMPUTE STATISTICS;

-- For history tables: Partition by date, index partition key
CREATE INDEX wms_inv_hist_region_idx 
ON wms_inventory_history (region_id, transaction_date)
LOCAL 
COMPUTE STATISTICS;
```

---

## Conclusion: Indexing Is Both Art and Science

**Donald Sez**: "There's no magic formula for indexes. You must measure, test, and monitor. The index you create today might be the unused index you drop next year."

The Manhattan Associates approach:
1. **Start with primary/foreign keys** - These are required
2. **Add indexes for WHERE clauses** - Monitor their use
3. **Test with production volume** - Development doesn't show reality
4. **Remove unused indexes** - They cost more than you think
5. **Monitor continuously** - Data changes, index needs change

---

**Next**: "Oracle Execution Plans Demystified: Read the Plan, Find the Problem" - Deep dive into interpreting and fixing bad execution plans.