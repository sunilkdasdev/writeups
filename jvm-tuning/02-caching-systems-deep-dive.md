# Caching Systems Deep Dive: Architecture, Patterns, and Implementation

## Table of Contents

1. [Cache Fundamentals and Architecture](#1-cache-fundamentals-and-architecture)
2. [Distributed Caching with Redis](#2-distributed-caching-with-redis)
3. [Cache Patterns and Strategies](#3-cache-patterns-and-strategies)
4. [Cache Invalidation and Consistency](#4-cache-invalidation-and-consistency)
5. [Memcached Architecture](#5-memcached-architecture)
6. [CDN and Edge Caching](#6-cdn-and-edge-caching)
7. [Local Caching (Caffeine, Guava, Ehcache)](#7-local-caching-caffeine-guava-ehcache)
8. [Cache Performance Optimization](#8-cache-performance-optimization)
9. [Cache Security and Monitoring](#9-cache-security-and-monitoring)
10. [Multi-Layer Caching Strategies](#10-multi-layer-caching-strategies)

---

## 1. Cache Fundamentals and Architecture

### 1.1 Why Caching Matters

```java
// The fundamental cache problem
public class CacheMotivation {
    
    /**
     * Without cache: Every request hits database
     * 
     * Request 1: SELECT * FROM users WHERE id = 1  ---> 50ms
     * Request 2: SELECT * FROM users WHERE id = 1  ---> 50ms
     * Request 3: SELECT * FROM users WHERE id = 1  ---> 50ms
     * 
     * With cache: First request hits DB, subsequent use cache
     * 
     * Request 1: GET cache:user:1 -> MISS -> DB 50ms -> SET cache -> RETURN
     * Request 2: GET cache:user:1 -> HIT -> RETURN 1ms
     * Request 3: GET cache:user:1 -> HIT -> RETURN 1ms
     * 
     * Speed improvement: 50x faster
     */
    
    /**
     * Cache hit ratio formula:
     * 
     * Hit Ratio = Hits / (Hits + Misses)
     * 
     * 95% hit ratio: 5% requests hit database
     * 99% hit ratio: 1% requests hit database
     * 99.9% hit ratio: 0.1% requests hit database
     * 
     * Impact of hit ratio:
     * - 80% hit: 1 in 5 requests hits DB
     * - 90% hit: 1 in 10 requests hits DB  
     * - 95% hit: 1 in 20 requests hits DB
     * - 99% hit: 1 in 100 requests hits DB
     * - 99.9% hit: 1 in 1000 requests hits DB
     */
}
```

### 1.2 Cache Architecture Patterns

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                    CACHE ARCHITECTURE PATTERNS                              │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  1. Local (In-Memory) Cache                                                │
│  ┌──────────────────────────────────────────────────────────────────────────┐ │
│  │  Application                                                           │ │
│  │  ┌─────────────┐                                                      │ │
│  │  │  Caffeine   │                                                      │ │
│  │  │  Guava      │                                                      │ │
│  │  │  Ehcache    │                                                      │ │
│  │  └─────────────┘                                                      │ │
│  └──────────────────────────────────────────────────────────────────────────┘ │
│  - Fastest (nanoseconds)                                                   │
│  - Limited by JVM heap                                                     │
│  - Not shared across instances                                             │
│                                                                              │
│  2. Distributed Cache                                                      │
│  ┌──────────────────────────────────────────────────────────────────────────┐ │
│  │  Application     ──►   Redis/Memcached    ──►   Database              │ │
│  │       │                    │                      │                       │ │
│  │       └───────────────────┼──────────────────────┘                       │ │
│  │                     (Network)                                           │ │
│  └──────────────────────────────────────────────────────────────────────────┘ │
│  - Shared across instances                                                 │
│  - Slower than local (milliseconds)                                       │
│  - Can handle larger datasets                                            │
│                                                                              │
│  3. Multi-Layer Caching                                                    │
│  ┌──────────────────────────────────────────────────────────────────────────┐ │
│  │  Request ──► L1 (Local) ──► L2 (Distributed) ──► Database             │ │
│  │              │              │                                           │ │
│  │              HIT           MISS                                         │ │
│  │              HIT           HIT                                           │ │
│  └──────────────────────────────────────────────────────────────────────────┘ │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

### 1.3 Cache Categories by Visibility

```java
// Cache categories
public class CacheCategories {
    
    /**
     * 1. Application-Level Cache
     * - Managed by application code
     * - Explicit get/put operations
     * - Full control over caching logic
     * 
     * Example: Redis, Memcached
     */
    
    /**
     * 2. Database Query Cache
     * - Caches query results
     * - Invalidated on table/row changes
     * - Limited flexibility
     * 
     * Example: MySQL query cache (deprecated in 8.0)
     */
    
    /**
     * 3. Object-Relational Mapping (ORM) Cache
     * - Caches entity objects
     * - Hibernate first-level (session), second-level (process)
     * - Transparent to application
     * 
     * Example: Hibernate, JPA
     */
    
    /**
     * 4. Web Response Cache
     * - Caches HTTP responses
     * - CDN, reverse proxies
     * - Full page or fragments
     * 
     * Example: Varnish, Nginx caching, CloudFront
     */
    
    /**
     * 5. Distributed Cache
     * - Cache-aside pattern
     * - Read-through, write-through
     * - Cluster-aware
     * 
     * Example: Redis Cluster, Memcached
     */
}
```

---

## 2. Distributed Caching with Redis

### 2.1 Redis Architecture Deep Dive

```java
// Redis architecture and data structures
public class RedisArchitecture {
    
    /**
     * Redis Data Structures:
     * 
     * ┌─────────────────────────────────────────────────────────────────────┐
     │                    REDIS DATA TYPES                                   │
     ├─────────────────────────────────────────────────────────────────────┤
     │                                                                      │
     │  STRING: "hello", "123", "\x00\x01"                                │
     │  - Used for: Cache, counters, session, simple values              │
     *  - Commands: GET, SET, INCR, APPEND                                 │
     │                                                                      │
     │  LIST: ["a", "b", "c", "d"]                                        │
     *  - Used for: Queues, chronological data, recent items            │
     *  - Commands: LPUSH, RPUSH, LRANGE, BLPOP                           │
     *                                                                      │
     │  SET: {"apple", "banana", "cherry"}                               │
     *  - Used for: Tags, unique items, membership testing                │
     *  - Commands: SADD, SREM, SISMEMBER, SMEMBERS                       │
     *                                                                      │
     │  SORTED SET: {"a": 1.0, "b": 2.0, "c": 3.0}                      │
     *  - Used for: Leaderboards, priorities, rankings                     │
     *  - Commands: ZADD, ZRANGE, ZRANK, ZRANGEBYSCORE                     │
     *                                                                      │
     │  HASH: {name: "John", age: 30, city: "NYC"}                        │
     *  - Used for: Objects, user profiles, metadata                      │
     *  - Commands: HSET, HGET, HGETALL, HMGET                             │
     *                                                                      │
     │  HYPERLOGLOG: (probabilistic)                                      │
     *  - Used for: Unique visits, cardinality estimation                  │
     *  - Commands: PFADD, PFCOUNT                                         │
     *                                                                      │
     │  BITMAP: [0,1,0,1,1,0]                                            │
     *  - Used for: Daily active users, boolean flags                      │
     *  - Commands: SETBIT, GETBIT, BITCOUNT, BITOP                         │
     *                                                                      │
     │  STREAM: log stream with consumer groups                           │
     *  - Used for: Event sourcing, message queues, audit logs             │
     *  - Commands: XADD, XREAD, XGROUP                                   │
     │                                                                      │
     └─────────────────────────────────────────────────────────────────────┘
     */
    
    /**
     * Redis Persistence:
     * 
     * RDB (Redis Database):
     * - Point-in-time snapshots
     * - fork() creates child process
     * - Good for backups, disaster recovery
     * - Config: save 900 1, save 300 10, save 60 10000
     * 
     * AOF (Append Only File):
     * - Write every command to log
     * - Three modes: always, everysec, no
     * - Better durability than RDB
     * - More disk space, slightly slower
     * 
     * Hybrid: RDB + AOF (recommended)
     */
    
    /**
     * Redis Cluster:
     * 
     * - Automatic sharding across 16384 slots
     * - 16384 slots / number of masters = slots per master
     * - Minimum 3 masters for quorum
     * - Automatic failover with replicas
     * 
     * Key distribution:
     * CRC16(key) % 16384 = slot
     * 
     * # redis.conf
     * cluster-enabled yes
     * cluster-config-file nodes.conf
     * cluster-node-timeout 15000
     */
}
```

### 2.2 Redis Client Implementation

```java
// Redis client patterns
public class RedisClientPatterns {
    
    // Jedis (synchronous) client
    public static class JedisExample {
        
        public void basicOperations() {
            Jedis jedis = new Jedis("localhost", 6379);
            
            // String operations
            jedis.set("user:1:name", "John");
            jedis.get("user:1:name");
            jedis.incr("counter");
            jedis.expire("user:1:name", 3600);  // TTL 1 hour
            
            // Hash operations
            Map<String, String> user = new HashMap<>();
            user.put("name", "John");
            user.put("email", "john@example.com");
            jedis.hmset("user:1", user);
            jedis.hgetAll("user:1");
            
            // List operations
            jedis.lpush("queue:orders", "order:1001");
            String order = jedis.rpop("queue:orders");
            
            // Set operations
            jedis.sadd("user:1:tags", "premium", "active", "vip");
            Set<String> tags = jedis.smembers("user:1:tags");
            
            // Sorted set for leaderboard
            jedis.zadd("leaderboard", 1500.0, "player:1");
            jedis.zrevrange("leaderboard", 0, 9);  // Top 10
            
            jedis.close();
        }
        
        /**
         * Connection pooling for high concurrency:
         */
        public void poolExample() {
            JedisPoolConfig config = new JedisPoolConfig();
            config.setMaxTotal(50);
            config.setMaxIdle(20);
            config.setMinIdle(5);
            config.setMaxWaitMillis(2000);
            
            JedisPool pool = new JedisPool(config, "localhost", 6379);
            
            try (Jedis jedis = pool.getResource()) {
                // Use jedis
            }
            
            pool.close();
        }
    }
    
    // Lettuce (reactive/async) client
    public static class LettuceExample {
        
        public void asyncOperations() {
            RedisClient client = RedisClient.create("redis://localhost:6379");
            StatefulRedisConnection<String, String> connection = 
                client.connect().sync();
            
            // Synchronous (from async)
            String value = connection.get("key");
            
            // For async:
            // RedisAsyncCommands async = connection.async();
            // Future<String> future = async.get("key");
            
            connection.close();
            client.shutdown();
        }
    }
}
```

### 2.3 Redis Pub/Sub and Streams

```java
// Redis messaging patterns
public class RedisMessaging {
    
    /**
     * Pub/Sub Pattern:
     * 
     * - Fire and forget
     * - No persistence
     * - Real-time message delivery
     * - At-least-once delivery
     */
    
    public static class PubSubExample {
        
        public void publisher(Jedis jedis) {
            jedis.publish("orders", "new:1001");
            jedis.publish("notifications", "user:123:login");
        }
        
        public void subscriber(Jedis jedis) {
            jedis.subscribe(new JedisPubSub() {
                @Override
                public void onMessage(String channel, String message) {
                    System.out.println("Received: " + message + " from " + channel);
                }
            }, "orders", "notifications");
        }
    }
    
    /**
     * Redis Streams (Kafka-like):
     * 
     * - Persistent messages
     * - Consumer groups
     * - Message IDs
     * - Range queries
     * - At-least-once delivery
     */
    
    public static class StreamExample {
        
        public void producer(Jedis jedis) {
            // Add to stream
            Map<String, String> event = new HashMap<>();
            event.put("type", "order_created");
            event.put("order_id", "1001");
            event.put("amount", "150.00");
            
            String messageId = jedis.xadd("events", null, event);
            System.out.println("Message ID: " + messageId);
            // Example: 1526985034072-0
        }
        
        public void consumer(Jedis jedis) {
            // Create consumer group
            jedis.xgroupCreate("events", "group1", "0", true);
            
            // Read new messages
            List<Map.Entry<String, Map<String, String>>> messages = 
                jedis.xreadGroup(
                    "group1",    // group name
                    "consumer1", // consumer name
                    ">",        // read new messages only
                    "COUNT", 10,
                    "BLOCK", 5000,  // block 5 seconds
                    "events"    // stream
                );
            
            for (Map.Entry<String, Map<String, String>> entry : messages) {
                String messageId = entry.getKey();
                Map<String, String> data = entry.getValue();
                
                System.out.println("ID: " + messageId + ", Data: " + data);
                
                // Acknowledge processing
                jedis.xack("events", "group1", messageId);
            }
        }
    }
}
```

---

## 3. Cache Patterns and Strategies

### 3.1 Cache-Aside Pattern

```java
// Cache-Aside (Lazy Loading) Pattern
public class CacheAsidePattern {
    
    /**
     * Read Operation:
     * 1. Check cache
     * 2. If hit, return cached data
     * 3. If miss, query database
     * 4. Store result in cache
     * 5. Return data
     * 
     * Write Operation:
     * 1. Update database
     * 2. Delete cache entry (not update!)
     *    - Why delete? Update could fail after DB update
     *    - Next read will populate cache correctly
     */
    
    private Jedis jedis;
    private UserDao userDao;
    
    public User getUserById(Long userId) {
        // Step 1: Check cache
        String cacheKey = "user:" + userId;
        String cached = jedis.get(cacheKey);
        
        if (cached != null) {
            return JSON.parseObject(cached, User.class);
        }
        
        // Step 2: Cache miss - query database
        User user = userDao.findById(userId);
        
        if (user != null) {
            // Step 3: Store in cache with TTL
            jedis.setex(cacheKey, 3600, JSON.toJSONString(user));
        }
        
        return user;
    }
    
    public void updateUser(User user) {
        // Step 1: Update database first
        userDao.update(user);
        
        // Step 2: Delete cache (not update!)
        // If we update cache and DB update fails,
        // cache has stale data
        jedis.del("user:" + user.getId());
        
        // Alternative: Set with short TTL as safety net
        jedis.setex("user:" + user.getId(), 60, JSON.toJSONString(user));
    }
    
    /**
     * Cache-Aside Pros:
     * - Simple implementation
     * - Cache only stores what's needed
     * - No cache code in application logic
     * 
     * Cache-Aside Cons:
     * - First request always slow (cache miss)
     * - Cache may have stale data
     * - Need to handle cache misses
     */
}
```

### 3.2 Write-Through and Write-Behind

```java
// Write patterns
public class WritePatterns {
    
    /**
     * Write-Through:
     * 
     * Update both cache and database at the same time
     * Cache always consistent with database
     * 
     * ┌─────────────────────────────────────────────────────────┐
     * │  Write ──► Cache ──► Database                          │
     └─────────────────────────────────────────────────────────┘
     */
    
    public static class WriteThrough {
        
        private CacheStore cache;
        private Database db;
        
        public void save(Entity entity) {
            // Update both simultaneously
            db.save(entity);
            cache.put(entity.getId(), entity);
        }
        
        /**
         * Pros:
         * - Data always consistent
         * - Read after write always hits cache
         * 
         * Cons:
         * - Slower writes (two operations)
         * - Cache could become bottleneck
         */
    }
    
    /**
     * Write-Behind (Write-Back):
     * 
     * Update cache immediately, batch database writes
     * 
     * ┌─────────────────────────────────────────────────────────┐
     * │  Write ──► Cache ──► [Queue] ──► Database (async)         │
     └─────────────────────────────────────────────────────────┘
     */
    
    public static class WriteBehind {
        
        private CacheStore cache;
        private BlockingQueue<Entity> writeQueue;
        
        public void save(Entity entity) {
            // Update cache immediately
            cache.put(entity.getId(), entity);
            
            // Queue for async database write
            writeQueue.offer(entity);
        }
        
        /**
         * Background thread processes queue:
         */
        public void processWrites() {
            while (true) {
                List<Entity> batch = new ArrayList<>();
                Entity entity;
                
                // Batch up to 100 or wait 1 second
                while ((entity = writeQueue.poll(1, TimeUnit.SECONDS)) != null 
                        && batch.size() < 100) {
                    batch.add(entity);
                }
                
                if (!batch.isEmpty()) {
                    db.batchSave(batch);
                }
            }
        }
        
        /**
         * Pros:
         * - Very fast writes
         * - Batch database operations
         * 
         * Cons:
         * - Risk of data loss if cache/server fails
         * - Complex implementation
         * - Need to handle queue overflow
         */
    }
}
```

### 3.3 Read-Through and Refresh-Ahead

```java
// Advanced caching patterns
public class AdvancedPatterns {
    
    /**
     * Read-Through:
     * 
     * Cache automatically loads from database on miss
     * Application only talks to cache
     * 
     * ┌─────────────────────────────────────────────────────────┐
     * │  Request ──► Cache (missing) ──► Load from DB ──► Return│
     └─────────────────────────────────────────────────────────┘
     */
    
    public static class ReadThrough {
        
        // Example with Spring Cache
        @Cacheable(value = "users", key = "#userId")
        public User getUser(Long userId) {
            // Only called on cache miss
            return database.findById(userId);
        }
        
        // Application code only calls cache
        public User getUserWrapper(Long userId) {
            return cacheLoader.load(userId);  // Automatic DB load
        }
    }
    
    /**
     * Refresh-Ahead (Speculative Loading):
     * 
     * Proactively refresh cache entries before they expire
     * Reduces thundering herd on cache expiration
     * 
     * ┌─────────────────────────────────────────────────────────┐
     │  Cache Entry                                            │
     │  - TTL: 1 hour                                          │
     │  - Refresh threshold: 80% (48 min)                      │
     │  - Background refresh at 48 min                        │
     └─────────────────────────────────────────────────────────┘
     */
    
    public static class RefreshAhead {
        
        // Caffeine supports refresh-ahead
        LoadingCache<String, Data> cache = Caffeine.newBuilder()
            .refreshAfterWrite(10, TimeUnit.MINUTES)  // Refresh after 10 min
            .maximumSize(10000)
            .build(key -> {
                // This is called to refresh expired entries
                return database.findByKey(key);
            });
        
        /**
         * How it works:
         * 
         * 1. Entry created at T=0, TTL=10min
         * 2. At T=8min, entry accessed
         * 3. Caffeine checks: (now - lastWrite) > refreshAfterWrite * 0.8
         * 4. If true, triggers async refresh
         * 5. While refreshing, returns old value (stale but available)
         * 6. Next access gets new value
         * 
         * Benefit: No cache misses, no thundering herd
         */
    }
}
```

---

## 4. Cache Invalidation and Consistency

### 4.1 Invalidation Strategies

```java
// Cache invalidation strategies
public class CacheInvalidation {
    
    /**
     * 1. TTL (Time To Live):
     * 
     * - Simple, automatic
     * - Eventually consistent
     * - Good for non-critical data
     */
    
    public void ttlInvalidation(Jedis jedis, String key) {
        // Set with TTL
        jedis.setex("user:123", 3600, "data");  // 1 hour
        
        // Or set then expire
        jedis.set("temp:data", "value");
        jedis.expire("temp:data", 300);  // 5 minutes
    }
    
    /**
     * 2. Write-Invalidate:
     * 
     * On write, delete cache entry
     * Next read will repopulate from DB
     */
    
    public void writeInvalidate(Jedis jedis) {
        userDao.update(user);
        jedis.del("user:" + user.getId());  // Delete, don't update
    }
    
    /**
     * 3. Event-Based Invalidation:
     * 
     * Database triggers event on change
     * Event triggers cache invalidation
     */
    
    public static class EventBasedInvalidation {
        
        public void databaseTrigger() {
            // In database trigger or application
            // After UPDATE/DELETE
            jedis.del("user:" + userId);
            jedis.publish("cache:invalidate", "user:" + userId);
        }
        
        public void subscriber(Jedis jedis) {
            jedis.subscribe(new JedisPubSub() {
                @Override
                public void onMessage(String channel, String message) {
                    // Invalidate related cache entries
                    String prefix = message.split(":")[0];
                    Set<String> keys = jedis.keys(prefix + ":*");
                    jedis.del(keys.toArray(new String[0]));
                }
            }, "cache:invalidate");
        }
    }
    
    /**
     * 4. Version-Based Invalidation:
     * 
     * Store version number with cache
     * Check version on read
     * Invalidate when version changes
     */
    
    public void versionInvalidation(Jedis jedis, long userId) {
        long newVersion = userDao.getVersion(userId);
        jedis.hset("user:" + userId, "version", String.valueOf(newVersion));
        
        // On read, check version
        String cachedVersion = jedis.hget("user:" + userId, "version");
        if (!String.valueOf(newVersion).equals(cachedVersion)) {
            jedis.del("user:" + userId);  // Invalidate
        }
    }
}
```

### 4.2 Handling Cache Stampede

```java
// Cache stampede prevention
public class CacheStampedePrevention {
    
    /**
     * What is Cache Stampede?
     * 
     * 1. Cache entry expires at T
     * 2. Multiple requests see cache miss at T+1, T+2, T+3...
     * 3. All hit database simultaneously
     * 4. Database overwhelmed
     * 5. No request gets data (all waiting)
     * 
     * Solution: Use distributed lock
     */
    
    private Jedis jedis;
    
    /**
     * Approach 1: Mutex / Single-Flight
     */
    
    public Data getWithLock(String key) {
        // Try to get distributed lock
        String lockKey = "lock:" + key;
        String lockValue = UUID.randomUUID().toString();
        
        Boolean acquired = jedis.set(lockKey, lockValue, 
            SetParams.nx().ex(10));  // 10 second lock
        
        if (Boolean.TRUE.equals(acquired)) {
            try {
                // Double-check after acquiring lock
                String cached = jedis.get(key);
                if (cached != null) {
                    return JSON.parseObject(cached, Data.class);
                }
                
                // Load from database
                Data data = database.load(key);
                
                // Store in cache
                jedis.setex(key, 3600, JSON.toJSONString(data));
                return data;
            } finally {
                // Only delete if we own the lock
                if (lockValue.equals(jedis.get(lockKey))) {
                    jedis.del(lockKey);
                }
            }
        } else {
            // Wait and retry
            try {
                Thread.sleep(100);
            } catch (InterruptedException e) {
                Thread.currentThread().interrupt();
            }
            return getWithLock(key);  // Retry
        }
    }
    
    /**
     * Approach 2: Probabilistic Early Expiration
     * 
     * Randomly refresh cache before expiration
     * Reduces chance of mass expiration
     */
    
    public void probabilisticRefresh(CaffeineCache cache, String key) {
        // Check if close to expiration and random chance
        if (shouldRefresh(key)) {
            // Refresh in background, don't block
            executor.submit(() -> {
                try {
                    cache.put(key, database.load(key));
                } catch (Exception e) {
                    // Log but don't fail
                }
            });
        }
    }
    
    private boolean shouldRefresh(String key) {
        // Get remaining TTL
        Optional<Long> ttl = cache.getIfPresent(key);
        
        if (!ttl.isPresent()) return false;
        
        // Refresh if 10% of TTL remains and 10% random chance
        long remaining = ttl.get();
        long initialTTL = cache.get().getExpireAfterWrite();
        
        return remaining < (initialTTL * 0.1) && Math.random() < 0.1;
    }
}
```

---

## 5. Memcached Architecture

### 5.1 Memcached Deep Dive

```java
// Memcached architecture
public class MemcachedArchitecture {
    
    /**
     * Memcached vs Redis:
     * 
     * ┌─────────────────────┬─────────────────────────┬──────────────────────┐
     │     Feature          │      Memcached         │        Redis          │
     ├─────────────────────┼─────────────────────────┼──────────────────────┤
     │  Data Structures     │  Strings only          │  Strings, Lists,     │
     │                     │                         │  Sets, ZSets, Hashes  │
     ├─────────────────────┼─────────────────────────┼──────────────────────┤
     │  Persistence        │  None (memory only)     │  RDB + AOF           │
     ├─────────────────────┼─────────────────────────┼──────────────────────┤
     │  Replication        │  No (master/slave only)│  Master/slave,       │
     │                     │  via consistent hashing│  Cluster             │
     ├─────────────────────┼─────────────────────────┼──────────────────────┤
     │  Transactions       │  No                     │  Yes (MULTI/EXEC)    │
     ├─────────────────────┼─────────────────────────┼──────────────────────┤
     │  Pub/Sub           │  No                     │  Yes                 │
     ├─────────────────────┼─────────────────────────┼──────────────────────┤
     │  Performance        │  Very fast, simple     │  Fast, more features │
     ├─────────────────────┼─────────────────────────┼──────────────────────┤
     │  Memory Model       │  Slab allocator        │  Free list + malloc  │
     ├─────────────────────┼─────────────────────────┼──────────────────────┤
     │  Use Case          │  Simple caching,        │  Complex data,       │
     │                     │  session storage        │  queues, pub/sub     │
     └─────────────────────┴─────────────────────────┴──────────────────────┘
     */
    
    /**
     * Memcached Memory Architecture:
     * 
     * ┌─────────────────────────────────────────────────────────────────────┐
     │                    MEMCACHED MEMORY                                  │
     ├─────────────────────────────────────────────────────────────────────┤
     │                                                                      │
     *  Slab 1 (64B):    [Item][Item][Item][Item][Item]...                │
     *  Slab 2 (128B):   [Item][Item][Item][Item]...                     │
     *  Slab 3 (256B):   [Item][Item][Item]...                           │
     *  Slab 4 (512B):   [Item][Item]...                                  │
     *  ...                                                              │
     *  Slab N (1MB):    [Item]                                          │
     *                                                                      │
     *  Each slab class stores items of fixed size                        │
     *  No memory fragmentation                                          │
     *  Items never moved or resized                                     │
     *                                                                      │
     *  Item structure:                                                  │
     *  [Key][Flags][Expiry][CAS][Value]                                 │
     *                                                                      │
     └─────────────────────────────────────────────────────────────────────┘
     */
    
    /**
     * Memcached client (Spymemcache):
     */
    
    public void memcachedExample() {
        // Connect to multiple servers
        List<InetSocketAddress> servers = Arrays.asList(
            new InetSocketAddress("server1", 11211),
            new InetSocketAddress("server2", 11211),
            new InetSocketAddress("server3", 11211)
        );
        
        // Ketema consistent hashing for distribution
        KetemaClient client = new KetemaClient.Builder()
            .addServers(servers)
            .hashAlg(HashAlgorithm.KETEMA_HASH)
            .build();
        
        // Store with expiration
        client.set("user:123", 3600, userJson);
        
        // Get
        String cached = client.get("user:123");
        
        // Delete
        client.delete("user:123");
        
        // Increment/Decrement (atomic)
        client.incr("counter", 1);
        client.decr("counter", 1);
        
        // Multi-get (batch)
        Map<String, Object> results = client.getBulk(
            Arrays.asList("user:1", "user:2", "user:3")
        );
        
        client.shutdown();
    }
}
```

---

## 6. CDN and Edge Caching

### 6.1 CDN Architecture

```java
// CDN caching
public class CDNArchitecture {
    
    /**
     * CDN Architecture:
     * 
     * ┌─────────────────────────────────────────────────────────────────────┐
     │                         CDN FLOW                                      │
     ├─────────────────────────────────────────────────────────────────────┤
     │                                                                      │
     *  User ──► Edge Server (closest) ──► Origin Server                    │
     *         │                    │                                        │
     *         │ HIT               │                                        │
     *         ▼                  │ MISS                                     │
     *       Return             Fetch                                      │
     *         │                  │                                         │
     *         │                  ▼                                         │
     *         │              Cache (if cacheable)                         │
     *         │                  │                                         │
     *         └──────────────────┘                                         │
     *                                                                      │
     *  Popular CDNs: CloudFront, Cloudflare, Akamai, Fastly, MaxCDN        │
     *                                                                      │
     └─────────────────────────────────────────────────────────────────────┘
     */
    
    /**
     * CDN Configuration:
     */
    
    public static class CloudFrontConfig {
        
        /**
         * Cache behaviors:
         * 
         * 1. Static content (images, CSS, JS):
         *    - Long cache (days/weeks)
         *    - No query string
         * 
         * 2. Dynamic content (API responses):
         *    - Short cache (seconds/minutes)
         *    - Based on query params
         * 
         * 3. No cache (personalized):
         *    - Always origin
         */
        
        // Cache policy: Cache for 1 day
        /*
         * {
         *   "Comments": "Object caching",
         *   "MinTTL": 86400,
         *   "DefaultTTL": 86400,
         *   "MaxTTL": 31536000,
         *   "Forward": "none"
         * }
         */
        
        // Cache with query string
        /*
         * {
         *   "Forward": "whitelist",
         *   "QueryStringWhitelist": ["version", "locale"]
         * }
         */
        
        // Cache invalidation
        /*
         * aws cloudfront create-invalidation \
         *   --distribution-id XYZ123 \
         *   --paths "/images/*" "/api/data"
         */
    }
    
    /**
     * Cache-Control Headers:
     */
    
    public void cacheHeaders(HttpServletResponse response) {
        // Public cache, max-age 1 hour
        response.setHeader("Cache-Control", "public, max-age=3600");
        
        // Private (browser only), max-age 10 min
        response.setHeader("Cache-Control", "private, max-age=600");
        
        // No cache, always revalidate
        response.setHeader("Cache-Control", "no-cache, no-store");
        response.setHeader("Pragma", "no-cache");
        
        // ETag for conditional requests
        response.setHeader("ETag", "abc123");
        
        // Last modified
        response.setHeader("Last-Modified", "Mon, 01 Jan 2024 00:00:00 GMT");
    }
}
```

---

## 7. Local Caching (Caffeine, Guava, Ehcache)

### 7.1 Caffeine Deep Dive

```java
// Caffeine cache implementation
public class CaffeineCaching {
    
    /**
     * Caffeine is the most performant in-memory cache for Java
     * 10-100x faster than Guava Cache
     * 
     * Features:
     * - Automatic loading of entries
     * - Size-based eviction (based on weight)
     * - Time-based expiration
     * - Reference-based eviction (weak/soft references)
     * - Statistics
     * - Removal notifications
     */
    
    public void caffeineBasics() {
        Cache<String, User> cache = Caffeine.newBuilder()
            .maximumSize(10_000)                // Max entries
            .maximumWeight(100_000_000)         // Or max weight in bytes
            .weigher((key, user) -> user.getSerializedSize())
            .expireAfterWrite(10, TimeUnit.MINUTES)  // Or .expireAfterAccess()
            .expireAfter(new Expiry<String, User>() {
                @Override
                public long expireAfterCreate(String key, User value, long currentTime) {
                    // Return TTL in nanoseconds
                    return TimeUnit.HOURS.toNanos(1);
                }
                
                @Override
                public long expireAfterUpdate(String key, User value, 
                        long currentTime, long currentDuration) {
                    return currentDuration;  // Keep current TTL
                }
                
                @Override
                public long expireAfterRead(String key, User value,
                        long currentTime, long currentDuration) {
                    return currentDuration;  // Reset TTL on access
                }
            })
            .refreshAfterWrite(5, TimeUnit.MINUTES)  // Async refresh
            .recordStats()  // Enable statistics
            .removalListener((key, value, cause) -> {
                // Removal notification
                // cause: EXPLICIT, REPLACED, SIZE, EXPIRED, COLLECTED
            })
            .build();
        
        // Basic operations
        cache.put("user:1", user);
        User cached = cache.getIfPresent("user:1");
        
        // Get with loader (cache-aside)
        User user = cache.get("user:1", () -> database.load("user:1"));
        
        // Invalidate
        cache.invalidate("user:1");
        cache.invalidateAll();
    }
    
    /**
     * Cache Loading Patterns:
     */
    
    public void loadingCache() {
        // Pre-load on creation
        LoadingCache<String, User> cache = Caffeine.newBuilder()
            .maximumSize(10_000)
            .build(key -> database.load(key));
        
        // Async loading
        AsyncLoadingCache<String, User> asyncCache = Caffeine.newBuilder()
            .maximumSize(10_000)
            .buildAsync(key -> database.loadAsync(key));
        
        // Usage
        User user = cache.get("user:1");
        
        // Async usage
        CompletableFuture<User> future = asyncCache.get("user:1");
    }
    
    /**
     * Statistics:
     */
    
    public void statistics() {
        CacheStats stats = cache.stats();
        
        // Hit rate
        double hitRate = stats.hitRate();
        double missRate = stats.missRate();
        
        // Counts
        long hits = stats.hitCount();
        long misses = stats.missCount();
        long evictions = stats.evictionCount();
        long loads = stats.loadSuccessCount();
        long loadFailures = stats.loadFailureCount();
        
        // Timing
        long loadTimeNanos = stats.totalLoadTime();
        double avgLoadTimeNanos = stats.averageLoadPenalty();
        
        System.out.printf("Hit Rate: %.2f%%, Miss Rate: %.2f%%, Evictions: %d%n",
            hitRate * 100, missRate * 100, evictions);
    }
}
```

---

## 8. Cache Performance Optimization

### 8.1 Benchmarking and Optimization

```java
// Cache performance optimization
public class CacheOptimization {
    
    /**
     * Measuring Cache Performance:
     */
    
    public void benchmark() {
        // Create stopwatch for measurement
        Stopwatch stopwatch = Stopwatch.started();
        
        // Benchmark GET
        for (int i = 0; i < 1_000_000; i++) {
            cache.get("key:" + (i % 10_000));
        }
        
        long getTime = stopwatch.elapsed(TimeUnit.MILLISECONDS);
        System.out.printf("1M GETs: %dms (%.2f us/op)%n", 
            getTime, getTime * 1000.0 / 1_000_000);
        
        // Benchmark PUT
        stopwatch.reset().start();
        for (int i = 0; i < 1_000_000; i++) {
            cache.put("key:" + (i % 10_000), data);
        }
        
        long putTime = stopwatch.elapsed(TimeUnit.MILLISECONDS);
        System.out.printf("1M PUTs: %dms (%.2f us/op)%n", 
            putTime, putTime * 1000.0 / 1_000_000);
    }
    
    /**
     * Optimization Techniques:
     */
    
    public void optimizationTechniques() {
        /**
         * 1. Batch Operations:
         */
        
        // Instead of individual gets
        for (Key key : keys) {
            cache.get(key);
        }
        
        // Use multi-get
        cache.getAll(keys);  // Much faster!
        
        /**
         * 2. Key Design:
         * 
         * - Short keys save memory
         * - Group related keys
         * - Use consistent prefixes
         */
        
        // Bad: "user:john:profile:preferences:theme"
        // Good: "u:john:p:t" (with documentation)
        
        /**
         * 3. Compression:
         */
        
        // Compress large values
        byte[] compressed = compress(originalData);
        cache.put(key, compressed);
        
        // Or use cached's built-in compression if available
        
        /**
         * 4. Serialization:
         */
        
        // JSON (slow, readable)
        String json = JSON.toJSONString(data);
        
        // Protocol Buffers (fast, compact)
        byte[] protobuf = data.toProto().toByteArray();
        
        // Kryo (fast, compact)
        byte[] kryo = kryo.serialize(data);
        
        /**
         * 5. Connection Pooling:
         */
        
        // For distributed caches, use connection pool
        // - Reduces connection overhead
        // - Handles connection failures
        // - Balances load
    }
}
```

---

## 9. Cache Security and Monitoring

### 9.1 Cache Security

```java
// Cache security
public class CacheSecurity {
    
    /**
     * Redis Security:
     */
    
    public void redisSecurity() {
        // redis.conf configurations
        
        // 1. Require password
        /*
         * requirepass your_password_here
         */
        
        // 2. Bind to specific interface
        /*
         * bind 127.0.0.1 192.168.1.100
         */
        
        // 3. Rename dangerous commands
        /*
         * rename-command FLUSHDB "FLUSHDB_9f3a2b1c"
         * rename-command FLUSHALL "FLUSHALL_8x7d2c1e9"
         * rename-command CONFIG "CONFIG_7d4e8f2a"
         */
        
        // 4. Enable TLS
        /*
         * tls-port 6380
         * port 0
         * tls-cert-file /path/to/redis.crt
         * tls-key-file /path/to/redis.key
         * tls-ca-cert-file /path/to/ca.crt
         */
    }
    
    /**
     * Data Encryption:
     */
    
    public void clientSideEncryption(Jedis jedis) {
        // Encrypt before storing
        String sensitive = "credit-card-1234";
        String encrypted = encrypt(sensitive);  // AES encryption
        
        jedis.set("data:" + id, encrypted);
        
        // Decrypt after retrieval
        String stored = jedis.get("data:" + id);
        String decrypted = decrypt(stored);
    }
    
    /**
     * Access Control in Application:
     */
    
    public void accessPatterns() {
        /**
         * 1. Input validation on cache keys
         * 2. Sanitize user input before using in keys
         * 3. Rate limit cache operations
         * 4. Log suspicious access patterns
         */
        
        // Validate key format
        String key = userInput.replaceAll("[^a-zA-Z0-9:_-]", "");
        if (!key.matches("^[a-zA-Z0-9:_-]+$")) {
            throw new IllegalArgumentException("Invalid key");
        }
    }
}
```

---

## 10. Multi-Layer Caching Strategies

### 10.1 Three-Tier Caching Architecture

```java
// Multi-layer caching
public class MultiLayerCaching {
    
    /**
     * Three-Tier Cache Architecture:
     * 
     * ┌─────────────────────────────────────────────────────────────────┐
     │                    REQUEST FLOW                                    │
     ├─────────────────────────────────────────────────────────────────┤
     │                                                                  │
     *  L1: Local Cache (Caffeine)                                       │
     *      - Fastest access (< 1 microsecond)                           │
     *      - Process-local                                              │
     *      - Limited size                                               │
     *      - Hit rate: ~80%                                             │
     *                   │                                                 │
     *                   ▼ (miss)                                          │
     *  L2: Distributed Cache (Redis)                                   │
     *      - Fast access (< 1 millisecond)                             │
     *      - Shared across processes                                   │
     *      - Larger dataset                                             │
     *      - Hit rate: ~95% (combined)                                │
     *                   │                                                 │
     *                   ▼ (miss)                                         │
     *  L3: Database (PostgreSQL/MySQL)                                  │
     *      - Slowest (< 10 milliseconds)                                │
     *      - Source of truth                                            │
     *      - Always available                                          │
     *                                                                  │
     └─────────────────────────────────────────────────────────────────┘
     */
    
    private final CaffeineCache l1Cache;
    private final Jedis l2Cache;
    private final UserDao userDao;
    
    public User getUser(Long userId) {
        String l1Key = "user:" + userId;
        
        // L1: Local cache (fastest)
        User user = l1Cache.getIfPresent(l1Key);
        if (user != null) {
            return user;
        }
        
        // L2: Distributed cache
        String l2Key = "user:distributed:" + userId;
        String cached = l2Cache.get(l2Key);
        if (cached != null) {
            user = JSON.parseObject(cached, User.class);
            
            // Populate L1 cache
            l1Cache.put(l1Key, user);
            return user;
        }
        
        // L3: Database
        user = userDao.findById(userId);
        if (user != null) {
            // Populate both caches
            l1Cache.put(l1Key, user);
            l2Cache.setex(l2Key, 3600, JSON.toJSONString(user));
        }
        
        return user;
    }
    
    /**
     * Invalidation Strategy:
     */
    
    public void invalidateUser(Long userId) {
        String l1Key = "user:" + userId;
        String l2Key = "user:distributed:" + userId;
        
        // Invalidate both layers
        l1Cache.invalidate(l1Key);
        l2Cache.del(l2Key);
        
        // Or use event-based invalidation
        // Publish invalidation event to all instances
    }
}
```

---

This comprehensive guide covers caching systems architecture, patterns, and implementation in depth.