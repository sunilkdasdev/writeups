# JVM Heap Deep Dive: Memory Management and Optimization

**By Donald K. Burleson**

---

## Introduction: Mastering Heap Memory

The heap is where your application lives or dies. Object allocation, garbage collection, and memory leaks all happen here.

At Manhattan Associates, we've learned that understanding heap behavior is essential for building stable, high-performance systems.

---

## Chapter 1: Heap Structure Deep Dive

### Young Generation

```bash
# Young generation sizing
-XX:NewSize=512m          # Initial young gen
-XX:MaxNewSize=2g         # Maximum young gen
-XX:NewRatio=2            # Old/New ratio (2 means old = 2 * young)
# Or use percentages
-XX:NewSizePercent=40      # 40% of heap to young gen
-XX:MaxNewSizePercent=60
```

### Survivor Spaces

```bash
# Survivor ratio (Eden/Survivor)
-XX:SurvivorRatio=8       # 8:1:1 ratio (Eden:Survivor:Survivor)

# Age threshold for tenuring
-XX:PretenureSizeThreshold=1m  # Objects > 1MB go directly to old
-XX:TenuringThreshold=15       # Max age before tenuring
```

### Old Generation

```bash
# Old generation = Heap - Young Generation
# Sizing: Old = Heap - (Eden + 2 * Survivor)
```

### Complete Heap Configuration

```bash
# Full heap configuration example
-Xms8g                    # Start at 8GB
-Xmx8g                    # Max 8GB
-Xmn2g                    # Young 2GB
-Xss512k                  # Stack 512KB
-XX:SurvivorRatio=8       # 8:1:1
-XX:MetaspaceSize=256m
-XX:MaxMetaspaceSize=512m
-XX:MaxDirectMemorySize=1g
```

---

## Chapter 2: Object Allocation Process

### TLAB (Thread Local Allocation Buffer)

```java
// TLAB - each thread has private buffer in Eden
// Avoids synchronization for most allocations

// Enable/Disable TLAB
-XX:+UseTLAB              // Default enabled
-XX:TLABSize=512k         // Initial TLAB size
-XX:ResizeTLAB            // Dynamic resize

// When TLAB is full:
// 1. Allocate in Eden (with GC bump)
// 2. Get new TLAB
```

### Allocation Fast Path

```java
class AllocationFastPath {
    // Fast path: TLAB allocation
    public void fast() {
        Object obj = new Object();  // ~10 CPU cycles
    }
    
    // Slow path: need to get new TLAB or allocate in old
    public void slow() {
        // Large object or TLAB full
        byte[] large = new byte[10 * 1024 * 1024];  // 10MB
    }
}
```

### Object Header Layout

```
┌─────────────────────────────────────────────────────────────────┐
│                    Object Header (64-bit)                      │
├─────────────────────────────────────────────────────────────────┤
│ Mark Word (8 bytes)                                            │
│   - Unlocked: hashcode (31 bits) + age (4) + biased(1) + lock(2)│
│   - Locked: ptr to monitor + lock state                        │
├─────────────────────────────────────────────────────────────────┤
│ Klass Pointer (8 bytes, compressed: 4 bytes)                   │
│   - Pointer to class metadata in Metaspace                    │
├─────────────────────────────────────────────────────────────────┤
│ Array Length (4 bytes, only for arrays)                        │
└─────────────────────────────────────────────────────────────────┘
```

---

## Chapter 3: Garbage Collection Deep Dive

### The Mark-Sweep-Compact Algorithm

```java
// Phase 1: Mark
// Traverse from GC roots, mark all reachable objects
// GC Roots: stack, static, JNI

// Phase 2: Sweep
// Scan heap, mark unmarked objects as dead
// Result: Memory holes (fragmentation)

// Phase 3: Compact
// Move objects together, update references
// Result: Contiguous free space
```

### Generational GC

