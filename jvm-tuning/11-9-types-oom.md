# How to Troubleshoot 9 Types of OutOfMemoryError

Most developers treat OutOfMemoryError as a single problem. In reality, it's nine distinct error types, each with different causes and solutions. Understanding which OOM you're facing is the first step to resolution.

## The 9 Types of OutOfMemoryError

### 1. Java heap space

**Cause**: The most common OOM. The heap cannot accommodate new objects.

**Diagnosis**:
```bash
jmap -heap <pid>  # Check heap usage
jmap -dump:format=b,file=heap.hprof <pid>  # Capture for analysis
```

**Solutions**:
- Increase -Xmx
- Fix memory leaks (analyze heap dump in MAT)
- Optimize object creation patterns

### 2. GC overhead limit exceeded

**Cause**: JVM spends >98% of time in GC but reclaims <2% of heap.

**Diagnosis**:
```bash
jstat -gc <pid>  # Look for frequent GC with low reclamation
```

**Solutions**:
- Increase heap size
- Reduce object allocation rate
- Fix memory leaks

### 3. Metaspace

**Cause**: Metaspace (class metadata) exceeds -XX:MaxMetaspaceSize.

**Diagnosis**:
```bash
jstat -gc <pid>  # Check MU (Metaspace Used) vs MC (Metaspace Capacity)
```

**Solutions**:
- Increase -XX:MaxMetaspaceSize
- Reduce class loading (check for dynamic class generation)
- Audit reflection usage

### 4. Unable to create new native thread

**Cause**: OS cannot create new threads (ulimit reached or memory exhausted).

**Diagnosis**:
```bash
ulimit -a  # Check thread limits
ps -eLf | grep java | wc -l  # Count threads
```

**Solutions**:
- Reduce thread pool sizes
- Limit concurrent requests
- Increase OS thread limits

### 5. Direct buffer memory

**Cause**: Native (off-heap) buffers exceed -XX:MaxDirectMemorySize.

**Diagnosis**:
```bash
jcmd <pid> VM.native_memory summary  # Check direct memory usage
```

**Solutions**:
- Increase -XX:MaxDirectMemorySize
- Fix NIO channel leaks
- Use smaller buffer sizes

### 6. Requested array size exceeds JVM limit

**Cause**: Trying to allocate array larger than maximum supported size.

**Diagnosis**: Check code for large array allocations

**Solutions**:
- Split into smaller chunks
- Use streaming/chunked processing
- Review algorithm logic

### 7. Java heap space (promotion failure)

**Cause**: Young generation objects cannot promote to old generation.

**Diagnosis**:
```bash
jstat -gcutil <pid>  # Check Old Space usage before OOM
```

**Solutions**:
- Increase old generation size
- Increase -Xmx
- Optimize promotion patterns

### 8. Compressed class space

**Cause**: Compressed class space (-pointer) limit exceeded.

**Diagnosis**:
```bash
jinfo -flag CompressedClassSpaceSize <pid>
```

**Solutions**:
- Increase -XX:CompressedClassSpaceSize
- Use -XX:-UseCompressedClassPointers if not needed

### 9. Unknown (native OOM)

**Cause**: Native memory allocation failed (not heap or metaspace).

**Diagnosis**:
```bash
dmesg  # Check for OOM killer messages
jcmd <pid> VM.native_memory summary
```

**Solutions**:
- Reduce JNI memory usage
- Increase OS memory
- Fix native leaks

## Diagnostic Framework

When OOM occurs:

1. **Read the message** — it tells you which area failed
2. **Check jstat** — understand GC behavior leading up to OOM
3. **Capture heap dump** — analyze for memory leaks
4. **Review code patterns** — identify allocation hotspots

## Conclusion

OutOfMemoryError is not a single problem to solve—it's a symptom classification. Each type requires a different diagnostic approach and solution. Master all nine, and no OOM will stump you.