# JVM Deep Dive: Understanding Java Virtual Machine Internals

**By Donald K. Burleson**

---

## Introduction: Why the JVM Matters

In my decades of Java consulting, I've seen developers write excellent code that runs slowly because they don't understand the JVM. The Java Virtual Machine is where your Java code becomes reality.

At Manhattan Associates, understanding JVM internals has saved us millions in hardware costs and prevented countless production outages.

---

## Chapter 1: JVM Architecture Overview

### The JVM Components

```
┌─────────────────────────────────────────────────────────────────┐
│                        JVM Process                               │
├─────────────────────────────────────────────────────────────────┤
│  Class Loader Subsystem                                          │
│  ───────────────────                                             │
│  • Bootstrap ClassLoader (JDK/lib)                              │
│  • Extension ClassLoader (JDK/lib/ext)                          │
│  • Application ClassLoader (classpath)                           │
│                                                                  │
│  Runtime Data Areas                                             │
│  ────────────────                                               │
│  • Method Area (class metadata)                                 │
│  • Heap (objects, arrays)                                       │
│  • JVM Stack (per-thread)                                       │
│  • Native Method Stack (per-thread)                             │
│  • PC Register (per-thread)                                    │
│                                                                  │
│  Execution Engine                                                │
│  ────────────────                                               │
│  • Interpreter                                                  │
│  • JIT Compiler (HotSpot)                                       │
│  • Garbage Collector                                            │
└─────────────────────────────────────────────────────────────────┘
```

### JVM Memory Model

```java
// Runtime memory regions
public class MemoryDemo {
    // Heap - allocated with new
    Object object = new Object();  // Heap
    
    // Static - in method area
    static String staticVar = "value";  // Method Area
    
    // Local variables - in stack
    public void method() {
        int local = 10;  // Stack (primitive)
        String str = "hello";  // Stack (reference to heap)
    }
}
```

---

## Chapter 2: Class Loading Deep Dive

### Loading Process

```java
// Class loading phases
class ClassLoader {
    // 1. Loading - read .class file
    // 2. Linking - verify, prepare, resolve
    // 3. Initialization - <clinit> execution
}
```

### Custom ClassLoader

```java
public class CustomClassLoader extends ClassLoader {
    @Override
    protected Class<?> findClass(String name) throws ClassNotFoundException {
        byte[] classData = loadClassData(name);
        return defineClass(name, classData, 0, classData.length);
    }
    
    private byte[] loadClassData(String name) {
        // Load .class file from disk/network
        return ...;
    }
}

// Usage
CustomClassLoader loader = new CustomClassLoader();
Class<?> clazz = loader.loadClass("com.example.MyClass");
```

### Parent Delegation

```java
// ClassLoader hierarchy
// Bootstrap → Extension → Application → Custom

// Delegation model
Class<?> loadClass(String name) {
    // 1. Check if already loaded
    Class<?> c = findLoadedClass(name);
    if (c != null) return c;
    
    // 2. Ask parent first
    if (parent != null) {
        c = parent.loadClass(name);
        if (c != null) return c;
    }
    
    // 3. Load myself
    return findClass(name);
}
```

---

## Chapter 3: Heap Deep Dive

### Heap Structure

```java
// JVM heap regions (in G1GC)
-XX:MaxGCPauseMillis=200
-XX:G1NewSizePercent=5
-XX:G1MaxNewSizePercent=60
-XX:InitiatingHeapOccupancyPercent=45
```