```java
// Why generational?
// - Most objects die young (98% in young gen)
// - Copying collector efficient for young gen
// - Old gen has few garbage, use Mark-Sweep

// Young GC flow
// 1. Objects allocated in Eden
// 2. Eden fills → Young GC
// 3. From Eden + Survivor → To Survivor (copy)
// 4. Age threshold reached → To Old
// 5. Survivor spaces swap
```

### GC Roots

```java
// What are GC Roots?
class GCRoots {
    // 1. Thread stack (local variables)
    void method() {
        Object local = new Object();  // GC Root!
    }
    
    // 2. Static fields
    static Object staticObj = new Object();  // GC Root!
    
    // 3. JNI references
    // Native code holding Java references
    
    // 4. Class loaders
    // Classes loaded by bootstrap loader
    
    // 5. Synchronized objects
    synchronized(obj) { }  // obj is GC Root
    
    // 6. Pending finalization
    // Objects with finalize()
}
```

---

## Chapter 4: Different GC Algorithms

### Serial GC (-XX:+UseSerialGC)

```bash
# Single-threaded, stop-the-world
# Best for small heaps (<100MB), single CPU
# Not suitable for production servers

java -XX:+UseSerialGC -Xms2g -Xmx2g -XX:+PrintGCDetails MyApp
```

### Parallel GC (-XX:+UseParallelGC)

```bash
# Throughput GC - maximizes throughput
# Good for batch processing, ETL
# Trade-off: longer stop-the-world pauses

java -XX:+UseParallelGC \
     -XX:ParallelGCThreads=8 \
     -XX:MaxGCPauseMillis=500 \
     -XX:GCTimeRatio=99 \
     -Xms8g -Xmx8g
```

### CMS GC (-XX:+UseConcMarkSweepGC)

```bash
# Concurrent Mark Sweep - low pause
# Most work concurrent, short pauses
# Deprecated in Java 14

java -XX:+UseConcMarkSweepGC \
     -XX:+UseParNewGC \
     -XX:CMSInitiatingOccupancyFraction=68 \
     -XX:+UseCMSInitiatingOccupancyOnly
```

### G1 GC (-XX:+UseG1GC) - Default

```bash
# Garbage First - balanced
# Region-based (1MB-32MB regions)
# Configurable pause time goal

java -XX:+UseG1GC \
     -XX:MaxGCPauseMillis=200 \
     -XX:G1HeapRegionSize=16m \
     -XX:InitiatingHeapOccupancyPercent=45 \
     -XX:G1ReservePercent=10
```

### ZGC (-XX:+UseZGC)

```bash
# Scalable low latency
# Pauses < 10ms regardless of heap size
# Good for large heaps, low latency requirements

java -XX:+UseZGC \
     -XX:ZCollectionInterval=10 \
     -XX:ZAllocationSpikeTolerance=5 \
     -Xms16g -Xmx16g
```

### Shenandoah (-XX:+UseShenandoahGC)

```bash
# Experimental, similar to ZGC
# Concurrent compaction
# Red Hat openJDK

java -XX:+UseShenandoahGC \
     -XX:ShenandoahGCHeuristics=adaptive
```

---

## Chapter 5: Memory Leaks and Troubleshooting

### Common Leak Patterns

```java
// Pattern 1: Static collections
class Leak1 {
    static List<Object> cache = new ArrayList<>();  // Grows forever!
    
    public void add(Object obj) {
        cache.add(obj);  // Never removed
    }
}

// Pattern 2: Listeners not removed
class Leak2 {
    List<Listener> listeners = new ArrayList<>();
    
    public void register(Listener l) {
        listeners.add(l);  // Never unregistered
    }
}

// Pattern 3: ThreadLocal
class Leak3 {
    static ThreadLocal<Context> ctx = new ThreadLocal<>();
    
    public void set(Context c) {
        ctx.set(c);  // Never removed!
    }
}

// Pattern 4: Connection leaks
class Leak4 {
    public void query() {
        Connection conn = pool.getConnection();
        // No close() in finally!
    }
}
```

