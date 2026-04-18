# Elasticsearch Internals and Deep Dive

## Table of Contents

1. [Cluster Architecture and Node Roles](#1-cluster-architecture-and-node-roles)
2. [Lucene Index Structure](#2-lucene-index-structure)
3. [Document Indexing Pipeline](#3-document-indexing-pipeline)
4. [Query Execution and Query Planning](#4-query-execution-and-query-planning)
5. [Aggregation Internals](#5-aggregation-internals)
6. [Memory Management and Caching](#6-memory-management-and-caching)
7. [Data Tier Architecture](#7-data-tier-architecture)
8. [Sharding and Rebalancing](#8-sharding-and-rebalancing)
9. [Search and Indexing Performance](#9-search-and-indexing-performance)
10. [Security Implementation](#10-security-implementation)
11. [Troubleshooting and Diagnostics](#11-troubleshooting-and-diagnostics)

---

## 1. Cluster Architecture and Node Roles

### 1.1 Master Node Responsibilities

```java
// Master node election and responsibilities
public class MasterNodeResponsibilities {
    
    /**
     * ┌─────────────────────────────────────────────────────────────────────┐
     │                    MASTER NODE                                      │
     ├─────────────────────────────────────────────────────────────────────┤
     │                                                                      │
     │  Cluster State Management:                                          │
     │  - Version: monotonically increasing                               │
     │  - Contents:                                                        │
     │    - Nodes in cluster                                               │
     │    - Index settings, mappings                                       │
     │    - Allocation decisions                                           │
     │    - Routing table                                                  │
     │                                                                      │
     │  Index Creation/Deletion:                                          │
     │  - Create index with settings/mappings                              │
     │  - Delete index                                                     │
     │  - Update cluster state                                             │
     │                                                                      │
     │  Shard Allocation:                                                  │
     │  - Decide which node gets which shard                              │
     │  - Rebalance after node join/leave                                 │
     │  - Handle failed shard recovery                                    │
     │                                                                      │
     │  Node Management:                                                   │
     │  - Detect node failure                                              │
     │  - Exclude nodes with high error rate                              │
     │  - Coordinate topology updates                                      │
     │                                                                      │
     └─────────────────────────────────────────────────────────────────────┘
     */
    
    /**
     * Minimum Master Nodes:
     * 
     * discovery.zen.minimum_master_nodes = (N/2) + 1
     * 
     * For 3-node cluster: 2
     * For 5-node cluster: 3
     * 
     * Purpose: Prevent split-brain
     * - Must have quorum to form cluster
     * - Split brain = two masters, inconsistent state
     */
    
    /**
     * In Elasticsearch 7+ (Zen2 Discovery):
     * 
     * - No more minimum_master_nodes
     * - Uses voting config
     * - Auto-adjusts voting config on node changes
     * - discovery.seed_hosts (list of master-eligible nodes)
     */
}
```

### 1.2 Data Node Architecture

```java
// Data node internals
public class DataNodeArchitecture {
    
    /**
     * ┌─────────────────────────────────────────────────────────────────────┐
     │                      DATA NODE                                       │
     ├─────────────────────────────────────────────────────────────────────┤
     │                                                                      │
     │  ┌──────────────────────────────────────────────────────────────────┐│
     │  │                Index (Shard)                                    ││
     │  │                                                                   ││
     │  │  ┌─────────────┐ ┌─────────────┐ ┌─────────────┐                ││
     │  │  │   Segments  │ │   Segments  │ │   Segments  │                ││
     │  │  │  (cfs/cfe)  │ │  (cfs/cfe)  │ │  (cfs/cfe)  │                ││
     │  │  └─────────────┘ └─────────────┘ └─────────────┘                ││
     │  │                                                                   ││
     │  │  Translog: Transaction log for durability                       ││
     │  │                                                                   ││
     │  └──────────────────────────────────────────────────────────────────┘│
     │                                                                      │
     │  ┌──────────────────────────────────────────────────────────────────┐│
     │  │                  In-Memory Structures                           ││
     │  │  - Index cache                                                   ││
     │  │  - Field data cache                                             ││
     │  │  - Request cache                                                ││
     │  │  - Query result cache                                           ││
     │  └──────────────────────────────────────────────────────────────────┘│
     │                                                                      │
     │  ┌──────────────────────────────────────────────────────────────────┐│
     │  │                  Node-Level Components                          ││
     │  │  - ShardController: Manage shards on this node                 ││
     │  │  - MemoryPool: Allocation for segments                          ││
     │  │  - CircuitBreaker: Prevent OOM                                  ││
     │  └──────────────────────────────────────────────────────────────────┘│
     │                                                                      │
     └─────────────────────────────────────────────────────────────────────┘
     */
    
    /**
     * Shard Types:
     * 
     * Primary Shard:
     * - Handles all writes
     * - Created when index created
     * - Can be explicitly set: 1-50 per index
     * 
     * Replica Shard:
     * - Copy of primary, for redundancy
     * - Handles reads (load balancing)
     * - Can be changed without recreating index
     * - Total shards = (1 + number_of_replicas) * number_of_primary_shards
     */
}
```

---

## 2. Lucene Index Structure

### 2.1 Segment Files Explained

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                      ELASTICSEARCH/LUCENE INDEX                             │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  Index (shard):                                                              │
│  ├─ segments_N                # Segment metadata                            │
│  │  - Names of all segments                                                │
│  │  - Files in each segment                                                │
│  │  - Generation counter                                                   │
│  │                                                                          │
│  ├─ *.cfs                    # Compound file (combined)                    │
│  │  ├── _0.cfe                # Compound field entries                      │
│  │  └── _0.cfs               # Compound field data                         │
│  │                                                                          │
│  ┌─┐                          # Individual segment files (if non-compound) │
│  ││  _0.si                    # Segment info                                │
│  ││  _0.fnm                   # Fields                                     │
│  ││  _0.fdx                   # Field data index                           │
│  ││  _0.fdt                   # Field data                                 │
│  ││  _0.tip                   # Term index (FST for dictionary)            │
│  ││  _0.tip                   # Term index                                 │
│  ││  _0.doc                   # Doc values (posting lists)                 │
│  ││  _0.pos                   # Positions                                  │
│  ││  _0.term                  # Term vectors                              │
│  ││  _0.nrm                   # Norms                                      │
│  ││  _0.blo                   # Bloom filter                               │
│  ││  _0.bst                   # Index sort                                 │
│  ││                                                                          │
│  ├─ write.lock                # Write lock                                  │
│  │                                                                          │
│  └─ .lock                     # Index lock                                  │
│                                                                              │
│  Segment Naming:                                                             │
│  - Segments are named by sequence number: _0, _1, _2, ...                   │
│  - New segment created on: flush, merge, index close                        │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

### 2.2 Inverted Index Deep Dive

```java
// Inverted index structure
public class InvertedIndexDeepDive {
    
    /**
     * Inverted Index Structure:
     * 
     * ┌─────────────────────────────────────────────────────────────────────┐
     │                        INVERTED INDEX                                │
     ├─────────────────────────────────────────────────────────────────────┤
     │                                                                      │
     │  Term Dictionary: (Sorted by term)                                  │
     │  ┌───────────────┬─────────────────────────────────────────────┐    │
     │  │    Term       │        Posting List (Doc IDs)               │    │
     │  ├───────────────┼─────────────────────────────────────────────┤    │
     │  │   "orders"    │  [1, 5, 12, 23, 45, 89, ...]                │    │
     │  │   "warehouse" │  [2, 8, 15, 44, ...]                        │    │
     │  │   "shipped"   │  [3, 7, 11, 19, 33, ...]                     │    │
     │  └───────────────┴─────────────────────────────────────────────┘    │
     │                                                                      │
     │  ┌──────────────────────────────────────────────────────────────┐   │
     │  │ Each posting contains:                                       │   │
     │  │ - Doc ID                                                     │   │
     │  │ - Term frequency (tf)                                        │   │
     │  │ - Position (for phrase queries)                             │   │
     │  │ - Payload (for custom data)                                  │   │
     │  │ - Norms (for field-length normalization)                     │   │
     │  └──────────────────────────────────────────────────────────────┘   │
     │                                                                      │
     └─────────────────────────────────────────────────────────────────────┘
     */
    
    /**
     * FST (Finite State Transducer) - Term Index:
     * 
     * - Stored in .tip file
     * - Maps term prefixes to block locations in term dictionary
     * - Enables fast term lookup
     * - Very compact, in-memory
     * 
     * Example: For terms [cat, catering, cathedral]
     * 
     *        (start)
     *           |
     *          c-a-t [block: cats]
     *           |
     *         -t-e-r [block: catering*]
     *           |
     *        -h-e-d-r-a-l [block: cathedral*]
     */
    
    /**
     * Posting List Compression:
     * 
     * - Lucene uses FOR (Fast Optimized RLE) encoding
     * - Block-based: 128 docs per block
     * - Delta encoding within block
     * - Bitmap for sparse docs (for highly repetitive)
     * 
     * Example: [1, 5, 12, 23] -> encoded as [1, 4, 7, 11] (deltas)
     */
}
```

---

## 3. Document Indexing Pipeline

### 3.1 Index Request Flow

```java
// Document indexing flow
public class IndexingPipeline {
    
    /**
     * ┌─────────────────────────────────────────────────────────────────────┐
     │                      INDEXING PIPELINE                               │
     ├─────────────────────────────────────────────────────────────────────┤
     │                                                                      │
     │  Client Request:                                                      │
     │  POST /orders/_doc { "order_id": "12345", "total": 100.00 }         │
     │                              │                                        │
     │                              ▼                                        │
     │  ┌──────────────────────────────────────────────────────────────────┐│
     │  │              Coordinating Node (any data node)                   ││
     │  │  - Parses request                                               ││
     │  │  - Validates document                                           ││
     │  │  - Determines target shard (routing)                            ││
     │  │  - Replicas: (primary + replicas)                               ││
     │  └──────────────────────────────────────────────────────────────────┘│
     │                              │                                        │
     │                              ▼                                        │
     │  ┌──────────────────────────────────────────────────────────────────┐│
     │  │              Primary Shard Node                                  ││
     │  │  - Parse JSON to Fields                                         ││
     │  │  - Analyzer tokenization                                        ││
     │  │  - Generate inverted index terms                                ││
     │  │  - Write to Translog (before commit)                            ││
     │  │  - Add to in-memory buffer                                      ││
     │  └──────────────────────────────────────────────────────────────────┘│
     │                              │                                        │
     │                  Wait for replication to replicas                    │
     │                              ▼                                        │
     │  ┌──────────────────────────────────────────────────────────────────┐│
     │  │              Replica Shard Nodes                                 ││
     │  │  - Apply same indexing logic                                    ││
     │  │  - Translog write                                               ││
     │  │  - Acknowledge to primary                                       ││
     │  └──────────────────────────────────────────────────────────────────┘│
     │                              │                                        │
     │                              ▼                                        │
     │  Response to client                                                   │
     │                                                                      │
     └─────────────────────────────────────────────────────────────────────┘
     */
    
    /**
     * Index Buffer and Refresh:
     * 
     * indices.memory.index_buffer_size = 10% (default)
     * 
     * Buffer fills -> refresh() called:
     * - Creates new Lucene segment from in-memory data
     * - New segment searchable immediately
     * - index.refresh_interval = 1s (default)
     * - Can be disabled for bulk indexing
     */
    
    /**
     * Translog:
     * 
     * - Write-ahead log for durability
     * - Every indexed document first written to translog
     * - Survives crash (within translog flush interval)
     * - translog.durability = request (default) or async
     * - translog.flush_threshold_size = 512MB (default)
     */
}
```

### 3.2 Analysis Pipeline

```java
// Analysis and tokenization
public class AnalysisPipeline {
    
    /**
     * Text Analysis Flow:
     * 
     * Input: "The quick brown fox jumps over the lazy dog"
     *                │
     *                ▼
     * ┌──────────────────────────────────────────────────────────────────┐
     │                 Character Filter(s)                               │
     │  - HTML strip: <b> → (removed)                                   │
     │  - Mapping: 'stop' → ' STOP '                                    │
     │  - Pattern: replace digits with #                                 │
     └──────────────────────────────────────────────────────────────────┘
     *                │
     *                ▼
     * ┌──────────────────────────────────────────────────────────────────┐
     │                 Tokenizer                                          │
     │  Standard: splits on whitespace/punctuation                       │
     │  Input: "The quick brown fox jumps over the lazy dog"            │
     │  Output: [The, quick, brown, fox, jumps, over, the, lazy, dog]  │
     └──────────────────────────────────────────────────────────────────┘
     *                │
     *                ▼
     * ┌──────────────────────────────────────────────────────────────────┐
     │                 Token Filter(s)                                    │
     │  - lowercase: [the, quick, brown, fox, jumps, over, the, lazy, dog]
     │  - stop: [quick, brown, fox, jumps, over, lazy, dog]
     │  - asciifolding: handle accents
     │  - snowball: stem to root form
     │  - edge_ngram: generate autocomplete tokens                       │
     └──────────────────────────────────────────────────────────────────┘
     *                │
     *                ▼
     * ┌──────────────────────────────────────────────────────────────────┐
     │                 Indexed Terms                                     │
     │  Inverted index now contains stemmed, normalized tokens          │
     └──────────────────────────────────────────────────────────────────┘
     */
    
    /**
     * Custom Analyzer Example:
     */
    
    /*
     PUT /orders
     {
       "settings": {
         "analysis": {
           "analyzer": {
             "warehouse_analyzer": {
               "type": "custom",
               "char_filter": ["html_strip"],
               "tokenizer": "standard",
               "filter": [
                 "lowercase",
                 "asciifolding",
                 "warehouse_synonym",
                 "snowball_english"
               ]
             }
           },
           "filter": {
             "warehouse_synonym": {
               "type": "synonym",
               "synonyms": [
                 "wh,warehouse,distribution center",
                 "sku,product,item"
               ]
             }
           }
         }
       }
     }
     */
    
    /**
     * Runtime Field Analysis:
     * 
     * POST /orders/_search
     * {
     *   "runtime_mappings": {
     *     "order_category": {
     *       "type": "keyword",
     *       "script": {
     *         "source": "if (doc['total'].value > 1000) { emit('premium'); } else { emit('standard'); }"
     *       }
     *     }
     *   }
     * }
     */
}
```

---

## 4. Query Execution and Query Planning

### 4.1 Query Phase Deep Dive

```java
// Query execution flow
public class QueryExecutionFlow {
    
    /**
     * ┌─────────────────────────────────────────────────────────────────────┐
     │                    QUERY PHASE                                        │
     ├─────────────────────────────────────────────────────────────────────┤
     │                                                                      │
     │  Client Request:                                                      │
     │  GET /orders/_search?q=status:pending                                │
     │                              │                                        │
     │                              ▼                                        │
     │  ┌──────────────────────────────────────────────────────────────────┐│
     │  │              Coordinating Node                                   ││
     │  │  - Parse query to Lucene Query                                    ││
     │  │  - Create SearchRequest with shards list                         ││
     │  │  - Send to all relevant shard copies (primary or replica)        ││
     │  └──────────────────────────────────────────────────────────────────┘│
     │                              │                                        │
     │                              ▼                                        │
     │  ┌──────────────────────────────────────────────────────────────────┐│
     │  │              Each Shard Executes Query                           ││
     │  │                                                                   ││
     │  │  1. Query Planning:                                              ││
     │  │     - Rewrite: Expand match_all to terms, etc.                   ││
     │  │     - Create weight tree from query                              ││
     │  │     - Determine execution plan (index or data nodes)            ││
     │  │                                                                   ││
     │  │  2. Get Relevant Docs:                                           ││
     │  │     - Iterate inverted index                                     ││
     │  │     - Collect matching document IDs                              ││
     │  │     - Score documents (TF-IDF or BM25)                          ││
     │  │                                                                   ││
     │  │  3. Fetch from index:                                            ││
     │  │     - Retrieve stored fields                                    ││
     │  │     - Apply field collapsing                                     ││
     │  │     - Build top N results                                        ││
     │  │                                                                   ││
     │  │  4. Return Results:                                              ││
     │  │     - Return top 100 (default) docs + highlight                 ││
     │  │     - Include aggregation results                                ││
     │  │     - Return search context for fetch phase                     ││
     │  └──────────────────────────────────────────────────────────────────┘│
     │                              │                                        │
     │                              ▼                                        │
     │  ┌──────────────────────────────────────────────────────────────────┐│
     │  │              Coordinating Node Reduces                          ││
     │  │  - Merge top N from each shard                                   ││
     │  │  - Sort to get global top N                                      ││
     │  │  - Execute post-filter if needed                                ││
     │  └──────────────────────────────────────────────────────────────────┘│
     │                              │                                        │
     │                              ▼                                        │
     │  Response to Client                                                  │
     │                                                                      │
     └─────────────────────────────────────────────────────────────────────┘
     */
    
    /**
     * Query Rewrite Process:
     * 
     * Original: match: { status: "pending" }
     *         - Can expand to terms query using analyze API
     * 
     * Original: prefix: { status: "pen" }
     *         - Expands to match_all with prefix filter
     * 
     * Original: wildcard: { status: "p*" }
     *         - Replaced with terms lookup or rewrite to prefix
     */
}
```

### 4.2 Query Cache

```java
// Query cache behavior
public class QueryCacheBehavior {
    
    /**
     * ┌─────────────────────────────────────────────────────────────────────┐
     │                      QUERY CACHING                                  │
     ├─────────────────────────────────────────────────────────────────────┤
     │                                                                      │
     │  Request Cache:                                                      │
     │  - Caches entire query results                                      │
     │  - Key = Lucene query + sorting + aggregations                     │
     │  - Size: 1% of heap (default)                                       │
     │  - TTL: explicit (when refresh occurs)                             │
     │  - Invalidated on: index refresh, mapping change                   │
     │                                                                      │
     │  Query Result Cache:                                                │
     │  - Caches actual document results                                  │
     │  - For large result sets, caches pages                             │
     │  - Key = query + sort + from/size                                  │
     │                                                                      │
     │  Filter Cache (deprecated in ES 5+):                                │
     │  - Replaced by node query cache                                     │
     │  - Caches filter results as bitset                                 │
     │                                                                      │
     └─────────────────────────────────────────────────────────────────────┘
     */
    
    /**
     * Caching Behavior by Query Type:
     * 
     * Cached:
     * - Term query (low cardinality)
     * - Range query (same ranges cached)
     * - Filters (boolean AND/OR)
     * - Aggregation (if same buckets)
     * 
     * Not Cached:
     * - Full text queries (match, phrase)
     * - Queries with scoring (must, should)
     * - Wildcard/regex (non-deterministic results)
     */
    
    /**
     * Explicit Cache Control:
     */
    
    /*
     GET /orders/_search?request_cache=true
     {
       "query": { "match_all": {} },
       "size": 0,
       "aggs": {
         "by_status": { "terms": { "field": "status" } }
       }
     }
     
     // Size > 0 not cached unless index.cache.query.enabled=true
     // Or use cache: false to explicitly disable
     GET /orders/_search?request_cache=false
     {
       "query": { "term": { "status": "pending" } }
     }
     */
}
```

---

## 5. Aggregation Internals

### 5.1 Aggregation Execution

```java
// Aggregation execution internals
public class AggregationInternals {
    
    /**
     * ┌─────────────────────────────────────────────────────────────────────┐
     │                    AGGREGATION EXECUTION                             │
     ├─────────────────────────────────────────────────────────────────────┤
     │                                                                      │
     │  Bucket Aggregations:                                               │
     │  - Create buckets based on field values                             │
     │  - Nested: execute children within parent buckets                  │
     │                                                                      │
     │  Example: terms on "status" -> terms on "customer_id"              │
     │                                                                      │
     │  ┌──────────────────────────────────────────────────────────────────┐│
     │  │ Status: PENDING                                                  ││
     │  │   ├─ Customer A: 150                                             ││
     │  │   ├─ Customer B: 89                                              ││
     │  │   └─ Customer C: 45                                               ││
     │  │                                                                   ││
     │  │ Status: SHIPPED                                                  ││
     │  │   ├─ Customer A: 200                                             ││
     │  │   ├─ Customer B: 75                                              ││
     │  │   └─ Customer C: 120                                             ││
     │  └──────────────────────────────────────────────────────────────────┘│
     │                                                                      │
     │  Metric Aggregations:                                               │
     │  - Single-value: avg, sum, min, max                                 │
     │  - Multi-value: stats, extended_stats, percentiles                 │
     │  - Pipeline: avg_bucket, derivative, moving_avg                    │
     │                                                                      │
     └─────────────────────────────────────────────────────────────────────┘
     */
    
    /**
     * Aggregation Optimization:
     */
    
    /**
     * 1. Shard-Level Aggregation:
     * 
     * - Aggregations run on each shard first
     * - Results merged at coordinating node
     * - trade-off: accuracy vs. performance
     * 
     * Example: terms aggregation
     * - Shard 1: {A: 100, B: 80, C: 50}
     * - Shard 2: {A: 120, B: 60, D: 40}
     * - Merged: {A: 220, B: 140, C: 50, D: 40} (approximate!)
     */
    
    /**
     * 2. Pre-Aggregation:
     * 
     * - Fielddata on fielddata field (preload)
     * - doc_values enabled by default for aggregations
     * - Investigate heavy terms aggregations
     * 
     * PUT /orders/_mapping
     * {
     *   "properties": {
     *     "status": {
     *       "type": "keyword",
     *       "eager_global_ordinals": true  // Pre-load for aggregations
     *     }
     *   }
     * }
     */
    
    /**
     * 3. Sampled Aggregations:
     * 
     * - For approximate results on large datasets
     * - Faster execution
     * 
     * GET /orders/_search
     * {
     *   "aggs": {
     *     "status_terms": {
     *       "terms": {
     *         "field": "status",
     *         "size": 10,
     *         "shard_size": 25,
     *         "shard_min_doc_count": 100  // Sampling threshold
     *       }
     *     }
     *   }
     * }
     */
}
```

### 5.2 Pipeline Aggregations

```java
// Pipeline aggregations
public class PipelineAggregations {
    
    /**
     * Pipeline Aggregations:
     * 
     * - Operate on output of other aggregations
     * - Cannot have sub-aggregations
     * - Common use: moving averages, derivatives
     * 
     * Example: Monthly sales with 3-month moving average
     */
    
    /*
     GET /orders/_search
     {
       "size": 0,
       "aggs": {
         "monthly_sales": {
           "date_histogram": {
             "field": "order_date",
             "calendar_interval": "month"
           },
           "aggs": {
             "total_sales": {
               "sum": { "field": "total" }
             },
             "moving_avg": {
               "moving_avg": {
                 "buckets_path": "total_sales",
                 "window": 3,
                 "shift": 0
               }
             },
             "derivative": {
               "derivative": {
                 "buckets_path": "total_sales"
               }
             }
           }
         }
       }
     }
     */
    
    /**
     * Common Pipeline Aggregations:
     * 
     * - moving_avg: Rolling average over window
     * - derivative: Rate of change between buckets
     * - cumulative_sum: Running total
     * - avg_bucket: Average of buckets
     * - max_bucket: Maximum bucket value
     * - bucket_selector: Filter based on bucket values
     * - bucket_script: Custom calculation on buckets
     */
}
```

---

## 6. Memory Management and Caching

### 6.1 JVM Heap Usage in Elasticsearch

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                    ELASTICSEARCH JVM HEAP                                    │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  Heap = 50% of container/machine memory                                     │
│                                                                              │
│  ┌────────────────────────────────────────────────────────────────────────┐ │
│  │                     HEAP BREAKDOWN                                    │ │
│  ├────────────────────────────────────────────────────────────────────────┤ │
│  │                                                                         │ │
│  │  Field Data + Data + Request Cache          (30% for query cache)    │ │
│  │  ┌─────────────────────────────────────────┐                          │ │
│  │  │ Field Data (per field):                 │                          │ │
│  │  │ - Uninverted form of inverted index    │                          │ │
│  │  │ - Used for sorting/aggregations         │                          │ │
│  │  │ - Heavy on memory!                      │                          │ │
│  │  └─────────────────────────────────────────┘                          │ │
│  │                                                                         │ │
│  │  Node Query Cache (Filters):                  (shared per node)       │ │
│  │  - Caches filter results                      │                          │ │
│  │  - LRU eviction                              │                          │ │
│  │                                                                         │ │
│  │  Request Cache (Results):                    (per index segment)      │ │
│  │  - Caches aggregation results                │                          │ │
│  │  - Size: indices.requests.cache.size         │                          │ │
│  │                                                                         │ │
│  └────────────────────────────────────────────────────────────────────────┘ │
│                                                                              │
│  ┌────────────────────────────────────────────────────────────────────────┐ │
│  │                   OFF-HEAP (Direct Memory)                            │ │
│  ├────────────────────────────────────────────────────────────────────────┤ │
│  │                                                                         │ │
│  │  - Lucene segment data (mmap)                  OS-managed              │ │
│  │  - Network buffers                            (netty)                  │ │
│  │  - Shard buffers                              (search)                 │ │
│  │  - Bulk processing buffers                   (indexing)              │ │
│  │                                                                         │ │
│  └────────────────────────────────────────────────────────────────────────┘ │
│                                                                              │
│  Circuit Breakers:                                                          │
│  - indices.breaker.fielddata.limit = 60%                                    │
│  - indices.breaker.request.limit = 40%                                     │
│  - indices.breaker.total.limit = 70%                                      │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

### 6.2 Circuit Breakers

```java
// Circuit breaker configuration
public class CircuitBreakers {
    
    /**
     * Circuit Breaker Purpose:
     * 
     * Prevent OOM by bailing early when memory would be exceeded
     * 
     * Types:
     * 
     * 1. Fielddata Circuit Breaker:
     *    - Triggers when loading fielddata would exceed limit
     *    - indices.breaker.fielddata.limit = 60% (default)
     * 
     * 2. Request Circuit Breaker:
     *    - Triggers when request memory would exceed limit
     *    - indices.breaker.request.limit = 40%
     * 
     * 3. In-Flight Request Circuit Breaker:
     *    - Triggers on total incoming request size
     *    - network.breaker.inflight_requests.limit = 100%
     * 
     * 4. Script Compilation Circuit Breaker:
     *    - Limits inline script compilation
     *    -.script.max_compilations_rate = 1000/1m
     * 
     * 5. Total Circuit Breaker:
     *    - Catches anything missed by others
     *    - indices.breaker.total.limit = 70%
     */
    
    /**
     * Handling Circuit Breaker Errors:
     * 
     * - Error message: "Data too large"
     * - Exception type: CircuitBreakingException
     * 
     * Fix options:
     * 1. Increase circuit breaker limit
     * 2. Reduce data loaded (query optimization)
     * 3. Use doc_values instead of fielddata
     * 4. Add more memory
     * 5. Reduce index size (more shards)
     */
    
    /**
     * Monitoring Circuit Breakers:
     */
    
    /*
     GET /_nodes/stats/breaker
    
     {
       "nodes": [
         {
           "name": "node-1",
           "breakers": {
             "fielddata": {
               "limit": 1000000000,
               "estimated": 500000000,
               "overhead": 1.03
             },
             "request": {
               "limit": 1000000000,
               "estimated": 10000000
             }
           }
         }
       ]
     }
     */
}
```

---

## 7. Data Tier Architecture

### 7.1 Data Lifecycle Tiers

```java
// Data tier configuration
public class DataTierConfiguration {
    
    /**
     * ┌─────────────────────────────────────────────────────────────────────┐
     │                    DATA TIER ARCHITECTURE                           │
     ├─────────────────────────────────────────────────────────────────────┤
     │                                                                      │
     │  Hot Tier (Elasticsearch 7.10+):                                    │
     │  ┌──────────────────────────────────────────────────────────────────┐│
     │  │ - Recently indexed data                                           ││
     │  │ - Active writes and frequent queries                             ││
     │  │ - Node type: data_hot                                             ││
     │  │ - Fast storage (NVMe SSD)                                         ││
     │  │ - Memory: Higher heap allocation                                  ││
     │  └──────────────────────────────────────────────────────────────────┘│
     │                              │                                        │
     │                              ▼                                        │
     │  Warm Tier:                                                           │
     │  ┌──────────────────────────────────────────────────────────────────┐│
     │  │ - Older data, infrequent access                                   ││
     │  │ - Read-only or rare writes                                        ││
     │  │ - Node type: data_warm                                            ││
     │  │ - Storage: Larger, slower SSD/HDD                                 ││
     │  │ - Reduce replicas: from 2 to 1                                    ││
     │  └──────────────────────────────────────────────────────────────────┘│
     │                              │                                        │
     │                              ▼                                        │
     │  Cold Tier:                                                           │
     │  ┌──────────────────────────────────────────────────────────────────┐│
     │  │ - Rarely accessed data                                            ││
     │  │ - Archive purposes                                                ││
     │  │ - Node type: data_cold                                            ││
     │  │ - Storage: HDD or object storage                                  ││
     │  │ - Reduced replicas: 1 or 0                                        ││
     │  │ - frozen tier: fully searchable with less resources              ││
     │  └──────────────────────────────────────────────────────────────────┘│
     │                                                                      │
     └─────────────────────────────────────────────────────────────────────┘
     */
    
    /**
     * Index Lifecycle Management (ILM):
     */
    
    /*
     PUT /_ilm/policy/orders-policy
     {
       "policy": {
         "phases": {
           "hot": {
             "min_age": "0ms",
             "actions": {
               "rollover": {
                 "max_age": "7d",
                 "max_size": "50gb",
                 "max_docs": 10000000
               },
               "set_priority": { "priority": 100 }
             }
           },
           "warm": {
             "min_age": "30d",
             "actions": {
               "shrink": { "number_of_shards": 1 },
               "forcemerge": { "max_num_segments": 1 },
               "set_priority": { "priority": 50 },
               "allocate": {
                 "number_of_replicas": 1
               }
             }
           },
           "cold": {
             "min_age": "90d",
             "actions": {
               "set_priority": { "priority": 0 },
               "allocate": {
                 "number_of_replicas": 0,
                 "include": { "data": "cold" }
               }
             }
           },
           "delete": {
             "min_age": "365d",
             "actions": {
               "delete": {}
             }
           }
         }
       }
     }
     */
}
```

---

## 8. Sharding and Rebalancing

### 8.1 Shard Allocation Decisions

```java
// Shard allocation internals
public class ShardAllocation {
    
    /**
     * Shard Allocation Filters:
     * 
     * Elasticsearch decides shard placement based on:
     * 
     * 1. Cluster Level:
     *    - cluster.routing.allocation.enable = all
     *    - node.ml: true/false (ML nodes)
     *    - node.data: true/false
     * 
     * 2. Index Level:
     *    - index.routing.allocation.include.zone
     *    - index.routing.allocation.exclude.zone
     *    - index.routing.allocation.require.zone
     * 
     * 3. Dynamic Allocation:
     *    - index.routing.rebalance.enable
     *    - index.routing.allocation.balance
     * 
     * Example:
     * 
     * PUT /orders/_settings
     * {
     *   "index": {
     *     "routing": {
     *       "allocation": {
     *         "include": {
     *           "zone": "us-east-1a"
     *         },
     *         "require": {
     *           "disk.threshold": "low"
     *         },
     *         "exclude": {
     *           "_ip": "192.168.1.100"
     *         }
     *       }
     *     }
     *   }
     * }
     */
    
    /**
     * Shard Rebalancing:
     * 
     * - cluster.routing.rebalance.enable = all
     * - cluster.routing.allocation.cluster_concurrent_rebalance = 2
     * 
     * Rebalance happens when:
     * - New node joins
     * - Node leaves
     * - Primary shard on failed node needs new replica
     * - Disk watermark exceeded
     */
}
```

---

## 9. Security Implementation

### 9.1 Authentication and Authorization

```java
// Security configuration
public class SecurityConfiguration {
    
    /**
     * Security Layers:
     * 
     * 1. Node Authentication:
     *    - Transport layer security (TLS/SSL)
     *    - Certificate-based
     *    - xpack.security.transport.ssl.enabled = true
     * 
     * 2. User Authentication:
     *    - Native (stored in ES)
     *    - LDAP/AD
     *    - SAML/OIDC (with Platinum license)
     *    - PKI (client certificates)
     * 
     * 3. Authorization:
     *    - Role-based access control (RBAC)
     *    - Field-level security
     *    - Document-level security
     */
    
    /**
     * Built-in Roles:
     * 
     * - superuser: All access
     * - kibana_admin: Kibana access
     * - monitoring_user: Monitoring API
     * - remote_monitoring_agent: Collection
     * - own_index: Access own indexes
     * 
     * Creating Custom Role:
     * 
     * POST /_security/role/orders-admin
     * {
     *   "indices": [
     *     {
     *       "names": ["orders*"],
     *       "privileges": ["all"]
     *     }
     *   ],
     *   "run_as": ["reporting_user"],
     *   "metadata": {
     *     "version": 1
     *   }
     * }
     */
}
```

---

## 10. Troubleshooting and Diagnostics

### 10.1 Key Metrics and APIs

```bash
# Cluster health
GET /_cluster/health

# Cluster stats
GET /_cluster/stats

# Node stats
GET /_nodes/stats

# Index stats
GET /orders/_stats

# Segments info (detailed shard state)
GET /orders/_segments

# Pending tasks
GET /_cluster/pending_tasks

# Allocation explanation
POST /_cluster/reroute
{
  "commands": [
    {
      "allocate_replica": {
        "index": "orders",
        "shard": 0,
        "node": "node-1"
      }
    }
  ]
}
```

---

This comprehensive guide covers Elasticsearch internals at a deep technical level suitable for production deployments and optimization.