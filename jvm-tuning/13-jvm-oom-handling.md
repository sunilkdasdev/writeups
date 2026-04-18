# How to Deal with JVM Out of Memory

When "Java heap space" errors appear in production, every second counts. This is the immediate checklist for handling OOM emergencies and regaining stability.

## Step 1: Read the Error Message

The OOM message tells you the location:

```
java.lang.OutOfMemoryError: Java heap space
java.lang.OutOfMemoryError: Metaspace
java.lang.OutOfMemoryError: GC overhead limit exceeded
```

Each indicates a different failure mode.

## Step 2: Immediate Actions

### Capture Evidence (Before Restart!)

```bash
# Thread dump - captures state at failure moment
jstack -F <pid> > threaddump.txt

# Heap dump - critical for post-mortem analysis
jmap -dump:format=b,file=heap.hprof <pid>

# GC logs - shows what led to failure
# Check -Xloggc location or use:
jcmd <pid> GC.heap_info
```

### If Application Still Running

```bash
# Monitor what's consuming memory
jstat -gc <pid> 1000

# Check class loading
jstat -class <pid>
```

## Step 3: Adjust Memory (Temporarily)

If you can modify JVM flags without restart (JDK 9+):

```bash
# Increase heap (if using CDS/AppCDS)
jinfo -flag -Xmx=4g <pid>
```

For immediate relief, add or increase swap (not ideal but can buy time):

```bash
# Linux
sudo swapon -a
```

## Step 4: Analyze Heap Dump

Open heap.hprof in Eclipse MAT or VisualVM:

1. Run "Leak Suspects" report
2. Sort by "Retained Heap" size
3. Right-click → "Path to GC Roots"
4. Trace why these objects are retained

## Step 5: Fix and Prevent

### If Memory Leak

- Code fix required (don't just increase heap)
- May need graceful restart strategy

### If Insufficient Heap

Calculate合理大小:

```bash
# Average object size × active objects + headroom
# Monitor with: -XX:+PrintGCDetails -XX:+PrintGCTimeStamps
```

### If GC Overhead

- More frequent minor GCs indicate allocation rate issue
- Full GCs indicate heap too small or memory leak

## Emergency Checklist

| Action | Command | Priority |
|--------|---------|----------|
| Thread dump | jstack -F | Immediate |
| Heap dump | jmap -dump | Immediate |
| GC logs | Check -Xloggc | Immediate |
| Heap usage | jstat -gc | Monitor |
| Process memory | ps -o pid,rss,vsz | Monitor |

## Conclusion

OOM is an emergency but not a mystery. Capture evidence before restart, analyze heap dump to find root cause, and implement fix—not just band-aid with larger heap.