### Finding Leaks with jmap

```bash
# Capture heap dump
jmap -dump:format=b,file=heap.hprof <pid>

# Histogram
jmap -histo <pid> | head -50

# Heap summary
jmap -heap <pid>
```

### Using MAT (Memory Analyzer Tool)

```java
// Open heap.hprof in MAT
// 1. Leak Suspects Report
// 2. Dominator Tree - find largest retained objects
// 3. Path to GC Roots - why objects retained
// 4. OQL - SQL-like queries on heap
```

### Leak Detection in Code

```java
// Use WeakReference for caches
class Cache {
    private Map<String, WeakReference<Object>> cache = new WeakHashMap<>();
    
    public void put(String key, Object value) {
        cache.put(key, new WeakReference<>(value));
    }
}

// Use try-with-resources
class DatabaseQuery {
    public void query() {
        try (Connection conn = dataSource.getConnection()) {
            // Auto-closed
        }
    }
}
```

---

## Chapter 6: Heap Tuning Best Practices

### Initial Sizing

```bash
# Start with reasonable size
# Rule of thumb: 25% more than normal usage

# Measure during normal operation
jstat -gc <pid> 1000

# If old gen consistently > 70%, increase heap
```

### Young Generation Sizing

```bash
# Larger young = more objects promoted = less old GC
# Smaller young = shorter pauses, more promotion

# If minor GC long: reduce young gen
# If old gen grows fast: increase young gen
# Target: 80-90% minor collections complete in <100ms
```

### Monitoring

```bash
# Real-time monitoring
jstat -gcutil <pid> 1000

# Output:
# S0 S1 E O M CCS YGC YGCT GGC FGCT GCT
# 0  0  20 45 30 28   100 1.234  5 2.567 3.801
```

### GC Tuning Workflow

```java
// 1. Enable GC logging
-XX:+PrintGCDetails
-XX:+PrintGCDateStamps
-Xloggc:gc.log

// 2. Monitor metrics
// - Minor GC frequency and duration
// - Full GC frequency and duration  
// - Old gen usage after GC

// 3. Tune iteratively
// - Adjust heap size
// - Adjust young gen size
// - Adjust GC algorithm

// 4. Test in staging before production
```

---

## Chapter 7: Container Memory Tuning

### Container Memory Limits

```bash
# Container awareness (Java 10+)
-XX:+UseContainerSupport  # Default enabled

# Set heap based on container limits
-XX:MaxRAMPercentage=75   # Use 75% of container memory for heap
-XX:InitialRAMPercentage=50

# Container-specific flags
-XX:+UnlockExperimentalVMOptions
-XX:+UseCGroupMemoryLimitForHeap
```

### Kubernetes Memory Settings

```yaml
# Pod spec
resources:
  requests:
    memory: "2Gi"
  limits:
    memory: "2Gi"

# JVM settings
env:
  - name: JAVA_TOOL_OPTIONS
    value: "-XX:MaxRAMPercentage=75 -XX:+UseContainerSupport -XX:+UseG1GC"
```

### Avoiding OOMKilled

```bash
# Common issue: JVM sees node memory, not container limit
# Solution: Use MaxRAMPercentage

# Monitor actual usage
docker stats container_id

# Check if JVM respects limits
jinfo -flag MaxHeapSize <pid>
```

---

## Conclusion

**Donald Sez**: "Heap tuning is iterative. Measure, adjust, measure again."

At Manhattan Associates:
1. **Use G1 for most cases** - Good balance
2. **Enable GC logging** - Essential for troubleshooting
3. **Set MaxRAMPercentage** - For container environments
4. **Monitor young/old ratio** - Catch issues early

---

**Next**: "JVM Performance Analysis: Tools and Techniques" - Using jstack, jstat, jmap, jcmd, and async-profiler for deep analysis.