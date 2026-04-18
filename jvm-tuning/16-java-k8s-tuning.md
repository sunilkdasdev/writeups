# Kubernetes 中 Java 应用性能调优指南

在Kubernetes中运行Java应用需要特殊考虑：资源限制、调度决策、监控集成都影响应用性能。本指南提供系统性的Kubernetes Java调优方法。

## 资源规划：Requests 和 Limits

### Requests：调度的基础

```yaml
resources:
  requests:
    cpu: "500m"
    memory: "1Gi"
```

Kubernetes调度器使用requests决定Pod应该放在哪个节点。

### Limits：保护与隔离

```yaml
resources:
  limits:
    cpu: "2000m"
    memory: "2Gi"
```

CPU是弹性资源(可压缩)，内存是硬限制(不可压缩)。

## JVM 参数与 Kubernetes 集成

### 正确配置堆大小

```yaml
env:
- name: JAVA_OPTS
  value: "-XX:MaxRAMPercentage=50 -XX:+UseContainerSupport"
```

50%留给非堆内存(Metaspace, Direct Memory, Buffer等)。

### G1GC 推荐配置

```yaml
env:
- name: JAVA_TOOL_OPTIONS
  value: "-XX:MaxRAMPercentage=50 -XX:+UseContainerSupport -XX:MaxGCPauseMillis=200 -XX:+UseG1GC"
```

### 线程栈配置

```yaml
env:
- name: JAVA_TOOL_OPTIONS
  value: "-Xss512k"  # 减少每线程内存占用
```

## 调度优化

### 亲和性和反亲和性

```yaml
affinity:
  podAntiAffinity:
    preferredDuringSchedulingIgnoredDuringExecution:
    - weight: 100
      podAffinityTerm:
        labelSelector:
          matchLabels:
            app: java-app
        topologyKey: kubernetes.io/hostname
```

防止单节点部署多个Java Pod导致资源争抢。

### 污点和容忍

```yaml
tolerations:
- key: "high-memory"
  operator: "Equal"
  value: "true"
  effect: "NoSchedule"
```

将Java应用调度到高内存节点。

## 监控集成

### 关键指标

| 指标 | 告警阈值 | 说明 |
|------|---------|------|
| Heap Used | >80% -Xmx | 堆使用率 |
| GC Frequency | >1/min | GC过于频繁 |
| GC Duration | >500ms | GC暂停过长 |
| Thread Count | >200 | 线程泄漏 |
| Pod Memory | >90% limit | 接近容器限制 |

### Prometheus + JMX Exporter

```yaml
sidecar:
- image: jmx-exporter
  ports:
    - containerPort: 9404
  env:
  - name: JAVA_TOOL_OPTIONS
    value: "-javaagent:jmx_prometheus_javaagent.jar=9404:config.yaml"
```

### Grafana 仪表板

导入jvm-dashboard，监控：
- Heap usage
- GC pause times
- Non-heap memory
- Thread count
- Class loading

## 健康检查

### Liveness Probe

```yaml
livenessProbe:
  httpGet:
    path: /health/live
    port: 8080
  initialDelaySeconds: 60
  periodSeconds: 10
```

初始延迟要足够长，避免JVM启动期间被误杀。

### Readiness Probe

```yaml
readinessProbe:
  httpGet:
    path: /health/ready
    port: 8080
  periodSeconds: 5
  failureThreshold: 3
```

## 总结

Kubernetes Java调优是一个系统性问题，涉及：
1. 资源限制的合理配置
2. JVM参数的正确设置
3. 调度策略的优化
4. 监控体系的完善

遵循本指南，可以实现Java应用在Kubernetes中的稳定运行。