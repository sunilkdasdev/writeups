# JVM 与 K8s Limits 不匹配导致 OOMKilled 故障复盘

这是一个典型的生产事故：JVM在Kubernetes中运行，设置了对等(equal)的requests和limits，看起来合理。然而，应用被OOMKilled了。

## 故障现象

```yaml
# Deployment配置
resources:
  requests:
    memory: "1Gi"
  limits:
    memory: "1Gi"
```

```bash
# Pod事件
Events:
  Type     Reason        Age   From                   Message
  ----     ------        ----  ----                   -------
  Warning  OOMKilled     2m    kubelet                Container java oom-killed
```

应用重启后再次OOMKilled，形成反复崩溃。

## 根因分析

### JVM 不认识 cgroup 限制

问题的核心：JVM默认使用物理内存而非容器限制来计算堆大小。

```bash
# 容器限制: 1GB
# JVM启动时看到的系统内存: 16GB (节点大小)

# JVM计算:
-Xmx = 物理内存 / 4 ≈ 4GB  # 默认最大堆
-Xms = 物理内存 / 64 ≈ 256MB
```

JVM请求了4GB堆，加上Metaspace、Direct Memory、线程栈，总需求远超1GB容器限制。

### cgroup 内存超出

当容器实际使用超过1GB时：
1. Linux OOM Killer触发
2. cgroup内存限制被触发
3. 容器被OOMKilled

## 解决方案

### 方案1：使用 MaxRAMPercentage (推荐)

```yaml
env:
  - name: JAVA_OPTS
    value: "-XX:MaxRAMPercentage=75.0 -XX:+UseContainerSupport"
```

-XX:+UseContainerSupport(Java 10+)让JVM自动读取容器cgroup限制。

### 方案2：手动设置堆大小

```yaml
env:
  - name: JAVA_OPTS
    value: "-Xmx800m -Xms400m -XX:MaxMetaspaceSize=128m -XX:MaxDirectMemorySize=100m"
```

### 方案3：使用JDK内置容器支持

```bash
# Java 8u191+ 支持容器资源检测
docker run -m 1g openjdk:8u191 ...
# JVM自动识别1GB限制
```

## 配置建议

```yaml
spec:
  containers:
  - name: java-app
    resources:
      limits:
        memory: "1Gi"
      requests:
        memory: "1Gi"
    env:
    - name: JAVA_TOOL_OPTIONS
      value: "-XX:MaxRAMPercentage=75 -XX:+UseContainerSupport -XX:+UseG1GC"
    # 留25%给非堆内存
```

## 验证配置

```bash
# 查看JVM实际使用的内存
jcmd <pid> VM.native_memory summary

# 查看容器内存使用
docker stats <container-id>

# 查看OOM原因
kubectl describe pod <pod-name> -n <namespace>
```

## 结论

Kubernetes limits和JVM内存配置必须匹配。使用MaxRAMPercentage是现代Java应用在容器中运行的最佳实践。