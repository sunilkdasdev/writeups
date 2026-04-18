# JDK自带调优五件套深度解析

当生产环境出现性能问题时，依赖外部工具往往远水解不了近火。JDK自带调优工具是每个Java工程师必须掌握的核心技能，它们能在秒级响应下诊断最常见的性能问题。

## Jstat：统计信息监控

Jstat是JVM统计信息监控工具，可以实时查看堆内存各区域的使用情况：

```bash
# 查看类加载统计
jstat -class <pid>

# 查看GC统计（每1000ms刷新一次，共5次）
jstat -gc <pid> 1000 5

# 查看年轻代GC统计
jstat -gcnew <pid>
```

关键输出指标：
- **S0C/S1C**: Survivor 0/1 容量
- **S0U/S1U**: Survivor 0/1 使用量
- **EC/EU**: Eden区容量/使用
- **OC/OU**: 老年代容量/使用
- **MC/MU**: Metaspace 容量/使用

## Jinfo：运行时配置查看与修改

Jinfo可以查看和修改JVM启动参数：

```bash
# 查看所有系统属性
jinfo -sysprops <pid>

# 查看所有JVM参数
jinfo -flags <pid>

# 动态修改参数（仅限manageable参数）
jinfo -flag MinHeapFreeRatio=30 <pid>
```

## Jmap：堆内存快照

Jmap用于生成堆转储文件和查看内存使用情况：

```bash
# 生成堆转储文件
jmap -dump:format=b,file=heap.bin <pid>

# 查看堆内存使用摘要
jmap -heap <pid>

# 查看对象统计（按对象大小排序）
jmap -histo <pid>
```

## Jhat：堆转储分析

Jmap生成的二进制堆转储需要分析工具：

```bash
# 启动堆分析服务器（默认端口7000）
jhat heap.bin

# 访问 http://localhost:7000 查看分析结果
```

Jhat提供OQL查询界面，可以执行类似SQL的查询来定位对象。

## Jstack：线程堆栈分析

Jstack是最常用的线程分析工具：

```bash
# 打印线程堆栈
jstack <pid>

# 打印锁信息
jstack -l <pid>

# 强制输出（如果正常输出卡住）
jstack -F <pid>
```

### 关键分析点

1. **Blocked/Waiting线程**：长时间阻塞可能表示死锁或资源等待
2. **Locked Ownable Synchronizers**：查看正在等待的锁
3. **CPU占用高的线程**：结合top -H命令定位具体线程

## 快速诊断流程

```bash
# 1. 检查进程是否存活
jps -l

# 2. 查看内存总体状况
jstat -gc 12345

# 3. 查看详细堆信息
jmap -heap 12345

# 4. 导出堆转储（可选）
jmap -dump:format=b,file=heap.hprof 12345

# 5. 查看线程信息
jstack 12345
```

掌握这五件套，80%的JVM问题都能在分钟级内定位。