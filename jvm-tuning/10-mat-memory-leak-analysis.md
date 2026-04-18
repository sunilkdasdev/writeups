# 深入Java性能调优与故障排查：MAT内存泄漏分析与GC Roots定位

当OutOfMemoryError反复出现时，表面的堆调整只是拖延问题。真正的解决方案需要找到内存泄漏的根源——那些不再使用但仍被引用的对象。Eclipse MAT是分析堆转储的首选工具。

## GC Roots：理解引用链的起点

GC Roots是垃圾回收的起点，从这些根对象开始遍历，所有可达的对象都会被保留，不可达的对象则被回收。常见的GC Roots包括：

1. **栈中的局部变量**：方法栈帧中的本地变量表
2. **静态变量**：类的静态属性
3. **JNI引用**：本地方法中的Java对象引用
4. **活跃的线程**：正在运行的线程对象

## Dominator Tree：快速定位支配节点

MAT的Dominator Tree显示对象之间的支配关系：

- 对象A支配对象B：如果A存活，则B必然存活
- 帮助你快速定位"谁持有了不该持有的内存"

## 查找泄漏实例

### 步骤1：导出堆转储

```bash
jmap -dump:format=b,file=heap.hprof <pid>
```

### 步骤2：打开MAT分析

使用MAT打开heap.hprof，选择"Leak Suspects"报告。

### 步骤3：分析支配树

找到占用大量内存的对象，问自己：
- 这个对象为什么这么大？
- 它的引用链来自哪里？
- 这些引用是否应该存在？

## 典型泄漏模式

### 模式1：静态集合持有

```java
public class Cache {
    private static Map<String, Object> cache = new HashMap<>();
    
    public void put(String key, Object value) {
        cache.put(key, value);  // 永远不清理
    }
}
```

分析：在MAT中看到java.util.HashMap$Node占用了大量内存，检查静态字段引用链。

### 模式2：监听器未注销

```java
public class EventManager {
    private List<Listener> listeners = new ArrayList<>();
    
    public void addListener(Listener l) {
        listeners.add(l);  // 添加后从不移除
    }
}
```

分析：找到EventManager实例，查看listeners数组中的对象是否都还是活动的。

### 模式3：ThreadLocal泄漏

```java
public class UserContext {
    private static ThreadLocal<User> userHolder = new ThreadLocal<>();
    
    public static void setUser(User u) {
        userHolder.set(u);  // 请求结束后未清理
    }
}
```

分析：在MAT中搜索ThreadLocal$ThreadLocalMap，查看Entry数组中的过期引用。

## GC Roots定位技巧

在MAT中使用"OQL"查询快速定位：

```sql
SELECT * FROM instanceof java.util.HashMap WHERE size > 1000
```

或者右键对象 → "Path to GC Roots" → 排除弱引用和软引用，查看实际强引用链。

## 结论

OutOfMemoryError不是终点，而是诊断的开始。通过MAT的Dominator Tree和GC Roots分析，你可以精确定位泄漏点，从根本上解决内存问题。