```
┌─────────────────────────────────────────────────────────────────┐
│                          Heap                                    │
├─────────────────────────────────────────────────────────────────┤
│  Young Generation                                               │
│  ────────────────                                               │
│  ┌─────────────┬─────────────┬─────────────┐                   │
│  │    Eden     │ Survivor 0 │ Survivor 1 │                   │
│  │   (New)     │    (S0)    │    (S1)     │                   │
│  │             │            │             │                   │
│  └─────────────┴─────────────┴─────────────┘                   │
│       ↑                                       ↑                 │
│       └────────── Allocation ────────────────┘                 │
│                                                                  │
│  Old Generation                                                 │
│  ──────────────                                                │
│  ┌─────────────────────────────────────────┐                  │
│  │           Tenured / Old Space            │                 │
│  │                                         │                  │
│  └─────────────────────────────────────────┘                  │
│                                                                  │
│  Metaspace                                                      │
│  ──────────                                                     │
│  ┌─────────────────────────────────────────┐                  │
│  │   Class Metadata, Methods, Constants    │                  │
│  └─────────────────────────────────────────┘                  │
└─────────────────────────────────────────────────────────────────┘
```

### Object Allocation

```java
// Allocation process
public class Allocation {
    public void allocate() {
        // 1. Check TLAB (Thread Local Allocation Buffer)
        // 2. If fits in TLAB, allocate in TLAB
        // 3. Otherwise, allocate in Eden (TLAB refill)
        // 4. If Eden full, trigger young GC
        
        Object obj = new Object();  // Fast allocation
    }
}

// Allocation shapes
class Shapes {
    // Regular object - TLAB allocation
    Object obj = new Object();
    
    // Large object - directly in old generation
    // -XX:PretenureSizeThreshold=1000000 (1MB)
    byte[] large = new byte[2 * 1024 * 1024];
}
```

### Object Header

```java
// Object header structure (64-bit JVM)
// [Mark Word: 8 bytes] [Klass Pointer: 8 bytes] [Array Length: 4 bytes]

// Mark Word contains:
// - HashCode (25 bits)
// - Age (4 bits)
// - Biased Lock (1 bit)
// - Lock (2 bits)

// Compressed class pointers (32-bit in 64-bit JVM)
// -XX:+UseCompressedClassPointers (default)
// -XX:+UseCompressedOops (default)
```

---

## Chapter 4: Garbage Collection Deep Dive

### GC Algorithms

#### Serial GC

```bash
# Single-threaded, stop-the-world
-XX:+UseSerialGC
# Young: Mark-Sweep-Compact
# Old: Mark-Sweep-Compact
```

#### Parallel GC (Throughput)

```bash
# Multi-threaded, stop-the-world
-XX:+UseParallelGC
-XX:ParallelGCThreads=8
-XX:MaxGCPauseMillis=500
```

#### CMS GC (Low Latency)

```bash
# Mostly concurrent, stop-the-world
-XX:+UseConcMarkSweepGC
-XX:CMSInitiatingOccupancyFraction=68
-XX:+UseCMSInitiatingOccupancyOnly
```

#### G1 GC (Balanced)

```bash
# Garbage First - default in Java 11+
-XX:+UseG1GC
-XX:MaxGCPauseMillis=200
-XX:G1HeapRegionSize=16m
-XX:InitiatingHeapOccupancyPercent=45
```

#### ZGC (Scalable Low Latency)

```bash
# Pauseless, scales to terabytes
-XX:+UseZGC
-XX:ZCollectionInterval=10
-XX:ZAllocationSpikeTolerance=5
```

### GC Phases

```java
// Young GC phases (ParNew/CMS)
class GCPhases {
    // 1. Initial Mark (STW) - Root objects
    // 2. Concurrent Mark - Mark live objects
    // 3. Remark (STW) - Final mark
    // 4. Concurrent Sweep - Remove dead
    // 5. Concurrent Reset - Prepare next
}
```

### Monitoring GC

```bash
# Enable GC logging
-XX:+PrintGCDetails
-XX:+PrintGCDateStamps
-Xloggc:gc.log

# Use jstat
jstat -gcutil <pid> 1000
# S0: Survivor 0 used
# S1: Survivor 1 used
# E: Eden used
# O: Old used
# M: Metaspace used
# CCS: Compressed class space
# YGC: Young GC count
# YGCT: Young GC time
# FGC: Full GC count
# FGCT: Full GC time
# GCT: Total GC time
```

