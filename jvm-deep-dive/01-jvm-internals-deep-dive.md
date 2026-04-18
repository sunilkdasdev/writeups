# JVM Internals Deep Dive: Memory Management, GC, and Performance

## Table of Contents

1. [JVM Memory Architecture Deep Dive](#1-jvm-memory-architecture-deep-dive)
2. [Garbage Collection Algorithms In-Depth](#2-garbage-collection-algorithms-in-depth)
3. [HotSpot JIT Compiler Internals](#3-hotspot-jit-compiler-internals)
4. [Class Loading and Bytecode Execution](#4-class-loading-and-bytecode-execution)
5. [JVM Performance Tuning](#5-jvm-performance-tuning)
6. [Memory Leaks and Troubleshooting](#6-memory-leaks-and-troubleshooting)
7. [JVM Profiling and Diagnostics](#7-jvm-profiling-and-diagnostics)
8. [Modern JVM Features and Optimizations](#8-modern-jvm-features-and-optimizations)

---

## 1. JVM Memory Architecture Deep Dive

### 1.1 Runtime Data Areas

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                           JVM RUNTIME DATA AREAS                             │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  ┌────────────────────────────────────────────────────────────────────────┐ │
│  │                     HEAP (Shared)                                       │ │
│  │  ┌──────────────────────────────────────────────────────────────────┐  │ │
│  │  │                     Young Generation                              │  │ │
│  │  │  ┌─────────────┬─────────────┬─────────────┐                   │  │ │
│  │  │  │    Eden     │  Survivor   │  Survivor   │                   │  │ │
│  │  │  │             │     (S0)    │     (S1)    │                   │  │ │
│  │  │  └─────────────┴─────────────┴─────────────┘                   │  │ │
│  │  │                                                                   │  │ │
│  │  └──────────────────────────────────────────────────────────────────┘  │ │
│  │                              │                                          │ │
│  │  ┌────────────────────────────▼────────────────────────────────────┐  │ │
│  │  │                   Old Generation                                  │  │ │
│  │  │  ┌──────────────────────────────────────────────────────────┐    │  │ │
│  │  │  │                   Tenured Space                          │    │  │ │
│  │  │  └──────────────────────────────────────────────────────────┘    │  │ │
│  │  └──────────────────────────────────────────────────────────────────┘  │ │
│  └────────────────────────────────────────────────────────────────────────┘ │
│                                                                              │
│  ┌────────────────────────────────────────────────────────────────────────┐ │
│  │                   METASPACE (Native Memory)                          │ │
│  │  ┌──────────────────────────────────────────────────────────────────┐  │ │
│  │  │ Class Metadata    │    Code Cache    │    Symbol Table       │  │ │
│  │  └──────────────────────────────────────────────────────────────────┘  │ │
│  └────────────────────────────────────────────────────────────────────────┘ │
│                                                                              │
│  ┌────────────────────────────────────────────────────────────────────────┐ │
│  │              PER-THREAD AREAS (Stack + PC + Native)                   │ │
│  │  ┌──────────────────────────────────────────────────────────────────┐  │ │
│  │  │ Thread 1: [Stack Frame][PC][Native]  │  Thread 2: [Stack]...   │  │ │
│  │  └──────────────────────────────────────────────────────────────────┘  │ │
│  └────────────────────────────────────────────────────────────────────────┘ │
│                                                                              │
│  ┌────────────────────────────────────────────────────────────────────────┐ │
│  │                   DIRECT BUFFERS (Off-Heap)                           │ │
│  └────────────────────────────────────────────────────────────────────────┘ │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

### 1.2 Object Allocation Deep Dive

```c
// HotSpot object allocation (simplified from source)

void* instanceOopKlass::allocate_instance(Klass* klass, TRAPS) {
    // 1. Check if TLAB (Thread Local Allocation Buffer) has room
    if (UseTLAB) {
        HeapWord* result = thread->tlab().allocate(size);
        if (result != NULL) return result;
        // TLAB exhausted, go to slow path
    }
    
    // 2. Try allocation in Eden
    result = Universe::heap()->allocate(size);
    
    // 3. If failed, trigger young GC
    if (result == NULL) {
        // Call collector, then retry allocation
        collect(GCCause::_allocation_failure);
        result = Universe::heap()->allocate(size);
        
        // 4. If still failed, expand heap or throw OOM
        if (result == NULL) {
            HandleException(THREAD, 
                java_lang_OutOfMemoryError::out_of_memory_error());
        }
    }
    
    // 5. Initialize object header
    return init_obj(result, klass);
}
```

```java
// Understanding object header structure
public class ObjectHeaderDemo {
    
    /**
     * Object Header (64-bit JVM):
     * 
     * ┌─────────────────────────────────────────────────────────────────────┐
     │                    OBJECT HEADER (Mark Word)                        │
     ├─────────────────────────────────────────────────────────────────────┤
     │  Locked state (biased):                                              │
     │  [1110 0010] [thread: 50 bits] [epoch: 2] [age: 4] [biased: 1] [00]│
     │                                                                       │
     │  Locked state (thin):                                                │
     │  [ptr to monitor]                                          [01]    │
     │                                                                       │
     │  Inflated (heavy):                                                   │
     │  [ptr to monitor]                                          [10]    │
     │                                                                       │
     │  Unlocked (biased not biased):                                       │
     │  [hashcode: 31 bits] [age: 4] [biased: 0] [00]                      │
     │                                                                       │
     │  GC state (during marking):                                          │
     │  [forwarding ptr]                                           [01]    │
     │                                                                       │
     └─────────────────────────────────────────────────────────────────────┘
     * 
     * The "Klass" pointer follows the mark word:
     * 
     * [Mark Word (8 bytes)] [Klass Pointer (8 bytes)] = 16 bytes minimum
     * 
     * For arrays, add 4 bytes for length:
     * [Mark (8)] [Klass (8)] [Length (4)] = 20 bytes, padded to 24
     */
    
    /**
     * TLAB (Thread Local Allocation Buffer):
     * 
     * - Each thread pre-allocates a chunk of Eden
     * - Fast path: just advance pointer in TLAB
     * - No synchronization needed for most allocations!
     * 
     * Configuration:
     * -XX:+UseTLAB - enable (default)
     * -XX:TLABSize - initial size
     * -XX:ResizeTLAB - dynamic resize
     * 
     * TLAB waste:
     * - If object doesn't fit in remaining TLAB, waste the rest
     * - Larger TLAB = less waste but longer GC
     */
}
```

### 1.3 Metaspace Deep Dive

```java
// Metaspace management
public class MetaspaceDeepDive {
    
    /**
     * Metaspace vs PermGen:
     * 
     * PermGen (pre-Java 8):
     * - Fixed size, hard to tune
     * - Part of heap (contiguous with old gen)
     * - Filled up with classloader leaks
     * - Full = PermGen OOM
     * 
     * Metaspace (Java 8+):
     * - Native memory, not heap
     * - Grows dynamically (up to MaxMetaspaceSize)
     * - Automatic cleanup when classes unloaded
     * - Different OOM: OutOfMemoryError: Metaspace
     * 
     * Why metaspace isn't in heap:
     * - Garbage collection is different
     * - Can be much larger
     * - No impact on GC pause times
     */
    
    /**
     * Metaspace structure:
     * 
     * ┌─────────────────────────────────────────────────────────────────────┐
     │                         METASPACE                                    │
     ├─────────────────────────────────────────────────────────────────────┤
     │  ┌──────────────────────────────────────────────────────────────┐  │
     │  │                Class Space (Compressed)                        │  │
     │  │  - Compressed class pointers                                  │  │
     │  │  - Max 4GB addressable                                        │  │
     │  │  - 32-bit pointer to class data                               │  │
     │  └──────────────────────────────────────────────────────────────┘  │
     │  ┌──────────────────────────────────────────────────────────────┐  │
     │  │                Non-Class Metaspace                             │  │
     │  │  - Symbol tables                                               │  │
     │  │  - Method data                                                │  │
     │  │  - Code cache (JIT compiled code)                            │  │
     │  └──────────────────────────────────────────────────────────────┘  │
     │                                                                       │
     │  Chunk: 64KB (default, aligned)                                      │
     │  Region: Multiple chunks                                             │
     │  Metachunk: Allocated from chunk                                     │
     │                                                                       │
     └─────────────────────────────────────────────────────────────────────┘
     */
    
    /**
     * Metaspace allocation flow:
     * 
     * 1. ClassLoader requests space for class metadata
     * 2. Metaspace allocates from current chunk
     * 3. If chunk full, allocate new chunk from VM
     * 4. If MetaspaceSize exceeded, trigger GC
     * 5. If still full, throw OOM
     * 
     * Tunable parameters:
     * -XX:MetaspaceSize=128m (initial threshold)
     * -XX:MaxMetaspaceSize=unlimited (or specific size)
     * -XX:MinMetaspaceFreeRatio=40% (after GC)
     * -XX:MaxMetaspaceFreeRatio=70%
     */
}
```

---

## 2. Garbage Collection Algorithms In-Depth

### 2.1 Mark-Sweep-Compact

```java
// GC algorithm visualization
public class GCAlgorithms {
    
    /**
     * MARK-SWEEP-COMPACT Algorithm:
     * 
     * ┌─────────────────────────────────────────────────────────────────────┐
     │                    MARK PHASE                                       │
     ├─────────────────────────────────────────────────────────────────────┤
     │                                                                      │
     │  1. Start from GC Roots:                                            │
     │     - Thread stacks (local variables)                                │
     │     - Static fields                                                  │
     │     - JNI references                                                 │
     │     - Class loaders                                                  │
     │     - Finalization queue                                            │
     │                                                                      │
     │  2. Traverse object graph:                                           │
     │     - Mark each reachable object as "live"                         │
     │     - Use BFS or DFS                                                │
     │     - Mark phase = O(number of reachable objects)                 │
     │                                                                      │
     │  Example:                                                            │
     │  Before: [A] ──► [B] ──► [C]          [D] ──► [E]                 │
     │            │                 │          │                 │        │
     │            └────────┬────────┘          └────────┬────────┘        │
     │                     │                           │                   │
     │               GC Root                     GC Root                 │
     │                                                                      │
     │  After marking: A,B,C marked live. D,E unmarked (garbage)        │
     │                                                                      │
     └─────────────────────────────────────────────────────────────────────┘
     * 
     * ┌─────────────────────────────────────────────────────────────────────┐
     │                    SWEEP PHASE                                      │
     ├─────────────────────────────────────────────────────────────────────┤
     │                                                                      │
     │  1. Scan all heap objects                                            │
     │  2. Identify unmarked objects (garbage)                            │
     │  3. Add to free list                                                  │
     │  4. Don't touch live objects                                         │
     │                                                                      │
     *  Problem: Memory fragmentation!                                      │
     *  [Live] [Free] [Live] [Free] [Live] [Free] [Live]                  │
     *                                                                      │
     └─────────────────────────────────────────────────────────────────────┘
     * 
     * ┌─────────────────────────────────────────────────────────────────────┐
     │                    COMPACT PHASE                                    │
     ├─────────────────────────────────────────────────────────────────────┤
     │                                                                      │
     *  1. Move all live objects together                                    │
     *  2. Update all references to point to new locations                 │
     *  3. Update card table (for old-gen references to young)            │
     *                                                                      │
     *  Result: [Live][Live][Live][Live] .... [Free continuous space]     │
     *                                                                      │
     *  Cost:                                                                │
     *  - Stop-the-world                                                    │
     *  - Must update all references (expensive!)                         │
     *  - Time proportional to live objects                                │
     *                                                                      │
     └─────────────────────────────────────────────────────────────────────┘
     */
    
    /**
     * GC Root types in HotSpot:
     * 
     * 1. Thread Stack:
     *    - Local variables (primitives and references)
     *    - Parameter references
     *    - Return address references
     * 
     * 2. Static Fields:
     *    - Class variables (static)
     *    - From SystemClassLoader
     * 
     * 3. JNI:
     *    - Global JNI references
     *    - Local JNI references (on native call stack)
     * 
     * 4. Synchronization:
     *    - Objects used as monitors
     *    - Objects in "waiting to be notified" queue
     * 
     * 5. Finalization:
     *    - Objects in finalize() queue
     *    - Classloader instances (if not yet collected)
     */
}
```

### 2.2 Generational Collection

```java
// Generational hypothesis
public class GenerationalGC {
    
    /**
     * Weak Generational Hypothesis:
     * 
     * "Most objects become unused quickly, and most object references 
     *  are short-lived."
     * 
     * Evidence:
     * - Studies show 98%+ of objects die young
     * - Old objects rarely become unreachable
     * - Copying collector efficient for high mortality
     * 
     * Result: Divide heap by age!
     * 
     * ┌─────────────────────────────────────────────────────────────────────┐
     │                    YOUNG GENERATION                                 │
     ├─────────────────────────────────────────────────────────────────────┤
     │                                                                      │
     │  Eden: New allocations go here                                      │
     │   - [New][New][New][New]...                                        │
     │                                                                      │
     │  After GC:                                                          │
     │   - Surviving objects copied to S0                                  │
     │   - [Survivor][Survivor][Survivor][Survivor]...                    │
     │                                                                      │
     │  After next GC:                                                      │
     │   - S0 and S1 swap                                                  │
     │   - Age tracking in mark word                                      │
     │   - Objects >= threshold promoted to Old                          │
     │   - Threshold: -XX:TenuringThreshold (default 15)                  │
     │                                                                      │
     └─────────────────────────────────────────────────────────────────────┘
     */
    
    /**
     * Card Table (Write Barrier):
     * 
     * Why needed? Old gen objects reference young gen objects!
     * Without card table, would have to scan entire old gen for refs.
     * 
     * ┌─────────────────────────────────────────────────────────────────────┐
     │                   CARD TABLE STRUCTURE                               │
     ├─────────────────────────────────────────────────────────────────────┤
     │  Heap is divided into 512-byte "cards"                              │
     │  Each card has 1 byte in card table                                  │
     │                                                                       │
     │  When reference written:                                            │
     *  - Write barrier intercepts                                         │
     *  - Card marked "dirty" (0x00 → 0x01)                               │
     │                                                                       │
     │  Young GC:                                                          │
     *  - Scan only dirty cards from old gen                               │
     *  - Much faster than full scan!                                      │
     │                                                                       │
     └─────────────────────────────────────────────────────────────────────┘
     * 
     * HotSpot card table:
     * - Card size: 512 bytes
     * - Location: Reserved space in Java heap
     * - Barrier: Assembler code in object field stores
     */
    
    /**
     * Young GC (Minor GC):
     * 
     * Trigger: Eden fills up
     * 
     * 1. Stop all application threads (STW)
     * 2. Mark live objects in Eden + S0 (from roots)
     * 3. Copy live objects to S1 (increment age)
     * 4. If age >= TenuringThreshold, copy to Old
     * 5. Swap S0 and S1
     * 6. Resume application threads
     * 
     * Speed: Usually fast (< 50ms for most apps)
     */
}
```

### 2.3 G1 (Garbage First) Algorithm

```java
// G1 algorithm deep dive
public class G1GCDeepDive {
    
    /**
     * G1 Overview:
     * 
     * - Introduced in Java 7, default since Java 9
     * - Region-based, not fixed young/old split
     * - Mixed collections for old gen
     * - Configurable pause time goal
     * - Compacts as it collects
     * 
     * Region Structure:
     * 
     * Heap = N x 1MB regions (can be 1-32MB, default 8MB)
     * 
     * ┌───────┬───────┬───────┬───────┬───────┬───────┐
     │  E    │  S0   │  S1   │ Old   │ Hum   │ Free  │
     │ (Eden)│(Survivor)│    │(Old) │(Humongous)│  │    │
     ├───────┴───────┴───────┴───────┴───────┴───────┤
     *  Region 0  Region 1   Region 2   Region 3  Region 4  Region 5
     * 
     * Humongous objects: > 50% of region size, stored in Humongous regions
     */
    
    /**
     * G1 Collection Phases:
     * 
     * Initial Mark (STW):
     * - Mark live objects in Root regions
     * - Trigger: Mixed collection or when old gen reaches threshold
     * - Overwrites: marking from previous pause
     * 
     * Root Region Scan:
     * - Scan root regions for references to young
     * - Runs concurrently with application
     * 
     * Concurrent Mark:
     * - Walk object graph, mark all live objects
     * - Uses write barriers to track changes
     * - Runs concurrently
     * 
     * Remark (STW):
     * - Complete marking
     * - Handle SATB (Snapshot-At-The-Beginning) log
     * - Reclaim empty regions
     * 
     * Cleanup (STW):
     * - Identify completely empty regions
     * - Calculate live object statistics
     * - Prepare for next phase
     */
    
    /**
     * Mixed Collections:
     * 
     * After each young collection:
     * - Increase number of old regions to collect
     * - After ~10 mixed collections, switch to pure young
     * - Trigger when old gen > -XX:InitiatingHeapOccupancyPercent
     * 
     * Collection Set (CSet):
     * - Regions chosen for collection
     * - Young regions (always included)
     * - Old regions (subset, most garbage)
     * - Humongous regions (always if marked empty)
     */
    
    /**
     * G1 Key Parameters:
     * 
     * -XX:MaxGCPauseMillis=200 - Target max pause time
     * -XX:G1HeapRegionSize=8m - Region size
     * -XX:InitiatingHeapOccupancyPercent=45 - Start mixed GC
     * -XX:G1NewSizePercent=5 - Min young gen size
     * -XX:G1MaxNewSizePercent=60 - Max young gen size
     * -XX:G1MixedGCLiveThresholdPercent=85 - Don't collect if >85% live
     */
}
```

### 2.4 ZGC and Shenandoah

```java
// Low-pause GC algorithms
public class LowPauseGC {
    
    /**
     * ZGC (Z Garbage Collector):
     * 
     * - Java 11+ (experimental), Java 15+ (production)
     * - Sub-millisecond pause times
     * - Scales to multi-terabyte heaps
     * - Concurrency: All major phases concurrent
     * 
     * Colors (Colored Pointers):
     * 
     * ZGC uses 64-bit pointers with extra bits:
     * - Mark bits: 3 (000 to 111 = 7 colors)
     * - Remap bit: 1
     * - Finalizable bit: 1
     * 
     * Object color transitions:
     * Mark0 → Mark1 → Mark2 → Mark0 (remap)
     * 
     * ┌─────────────────────────────────────────────────────────────────────┐
     │                      ZGC WORKING                                    │
     ├─────────────────────────────────────────────────────────────────────┤
     │                                                                      │
     │  Start:         All objects white                                    │
     │                                                                      │
     │  Mark Phase:   Objects reachable = Gray, mark in pointer           │
     │                References followed, marked in-place                │
     │                                                                      │
     │  Relocate:     Move objects, update references (concurrent)        │
     │                                                                      │
     │  Remap:        Update remaining references (concurrent)            │
     │                Remap bit set in old location                       │
     │                                                                      │
     │  Reference Processing: Handle soft/weak/phantom refs (concurrent)  │
     │                                                                      │
     │  Class Unloading: Unload classes (concurrent)                      │
     │                                                                      │
     └─────────────────────────────────────────────────────────────────────┘
     */
    
    /**
     * ZGC Configuration:
     * 
     * -XX:+UseZGC - Enable
     * -XX:ParallelGCThreads=auto - GC threads
     * -XX:ConcGCThreads=auto - Concurrent threads
     * -XX:ZCollectionInterval=10 - Force collection every 10s
     * -XX:ZAllocationSpikeTolerance=5 - Allow 5x allocation spike
     * -XX:ZHeapInitialSize=10g - Initial heap
     * -XX:ZHeapMaximumSize=100g - Max heap
     * 
     * Use cases:
     * - Large heaps (> 100GB)
     * - Ultra-low latency requirements
     * - Consistent pause times regardless of heap size
     */
    
    /**
     * Shenandoah (Red Hat):
     * 
     * - Java 12+ (experimental), 15+ production-ready
     * - Similar to ZGC but different approach
     * - Uses Brooks pointers (forwarding pointers in objects)
     * - Available in OpenJDK
     * 
     * -XX:+UseShenandoahGC - Enable
     * -XX:ShenandoahGCHeuristics=adaptive - Auto-select strategy
     * -XX:ShenandoahInitiationFreeThreshold=15 - Start GC when 15% free
     */
}
```

---

## 3. HotSpot JIT Compiler Internals

### 3.1 Tiered Compilation

```java
// JIT compilation flow
public class JITCompilationFlow {
    
    /**
     * Tiered Compilation:
     * 
     * ┌─────────────────────────────────────────────────────────────────────┐
     │                   COMPILATION TIERS                                 │
     ├─────────────────────────────────────────────────────────────────────┤
     │                                                                      │
     │  Level 0: Interpreter (Interpreted)                                  │
     │  - Bytecode interpreter                                            │
     │  - Fast startup                                                    │
     │  - Slow execution                                                  │
     │  - Invoked immediately                                              │
     │                                                                      │
     │  Level 1: C1 (Client Compiler)                                     │
     │  - Quick compilation                                               │
     │  - No profiling                                                    │
     │  - Fast compilation                                                │
     │  - Triggers: -XX:Threshold1 (default 1000 invocations)             │
     │                                                                      │
     │  Level 2: C1 with Profiling                                         │
     │  - Collect type profiling                                          │
     │  - Branch probabilities                                            │
     │  - Triggers: -XX:Threshold2 (default 20000 invocations)          │
     │                                                                      │
     │  Level 3: C2 (Server Compiler)                                      │
     │  - Optimized compilation                                           │
     │  - Aggressive optimizations                                        │
     │  - Triggers: -XX:Threshold3 (default 20000 invocations)          │
     │                                                                      │
     │  Level 4: C2 with Tiered Compilation                               │
     │  - Re-compile with all profiling data                              │
     │  - Triggers: after enough invocations at level 3                  │
     │                                                                      │
     └─────────────────────────────────────────────────────────────────────┘
     */
    
    /**
     * Profiling Data Collected:
     * 
     * - Type profiling: What types are method parameters and fields?
     * - Call profiling: Which methods are called?
     * - Branch profiling: Which branches are taken?
     * - Counter wrapping: When counters overflow, trigger compilation
     * 
     * Example:
     * 
     * void process(Object obj) {
     *     // Type profile: obj is String 90% of the time
     *     // Call profile: method1 called 80%, method2 called 20%
     *     obj.method1();
     * }
     * 
     * C2 can specialize: if (obj known to be String) use String.method1
     */
    
    /**
     * JIT Compilation Process:
     * 
     * 1. Method becomes "hot" (invoke counter exceeds threshold)
     * 2. Request added to compilation queue
     * 3. Compiler thread picks up method
     * 4. Parse bytecode to IR (Intermediate Representation)
     * 5. Optimize IR (inlining, escape analysis, etc.)
     * 6. Generate machine code
     * 7. Install in code cache
     * 8. Replace interpreter calls with compiled code
     */
}
```

### 3.2 JIT Optimizations

```java
// JIT optimizations
public class JITOptimizations {
    
    /**
     * Key JIT Optimizations:
     */
    
    /**
     * 1. Method Inlining:
     * 
     * Replace method call with compiled method body
     * 
     * - Small methods: Always inline (< 35 bytes)
     * - Hot methods: Inlined when frequently called
     * - Virtual methods: Devirtualized when possible
     * 
     * Example:
     * 
     * int add(int a, int b) { return a + b; }  // Inline!
     * 
     * if (x > 10) return x;  // Inlined
     * 
     * Can be controlled:
     * -XX:MaxInlineSize=35
     * -XX:FreqInlineSize=325
     */
    
    /**
     * 2. Escape Analysis:
     * 
     * Analyze if object escapes method
     * 
     * - If not escaped: Stack-allocate object (no heap!)
     * - If not escape: Eliminate synchronization
     * 
     * Example:
     * 
     * StringBuilder sb = new StringBuilder();
     * sb.append("hello");
     * return sb.toString();  // All inlined, no allocation!
     */
    
    /**
     * 3. Constant Folding:
     * 
     * Compute constants at compile time
     * 
     * int x = 10 * 20;  // Compile: int x = 200;
     * System.out.println("value=" + 42);  // Print "value=42"
     */
    
    /**
     * 4. Loop Unrolling:
     * 
     * Execute multiple iterations in one loop cycle
     * 
     * for (int i = 0; i < 8; i++) {  // Unroll to:
     *     sum += arr[i];             // sum += arr[0] + ... + arr[7];
     * }                              // 
     */
    
    /**
     * 5. Intrinsics:
     * 
     * Replace Java calls with optimized native code
     * 
     * - System.arraycopy()
     * - String.charAt()
     * - Math.sin(), Math.cos()
     * - Array.equals()
     * - Unsafe.getObject()
     * 
     * Controlled by: -XX:InlineIntrinsics
     */
    
    /**
     * 6. Lock Coarsening and Elision:
     * 
     * // Lock coarsening
     * synchronized(obj) {  // Multiple synchronized blocks
     *     x = 1;           // combined into one
     * }
     * synchronized(obj) {
     *     x = 2;
     * }
     * 
     * // Lock elision (escape analysis)
     * synchronized(new Object()) { // Lock on local object never escapes
     *     // Lock removed entirely
     * }
     */
}
```

---

## 4. Class Loading and Bytecode Execution

### 4.1 Class Loading Process

```java
// Class loading mechanism
public class ClassLoadingDeepDive {
    
    /**
     * Class Loading Process:
     * 
     * ┌─────────────────────────────────────────────────────────────────────┐
     │                   CLASS LOADING FLOW                                │
     ├─────────────────────────────────────────────────────────────────────┤
     │                                                                      │
     │  1. Loading (Loading)                                                │
     │     - Read .class file bytes                                         │
     │     - Verify magic (0xCAFEBABE)                                     │
     │     - Create Class<?> in Metaspace                                  │
     │     - Not yet linked                                                │
     │                                                                      │
     │  2. Linking (Linking)                                               │
     │     a) Verification: Bytecode verification                         │
     │        - Type safety                                                │
     *        - Stack operations                                           │
     *        - Field/method access                                        │
     │     b) Preparation: Allocate static fields                         │
     *        - Zero-initialized                                           │
     *     c) Resolution: Symbolic refs → Direct refs                       │
     │        - Class, field, method references                           │
     │                                                                      │
     │  3. Initialization (Initialization)                                 │
     │     - Execute <clinit> (static initializer)                        │
     │     - Run static initializers                                      │
     │     - Thread-safe (only one thread)                                │
     │                                                                      │
     └─────────────────────────────────────────────────────────────────────┘
     */
    
    /**
     * Class Loader Hierarchy:
     * 
     * ┌─────────────────────────────────────────────────────────────────────┐
     │                   CLASS LOADERS                                      │
     ├─────────────────────────────────────────────────────────────────────┤
     │                                                                      │
     │  Bootstrap ClassLoader (null)                                        │
     │  - Loads JAVA_HOME/jre/lib/rt.jar, etc.                            │
     │  - Native code (C++)                                               │
     │  - Part of JVM                                                     │
     │                                                                      │
     │  Platform ClassLoader (Java 9+)                                      │
     │  - Loads java.*, javax.*, etc.                                      │
     │  - Replaces Extension ClassLoader (pre-9)                          │
     │                                                                      │
     │  Application ClassLoader                                            │
     *  - Loads -classpath, -cp, module path                              │
     *  - System class loader                                             │
     *                                                                      │
     │  Custom ClassLoader (User-defined)                                  │
     *  - extend ClassLoader                                               │
     *  - Used for plugins, hot deploy, etc.                              │
     *                                                                      │
     └─────────────────────────────────────────────────────────────────────┘
     * 
     * Delegation: Parent-first (by default)
     */
    
    /**
     * Custom ClassLoader Example:
     */
    
    public class PluginClassLoader extends ClassLoader {
        
        private final Path pluginPath;
        
        public PluginClassLoader(Path pluginPath, ClassLoader parent) {
            super(parent);
            this.pluginPath = pluginPath;
        }
        
        @Override
        protected Class<?> findClass(String name) throws ClassNotFoundException {
            // Convert class name to file path
            String classFile = name.replace('.', '/') + ".class";
            Path classPath = pluginPath.resolve(classFile);
            
            if (!Files.exists(classPath)) {
                throw new ClassNotFoundException(name);
            }
            
            try {
                byte[] classBytes = Files.readAllBytes(classPath);
                return defineClass(name, classBytes, 0, classBytes.length);
            } catch (IOException e) {
                throw new ClassNotFoundException(name, e);
            }
        }
    }
    
    /**
     * Common Class Loading Pitfalls:
     * 
     * 1. ClassNotFoundException:
     *    - Class not on classpath
     *    - Delegation to wrong loader
     * 
     * 2. NoClassDefFoundError:
     *    - Class was loaded but no longer available
     *    - Version mismatch
     * 
     * 3. LinkageError:
     *    - Class loaded by different loaders (A and B)
     *    - A instanceof B = false!
     */
}
```

### 4.2 Bytecode Deep Dive

```java
// Bytecode analysis
public class BytecodeAnalysis {
    
    /**
     * Bytecode Instruction Set:
     * 
     * ┌─────────────────────────────────────────────────────────────────────┐
     │                   BYTECODE INSTRUCTIONS                             │
     ├─────────────────────────────────────────────────────────────────────┤
     │                                                                      │
     │  Stack:                                                              │
     │  - iconst_0-5, bipush, sipush   Push constants                     │
     │  - aload_0-3, aload             Load local variable               │
     │  - astore_0-3, astore           Store local variable               │
     │  - dup, pop, swap               Stack operations                   │
     │                                                                      │
     │  Arithmetic:                                                        │
     │  - iadd, ladd, fadd, dadd       Add                                  │
     │  - isub, lsub, fsub, dsub       Subtract                            │
     │  - imul, idiv, irem             Multiply/Divide/Remainder          │
     │  - ineg                         Negate                               │
     │                                                                      │
     │  Control Flow:                                                       │
     │  - ifeq, ifne, iflt, ifle      Comparison branches                 │
     │  - if_icmpeq, if_acmpeq         Object comparison branches         │
     │  - goto, goto_w                Unconditional branch                │
     │  - tableswitch, lookupswitch    Switch                               │
     │  - return, areturn              Return                              │
     │                                                                      │
     │  Object/Array:                                                       │
     │  - new, instanceof, checkcast  Object creation and casting        │
     │  - aaload, aastore             Array load/store                    │
     │  - arraylength                 Array length                         │
     │                                                                      │
     │  Method:                                                             │
     │  - invokevirtual               Instance method                     │
     │  - invokestatic                Static method                       │
     │  - invokespecial               Constructor/private                  │
     │  - invokeinterface             Interface method                    │
     │                                                                      │
     │  Synchronized:                                                       │
     │  - monitorenter, monitorexit   Synchronized block                   │
     │                                                                      │
     └─────────────────────────────────────────────────────────────────────┘
     */
    
    /**
     * Bytecode Example:
     */
    
    public int calculate(int x, int y) {
        if (x > y) {
            return x - y;
        }
        return y - x;
    }
    
    /*
    // Compiled bytecode:
    0: iload_1           // Load x (local variable 1)
    1: iload_2           // Load y (local variable 2)
    2: if_icmple 9       // If x <= y, jump to 9
    5: iload_1           // Load x
    6: iload_2           // Load y
    7: isub              // x - y
    8: ireturn           // Return int
    9: iload_2           // Load y
    10: iload_1          // Load x
    11: isub             // y - x
    12: ireturn          // Return int
    */
    
    /**
     * Frame Stack:
     * 
     * Each method invocation creates a stack frame:
     * 
     * ┌─────────────────────────────────────────────────────────────────────┐
     │                    STACK FRAME                                       │
     ├─────────────────────────────────────────────────────────────────────┤
     │  Local Variables:                                                   │
     │  - this, param1, param2, ..., local vars                           │
     │  - Accessed by: aload_0, aload_1, astore_0, astore_1               │
     │                                                                       │
     │  Operand Stack:                                                     │
     *  - Where operations happen                                           │
     *  - Max stack: method attributes                                      │
     │  - Pop/push during execution                                        │
     │                                                                       │
     │  Frame Data:                                                         │
     *  - Constant pool reference                                           │
     *  - Return address                                                    │
     │  - Monitor (for synchronized)                                       │
     │                                                                       │
     └─────────────────────────────────────────────────────────────────────┘
     */
}
```

---

## 5. JVM Performance Tuning

### 5.1 Heap Sizing

```java
// Heap sizing guidance
public class HeapTuning {
    
    /**
     * Determining Heap Size:
     * 
     * Rule of thumb: 
     * - Start with 25-30% of available system memory
     * - Tune based on actual usage patterns
     * - Monitor and adjust
     * 
     * Key metrics to watch:
     * - Old gen usage after full GC
     * - Survivor space usage
     * - Metaspace usage
     * - Direct memory usage
     */
    
    /**
     * Example Sizing:
     * 
     * For a server with 64GB RAM:
     * 
     * Option 1: Large heap
     * -Xms30g -Xmx30g
     * - Good for large datasets
     * - Risk: Long GC pauses
     * 
     * Option 2: Moderate with G1
     * -Xms16g -Xmx16g
     * -XX:MaxGCPauseMillis=200
     * - Good balance for most workloads
     * 
     * Option 3: Small heap with more containers
     * -Xms4g -Xmx4g (per container)
     * -XX:MaxRAMPercentage=75
     * - If running in Kubernetes
     */
    
    /**
     * Young Generation Sizing:
     * 
     * -XX:NewRatio=2     (young = 1/3 of heap, default)
     * -XX:NewSize=512m  (min young)
     * -XX:MaxNewSize=2g (max young)
     * 
     * More young = more memory for new objects, less promotion
     * Less young = less GC pause, more promotion to old
     * 
     * Target: Minor GC should take < 100ms
     */
}
```

### 5.2 GC Tuning Strategies

```java
// GC tuning strategies
public class GCTuning {
    
    /**
     * G1 Tuning:
     */
    
    /**
     * 1. Set pause time goal:
     * -XX:MaxGCPauseMillis=200
     * 
     * G1 will try to meet this, may adjust young gen size
     * If you need more throughput, increase this value
     */
    
    /**
     * 2. Set heap region size:
     * -XX:G1HeapRegionSize=16m (for large objects)
     * -XX:G1HeapRegionSize=4m (for many small objects)
     * 
     * If you see many humongous allocations, increase
     */
    
    /**
     * 3. Tune mixed collections:
     * -XX:InitiatingHeapOccupancyPercent=45 (default)
     * -XX:G1MixedGCLiveThresholdPercent=85 (don't collect regions >85% full)
     * 
     * If old gen grows fast, decrease IHOP
     */
    
    /**
     * ZGC Tuning:
     * 
     * -XX:+UseZGC
     * -XX:ZHeapInitialSize=4g
     * -XX:ZHeapMaximumSize=16g
     * -XX:ParallelGCThreads=8
     * -XX:ConcGCThreads=2
     * 
     * ZGC scales with available CPUs
     */
    
    /**
     * Common GC Problems and Solutions:
     * 
     * Problem: Long minor GC pauses
     * Solution: Increase young gen size or reduce allocation rate
     * 
     * Problem: Full GC takes too long
     * Solution: Increase heap or switch to G1/ZGC
     * 
     * Problem: Old gen fills up
     * Solution: Fix memory leaks, increase old gen ratio
     * 
     * Problem: Metaspace OOM
     * Solution: Increase MaxMetaspaceSize, check classloader leaks
     */
}
```

---

## 6. Memory Leaks and Troubleshooting

### 6.1 Common Leak Patterns

```java
// Memory leak patterns
public class MemoryLeakPatterns {
    
    /**
     * Pattern 1: Static Collections
     * 
     * Most common in enterprise applications:
     */
    
    // This NEVER gets cleaned!
    public class BadCache {
        private static final Map<String, Object> CACHE = new HashMap<>();
        
        public void put(String key, Object value) {
            CACHE.put(key, value);  // Never removed!
        }
        
        // Fix: Use WeakHashMap or add TTL
        // private static final Map<String, WeakReference<Object>> CACHE = ...
    }
    
    /**
     * Pattern 2: Listener/Callback Leaks
     */
    
    public class EventSource {
        private final List<EventListener> listeners = new ArrayList<>();
        
        public void addListener(EventListener l) {
            listeners.add(l);  // Never removed!
        }
        
        // Fix: Add removeListener() and call it!
    }
    
    /**
     * Pattern 3: ThreadLocal
     */
    
    public class ThreadLocalLeak {
        private static final ThreadLocal<Connection> conn = 
            ThreadLocal.withInitial(() -> {
                try {
                    return DataSource.getConnection();
                } catch (SQLException e) {
                    throw new RuntimeException(e);
                }
            });
        
        // Problem: Thread pool reuses threads!
        // If not removed, Connection lives for thread lifetime
        // 
        // Fix: Always clean up
        // finally { conn.remove(); }
    }
    
    /**
     * Pattern 4: Connection Leaks
     */
    
    public class ConnectionLeak {
        public void bad() throws SQLException {
            Connection c = ds.getConnection();  // Not closed!
            // Fix: try-with-resources
        }
        
        public void good() throws SQLException {
            try (Connection c = ds.getConnection()) {
                // Auto-closed
            }
        }
    }
    
    /**
     * Pattern 5: Inappropriate Object References
     */
    
    public class ObjectReferenceLeak {
        // This keeps entire object graph alive!
        private static Object bigObject;
        
        public void leak() {
            bigObject = createLargeObject();
        }
        
        // Fix: Use weak references or clear explicitly
    }
}
```

### 6.2 Leak Detection Tools

```java
// Leak detection approaches
public class LeakDetection {
    
    /**
     * 1. Heap Dump Analysis:
     * 
     * jmap -dump:format=b,file=heap.bin <pid>
     * 
     * Tools:
     * - Eclipse MAT (Memory Analyzer Tool)
     * - VisualVM
     * - JProfiler
     * - YourKit
     * 
     * Key MAT features:
     * - Leak Suspects Report
     * - Dominator Tree (who keeps what alive)
     * - Path to GC Roots (why is it retained)
     * - OQL (SQL for heap)
     */
    
    /**
     * 2. JProfiler Leak Detection:
     */
    
    /*
     * - Allocate heap recorder
     * - Take two snapshots
     * - Compare - look for growing allocations
     * 
     * JProfiler > Snapshots > Compare
     */
    
    /**
     * 3. VisualVM with Heap Walker:
     */
    
    /*
     * - Heap dump
     * - Classes (sort by instances)
     * - Right click > Show in Heap Walker
     * - Find retention path
     */
    
    /**
     * 4. JConsole / JMX:
     */
    
    /*
     * - Monitor MBeans
     * - Java.lang > Memory > HeapMemoryUsage
     * - Trigger GC and watch
     */
    
    /**
     * 5. Java Flight Recorder (JFR):
     */
    
    /*
     * Start recording:
     * -XX:StartFlightRecording:filename=recording.jfr
     * 
     * Analyze:
     * - Object Allocation Profiling
     * - GC Configuration
     * - Memory Leak detection events
     */
}
```

---

## 7. JVM Profiling and Diagnostics

### 7.1 Diagnostic Tools

```java
// JVM diagnostic tools
public class DiagnosticTools {
    
    /**
     * jcmd - All-in-one diagnostic command:
     * 
     * jcmd <pid> VM.native_memory summary
     * jcmd <pid> GC.heap_info
     * jcmd <pid> Thread.print
     * jcmd <pid> VM.log
     * jcmd <pid> GC.run
     * jcmd <pid> GC.class_histogram
     */
    
    /**
     * jstack - Thread dumps:
     * 
     * jstack -l <pid>  // Full thread dump
     * jstack -F <pid>  // Force if regular dump fails
     * 
     * Shows:
     * - Thread states
     * - Lock information
     * - Stack traces
     * - Deadlock detection
     */
    
    /**
     * jmap - Memory tools:
     * 
     * jmap -heap <pid>     // Heap summary
     * jmap -clstats <pid>  // Classloader stats
     * jmap -dump:format=b,file=heap.hprof <pid>
     * jmap -histo <pid>    // Histogram of objects
     */
    
    /**
     * jstat - Statistics:
     * 
     * jstat -gcutil <pid> 1000  // GC statistics every 1s
     * 
     * Output:
     * S0  S1  E   O   M   CCS  YGC YGCT  GGC  FGCT  GCT
     * 0   0  45  67  78  80    5  0.234   0     0    0.234
     * 
     * YGC = Young GC count
     * YGCT = Young GC cumulative time
     * GGC = Full GC count
     * FGCT = Full GC cumulative time
     */
}
```

### 7.2 Java Flight Recorder

```java
// JFR configuration
public class JFRConfiguration {
    
    /**
     * JFR Events:
     * 
     * - jdk.ObjectAllocationInNewTLAB
     * - jdk.ObjectAllocationOutsideTLAB
     * - jdk.OldObjectSample (for leak detection)
     * - jdk.GCConfiguration
     * - jdk.GCHeapSummary
     * - jdk.CPULoad
     * - jdk.JavaExceptionThrow
     * 
     * Enabled by default in Java 11+ (needs commercial license < 11)
     */
    
    /**
     * Recording Types:
     * 
     * 1. Continuous (background):
     *    -XX:StartFlightRecording:filename=recording.jfr
     *    -XX:StartFlightRecording=maxsize=100m,maxage=6h
     * 
     * 2. On-demand (one-shot):
     *    jcmd <pid> JFR.start duration=60s filename=dump.jfr
     * 
     * 3. Triggered (on event):
     *    jcmd <pid> JFR.start settings=profile ...
     */
    
    /**
     * Analyzing with jfr:
     * 
     * jfr print --events "jdk.ObjectAllocationInNewTLAB" recording.jfr
     * 
     * jfr print --json recording.jfr > analysis.json
     * 
     * JMC (Java Mission Control):
     * - GUI for JFR
     * - Built-in analysis
     * - Great for production debugging
     */
}
```

---

## 8. Modern JVM Features and Optimizations

### 8.1 Project Valhalla

```java
// Value types preview
public class ValhallaPreview {
    
    /**
     * Value Types (Project Valhalla):
     * 
     * - Currently in progress (preview in Java 21+)
     * - Inline types with identity
     * - No object header (except for alignment)
     * - No nullability (can have default)
     * - Comparisons by value, not reference
     */
    
    // Example (when released):
    
    /*
     inline class Point {
         public final int x;
         public final int y;
         
         public Point(int x, int y) {
             this.x = x;
             this.y = y;
         }
     }
     
     // No object header - stored inline in containing object
     // Point[] stored as contiguous int pairs!
     */
    
    /**
     * Benefits:
     * 
     * - Better cache locality
     * - No GC for small objects
     * - Memory savings (no object header)
     * - Automatic inlining by JIT
     */
}
```

### 8.2 Project Loom (Virtual Threads)

```java
// Virtual threads preview
public class VirtualThreadsPreview {
    
    /**
     * Virtual Threads (Project Loom, Java 21+):
     * 
     * - Very lightweight threads (MB vs GB)
     * - Millions per application possible
     * - Managed by JVM, not OS
     * - No more thread-per-request model limitations
     */
    
    // Creating virtual threads:
    
    /*
     Thread virtualThread = Thread.startVirtualThread(() -> {
         // Runs on virtual thread
         // Can use regular blocking I/O
     });
     
     // Or using executor
     ExecutorService executor = Executors.newVirtualThreadPerTaskExecutor();
     Future<?> result = executor.submit(() -> process(request));
     */
    
    /**
     * How it works:
     * 
     * - Virtual thread runs on carrier thread
     * - When blocking I/O, carrier thread "parks" virtual
     * - Scheduler picks another virtual to run on carrier
     * - Result: Many virtual threads, few carrier threads
     * 
     * Traditional: 10k concurrent requests = 10k threads = lots of memory
     * Virtual: 10k concurrent requests = 10k virtual, ~100 carrier
     */
    
    /**
     * Compatibility:
     * 
     * - Works with existing thread APIs
     * - No changes to synchronization needed (but don't hold locks!)
     * - ThreadLocal can still be used but consider ThreadLocal::remove
     */
}
```

---

This comprehensive JVM internals guide covers deep technical details needed for advanced Java development and performance optimization.