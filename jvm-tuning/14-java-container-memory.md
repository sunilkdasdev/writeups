# 揭开 Java 容器“消失的内存”之谜

在Kubernetes中运行Java应用时，一个常见的困惑是：容器的内存使用量超过了JVM堆大小。设置了-Xmx512m，容器却用了800MB。这"消失"的内存去哪了？

## 内存分布：JVM不只是堆

JVM的内存不仅仅包含堆(Heap)，还包括：

```
容器内存 = 
  JVM Heap (堆内)
  + Metaspace (类元数据)
  + Code Cache (JIT编译代码)
  + Direct Memory (NIO直接缓冲区)
  + Thread Stacks (线程栈)
  + Native Memory (JNI、本地代码)
  + JVM内部结构
```

## 原因1：Off-Heap 内存

NIO的Direct ByteBuffer使用堆外内存：

```java
ByteBuffer buffer = ByteBuffer.allocateDirect(1024 * 1024);  // 不在堆中
```

这些内存由-XX:MaxDirectMemorySize控制，默认为heap大小。

## 原因2：Metaspace

类加载器加载的类信息存储在Metaspace：

```bash
jstat -gc <pid> | grep MC MU
# MC = Metaspace Capacity
# MU = Metaspace Used
```

动态类生成(Reflection, ASM, 代理)会快速填满Metaspace。

## 原因3：Thread Stacks

每个线程默认占用1MB栈空间：

```bash
# 100个线程 = 100MB额外内存
jinfo -flag -Xss1m <pid>
```

## 原因4：GC Logs和内部开销

GC日志、JVMTI Agent、instrumentation都会占用内存。

## 原因5：RSS vs RSS

容器显示的RSS(Resident Set Size)包含：

- JVM堆
- 元空间
- 直接内存
- 线程栈
- 共享库
- JVM内部结构

## 解决方案

### 1. 正确设置JVM参数

```yaml
# Kubernetes配置
resources:
  limits:
    memory: "1Gi"
env:
  - name: JAVA_OPTS
    value: "-XX:MaxRAMPercentage=75 -XX:+UseContainerSupport"
```

关键参数：
- -XX:MaxRAMPercentage：自动根据容器限制计算堆大小
- -XX:+UseContainerSupport：启用容器感知(Java 10+)

### 2. 设置堆外内存限制

```bash
# 限制直接内存
JAVA_OPTS="-XX:MaxDirectMemorySize=256m"

# 限制Metaspace
JAVA_OPTS="-XX:MaxMetaspaceSize=256m"
```

### 3. 监控并调优

```bash
# 查看实际内存分布
jcmd <pid> VM.native_memory summary
```

## 结论

容器内存 ≠ JVM堆。了解Off-Heap各组件的大小，正确配置MaxRAMPercentage和各项限制，才能实现容器内存的精确控制。