---

## Chapter 5: JIT Compiler Deep Dive

### Compilation Levels

```java
// HotSpot compiles based on invocation count
// Level 0: Interpreted
// Level 1: C1 (Client) - quick compilation
// Level 2: C1 with profiling
// Level 3: C2 (Server) - optimized compilation

// Trigger compilation
for (int i = 0; i < 10000; i++) {
    hotMethod();  // After ~1000 invocations, compiled
}
```

### JIT Compiler Options

```bash
# Method inlining
-XX:MaxInlineSize=35
-XX:FreqInlineSize=325

# Compilation thresholds
-XX:CompileThreshold=10000
-XX:Tier2CompileThreshold=2000
-XX:Tier3CompileThreshold=20000

# Code cache
-XX:InitialCodeCacheSize=48m
-XX:ReservedCodeCacheSize=240m
```

### Deoptimization

```java
// When compiled code becomes invalid
// - Assumptions violated (e.g., class loaded)
// - Bail back to interpreted mode

// Inline cache invalidation
class InlineCache {
    // Initially: polymorphic call
    // If too many types: megamorphic -> stub
    
    // Check inline cache
    if (receiver.klass == cachedKlass) {
        // Fast path
    } else {
        // Megamorphic - use interface dispatch
    }
}
```

---

## Chapter 6: Bytecode Deep Dive

### Understanding Bytecode

```java
// Java source
public class Demo {
    public int add(int a, int b) {
        return a + b;
    }
}
```

```bytecode
// Compiled bytecode (javap -c)
public int add(int, int);
  Code:
   0: iload_1        // Load parameter 1
   1: iload_2        // Load parameter 2
   2: iadd           // Add
   3: ireturn        // Return int
```

### Common Bytecode Instructions

| Opcode | Meaning |
|--------|---------|
| aload_0 | Load reference from local 0 |
| aaload | Load from array |
| anewarray | Create new array |
| areturn | Return reference |
| astore | Store into local |
| checkcast | Type cast |
| dup | Duplicate stack |
| getfield | Get field value |
| invokespecial | Call constructor/private |
| invokevirtual | Call instance method |
| invokestatic | Call static method |
| monitorenter | Enter synchronized |
| new | Create object |
| putfield | Set field value |
| return | Return void |

---

## Chapter 7: JVM Performance Tuning

### Heap Sizing

```bash
# Initial and max heap
-Xms4g        # Initial heap
-Xmx4g        # Maximum heap
-Xmn2g        # Young generation size

# Metaspace
-XX:MetaspaceSize=256m
-XX:MaxMetaspaceSize=512m

# Direct memory
-XX:MaxDirectMemorySize=2g
```

### Thread Stack

```bash
# Stack size (default 1MB)
-Xss512k      # Reduce for more threads
-Xss2m        # Increase for deep recursion
```

### GC Tuning

```bash
# G1 tuning
-XX:MaxGCPauseMillis=200
-XX:G1HeapRegionSize=16m
-XX:ParallelGCThreads=16
-XX:ConcGCThreads=4
-XX:InitiatingHeapOccupancyPercent=45
-XX:G1ReservePercent=10
```

### String Deduplication

```bash
# Reduce String memory (Java 8+)
-XX:+UseStringDeduplication
```

---

## Conclusion

**Donald Sez**: "The JVM is your partner, not a black box. Understanding its internals makes you a better Java developer."

At Manhattan Associates:
1. **Size heap correctly** - Monitor actual usage
2. **Choose right GC** - G1 for balanced, ZGC for low latency
3. **Enable GC logs** - Essential for troubleshooting
4. **Understand bytecode** - Debug performance issues

---

**Next**: "JVM Heap Deep Dive: Memory Management and Optimization" - Advanced heap tuning and memory management.