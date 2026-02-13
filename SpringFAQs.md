# Spring Framework FAQs - Detailed Answers

## 1️⃣ Core Spring Container & Dependency Injection

### Q1: How does Spring's `DefaultListableBeanFactory` manage bean definitions internally?

**Simple Answer:**
Spring stores all bean definitions in a thread-safe HashMap where the key is the bean name and the value contains all the metadata about how to create that bean.

**Deep Dive:**
- Uses `ConcurrentHashMap<String, BeanDefinition>` internally for the bean definition registry
- Each `BeanDefinition` contains:
  - Bean class name
  - Constructor argument values
  - Property values
  - Scope (singleton, prototype, etc.)
  - Initialization and destruction callbacks
  - Autowiring mode
- Supports parent-child factory hierarchy for definition inheritance
- O(1) lookup performance for bean retrieval
- Thread-safe operations allow concurrent read access
- Bean definitions can be merged from parent factories during lookup
- Also maintains separate caches for singleton instances, factory bean objects, and partially created beans

**Key Internal Data Structures:**
```java
// Simplified internal structure
private final Map<String, BeanDefinition> beanDefinitionMap = new ConcurrentHashMap<>(256);
private volatile List<String> beanDefinitionNames = new ArrayList<>(256);
private final Map<String, Object> singletonObjects = new ConcurrentHashMap<>(256);
private final Map<String, ObjectFactory<?>> singletonFactories = new HashMap<>(16);
```

---

### Q2: Explain the complete lifecycle of a Spring bean from definition registration to destruction.

**Simple Answer:**
A Spring bean goes through several phases: registration → instantiation → dependency injection → initialization → ready for use → destruction when context shuts down.

**Deep Dive:**

**Phase 1: Definition Registration**
- Bean definitions are registered from @Configuration classes, XML, or component scanning
- Stored in `BeanDefinitionRegistry`

**Phase 2: BeanFactoryPostProcessor Execution**
- Modify bean definitions before any beans are instantiated
- Examples: `PropertyPlaceholderConfigurer`, `CustomScopeConfigurer`

**Phase 3: Instantiation**
- `InstantiationAwareBeanPostProcessor.postProcessBeforeInstantiation()` (optional proxy creation)
- Constructor or factory method invoked
- Bean instance created in memory
- `InstantiationAwareBeanPostProcessor.postProcessAfterInstantiation()`

**Phase 4: Property Population**
- `InstantiationAwareBeanPostProcessor.postProcessProperties()` - modify properties
- Dependency injection occurs (field, setter, or constructor injection)
- `@Autowired`, `@Value`, `@Resource` resolved here

**Phase 5: Aware Interfaces Callbacks** (in order)
1. `BeanNameAware.setBeanName()`
2. `BeanClassLoaderAware.setBeanClassLoader()`
3. `BeanFactoryAware.setBeanFactory()`
4. `EnvironmentAware.setEnvironment()`
5. `EmbeddedValueResolverAware.setEmbeddedValueResolver()`
6. `ResourceLoaderAware.setResourceLoader()`
7. `ApplicationEventPublisherAware.setApplicationEventPublisher()`
8. `MessageSourceAware.setMessageSource()`
9. `ApplicationContextAware.setApplicationContext()`

**Phase 6: BeanPostProcessor Pre-Initialization**
- `BeanPostProcessor.postProcessBeforeInitialization()` for all registered post-processors
- Common AOP proxy creation happens here

**Phase 7: Initialization Callbacks** (in order)
1. `@PostConstruct` annotated methods
2. `InitializingBean.afterPropertiesSet()`
3. Custom `init-method` specified in configuration

**Phase 8: BeanPostProcessor Post-Initialization**
- `BeanPostProcessor.postProcessAfterInitialization()`
- Proxy wrapping (if not done earlier)
- Bean is now fully initialized and ready

**Phase 9: Bean Ready for Use**
- Bean is available in container
- Can be injected into other beans

**Phase 10: Destruction** (on context shutdown, in order)
1. `@PreDestroy` annotated methods
2. `DisposableBean.destroy()`
3. Custom `destroy-method` specified in configuration
4. `DestructionAwareBeanPostProcessor.postProcessBeforeDestruction()`

**Code Example:**
```java
@Component
public class LifecycleBean implements BeanNameAware, BeanFactoryAware, 
        InitializingBean, DisposableBean {
    
    public LifecycleBean() {
        System.out.println("1. Constructor called");
    }
    
    @Autowired
    public void setDependency(SomeDependency dep) {
        System.out.println("2. Dependency injected");
    }
    
    @Override
    public void setBeanName(String name) {
        System.out.println("3. BeanNameAware: " + name);
    }
    
    @Override
    public void setBeanFactory(BeanFactory beanFactory) {
        System.out.println("4. BeanFactoryAware");
    }
    
    @PostConstruct
    public void postConstruct() {
        System.out.println("5. @PostConstruct");
    }
    
    @Override
    public void afterPropertiesSet() {
        System.out.println("6. InitializingBean.afterPropertiesSet()");
    }
    
    // Bean ready for use here
    
    @PreDestroy
    public void preDestroy() {
        System.out.println("7. @PreDestroy");
    }
    
    @Override
    public void destroy() {
        System.out.println("8. DisposableBean.destroy()");
    }
}
```

---

### Q3: What is the difference between type-based and name-based autowiring?

**Simple Answer:**
Type-based autowiring matches beans by their Java class type. Name-based autowiring matches beans by their string name in the Spring container.

**Deep Dive:**

**Type-Based Autowiring (`@Autowired`)**
- Matches by Java type
- Uses `AutowiredAnnotationBeanPostProcessor`
- Resolution strategy:
  1. Find all beans of matching type
  2. If exactly one → inject it
  3. If multiple → check for `@Primary`
  4. If still multiple → check for `@Qualifier`
  5. If still multiple → fallback to field/parameter name matching
  6. If still ambiguous → throw `NoUniqueBeanDefinitionException`

**Name-Based Autowiring (`@Resource`)**
- JSR-250 standard annotation
- Matches by bean name first, then by type
- Uses `CommonAnnotationBeanPostProcessor`
- Resolution strategy:
  1. Look for bean with exact name specified in `@Resource(name="...")`
  2. If no name specified, use field/parameter name
  3. If name match fails, fallback to type matching
  4. Throws `NoSuchBeanDefinitionException` if not found

**Comparison:**
```java
@Component
public class ServiceA implements MyService { }

@Component
public class ServiceB implements MyService { }

public class Example {
    // Type-based: Fails with NoUniqueBeanDefinitionException
    @Autowired
    private MyService service;
    
    // Type-based with qualifier: Works
    @Autowired
    @Qualifier("serviceA")
    private MyService service;
    
    // Name-based: Matches by name "serviceA"
    @Resource(name = "serviceA")
    private MyService service;
    
    // Name-based: Uses field name "serviceB" to find bean
    @Resource
    private MyService serviceB;
}
```

**When to Use:**
- **Type-based**: Default choice, clearer intent, better for refactoring
- **Name-based**: When you have multiple beans of same type and want explicit name matching

---

### Q4: How does Spring resolve generic-type injection points (e.g., `Repository<User>`)?

**Simple Answer:**
Spring uses Java's reflection API to read generic type parameters at runtime and matches them against the actual generic types declared on beans.

**Deep Dive:**

**Resolution Process:**
1. **Type Extraction**: Spring uses `ResolvableType` class to extract generic information
2. **Erasure Handling**: Works around Java's type erasure using reflection on fields/methods
3. **Matching Algorithm**:
   - Extract raw type (e.g., `Repository`)
   - Extract generic arguments (e.g., `User`)
   - Find all beans matching raw type
   - Filter by generic argument compatibility
   - Apply qualifier/primary bean rules if needed

**Internal Mechanism:**
```java
// Spring's internal resolution
ResolvableType injectionType = ResolvableType.forField(field);
Class<?> rawClass = injectionType.resolve(); // Repository
ResolvableType genericArg = injectionType.getGeneric(0); // User

// Find matching beans
for (String beanName : candidateBeans) {
    ResolvableType beanType = getBeanType(beanName);
    if (beanType.isAssignableFrom(injectionType)) {
        // Match found
    }
}
```

**Example:**
```java
// Generic repository interface
public interface Repository<T> {
    T findById(Long id);
}

// Concrete implementations
@Component
public class UserRepository implements Repository<User> { }

@Component
public class ProductRepository implements Repository<Product> { }

// Injection points
@Service
public class UserService {
    @Autowired
    private Repository<User> userRepo; // Correctly injects UserRepository
    
    @Autowired
    private Repository<Product> productRepo; // Correctly injects ProductRepository
}
```

**Limitations:**
- Generic type info must be available at runtime (can't use wildcards like `Repository<?>`)
- Doesn't work with local variables or constructor parameter generics in some cases
- Bridge methods from type erasure can complicate matching

**Advanced Use Case:**
```java
// Custom generic qualifier
@Component
public class GenericService<T> {
    @Autowired
    private List<Processor<T>> processors; // Injects all matching processors
}
```

---

### Q10: How does Spring handle a prototype bean injected into a singleton?

**Simple Answer:**
The singleton bean gets **one instance** of the prototype bean at creation time and keeps using that same instance, defeating the purpose of prototype scope.

**Deep Dive:**

**The Problem:**
```java
@Component
@Scope("prototype")
public class PrototypeBean {
    private UUID id = UUID.randomUUID();
    public UUID getId() { return id; }
}

@Component // singleton by default
public class SingletonBean {
    @Autowired
    private PrototypeBean prototypeBean;
    
    public void doSomething() {
        System.out.println(prototypeBean.getId()); // Always same ID!
    }
}
```

**Why This Happens:**
1. Spring creates `SingletonBean` once at startup
2. Dependency injection occurs during singleton creation
3. Spring creates **one** `PrototypeBean` instance and injects it
4. `SingletonBean` holds reference to that one instance forever
5. Subsequent calls to `doSomething()` use the same cached instance

**Solutions:**

**Solution 1: Method Injection with `@Lookup`** (Recommended)
```java
@Component
public abstract class SingletonBean {
    
    @Lookup // Spring generates implementation at runtime
    public abstract PrototypeBean getPrototypeBean();
    
    public void doSomething() {
        PrototypeBean bean = getPrototypeBean(); // New instance each time
        System.out.println(bean.getId());
    }
}
```

How it works:
- Spring creates a CGLIB subclass at runtime
- Overrides the abstract method to return `applicationContext.getBean(PrototypeBean.class)`
- Each call returns a fresh instance

**Solution 2: `ObjectProvider<T>`** (Clean, Type-Safe)
```java
@Component
public class SingletonBean {
    
    @Autowired
    private ObjectProvider<PrototypeBean> prototypeBeanProvider;
    
    public void doSomething() {
        PrototypeBean bean = prototypeBeanProvider.getObject(); // New instance
        System.out.println(bean.getId());
    }
}
```

**Solution 3: `ObjectFactory<T>`** (Similar to Provider)
```java
@Component
public class SingletonBean {
    
    @Autowired
    private ObjectFactory<PrototypeBean> prototypeBeanFactory;
    
    public void doSomething() {
        PrototypeBean bean = prototypeBeanFactory.getObject();
        System.out.println(bean.getId());
    }
}
```

**Solution 4: `ApplicationContext` Injection** (Less Preferred)
```java
@Component
public class SingletonBean {
    
    @Autowired
    private ApplicationContext context;
    
    public void doSomething() {
        PrototypeBean bean = context.getBean(PrototypeBean.class);
        System.out.println(bean.getId());
    }
}
```

Drawbacks: Couples code to Spring, harder to test

**Solution 5: Scoped Proxy** (For Web Scopes Mainly)
```java
@Component
@Scope(value = "prototype", proxyMode = ScopedProxyMode.TARGET_CLASS)
public class PrototypeBean { }

@Component
public class SingletonBean {
    @Autowired
    private PrototypeBean prototypeBean; // Actually a proxy
    
    public void doSomething() {
        // Proxy creates new instance for each method call
        System.out.println(prototypeBean.getId());
    }
}
```

**Performance Comparison:**
- `@Lookup`: Fastest, no interface overhead
- `ObjectProvider`: Slight overhead, excellent for optional dependencies
- `ApplicationContext`: Slowest, most flexible

**Testing:**
```java
@Test
void testPrototypeInjection() {
    UUID firstId = singletonBean.getPrototypeBean().getId();
    UUID secondId = singletonBean.getPrototypeBean().getId();
    assertNotEquals(firstId, secondId); // Should be different
}
```

---

### Q12: How does `@Configuration` class proxying affect bean method calls?

**Simple Answer:**
When `proxyBeanMethods = true` (default), Spring creates a proxy that intercepts calls between `@Bean` methods to ensure proper bean scoping. When `false`, methods are called directly like regular Java methods.

**Deep Dive:**

**With Proxying (Default: `proxyBeanMethods = true`)**
```java
@Configuration // proxyBeanMethods = true by default
public class AppConfig {
    
    @Bean
    public ServiceA serviceA() {
        return new ServiceA(serviceB()); // Intercepted!
    }
    
    @Bean
    public ServiceB serviceB() {
        return new ServiceB();
    }
}
```

**What Happens:**
1. Spring creates a CGLIB proxy subclass of `AppConfig`
2. Proxy intercepts all `@Bean` method calls
3. When `serviceA()` calls `serviceB()`:
   - Proxy checks if `serviceB` bean already exists in container
   - If yes: Returns existing singleton instance
   - If no: Calls actual method, registers result, returns it
4. Guarantees singleton semantics even for inter-bean method calls

**Internal Proxy Mechanism:**
```java
// Simplified proxy behavior
public class AppConfig$$EnhancerBySpringCGLIB extends AppConfig {
    
    @Override
    public ServiceB serviceB() {
        // Check container first
        if (beanFactory.containsBean("serviceB")) {
            return beanFactory.getBean("serviceB", ServiceB.class);
        }
        // Call actual method if not found
        return super.serviceB();
    }
}
```

**Without Proxying (`proxyBeanMethods = false`)**
```java
@Configuration(proxyBeanMethods = false)
public class AppConfig {
    
    @Bean
    public ServiceA serviceA() {
        return new ServiceA(serviceB()); // Direct call!
    }
    
    @Bean
    public ServiceB serviceB() {
        return new ServiceB(); // Creates NEW instance every call
    }
}
```

**What Happens:**
1. No CGLIB proxy created
2. Methods called directly as regular Java methods
3. `serviceA()` calling `serviceB()` creates a **new instance** each time
4. Breaks singleton semantics for inter-bean calls
5. Faster startup time (no proxy generation)

**Comparison Table:**

| Aspect | proxyBeanMethods = true | proxyBeanMethods = false |
|--------|------------------------|--------------------------|
| Proxy Creation | CGLIB subclass | None (plain class) |
| Inter-bean calls | Container-managed | Direct Java calls |
| Singleton guarantee | Yes | Only for external calls |
| Startup time | Slower | Faster |
| Memory usage | Higher | Lower |
| Use case | Inter-bean dependencies | Independent beans |

**When to Use `false`:**
- All `@Bean` methods are independent (no inter-method calls)
- Configuration only creates beans, doesn't wire them together
- Performance-critical applications (microservices)
- Using Spring Boot auto-configuration (most already use `false`)

**Example Problem with `false`:**
```java
@Configuration(proxyBeanMethods = false)
public class ProblematicConfig {
    
    @Bean
    public DataSource dataSource() {
        return new HikariDataSource(...);
    }
    
    @Bean
    public JdbcTemplate jdbcTemplate() {
        // Creates NEW DataSource instead of using the bean!
        return new JdbcTemplate(dataSource());
    }
    
    @Bean
    public TransactionManager txManager() {
        // Another NEW DataSource instance!
        return new DataSourceTransactionManager(dataSource());
    }
}
```

**Correct Solution with `false`:**
```java
@Configuration(proxyBeanMethods = false)
public class CorrectConfig {
    
    @Bean
    public DataSource dataSource() {
        return new HikariDataSource(...);
    }
    
    @Bean
    public JdbcTemplate jdbcTemplate(DataSource dataSource) {
        return new JdbcTemplate(dataSource); // Injected by Spring
    }
    
    @Bean
    public TransactionManager txManager(DataSource dataSource) {
        return new DataSourceTransactionManager(dataSource); // Same instance
    }
}
```

**Performance Impact:**
- Proxy creation adds ~50-100ms per configuration class
- For large applications with hundreds of `@Configuration` classes, this adds up
- Spring Boot 2.2+ uses `proxyBeanMethods = false` for most auto-configurations

---

## 2️⃣ Aspect-Oriented Programming (AOP)

### Q31: Describe Spring's proxy-creation strategy: when does it pick JDK dynamic proxies vs. CGLIB?

**Simple Answer:**
Spring uses JDK proxies when the target bean implements interfaces, and CGLIB proxies when the bean is a concrete class without interfaces.

**Deep Dive:**

**Decision Tree:**
```
Target Bean
    │
    ├─ Implements interface(s)?
    │   ├─ Yes → JDK Dynamic Proxy (default)
    │   └─ No → CGLIB Proxy
    │
    └─ proxyTargetClass = true?
        └─ Yes → CGLIB Proxy (forced)
```

**JDK Dynamic Proxy:**
- Uses `java.lang.reflect.Proxy`
- Creates a proxy that implements the same interfaces
- Delegates to `InvocationHandler`
- **Cannot** proxy classes, only interfaces
- Faster proxy creation
- Smaller bytecode footprint

```java
public interface UserService {
    User findById(Long id);
}

@Service
public class UserServiceImpl implements UserService {
    @Override
    public User findById(Long id) { }
}

// Spring creates:
// Proxy implements UserService
// Proxy delegates to UserServiceImpl
```

**CGLIB Proxy:**
- Uses Code Generation Library (CGLIB)
- Creates a **subclass** of the target class
- Overrides all non-final methods
- Uses `MethodInterceptor` callback
- Can proxy concrete classes
- Slower proxy creation (bytecode generation)
- Larger memory footprint

```java
@Service
public class UserService { // No interface
    public User findById(Long id) { }
}

// Spring creates:
// UserService$$EnhancerBySpringCGLIB extends UserService
// Overrides findById() to add advice
```

**Forcing CGLIB:**
```java
@EnableAspectJAutoProxy(proxyTargetClass = true)
@Configuration
public class AppConfig { }

// Or in Spring Boot
spring.aop.proxy-target-class=true
```

**Limitations:**

**JDK Proxy Limitations:**
- Can only proxy interface methods
- Cannot proxy concrete class methods
- Cannot inject the concrete class type

```java
@Autowired
private UserServiceImpl service; // FAILS with JDK proxy
// Use interface type instead:
@Autowired
private UserService service; // WORKS
```

**CGLIB Proxy Limitations:**
- Cannot override `final` methods
- Cannot override `private` methods
- Cannot proxy `final` classes
- Requires no-arg constructor (in older versions)

```java
@Service
public class UserService {
    public final User findById(Long id) { } // NOT PROXIED
    private void helper() { } // NOT PROXIED
}
```

**Performance Comparison:**
- JDK: ~5-10x faster proxy creation
- CGLIB: ~10-15% slower method invocation
- For most apps: Negligible difference

**Best Practices:**
1. **Prefer interfaces** for better testability and loose coupling
2. Use CGLIB only when necessary (concrete classes, framework requirements)
3. Be aware of final method limitations with CGLIB
4. Spring Boot defaults to CGLIB since 2.0

---

### Q34: What is the self-invocation problem and solutions?

**Simple Answer:**
When a Spring bean calls its own method, the call bypasses the proxy, so AOP advice (like `@Transactional`) doesn't apply. Solutions include injecting the bean's own proxy or refactoring.

**Deep Dive:**

**The Problem:**
```java
@Service
public class UserService {
    
    @Transactional
    public void updateUser(User user) {
        // Save user
        sendNotification(user); // Self-invocation!
    }
    
    @Transactional(propagation = Propagation.REQUIRES_NEW)
    public void sendNotification(User user) {
        // This transaction advice is IGNORED!
        // Called directly, not through proxy
    }
}
```

**Why It Happens:**
```
Client → Proxy → Target Object
             ↓
         Advice Applied
         
Internal call: Target Object → Target Object
                            ↑
                      No Proxy, No Advice!
```

When `updateUser()` calls `sendNotification()`:
1. Call goes directly from `updateUser` to `sendNotification`
2. Doesn't pass through the proxy
3. Transaction advice on `sendNotification` never executes
4. Both methods run in the same transaction

**Solution 1: Inject Self-Proxy**
```java
@Service
public class UserService {
    
    @Autowired
    @Lazy // Prevents circular dependency
    private UserService self;
    
    @Transactional
    public void updateUser(User user) {
        // Save user
        self.sendNotification(user); // Goes through proxy!
    }
    
    @Transactional(propagation = Propagation.REQUIRES_NEW)
    public void sendNotification(User user) {
        // NEW transaction created
    }
}
```

**Solution 2: `AopContext.currentProxy()`**
```java
@EnableAspectJAutoProxy(exposeProxy = true)
@Configuration
public class AppConfig { }

@Service
public class UserService {
    
    @Transactional
    public void updateUser(User user) {
        UserService proxy = (UserService) AopContext.currentProxy();
        proxy.sendNotification(user); // Through proxy
    }
    
    @Transactional(propagation = Propagation.REQUIRES_NEW)
    public void sendNotification(User user) { }
}
```

Drawbacks:
- Couples code to Spring AOP
- `exposeProxy = true` has performance overhead (ThreadLocal)
- Can throw `IllegalStateException` if no proxy available

**Solution 3: Refactor to Separate Service** (Best Practice)
```java
@Service
public class UserService {
    @Autowired
    private NotificationService notificationService;
    
    @Transactional
    public void updateUser(User user) {
        // Save user
        notificationService.sendNotification(user); // Different bean
    }
}

@Service
public class NotificationService {
    @Transactional(propagation = Propagation.REQUIRES_NEW)
    public void sendNotification(User user) {
        // NEW transaction in separate service
    }
}
```

Benefits:
- Clear separation of concerns
- No coupling to Spring AOP
- Easier to test
- Follows Single Responsibility Principle

**Solution 4: AspectJ Load-Time Weaving**
```java
@EnableLoadTimeWeaving
@Configuration
public class AppConfig { }

// Run with: -javaagent:path/to/spring-instrument.jar

@Service
public class UserService {
    @Transactional
    public void updateUser(User user) {
        sendNotification(user); // Works! AspectJ weaves bytecode
    }
    
    @Transactional(propagation = Propagation.REQUIRES_NEW)
    public void sendNotification(User user) { }
}
```

How it works:
- AspectJ modifies bytecode at load time
- Weaves advice directly into class
- No proxy needed
- Works for private methods, final classes

Drawbacks:
- Requires JVM agent
- More complex setup
- Longer startup time

**Debugging Self-Invocation:**
```java
@Aspect
@Component
public class TransactionDebugAspect {
    @Before("@annotation(transactional)")
    public void logTransaction(JoinPoint jp, Transactional transactional) {
        System.out.println("Transaction started: " + jp.getSignature());
    }
}
```

If this doesn't print for internal calls, you have self-invocation issue.

**Performance Comparison:**
- Self-injection: Minimal overhead
- `AopContext`: ThreadLocal lookup overhead (~5-10ns)
- Separate service: No overhead, cleanest
- AspectJ LTW: No runtime overhead, bytecode weaving cost at startup

---

## 3️⃣ Transaction Management

### Q51: List all transaction propagation types with a REQUIRES_NEW use case.

**Simple Answer:**
Spring has 7 propagation types: REQUIRED (default), REQUIRES_NEW, SUPPORTS, NOT_SUPPORTED, MANDATORY, NEVER, and NESTED. `REQUIRES_NEW` is used when you need a completely independent transaction that commits regardless of the outer transaction's outcome.

**Deep Dive:**

**All Propagation Types:**

**1. REQUIRED (Default)**
- Joins existing transaction if present
- Creates new transaction if none exists
- Most common setting

```java
@Transactional(propagation = Propagation.REQUIRED)
public void method() {
    // If transaction exists: join it
    // If no transaction: create new one
}
```

**2. REQUIRES_NEW**
- **Always** creates a new transaction
- Suspends current transaction if exists
- Inner transaction commits/rolls back independently

```java
@Transactional(propagation = Propagation.REQUIRES_NEW)
public void method() {
    // Always creates new transaction
    // Outer transaction suspended temporarily
}
```

**3. SUPPORTS**
- Runs within transaction if one exists
- Runs non-transactionally if none exists
- Use for read-only operations

```java
@Transactional(propagation = Propagation.SUPPORTS)
public void method() {
    // Transaction optional
}
```

**4. NOT_SUPPORTED**
- Suspends current transaction
- Always runs non-transactionally

```java
@Transactional(propagation = Propagation.NOT_SUPPORTED)
public void method() {
    // No transaction even if caller has one
}
```

**5. MANDATORY**
- **Requires** existing transaction
- Throws exception if no transaction exists

```java
@Transactional(propagation = Propagation.MANDATORY)
public void method() {
    // Must be called within transaction
    // Throws IllegalTransactionStateException otherwise
}
```

**6. NEVER**
- **Cannot** run within transaction
- Throws exception if transaction exists

```java
@Transactional(propagation = Propagation.NEVER)
public void method() {
    // Must NOT be called within transaction
}
```

**7. NESTED**
- Creates nested transaction (savepoint)
- Rolls back to savepoint on failure
- Only works with JDBC, not JTA

```java
@Transactional(propagation = Propagation.NESTED)
public void method() {
    // Creates savepoint
    // Can rollback partially
}
```

**REQUIRES_NEW Use Case: Audit Logging**

**Problem:** You want to log all actions even if the main business transaction fails.

```java
@Service
public class OrderService {
    @Autowired
    private AuditService auditService;
    
    @Transactional
    public void processOrder(Order order) {
        try {
            // Log attempt - should ALWAYS be saved
            auditService.logOrderAttempt(order);
            
            // Process order
            validateOrder(order);
            saveOrder(order);
            sendConfirmation(order);
            
            // Log success
            auditService.logOrderSuccess(order);
            
        } catch (Exception e) {
            // Log failure - should STILL be saved
            auditService.logOrderFailure(order, e);
            throw e; // Rollback main transaction
        }
    }
}

@Service
public class AuditService {
    
    @Transactional(propagation = Propagation.REQUIRES_NEW)
    public void logOrderAttempt(Order order) {
        AuditLog log = new AuditLog();
        log.setAction("ORDER_ATTEMPT");
        log.setOrderId(order.getId());
        auditRepository.save(log); // Commits in separate transaction
    }
    
    @Transactional(propagation = Propagation.REQUIRES_NEW)
    public void logOrderSuccess(Order order) {
        AuditLog log = new AuditLog();
        log.setAction("ORDER_SUCCESS");
        log.setOrderId(order.getId());
        auditRepository.save(log); // Commits independently
    }
    
    @Transactional(propagation = Propagation.REQUIRES_NEW)
    public void logOrderFailure(Order order, Exception e) {
        AuditLog log = new AuditLog();
        log.setAction("ORDER_FAILURE");
        log.setOrderId(order.getId());
        log.setError(e.getMessage());
        auditRepository.save(log); // Commits even if order transaction rolls back
    }
}
```

**Execution Flow:**
```
1. processOrder() starts → Transaction A begins
2. logOrderAttempt() called → Transaction A suspended
                              → Transaction B begins
                              → Audit logged
                              → Transaction B commits
                              → Transaction A resumed
3. validateOrder() fails → Exception thrown
4. logOrderFailure() called → Transaction A suspended
                              → Transaction C begins
                              → Failure logged
                              → Transaction C commits
                              → Transaction A resumed
5. Exception propagates → Transaction A rolls back
6. Result: Order not saved, but audit logs ARE saved
```

**Other REQUIRES_NEW Use Cases:**

**Background Job Processing:**
```java
@Transactional
public void processBatch(List<Item> items) {
    for (Item item : items) {
        try {
            processItem(item); // Each in separate transaction
        } catch (Exception e) {
            // Continue processing other items
        }
    }
}

@Transactional(propagation = Propagation.REQUIRES_NEW)
public void processItem(Item item) {
    // If this fails, only this item rolls back
}
```

**Notification Sending:**
```java
@Transactional
public void registerUser(User user) {
    userRepository.save(user);
    notificationService.sendWelcomeEmail(user); // Should not fail registration
}

@Transactional(propagation = Propagation.REQUIRES_NEW)
public void sendWelcomeEmail(User user) {
    // Email sending failure won't rollback user registration
}
```

**Performance Considerations:**
- REQUIRES_NEW has overhead (suspend/resume transactions)
- Creates additional database connections
- Can cause deadlocks if not careful
- Use sparingly, only when truly needed

---

### Q58: How to programmatically mark a transaction for rollback without throwing?

**Simple Answer:**
Call `TransactionAspectSupport.currentTransactionStatus().setRollbackOnly()` to mark the current transaction for rollback without throwing an exception.

**Deep Dive:**

**Basic Usage:**
```java
@Service
public class PaymentService {
    
    @Transactional
    public void processPayment(Payment payment) {
        try {
            validatePayment(payment);
            chargeCard(payment);
            
            if (fraudDetected(payment)) {
                // Mark for rollback without throwing
                TransactionAspectSupport.currentTransactionStatus()
                    .setRollbackOnly();
                return; // Exit gracefully
            }
            
            confirmPayment(payment);
        } catch (Exception e) {
            // Transaction will rollback automatically
            log.error("Payment failed", e);
        }
    }
}
```

**Why Use This:**
1. **Graceful Degradation**: Return error response without exception
2. **Conditional Rollback**: Based on business logic, not exceptions
3. **Partial Processing**: Mark rollback after some operations complete
4. **API Contracts**: Methods that shouldn't throw exceptions

**Complete Example with Status Checking:**
```java
@Service
public class OrderService {
    
    @Transactional
    public OrderResult processOrder(Order order) {
        TransactionStatus status = TransactionAspectSupport.currentTransactionStatus();
        
        try {
            // Step 1: Validate
            if (!isValid(order)) {
                status.setRollbackOnly();
                return OrderResult.validationFailed();
            }
            
            // Step 2: Check inventory
            if (!hasInventory(order)) {
                status.setRollbackOnly();
                return OrderResult.outOfStock();
            }
            
            // Step 3: Process payment
            PaymentResult paymentResult = processPayment(order);
            if (!paymentResult.isSuccessful()) {
                status.setRollbackOnly();
                return OrderResult.paymentFailed();
            }
            
            // Step 4: Save order
            saveOrder(order);
            
            // Check if still good to commit
            if (status.isRollbackOnly()) {
                return OrderResult.failed();
            }
            
            return OrderResult.success();
            
        } catch (Exception e) {
            status.setRollbackOnly();
            return OrderResult.error(e);
        }
    }
}
```

**Checking Rollback Status:**
```java
@Transactional
public void complexOperation() {
    TransactionStatus status = TransactionAspectSupport.currentTransactionStatus();
    
    // Check if already marked for rollback
    if (status.isRollbackOnly()) {
        log.warn("Transaction already marked for rollback");
        return;
    }
    
    // Do work...
    
    // Check again before proceeding
    if (!status.isRollbackOnly()) {
        proceedWithMoreWork();
    }
}
```

**Alternative: Using TransactionTemplate**
```java
@Service
public class AlternativeService {
    
    @Autowired
    private TransactionTemplate transactionTemplate;
    
    public Result doWork() {
        return transactionTemplate.execute(status -> {
            try {
                performWork();
                
                if (shouldRollback()) {
                    status.setRollbackOnly();
                    return Result.failed();
                }
                
                return Result.success();
                
            } catch (Exception e) {
                status.setRollbackOnly();
                return Result.error(e);
            }
        });
    }
}
```

**Nested Transactions:**
```java
@Transactional
public void outerMethod() {
    TransactionStatus outerStatus = TransactionAspectSupport.currentTransactionStatus();
    
    innerMethod();
    
    // Inner method can't force outer to rollback with REQUIRES_NEW
    // But with REQUIRED, it will
    if (outerStatus.isRollbackOnly()) {
        log.warn("Inner method marked transaction for rollback");
    }
}

@Transactional(propagation = Propagation.REQUIRED)
public void innerMethod() {
    if (someCondition()) {
        TransactionAspectSupport.currentTransactionStatus()
            .setRollbackOnly(); // Marks OUTER transaction too
    }
}
```

**Exception Handling:**
```java
@Transactional
public void handleRollback() {
    try {
        TransactionAspectSupport.currentTransactionStatus()
            .setRollbackOnly();
    } catch (NoTransactionException e) {
        // Called outside transaction context
        log.error("No active transaction", e);
    } catch (IllegalTransactionStateException e) {
        // Transaction in invalid state
        log.error("Invalid transaction state", e);
    }
}
```

**Testing:**
```java
@SpringBootTest
class TransactionTest {
    
    @Autowired
    private OrderService orderService;
    
    @Autowired
    private OrderRepository orderRepository;
    
    @Test
    @Transactional
    void testRollbackOnly() {
        Order order = new Order();
        order.setInvalid(true);
        
        OrderResult result = orderService.processOrder(order);
        
        assertFalse(result.isSuccess());
        
        // Verify nothing was saved
        entityManager.flush();
        assertEquals(0, orderRepository.count());
    }
}
```

**Best Practices:**
1. **Document clearly** when methods set rollback without throwing
2. **Return status objects** instead of throwing exceptions
3. **Check rollback status** before proceeding with expensive operations
4. **Use sparingly** - exceptions are clearer in most cases
5. **Test thoroughly** - rollback behavior can be subtle

**Common Pitfalls:**
```java
// WRONG: Trying to commit after setRollbackOnly
@Transactional
public void wrong() {
    TransactionStatus status = TransactionAspectSupport.currentTransactionStatus();
    status.setRollbackOnly();
    // Transaction WILL rollback, you cannot change this
}

// WRONG: Setting rollback in wrong propagation
@Transactional(propagation = Propagation.NEVER)
public void alsoWrong() {
    // NoTransactionException - no transaction exists!
    TransactionAspectSupport.currentTransactionStatus().setRollbackOnly();
}
```

---

## 4️⃣ Spring Boot

### Q76: What three meta-annotations compose `@SpringBootApplication`?

**Simple Answer:**
`@SpringBootApplication` combines three annotations: `@Configuration` (for Java configuration), `@EnableAutoConfiguration` (for automatic bean registration), and `@ComponentScan` (for scanning components in the package).

**Deep Dive:**

**The Composition:**
```java
@Target(ElementType.TYPE)
@Retention(RetentionPolicy.RUNTIME)
@Documented
@Inherited
@SpringBootConfiguration  // Which is itself @Configuration
@EnableAutoConfiguration
@ComponentScan(excludeFilters = {
    @Filter(type = FilterType.CUSTOM, classes = TypeExcludeFilter.class),
    @Filter(type = FilterType.CUSTOM, classes = AutoConfigurationExcludeFilter.class)
})
public @interface SpringBootApplication {
    // Customization options...
}
```

**1. `@Configuration` (via `@SpringBootConfiguration`)**
- Marks the class as a source of bean definitions
- Allows `@Bean` methods
- Subject to CGLIB proxying for inter-bean calls

```java
@SpringBootApplication
public class MyApp {
    @Bean
    public MyService myService() {
        return new MyServiceImpl();
    }
}
```

**2. `@EnableAutoConfiguration`**
- Triggers Spring Boot's auto-configuration mechanism
- Reads `META-INF/spring.factories` and `META-INF/spring/org.springframework.boot.autoconfigure.AutoConfiguration.imports`
- Conditionally registers beans based on classpath and existing beans

**How it works:**
```java
@EnableAutoConfiguration
    ↓
@Import(AutoConfigurationImportSelector.class)
    ↓
Reads: META-INF/spring/org.springframework.boot.autoconfigure.AutoConfiguration.imports
    ↓
Loads all auto-configuration classes
    ↓
Evaluates @Conditional annotations
    ↓
Registers matching beans
```

**Example auto-configurations activated:**
- `DataSourceAutoConfiguration` (if JDBC on classpath)
- `JpaRepositoriesAutoConfiguration` (if Spring Data JPA on classpath)
- `WebMvcAutoConfiguration` (if Spring MVC on classpath)
- `SecurityAutoConfiguration` (if Spring Security on classpath)

**3. `@ComponentScan`**
- Scans for `@Component`, `@Service`, `@Repository`, `@Controller` annotated classes
- Default: Scans the package of the `@SpringBootApplication` class and all sub-packages
- Discovers and registers beans automatically

**Scan behavior:**
```
com.example.myapp
    ↓ @SpringBootApplication here
    ├── MyApp.java
    ├── controller/     ✅ Scanned
    ├── service/        ✅ Scanned
    ├── repository/     ✅ Scanned
    └── config/         ✅ Scanned

com.example.other/      ❌ NOT scanned (outside package)
```

**Customizing the Annotations:**

**Exclude auto-configurations:**
```java
@SpringBootApplication(exclude = {
    DataSourceAutoConfiguration.class,
    SecurityAutoConfiguration.class
})
public class MyApp { }
```

**Custom component scan:**
```java
@SpringBootApplication(scanBasePackages = {
    "com.example.myapp",
    "com.example.shared"
})
public class MyApp { }

// Or exclude specific packages
@SpringBootApplication(
    scanBasePackageClasses = {MyApp.class, OtherPackage.class},
    excludeFilters = @Filter(
        type = FilterType.REGEX,
        pattern = "com.example.myapp.test.*"
    )
)
public class MyApp { }
```

**Disable auto-configuration entirely:**
```java
@Configuration
@ComponentScan
public class MyApp {
    // No auto-configuration, full manual control
}
```

**Equivalent Expanded Form:**
```java
// Instead of @SpringBootApplication
@Configuration
@EnableAutoConfiguration
@ComponentScan
public class MyApp {
    public static void main(String[] args) {
        SpringApplication.run(MyApp.class, args);
    }
}
```

**Processing Order:**
1. `@ComponentScan` runs first → discovers user-defined beans
2. `@EnableAutoConfiguration` runs second → registers auto-configured beans
3. User beans take precedence over auto-configured beans (due to `@ConditionalOnMissingBean`)

**Common Patterns:**

**Multiple packages:**
```java
@SpringBootApplication
@ComponentScan(basePackages = {
    "com.example.core",
    "com.example.web",
    "com.example.data"
})
public class MyApp { }
```

**Excluding test components:**
```java
@SpringBootApplication(excludeFilters = {
    @Filter(type = FilterType.REGEX, pattern = ".*Test.*")
})
public class MyApp { }
```

---

### Q77: How does auto-configuration discover candidate classes?

**Simple Answer:**
Spring Boot reads configuration files (`META-INF/spring/org.springframework.boot.autoconfigure.AutoConfiguration.imports` in Spring Boot 3.x, or `META-INF/spring.factories` in older versions) that list auto-configuration classes, then evaluates their `@Conditional` annotations to decide which to activate.

**Deep Dive:**

**Discovery Process (Spring Boot 3.x):**

**Step 1: Load Auto-Configuration Imports**
```java
// Spring Boot reads this file from all JARs on classpath
META-INF/spring/org.springframework.boot.autoconfigure.AutoConfiguration.imports

// Example contents:
org.springframework.boot.autoconfigure.jdbc.DataSourceAutoConfiguration
org.springframework.boot.autoconfigure.orm.jpa.HibernateJpaAutoConfiguration
org.springframework.boot.autoconfigure.web.servlet.WebMvcAutoConfiguration
```

**Step 2: `AutoConfigurationImportSelector` Processing**
```java
@EnableAutoConfiguration
    ↓
@Import(AutoConfigurationImportSelector.class)
    ↓
AutoConfigurationImportSelector.selectImports() is called
    ↓
Reads META-INF/spring/org.springframework.boot.autoconfigure.AutoConfiguration.imports
    ↓
Returns array of configuration class names
```

**Step 3: Conditional Evaluation**
Each auto-configuration class has `@Conditional` annotations:
```java
@Configuration
@ConditionalOnClass(DataSource.class)  // Only if DataSource on classpath
@ConditionalOnMissingBean(DataSource.class)  // Only if no DataSource bean exists
@EnableConfigurationProperties(DataSourceProperties.class)
public class DataSourceAutoConfiguration {
    
    @Bean
    @ConditionalOnProperty(name = "spring.datasource.type")
    public DataSource dataSource(DataSourceProperties properties) {
        // Create DataSource
    }
}
```

**Step 4: Ordering**
Auto-configurations are ordered using `@AutoConfigureAfter`, `@AutoConfigureBefore`, `@AutoConfigureOrder`:
```java
@Configuration
@AutoConfigureAfter(DataSourceAutoConfiguration.class)
public class JpaAutoConfiguration {
    // Runs after DataSource is configured
}
```

**Complete Flow Diagram:**
```
Application Starts
    ↓
@EnableAutoConfiguration detected
    ↓
AutoConfigurationImportSelector invoked
    ↓
Read AutoConfiguration.imports from ALL JARs
    ↓
Load class metadata (doesn't instantiate yet)
    ↓
Evaluate @Conditional annotations:
    - @ConditionalOnClass → Check classpath
    - @ConditionalOnBean → Check existing beans
    - @ConditionalOnProperty → Check properties
    - @ConditionalOnMissingBean → Check bean doesn't exist
    ↓
Filter out non-matching configurations
    ↓
Sort by @AutoConfigureOrder
    ↓
Process remaining configurations
    ↓
Register beans in ApplicationContext
```

**Example Auto-Configuration:**
```java
@Configuration(proxyBeanMethods = false)
@ConditionalOnClass({ ServletRequest.class, StandardServletEnvironment.class })
@ConditionalOnWebApplication(type = Type.SERVLET)
@EnableConfigurationProperties(ServerProperties.class)
@AutoConfigureOrder(Ordered.HIGHEST_PRECEDENCE)
public class WebMvcAutoConfiguration {
    
    @Bean
    @ConditionalOnMissingBean
    public RequestMappingHandlerMapping requestMappingHandlerMapping() {
        // Only created if user hasn't defined one
    }
}
```

**Conditional Annotations Deep Dive:**

**1. `@ConditionalOnClass`**
```java
@ConditionalOnClass(name = "javax.sql.DataSource")
// Checks if class exists on classpath WITHOUT loading it
// Uses ASM to read class metadata
```

**2. `@ConditionalOnBean`**
```java
@ConditionalOnBean(DataSource.class)
// Checks if bean of type DataSource exists
// Evaluated AFTER all user-defined beans are registered
```

**3. `@ConditionalOnMissingBean`**
```java
@ConditionalOnMissingBean(DataSource.class)
// Only if NO DataSource bean exists
// Allows user beans to override auto-configuration
```

**4. `@ConditionalOnProperty`**
```java
@ConditionalOnProperty(
    name = "spring.datasource.enabled",
    havingValue = "true",
    matchIfMissing = true
)
// Checks application.properties/yml
```

**5. `@ConditionalOnWebApplication`**
```java
@ConditionalOnWebApplication(type = Type.SERVLET)
// Only if servlet-based web app
```

**Creating Custom Auto-Configuration:**

**Step 1: Create Configuration Class**
```java
package com.example.autoconfigure;

@Configuration
@ConditionalOnClass(MyService.class)
@ConditionalOnMissingBean(MyService.class)
@EnableConfigurationProperties(MyServiceProperties.class)
public class MyServiceAutoConfiguration {
    
    @Bean
    public MyService myService(MyServiceProperties properties) {
        return new MyServiceImpl(properties);
    }
}
```

**Step 2: Create Properties Class**
```java
@ConfigurationProperties(prefix = "myservice")
public class MyServiceProperties {
    private boolean enabled = true;
    private String endpoint;
    // getters/setters
}
```

**Step 3: Register Auto-Configuration**
Create file: `META-INF/spring/org.springframework.boot.autoconfigure.AutoConfiguration.imports`
```
com.example.autoconfigure.MyServiceAutoConfiguration
```

**Step 4: Package as Starter**
```xml
<dependency>
    <groupId>com.example</groupId>
    <artifactId>myservice-spring-boot-starter</artifactId>
    <version>1.0.0</version>
</dependency>
```

**Debugging Auto-Configuration:**

**Enable debug logging:**
```properties
# application.properties
debug=true
```

Output shows:
```
Positive matches:
   DataSourceAutoConfiguration matched:
      - @ConditionalOnClass found required class 'javax.sql.DataSource'

Negative matches:
   RedisAutoConfiguration:
      Did not match:
         - @ConditionalOnClass did not find required class 'redis.clients.jedis.Jedis'
```

**Programmatic access:**
```java
@SpringBootApplication
public class MyApp {
    public static void main(String[] args) {
        ConfigurableApplicationContext context = 
            SpringApplication.run(MyApp.class, args);
        
        // Get auto-configuration report
        ConditionEvaluationReport report = 
            context.getBean(ConditionEvaluationReport.class);
        
        report.getConditionAndOutcomesBySource().forEach((source, outcomes) -> {
            System.out.println(source + " -> " + outcomes);
        });
    }
}
```

**Excluding Auto-Configurations:**
```java
// Method 1: Annotation
@SpringBootApplication(exclude = DataSourceAutoConfiguration.class)

// Method 2: Properties
spring.autoconfigure.exclude=\
  org.springframework.boot.autoconfigure.jdbc.DataSourceAutoConfiguration
```

**Performance Optimization:**
```java
// Disable expensive auto-configurations
@Configuration(proxyBeanMethods = false)  // Faster startup
@ConditionalOnClass(value = MyService.class, classLoader = MyClassLoader.class)
```

---

### Q83: When to use `@ConfigurationProperties` vs `@Value`?

**Simple Answer:**
Use `@ConfigurationProperties` for grouping related properties into a type-safe bean with validation. Use `@Value` for injecting individual properties or when you need SpEL expressions.

**Deep Dive:**

**`@ConfigurationProperties` - Type-Safe Property Binding**

**Basic Usage:**
```java
@ConfigurationProperties(prefix = "app.mail")
@Component
public class MailProperties {
    private String host;
    private int port = 587;
    private String username;
    private String password;
    private Map<String, String> headers = new HashMap<>();
    private List<String> recipients = new ArrayList<>();
    
    // Getters and setters required for binding
}
```

**application.yml:**
```yaml
app:
  mail:
    host: smtp.gmail.com
    port: 587
    username: user@example.com
    password: secret
    headers:
      X-Priority: 1
      X-Mailer: MyApp
    recipients:
      - admin@example.com
      - support@example.com
```

**Enabling ConfigurationProperties:**
```java
// Method 1: Component scanning
@ConfigurationProperties(prefix = "app.mail")
@Component
public class MailProperties { }

// Method 2: @EnableConfigurationProperties
@Configuration
@EnableConfigurationProperties(MailProperties.class)
public class AppConfig { }

// Method 3: @ConfigurationPropertiesScan (Spring Boot 2.2+)
@SpringBootApplication
@ConfigurationPropertiesScan("com.example.config")
public class MyApp { }
```

**Advanced Features:**

**1. Nested Properties:**
```java
@ConfigurationProperties(prefix = "app")
public class AppProperties {
    private Database database = new Database();
    private Security security = new Security();
    
    public static class Database {
        private String url;
        private String username;
        private String password;
        private Pool pool = new Pool();
        
        public static class Pool {
            private int maxSize = 10;
            private int minIdle = 2;
        }
    }
    
    public static class Security {
        private boolean enabled = true;
        private List<String> allowedOrigins;
    }
}
```

```yaml
app:
  database:
    url: jdbc:postgresql://localhost/mydb
    username: user
    password: pass
    pool:
      max-size: 20
      min-idle: 5
  security:
    enabled: true
    allowed-origins:
      - https://example.com
      - https://api.example.com
```

**2. Validation:**
```java
@ConfigurationProperties(prefix = "app")
@Validated
public class AppProperties {
    
    @NotBlank
    private String name;
    
    @Min(1)
    @Max(65535)
    private int port;
    
    @Email
    private String adminEmail;
    
    @Pattern(regexp = "^https?://.*")
    private String apiUrl;
    
    @Valid
    private Database database;
    
    public static class Database {
        @NotNull
        private String url;
        
        @Size(min = 3, max = 50)
        private String username;
    }
}
```

**3. Duration and DataSize Support:**
```java
@ConfigurationProperties(prefix = "app")
public class AppProperties {
    @DurationUnit(ChronoUnit.SECONDS)
    private Duration timeout = Duration.ofSeconds(30);
    
    @DataSizeUnit(DataUnit.MEGABYTES)
    private DataSize maxFileSize = DataSize.ofMegabytes(10);
}
```

```yaml
app:
  timeout: 30s  # or 30, 30ms, 30m, 30h
  max-file-size: 10MB  # or 10, 10KB, 10GB
```

**4. Constructor Binding (Immutable Configuration):**
```java
@ConfigurationProperties(prefix = "app")
@ConstructorBinding
public class AppProperties {
    private final String name;
    private final int port;
    private final Database database;
    
    public AppProperties(String name, int port, Database database) {
        this.name = name;
        this.port = port;
        this.database = database;
    }
    
    // Only getters, no setters
    
    public record Database(String url, String username) { }
}

// Enable constructor binding
@EnableConfigurationProperties(AppProperties.class)
```

**`@Value` - Individual Property Injection**

**Basic Usage:**
```java
@Service
public class MyService {
    
    @Value("${app.name}")
    private String appName;
    
    @Value("${app.port:8080}")  // Default value
    private int port;
    
    @Value("${app.enabled:true}")
    private boolean enabled;
}
```

**SpEL Expressions:**
```java
@Component
public class AdvancedConfig {
    
    // Property access
    @Value("${app.name}")
    private String name;
    
    // Expression
    @Value("#{systemProperties['user.home']}")
    private String userHome;
    
    // Bean property access
    @Value("#{@myBean.someProperty}")
    private String beanProperty;
    
    // Conditional
    @Value("#{${app.enabled} ? '${app.name}' : 'default'}")
    private String conditionalValue;
    
    // Math operations
    @Value("#{${app.timeout} * 1000}")
    private long timeoutMillis;
    
    // String concatenation
    @Value("#{T(java.lang.Math).random() * 100}")
    private double randomValue;
}
```

**Lists and Maps with @Value:**
```java
@Component
public class ListConfig {
    
    @Value("${app.servers}")  // comma-separated
    private List<String> servers;
    
    @Value("#{${app.config}}")  // Map from SpEL
    private Map<String, String> config;
}
```

```properties
app.servers=server1,server2,server3
app.config={'key1':'value1','key2':'value2'}
```

**Comparison Table:**

| Feature | @ConfigurationProperties | @Value |
|---------|-------------------------|--------|
| **Use Case** | Group of related properties | Single property |
| **Type Safety** | ✅ Full IDE support | ❌ String-based |
| **Validation** | ✅ JSR-303 support | ❌ Manual |
| **Complex Types** | ✅ Nested objects, collections | ⚠️ Limited |
| **Default Values** | ✅ Field initialization | ✅ ${prop:default} |
| **SpEL** | ❌ Not supported | ✅ Full support |
| **Relaxed Binding** | ✅ kebab-case, camelCase | ❌ Exact match |
| **Metadata** | ✅ IDE autocomplete | ❌ No metadata |
| **Immutability** | ✅ Constructor binding | ❌ Field injection |
| **Testing** | ✅ Easy to mock | ⚠️ Harder to mock |

**Relaxed Binding (ConfigurationProperties only):**
```java
@ConfigurationProperties(prefix = "app")
public class AppProperties {
    private String firstName;  // Binds to any of:
}
```

All these work:
```yaml
app.firstName: John
app.first-name: John  # kebab-case (recommended)
app.first_name: John  # underscore
app.FIRST_NAME: John  # uppercase
```

**When to Use Each:**

**Use `@ConfigurationProperties` when:**
- Multiple related properties (database config, mail settings, etc.)
- Need validation
- Need type safety and IDE support
- Configuration might grow over time
- Sharing configuration across modules
- Need immutable configuration

**Use `@Value` when:**
- Single, unrelated property
- Need SpEL expression
- Simple configuration
- Property used in one place only
- Need system properties or environment variables

**Best Practices:**

**Good - Using ConfigurationProperties:**
```java
@ConfigurationProperties(prefix = "app.datasource")
public class DataSourceProperties {
    private String url;
    private String username;
    private String password;
    private int maxPoolSize = 10;
}

@Configuration
public class DataSourceConfig {
    @Bean
    public DataSource dataSource(DataSourceProperties props) {
        HikariConfig config = new HikariConfig();
        config.setJdbcUrl(props.getUrl());
        config.setUsername(props.getUsername());
        config.setPassword(props.getPassword());
        config.setMaximumPoolSize(props.getMaxPoolSize());
        return new HikariDataSource(config);
    }
}
```

**Bad - Using @Value for related properties:**
```java
@Configuration
public class DataSourceConfig {
    @Value("${app.datasource.url}")
    private String url;
    
    @Value("${app.datasource.username}")
    private String username;
    
    @Value("${app.datasource.password}")
    private String password;
    
    @Value("${app.datasource.max-pool-size:10}")
    private int maxPoolSize;
    
    @Bean
    public DataSource dataSource() {
        // Harder to test, no validation
    }
}
```

**Combining Both:**
```java
@ConfigurationProperties(prefix = "app")
public class AppProperties {
    private String name;
    private int port;
    // Complex configuration
}

@Service
public class MyService {
    @Autowired
    private AppProperties appProperties;  // Complex config
    
    @Value("${simple.flag:false}")  // Simple flag
    private boolean simpleFlag;
    
    @Value("#{T(java.lang.Runtime).getRuntime().availableProcessors()}")
    private int processors;  // SpEL expression
}
```

**Testing:**
```java
// Easy with ConfigurationProperties
@Test
void testWithConfigProperties() {
    AppProperties props = new AppProperties();
    props.setName("test");
    props.setPort(8080);
    MyService service = new MyService(props);
}

// Harder with @Value
@SpringBootTest
@TestPropertySource(properties = {
    "app.name=test",
    "app.port=8080"
})
class MyServiceTest {
    @Autowired
    private MyService service;
}
```

---

## 5️⃣ Spring Data & Persistence

### Q121: How does Spring Data generate repository implementations from method names?

**Simple Answer:**
Spring Data parses repository method names into parts (find/By/Property/Operator), builds a query from those parts, and generates an implementation that executes the query against the database.

**Deep Dive:**

**Method Name Query Creation Process:**

**Step 1: Method Name Parsing**
```java
public interface UserRepository extends JpaRepository<User, Long> {
    
    // Method name: findByLastnameAndAgeGreaterThan
    List<User> findByLastnameAndAgeGreaterThan(String lastname, int age);
}
```

**Parsing breakdown:**
```
findByLastnameAndAgeGreaterThan
  ↓
find           → Query type (find, read, get, query, stream, count, exists, delete)
By             → Separator
Lastname       → Property name (User.lastname)
And            → Logical operator
Age            → Property name (User.age)
GreaterThan    → Comparison operator
```

**Step 2: Query Creation**
Spring Data generates JPQL:
```sql
SELECT u FROM User u 
WHERE u.lastname = ?1 
  AND u.age > ?2
```

**Complete Method Name Keywords:**

**Query Types:**
```java
// Retrieve data
List<User> findBy...()
List<User> readBy...()
List<User> getBy...()
List<User> queryBy...()
Stream<User> streamBy...()

// Count
long countBy...()

// Exists check
boolean existsBy...()

// Delete
void deleteBy...()
long removeBy...()

// First/Top results
User findFirstBy...()
List<User> findTop3By...()
List<User> findFirst10By...()
```

**Property Expressions:**
```java
public interface UserRepository extends JpaRepository<User, Long> {
    
    // Simple property
    User findByEmail(String email);
    
    // Nested property
    List<User> findByAddressCity(String city);
    
    // Multiple properties with AND
    User findByFirstnameAndLastname(String firstname, String lastname);
    
    // Multiple properties with OR
    List<User> findByFirstnameOrLastname(String name);
}
```

**Comparison Operators:**
```java
// Equality
User findByAge(int age);                    // age = ?

// Comparison
List<User> findByAgeGreaterThan(int age);   // age > ?
List<User> findByAgeLessThan(int age);      // age < ?
List<User> findByAgeGreaterThanEqual(int age);  // age >= ?
List<User> findByAgeLessThanEqual(int age); // age <= ?
List<User> findByAgeBetween(int start, int end);  // age BETWEEN ? AND ?

// String operations
List<User> findByFirstnameContaining(String str);  // LIKE %str%
List<User> findByFirstnameStartingWith(String prefix);  // LIKE prefix%
List<User> findByFirstnameEndingWith(String suffix);  // LIKE %suffix
List<User> findByFirstnameLike(String pattern);  // LIKE pattern

// Case insensitive
List<User> findByFirstnameIgnoreCase(String firstname);
List<User> findByFirstnameContainingIgnoreCase(String str);

// NULL checks
List<User> findByAgeIsNull();
List<User> findByAgeIsNotNull();

// Boolean
List<User> findByActiveTrue();
List<User> findByActiveFalse();

// Collection operations
List<User> findByAgeIn(Collection<Integer> ages);
List<User> findByAgeNotIn(Collection<Integer> ages);
```

**Logical Operators:**
```java
// AND
User findByFirstnameAndLastname(String firstname, String lastname);

// OR
List<User> findByFirstnameOrLastname(String name);

// Combination
List<User> findByFirstnameAndLastnameOrEmail(
    String firstname, String lastname, String email);
// WHERE (firstname = ? AND lastname = ?) OR email = ?
```

**Ordering:**
```java
// Ascending
List<User> findByLastnameOrderByFirstnameAsc(String lastname);

// Descending
List<User> findByLastnameOrderByFirstnameDesc(String lastname);

// Multiple sort fields
List<User> findByLastnameOrderByFirstnameAscAgeDesc(String lastname);

// With Sort parameter
List<User> findByLastname(String lastname, Sort sort);
// Usage: repository.findByLastname("Smith", Sort.by("firstname").ascending())
```

**Pagination:**
```java
// Page results
Page<User> findByLastname(String lastname, Pageable pageable);
// Usage: repository.findByLastname("Smith", PageRequest.of(0, 10))

// Slice results (lighter than Page)
Slice<User> findByLastname(String lastname, Pageable pageable);

// List with Pageable
List<User> findByLastname(String lastname, Pageable pageable);
```

**Limiting Results:**
```java
// First result
User findFirstByOrderByAgeDesc();

// Top N results
List<User> findTop3ByOrderByAgeDesc();
List<User> findFirst10ByLastname(String lastname);

// With Pageable
List<User> findTop3ByLastname(String lastname, Pageable pageable);
```

**Internal Implementation Process:**

**Step 1: Repository Proxy Creation**
```java
@EnableJpaRepositories
@Configuration
public class JpaConfig { }

// At runtime:
JpaRepositoryFactoryBean creates proxy
    ↓
SimpleJpaRepository (default implementation)
    ↓
PartTreeJpaQuery (for method-name queries)
```

**Step 2: Query Generation**
```java
// Simplified internal process
public class PartTreeJpaQuery extends AbstractJpaQuery {
    
    public PartTree tree; // Parsed method name
    
    @Override
    protected Query createQuery(Object[] parameters) {
        CriteriaBuilder builder = entityManager.getCriteriaBuilder();
        CriteriaQuery<T> query = builder.createQuery(domainClass);
        Root<T> root = query.from(domainClass);
        
        // Build predicates from parsed tree
        Predicate predicate = tree.toPredicate(root, query, builder);
        query.where(predicate);
        
        return entityManager.createQuery(query);
    }
}
```

**Step 3: Parameter Binding**
```java
User findByFirstnameAndAge(String firstname, int age);

// Spring Data binds:
// Parameter 0 → firstname
// Parameter 1 → age

// Generates:
SELECT u FROM User u WHERE u.firstname = ?1 AND u.age = ?2
```

**Complex Examples:**

**Nested Properties:**
```java
@Entity
public class User {
    private Address address;
}

@Entity
public class Address {
    private String city;
    private String zipCode;
}

public interface UserRepository extends JpaRepository<User, Long> {
    List<User> findByAddressCity(String city);
    // SELECT u FROM User u WHERE u.address.city = ?1
    
    List<User> findByAddressCityAndAddressZipCode(String city, String zip);
    // SELECT u FROM User u 
    // WHERE u.address.city = ?1 AND u.address.zipCode = ?2
}
```

**Collections:**
```java
@Entity
public class User {
    @ManyToMany
    private Set<Role> roles;
}

public interface UserRepository extends JpaRepository<User, Long> {
    List<User> findByRolesName(String roleName);
    // SELECT DISTINCT u FROM User u 
    // INNER JOIN u.roles r WHERE r.name = ?1
}
```

**Alternative: @Query for Complex Queries**
```java
public interface UserRepository extends JpaRepository<User, Long> {
    
    // Method name query - simple
    List<User> findByAgeGreaterThan(int age);
    
    // @Query - complex logic
    @Query("SELECT u FROM User u WHERE u.age > :age AND u.active = true " +
           "AND u.createdDate > :date ORDER BY u.lastname")
    List<User> findActiveUsersOlderThan(@Param("age") int age, 
                                        @Param("date") LocalDate date);
    
    // Native query
    @Query(value = "SELECT * FROM users u WHERE u.age > ?1 " +
                   "AND EXISTS (SELECT 1 FROM orders o WHERE o.user_id = u.id)",
           nativeQuery = true)
    List<User> findUsersWithOrders(int age);
}
```

**Performance Considerations:**
```java
// GOOD - Specific query
User findByEmail(String email);

// BAD - Fetches all users then filters in memory
List<User> findAll().stream()
    .filter(u -> u.getEmail().equals(email))
    .findFirst();

// GOOD - Database-level pagination
Page<User> findByActive(boolean active, Pageable pageable);

// BAD - Loads all then paginates in memory
List<User> findByActive(boolean active);
```

**Limitations and When to Use @Query:**
```java
// Method names become unwieldy
List<User> findByFirstnameAndLastnameAndAgeGreaterThanAndActiveTrueOrderByCreatedDateDesc(
    String firstname, String lastname, int age);

// Better with @Query:
@Query("SELECT u FROM User u WHERE u.firstname = :first AND u.lastname = :last " +
       "AND u.age > :age AND u.active = true ORDER BY u.createdDate DESC")
List<User> findActiveUsers(@Param("first") String firstname,
                           @Param("last") String lastname,
                           @Param("age") int age);
```

---

### Q122: Explain `@EntityGraph` and solving the N+1 problem.

**Simple Answer:**
`@EntityGraph` tells JPA to fetch specified associations eagerly in a single query using JOINs, eliminating the N+1 select problem where lazy-loaded associations cause multiple database queries.

**Deep Dive:**

**The N+1 Problem:**

**Problem Example:**
```java
@Entity
public class User {
    @Id
    private Long id;
    private String name;
    
    @OneToMany(mappedBy = "user", fetch = FetchType.LAZY)
    private List<Order> orders;
    
    @ManyToOne(fetch = FetchType.LAZY)
    private Address address;
}

// Code that triggers N+1:
List<User> users = userRepository.findAll();  // 1 query
for (User user : users) {
    System.out.println(user.getOrders());  // N queries (one per user!)
}
```

**What happens:**
```sql
-- Query 1: Fetch users
SELECT * FROM users;  -- Returns 100 users

-- Query 2-101: Fetch orders for each user (N queries!)
SELECT * FROM orders WHERE user_id = 1;
SELECT * FROM orders WHERE user_id = 2;
SELECT * FROM orders WHERE user_id = 3;
...
SELECT * FROM orders WHERE user_id = 100;

-- Total: 101 queries instead of 1!
```

**Solution 1: `@EntityGraph` Annotation**

**Basic Usage:**
```java
public interface UserRepository extends JpaRepository<User, Long> {
    
    @EntityGraph(attributePaths = {"orders", "address"})
    List<User> findAll();
}
```

**Generated SQL:**
```sql
SELECT u.*, o.*, a.*
FROM users u
LEFT JOIN orders o ON u.id = o.user_id
LEFT JOIN address a ON u.address_id = a.id
```

**Result:** Single query fetches users, orders, and addresses together!

**EntityGraph Types:**

**1. FETCH Type (Default) - Only fetch specified paths:**
```java
@EntityGraph(attributePaths = {"orders"}, type = EntityGraph.EntityGraphType.FETCH)
List<User> findAll();
```

- Fetches only `orders` eagerly
- All other LAZY associations remain lazy
- Other EAGER associations still fetched

**2. LOAD Type - Fetch specified + all EAGER:**
```java
@EntityGraph(attributePaths = {"orders"}, type = EntityGraph.EntityGraphType.LOAD)
List<User> findAll();
```

- Fetches `orders` eagerly
- Also fetches all associations marked `FetchType.EAGER`

**Named Entity Graphs:**

**Define in Entity:**
```java
@Entity
@NamedEntityGraph(
    name = "User.withOrdersAndAddress",
    attributeNodes = {
        @NamedAttributeNode("orders"),
        @NamedAttributeNode("address")
    }
)
public class User {
    @Id
    private Long id;
    
    @OneToMany(mappedBy = "user")
    private List<Order> orders;
    
    @ManyToOne
    private Address address;
}
```

**Use in Repository:**
```java
public interface UserRepository extends JpaRepository<User, Long> {
    
    @EntityGraph(value = "User.withOrdersAndAddress")
    List<User> findAll();
    
    @EntityGraph(value = "User.withOrdersAndAddress")
    Optional<User> findById(Long id);
}
```

**Nested Entity Graphs:**

**Complex associations:**
```java
@Entity
public class User {
    @OneToMany
    private List<Order> orders;
}

@Entity
public class Order {
    @OneToMany
    private List<OrderItem> items;
    
    @ManyToOne
    private Product product;
}
```

**Fetch nested associations:**
```java
@Entity
@NamedEntityGraph(
    name = "User.detailed",
    attributeNodes = {
        @NamedAttributeNode(
            value = "orders",
            subgraph = "orders-subgraph"
        )
    },
    subgraphs = {
        @NamedSubgraph(
            name = "orders-subgraph",
            attributeNodes = {
                @NamedAttributeNode("items"),
                @NamedAttributeNode("product")
            }
        )
    }
)
public class User { }

// Usage
@EntityGraph("User.detailed")
List<User> findAll();
```

**Generated SQL:**
```sql
SELECT u.*, o.*, oi.*, p.*
FROM users u
LEFT JOIN orders o ON u.id = o.user_id
LEFT JOIN order_items oi ON o.id = oi.order_id
LEFT JOIN products p ON o.product_id = p.id
```

**Dynamic Entity Graphs:**

**Ad-hoc entity graph:**
```java
@Repository
public class CustomUserRepository {
    
    @PersistenceContext
    private EntityManager em;
    
    public List<User> findUsersWithOrders() {
        EntityGraph<User> graph = em.createEntityGraph(User.class);
        graph.addAttributeNodes("orders");
        
        return em.createQuery("SELECT u FROM User u", User.class)
                 .setHint("javax.persistence.fetchgraph", graph)
                 .getResultList();
    }
    
    public List<User> findUsersComplete() {
        EntityGraph<User> graph = em.createEntityGraph(User.class);
        graph.addAttributeNodes("orders", "address", "roles");
        
        Subgraph<Order> orderSubgraph = graph.addSubgraph("orders");
        orderSubgraph.addAttributeNodes("items", "payment");
        
        return em.createQuery("SELECT u FROM User u", User.class)
                 .setHint("javax.persistence.loadgraph", graph)
                 .getResultList();
    }
}
```

**Multiple Entity Graphs:**

**Different graphs for different queries:**
```java
@Entity
@NamedEntityGraphs({
    @NamedEntityGraph(
        name = "User.summary",
        attributeNodes = @NamedAttributeNode("address")
    ),
    @NamedEntityGraph(
        name = "User.detailed",
        attributeNodes = {
            @NamedAttributeNode("address"),
            @NamedAttributeNode("orders"),
            @NamedAttributeNode("roles")
        }
    )
})
public class User { }

public interface UserRepository extends JpaRepository<User, Long> {
    
    @EntityGraph("User.summary")
    List<User> findAllSummary();
    
    @EntityGraph("User.detailed")
    List<User> findAllDetailed();
    
    @EntityGraph("User.detailed")
    Optional<User> findDetailedById(Long id);
}
```

**Cartesian Product Problem:**

**Problem with multiple collections:**
```java
@Entity
public class User {
    @OneToMany
    private List<Order> orders;      // 10 orders
    
    @OneToMany
    private List<Address> addresses;  // 3 addresses
}

@EntityGraph(attributePaths = {"orders", "addresses"})
List<User> findAll();
```

**Generated SQL creates Cartesian product:**
```sql
SELECT u.*, o.*, a.*
FROM users u
LEFT JOIN orders o ON u.id = o.user_id
LEFT JOIN addresses a ON u.id = a.user_id

-- Returns 10 × 3 = 30 rows for 1 user!
```

**Solution: Use separate queries or subselects:**
```java
// Option 1: Multiple queries
@EntityGraph(attributePaths = "orders")
List<User> findAll();

// Then in service:
users.forEach(user -> {
    Hibernate.initialize(user.getAddresses());
});

// Option 2: Batch fetching
@Entity
public class User {
    @OneToMany
    @BatchSize(size = 10)
    private List<Order> orders;
}
```

**Testing N+1 Prevention:**

**Enable query logging:**
```properties
spring.jpa.show-sql=true
spring.jpa.properties.hibernate.format_sql=true

# Count queries
logging.level.org.hibernate.SQL=DEBUG
logging.level.org.hibernate.type.descriptor.sql.BasicBinder=TRACE
```

**Unit test:**
```java
@SpringBootTest
@Transactional
class EntityGraphTest {
    
    @Autowired
    private UserRepository userRepository;
    
    @PersistenceContext
    private EntityManager em;
    
    @Test
    void testNoNPlusOne() {
        // Arrange: Create test data
        User user1 = new User();
        user1.setOrders(Arrays.asList(new Order(), new Order()));
        em.persist(user1);
        
        User user2 = new User();
        user2.setOrders(Arrays.asList(new Order()));
        em.persist(user2);
        
        em.flush();
        em.clear();
        
        // Act: Fetch with EntityGraph
        List<User> users = userRepository.findAll();
        
        // Access lazy collection - should not trigger queries
        users.forEach(user -> {
            user.getOrders().size();  // No additional queries!
        });
        
        // Assert: Verify query count using Hibernate statistics
        Statistics stats = em.getEntityManagerFactory()
                             .unwrap(SessionFactory.class)
                             .getStatistics();
        
        assertEquals(1, stats.getQueryExecutionCount());
    }
}
```

**Performance Comparison:**

```java
// WITHOUT EntityGraph - 101 queries for 100 users
List<User> users = userRepository.findAll();
users.forEach(u -> u.getOrders().size());

// WITH EntityGraph - 1 query
@EntityGraph(attributePaths = "orders")
List<User> findAll();
```

**Best Practices:**

1. **Use for read-heavy operations:** Don't eagerly fetch for write operations
2. **Profile first:** Confirm N+1 exists before optimizing
3. **Avoid multiple collections:** Causes Cartesian products
4. **Consider projections:** Sometimes DTOs are better than entity graphs
5. **Use @BatchSize as alternative:** For simpler cases

```java
@Entity
public class User {
    @OneToMany
    @BatchSize(size = 25)  // Fetches 25 collections in one query
    private List<Order> orders;
}
```

---

## 6️⃣ Spring Security

### Q154: Implement stateless JWT authentication in Spring Security 6.

**Simple Answer:**
Configure Spring Security to validate JWT tokens on each request without using sessions, by creating a filter that extracts the token, validates it, and sets the authentication in the SecurityContext.

**Deep Dive:**

**Complete Implementation:**

**Step 1: Dependencies**
```xml
<dependencies>
    <dependency>
        <groupId>org.springframework.boot</groupId>
        <artifactId>spring-boot-starter-security</artifactId>
    </dependency>
    <dependency>
        <groupId>org.springframework.boot</groupId>
        <artifactId>spring-boot-starter-oauth2-resource-server</artifactId>
    </dependency>
</dependencies>
```

**Step 2: JWT Properties Configuration**
```java
@ConfigurationProperties(prefix = "jwt")
public class JwtProperties {
    private String secretKey;
    private long expirationMs = 86400000; // 24 hours
    private String issuer;
    
    // Getters and setters
}
```

```yaml
jwt:
  secret-key: your-256-bit-secret-key-here-make-it-long-and-random
  expiration-ms: 86400000
  issuer: myapp
```

**Step 3: JWT Service**
```java
@Service
public class JwtService {
    
    private final Key key;
    private final JwtProperties jwtProperties;
    
    public JwtService(JwtProperties jwtProperties) {
        this.jwtProperties = jwtProperties;
        byte[] keyBytes = Decoders.BASE64.decode(jwtProperties.getSecretKey());
        this.key = Keys.hmacShaKeyFor(keyBytes);
    }
    
    public String generateToken(UserDetails userDetails) {
        Map<String, Object> claims = new HashMap<>();
        claims.put("roles", userDetails.getAuthorities().stream()
            .map(GrantedAuthority::getAuthority)
            .collect(Collectors.toList()));
        
        return Jwts.builder()
            .setClaims(claims)
            .setSubject(userDetails.getUsername())
            .setIssuer(jwtProperties.getIssuer())
            .setIssuedAt(new Date())
            .setExpiration(new Date(System.currentTimeMillis() + jwtProperties.getExpirationMs()))
            .signWith(key, SignatureAlgorithm.HS256)
            .compact();
    }
    
    public String extractUsername(String token) {
        return extractClaim(token, Claims::getSubject);
    }
    
    public <T> T extractClaim(String token, Function<Claims, T> claimsResolver) {
        final Claims claims = extractAllClaims(token);
        return claimsResolver.apply(claims);
    }
    
    private Claims extractAllClaims(String token) {
        return Jwts.parserBuilder()
            .setSigningKey(key)
            .build()
            .parseClaimsJws(token)
            .getBody();
    }
    
    public boolean isTokenValid(String token, UserDetails userDetails) {
        final String username = extractUsername(token);
        return (username.equals(userDetails.getUsername()) && !isTokenExpired(token));
    }
    
    private boolean isTokenExpired(String token) {
        return extractExpiration(token).before(new Date());
    }
    
    private Date extractExpiration(String token) {
        return extractClaim(token, Claims::getExpiration);
    }
    
    public List<String> extractRoles(String token) {
        Claims claims = extractAllClaims(token);
        return (List<String>) claims.get("roles");
    }
}
```

**Step 4: JWT Authentication Filter**
```java
@Component
public class JwtAuthenticationFilter extends OncePerRequestFilter {
    
    private final JwtService jwtService;
    private final UserDetailsService userDetailsService;
    
    public JwtAuthenticationFilter(JwtService jwtService, 
                                   UserDetailsService userDetailsService) {
        this.jwtService = jwtService;
        this.userDetailsService = userDetailsService;
    }
    
    @Override
    protected void doFilterInternal(
            HttpServletRequest request,
            HttpServletResponse response,
            FilterChain filterChain) throws ServletException, IOException {
        
        // Extract JWT from Authorization header
        final String authHeader = request.getHeader("Authorization");
        
        if (authHeader == null || !authHeader.startsWith("Bearer ")) {
            filterChain.doFilter(request, response);
            return;
        }
        
        try {
            final String jwt = authHeader.substring(7);
            final String username = jwtService.extractUsername(jwt);
            
            // If username is extracted and no authentication exists
            if (username != null && SecurityContextHolder.getContext().getAuthentication() == null) {
                UserDetails userDetails = userDetailsService.loadUserByUsername(username);
                
                // Validate token
                if (jwtService.isTokenValid(jwt, userDetails)) {
                    // Extract roles from token
                    List<String> roles = jwtService.extractRoles(jwt);
                    List<GrantedAuthority> authorities = roles.stream()
                        .map(SimpleGrantedAuthority::new)
                        .collect(Collectors.toList());
                    
                    // Create authentication token
                    UsernamePasswordAuthenticationToken authToken = 
                        new UsernamePasswordAuthenticationToken(
                            userDetails,
                            null,
                            authorities
                        );
                    
                    // Set additional details
                    authToken.setDetails(
                        new WebAuthenticationDetailsSource().buildDetails(request)
                    );
                    
                    // Set authentication in SecurityContext
                    SecurityContextHolder.getContext().setAuthentication(authToken);
                }
            }
            
            filterChain.doFilter(request, response);
            
        } catch (ExpiredJwtException e) {
            response.setStatus(HttpServletResponse.SC_UNAUTHORIZED);
            response.getWriter().write("Token expired");
        } catch (JwtException e) {
            response.setStatus(HttpServletResponse.SC_UNAUTHORIZED);
            response.getWriter().write("Invalid token");
        }
    }
}
```

**Step 5: Security Configuration**
```java
@Configuration
@EnableWebSecurity
@EnableMethodSecurity
public class SecurityConfig {
    
    private final JwtAuthenticationFilter jwtAuthFilter;
    private final AuthenticationProvider authenticationProvider;
    
    public SecurityConfig(JwtAuthenticationFilter jwtAuthFilter,
                         AuthenticationProvider authenticationProvider) {
        this.jwtAuthFilter = jwtAuthFilter;
        this.authenticationProvider = authenticationProvider;
    }
    
    @Bean
    public SecurityFilterChain securityFilterChain(HttpSecurity http) throws Exception {
        http
            .csrf(csrf -> csrf.disable())  // Disable CSRF for stateless JWT
            .sessionManagement(session -> 
                session.sessionCreationPolicy(SessionCreationPolicy.STATELESS))
            .authorizeHttpRequests(auth -> auth
                .requestMatchers("/api/auth/**").permitAll()  // Public endpoints
                .requestMatchers("/api/admin/**").hasRole("ADMIN")
                .requestMatchers("/api/user/**").hasAnyRole("USER", "ADMIN")
                .anyRequest().authenticated()
            )
            .authenticationProvider(authenticationProvider)
            .addFilterBefore(jwtAuthFilter, UsernamePasswordAuthenticationFilter.class)
            .exceptionHandling(ex -> ex
                .authenticationEntryPoint(
                    (request, response, authException) -> {
                        response.setStatus(HttpServletResponse.SC_UNAUTHORIZED);
                        response.getWriter().write("Unauthorized");
                    }
                )
            );
        
        return http.build();
    }
    
    @Bean
    public AuthenticationProvider authenticationProvider(
            UserDetailsService userDetailsService,
            PasswordEncoder passwordEncoder) {
        DaoAuthenticationProvider authProvider = new DaoAuthenticationProvider();
        authProvider.setUserDetailsService(userDetailsService);
        authProvider.setPasswordEncoder(passwordEncoder);
        return authProvider;
    }
    
    @Bean
    public AuthenticationManager authenticationManager(AuthenticationConfiguration config) 
            throws Exception {
        return config.getAuthenticationManager();
    }
    
    @Bean
    public PasswordEncoder passwordEncoder() {
        return new BCryptPasswordEncoder();
    }
}
```

**Step 6: Authentication Controller**
```java
@RestController
@RequestMapping("/api/auth")
public class AuthenticationController {
    
    private final AuthenticationManager authenticationManager;
    private final JwtService jwtService;
    private final UserDetailsService userDetailsService;
    
    public AuthenticationController(AuthenticationManager authenticationManager,
                                   JwtService jwtService,
                                   UserDetailsService userDetailsService) {
        this.authenticationManager = authenticationManager;
        this.jwtService = jwtService;
        this.userDetailsService = userDetailsService;
    }
    
    @PostMapping("/login")
    public ResponseEntity<AuthenticationResponse> login(
            @RequestBody AuthenticationRequest request) {
        
        // Authenticate user
        authenticationManager.authenticate(
            new UsernamePasswordAuthenticationToken(
                request.getUsername(),
                request.getPassword()
            )
        );
        
        // Load user details
        UserDetails userDetails = userDetailsService.loadUserByUsername(request.getUsername());
        
        // Generate JWT
        String token = jwtService.generateToken(userDetails);
        
        return ResponseEntity.ok(new AuthenticationResponse(token));
    }
    
    @PostMapping("/register")
    public ResponseEntity<AuthenticationResponse> register(
            @RequestBody RegisterRequest request) {
        // Registration logic here
        // ...
        
        UserDetails userDetails = userDetailsService.loadUserByUsername(request.getUsername());
        String token = jwtService.generateToken(userDetails);
        
        return ResponseEntity.ok(new AuthenticationResponse(token));
    }
}

record AuthenticationRequest(String username, String password) {}
record RegisterRequest(String username, String password, String email) {}
record AuthenticationResponse(String token) {}
```

**Step 7: Protected Resource Example**
```java
@RestController
@RequestMapping("/api/user")
public class UserController {
    
    @GetMapping("/profile")
    public ResponseEntity<UserProfile> getProfile(@AuthenticationPrincipal UserDetails userDetails) {
        UserProfile profile = new UserProfile(
            userDetails.getUsername(),
            userDetails.getAuthorities().stream()
                .map(GrantedAuthority::getAuthority)
                .collect(Collectors.toList())
        );
        return ResponseEntity.ok(profile);
    }
    
    @GetMapping("/dashboard")
    @PreAuthorize("hasRole('USER')")
    public ResponseEntity<String> getDashboard() {
        return ResponseEntity.ok("User dashboard");
    }
}

@RestController
@RequestMapping("/api/admin")
@PreAuthorize("hasRole('ADMIN')")
public class AdminController {
    
    @GetMapping("/users")
    public ResponseEntity<List<User>> getAllUsers() {
        // Admin-only endpoint
        return ResponseEntity.ok(List.of());
    }
}

record UserProfile(String username, List<String> roles) {}
```

**Usage Example:**

**Login Request:**
```bash
curl -X POST http://localhost:8080/api/auth/login \
  -H "Content-Type: application/json" \
  -d '{"username":"user@example.com","password":"password123"}'
```

**Response:**
```json
{
  "token": "eyJhbGciOiJIUzI1NiJ9.eyJyb2xlcyI6WyJST0xFX1VTRVIiXSwic3ViIjoidXNlckBleGFtcGxlLmNvbSIsImlzcyI6Im15YXBwIiwiaWF0IjoxNzA2NzI0MDAwLCJleHAiOjE3MDY4MTA0MDB9.xxx"
}
```

**Authenticated Request:**
```bash
curl http://localhost:8080/api/user/profile \
  -H "Authorization: Bearer eyJhbGciOiJIUzI1NiJ9..."
```

**Advanced Features:**

**1. Token Refresh:**
```java
@PostMapping("/refresh")
public ResponseEntity<AuthenticationResponse> refresh(
        @RequestHeader("Authorization") String authHeader) {
    
    String token = authHeader.substring(7);
    String username = jwtService.extractUsername(token);
    UserDetails userDetails = userDetailsService.loadUserByUsername(username);
    
    if (jwtService.isTokenValid(token, userDetails)) {
        String newToken = jwtService.generateToken(userDetails);
        return ResponseEntity.ok(new AuthenticationResponse(newToken));
    }
    
    return ResponseEntity.status(HttpStatus.UNAUTHORIZED).build();
}
```

**2. Logout (Blacklist Token):**
```java
@Service
public class TokenBlacklistService {
    private final Set<String> blacklist = ConcurrentHashMap.newKeySet();
    
    public void blacklistToken(String token) {
        blacklist.add(token);
    }
    
    public boolean isBlacklisted(String token) {
        return blacklist.contains(token);
    }
}

// In JwtAuthenticationFilter:
if (tokenBlacklistService.isBlacklisted(jwt)) {
    response.setStatus(HttpServletResponse.SC_UNAUTHORIZED);
    return;
}
```

**3. Custom Claims:**
```java
public String generateToken(UserDetails userDetails, Map<String, Object> extraClaims) {
    Map<String, Object> claims = new HashMap<>(extraClaims);
    claims.put("roles", userDetails.getAuthorities());
    claims.put("userId", ((CustomUserDetails) userDetails).getId());
    claims.put("email", ((CustomUserDetails) userDetails).getEmail());
    
    return Jwts.builder()
        .setClaims(claims)
        .setSubject(userDetails.getUsername())
        // ...
        .compact();
}
```

**Testing:**
```java
@SpringBootTest
@AutoConfigureMockMvc
class JwtAuthenticationTest {
    
    @Autowired
    private MockMvc mockMvc;
    
    @Autowired
    private JwtService jwtService;
    
    @Test
    void testAuthenticatedRequest() throws Exception {
        UserDetails user = User.builder()
            .username("test@example.com")
            .password("password")
            .roles("USER")
            .build();
        
        String token = jwtService.generateToken(user);
        
        mockMvc.perform(get("/api/user/profile")
                .header("Authorization", "Bearer " + token))
            .andExpect(status().isOk());
    }
    
    @Test
    void testUnauthorizedWithoutToken() throws Exception {
        mockMvc.perform(get("/api/user/profile"))
            .andExpect(status().isUnauthorized());
    }
}
```

---

## 7️⃣ Spring Cloud & Microservices

### Q176: Difference between `@EnableDiscoveryClient` and `@EnableEurekaClient`.

**Simple Answer:**
`@EnableDiscoveryClient` is a generic annotation that works with any service discovery implementation (Eureka, Consul, Zookeeper). `@EnableEurekaClient` is specific to Netflix Eureka only.

**Deep Dive:**

**Historical Context:**
- `@EnableEurekaClient` was the original Eureka-specific annotation
- `@EnableDiscoveryClient` was added to support multiple discovery clients
- Since Spring Cloud 2020+, both are optional (auto-configuration handles it)

**`@EnableDiscoveryClient` - Generic Approach**
```java
@SpringBootApplication
@EnableDiscoveryClient  // Works with any implementation
public class MyServiceApplication {
    public static void main(String[] args) {
        SpringApplication.run(MyServiceApplication.class, args);
    }
}
```

**Supported Implementations:**
- Netflix Eureka
- HashiCorp Consul
- Apache Zookeeper
- Kubernetes
- Cloud Foundry

**`@EnableEurekaClient` - Eureka-Specific**
```java
@SpringBootApplication
@EnableEurekaClient  // Only works with Eureka
public class MyServiceApplication {
    public static void main(String[] args) {
        SpringApplication.run(MyServiceApplication.class, args);
    }
}
```

**Comparison:**

| Aspect | @EnableDiscoveryClient | @EnableEurekaClient |
|--------|----------------------|-------------------|
| **Supported registries** | Any (Eureka, Consul, Zookeeper) | Eureka only |
| **Abstraction level** | High (generic) | Low (specific) |
| **Spring Cloud version** | All | All |
| **Recommended** | ✅ Yes (flexible) | ⚠️ Only if Eureka-only |
| **Auto-configuration** | Works automatically | Works automatically |

**Modern Approach (Spring Cloud 2020+):**
```java
@SpringBootApplication  // No annotation needed!
public class MyServiceApplication {
    // Discovery client auto-configured based on dependencies
}
```

**Dependency determines implementation:**
```xml
<!-- Eureka -->
<dependency>
    <groupId>org.springframework.cloud</groupId>
    <artifactId>spring-cloud-starter-netflix-eureka-client</artifactId>
</dependency>

<!-- OR Consul -->
<dependency>
    <groupId>org.springframework.cloud</groupId>
    <artifactId>spring-cloud-starter-consul-discovery</artifactId>
</dependency>
```

**Using Discovery Client:**
```java
@Service
public class MyService {
    
    @Autowired
    private DiscoveryClient discoveryClient;  // Generic interface
    
    public List<ServiceInstance> getInstances(String serviceName) {
        return discoveryClient.getInstances(serviceName);
    }
    
    public List<String> getServices() {
        return discoveryClient.getServices();
    }
}

// Works with ANY implementation!
```

**Eureka-Specific Features:**
```java
@Service
public class EurekaSpecificService {
    
    @Autowired
    private EurekaClient eurekaClient;  // Eureka-specific
    
    public InstanceInfo getInstanceInfo(String appName) {
        Application application = eurekaClient.getApplication(appName);
        return application.getInstances().get(0);
    }
    
    // Eureka-only features like health checks, metadata, etc.
}
```

**Configuration Examples:**

**Eureka:**
```yaml
eureka:
  client:
    service-url:
      defaultZone: http://localhost:8761/eureka/
  instance:
    prefer-ip-address: true
    instance-id: ${spring.application.name}:${random.value}
```

**Consul:**
```yaml
spring:
  cloud:
    consul:
      host: localhost
      port: 8500
      discovery:
        prefer-ip-address: true
        health-check-path: /actuator/health
```

**Best Practices:**
1. **Use `@EnableDiscoveryClient`** for flexibility
2. **Omit annotations** in modern Spring Cloud (auto-configured)
3. **Use generic `DiscoveryClient` interface** in code
4. **Only use `EurekaClient`** if you need Eureka-specific features

---

### Q180: `@LoadBalanced` RestTemplate vs WebClient – how do they resolve service names?

**Simple Answer:**
Both use Spring Cloud LoadBalancer (or legacy Ribbon) to intercept HTTP requests, resolve service names to actual instance URLs from the discovery client, and distribute requests across available instances.

**Deep Dive:**

**`@LoadBalanced` RestTemplate:**

**Configuration:**
```java
@Configuration
public class RestTemplateConfig {
    
    @Bean
    @LoadBalanced  // Enables client-side load balancing
    public RestTemplate restTemplate() {
        return new RestTemplate();
    }
}
```

**Usage:**
```java
@Service
public class OrderService {
    
    @Autowired
    @LoadBalanced
    private RestTemplate restTemplate;
    
    public Product getProduct(Long productId) {
        // "product-service" is logical service name
        String url = "http://product-service/api/products/" + productId;
        return restTemplate.getForObject(url, Product.class);
    }
}
```

**How It Works:**
```
1. Request: http://product-service/api/products/123
           ↓
2. LoadBalancerInterceptor intercepts
           ↓
3. Query DiscoveryClient for "product-service" instances
           ↓
4. Receives: [192.168.1.10:8081, 192.168.1.11:8081, 192.168.1.12:8081]
           ↓
5. LoadBalancer selects instance (round-robin, random, etc.)
           ↓
6. Rewrites URL: http://192.168.1.10:8081/api/products/123
           ↓
7. Executes actual HTTP request
           ↓
8. Returns response
```

**`@LoadBalanced` WebClient:**

**Configuration:**
```java
@Configuration
public class WebClientConfig {
    
    @Bean
    @LoadBalanced
    public WebClient.Builder webClientBuilder() {
        return WebClient.builder();
    }
}
```

**Usage:**
```java
@Service
public class OrderService {
    
    private final WebClient webClient;
    
    public OrderService(@LoadBalanced WebClient.Builder builder) {
        this.webClient = builder.build();
    }
    
    public Mono<Product> getProduct(Long productId) {
        return webClient.get()
            .uri("http://product-service/api/products/{id}", productId)
            .retrieve()
            .bodyToMono(Product.class);
    }
    
    public Flux<Product> getAllProducts() {
        return webClient.get()
            .uri("http://product-service/api/products")
            .retrieve()
            .bodyToFlux(Product.class);
    }
}
```

**Internal Resolution Process:**

**Step 1: Service Discovery**
```java
// Spring Cloud LoadBalancer queries discovery client
DiscoveryClient discoveryClient;
List<ServiceInstance> instances = discoveryClient.getInstances("product-service");

// Returns instances:
[
  ServiceInstance{host="192.168.1.10", port=8081},
  ServiceInstance{host="192.168.1.11", port=8081},
  ServiceInstance{host="192.168.1.12", port=8081}
]
```

**Step 2: Load Balancing**
```java
// Default: Round-robin load balancer
ReactorLoadBalancer<ServiceInstance> loadBalancer;
Response<ServiceInstance> response = loadBalancer.choose();
ServiceInstance instance = response.getServer();

// Selected: 192.168.1.10:8081
```

**Step 3: URL Reconstruction**
```java
// Original: http://product-service/api/products/123
// Becomes:  http://192.168.1.10:8081/api/products/123
```

**Load Balancing Strategies:**

**1. Round-Robin (Default):**
```java
@Configuration
public class LoadBalancerConfig {
    
    @Bean
    public ReactorLoadBalancer<ServiceInstance> reactorServiceInstanceLoadBalancer(
            Environment environment,
            LoadBalancerClientFactory loadBalancerClientFactory) {
        
        String name = environment.getProperty(LoadBalancerClientFactory.PROPERTY_NAME);
        return new RoundRobinLoadBalancer(
            loadBalancerClientFactory.getLazyProvider(name, ServiceInstanceListSupplier.class),
            name
        );
    }
}
```

**2. Random:**
```java
@Configuration
public class RandomLoadBalancerConfig {
    
    @Bean
    public ReactorLoadBalancer<ServiceInstance> randomLoadBalancer(
            Environment environment,
            LoadBalancerClientFactory loadBalancerClientFactory) {
        
        String name = environment.getProperty(LoadBalancerClientFactory.PROPERTY_NAME);
        return new RandomLoadBalancer(
            loadBalancerClientFactory.getLazyProvider(name, ServiceInstanceListSupplier.class),
            name
        );
    }
}
```

**3. Weighted Response Time:**
```java
@Configuration
public class WeightedLoadBalancerConfig {
    
    @Bean
    public ReactorLoadBalancer<ServiceInstance> weightedLoadBalancer() {
        return new WeightedResponseTimeLoadBalancer();
    }
}
```

**Comparison: RestTemplate vs WebClient:**

| Aspect | RestTemplate | WebClient |
|--------|-------------|-----------|
| **Paradigm** | Synchronous/Blocking | Reactive/Non-blocking |
| **Return Type** | `Product` | `Mono<Product>`, `Flux<Product>` |
| **Performance** | One thread per request | Fewer threads, higher throughput |
| **Spring Version** | All | Spring 5+ |
| **Status** | Maintenance mode | Recommended |
| **Backpressure** | ❌ No | ✅ Yes |
| **Memory** | Higher (thread per request) | Lower (event loop) |

**Advanced Configuration:**

**Retry Logic:**
```java
@Bean
@LoadBalanced
public WebClient.Builder webClientBuilder() {
    return WebClient.builder()
        .filter((request, next) -> next.exchange(request)
            .retryWhen(Retry.backoff(3, Duration.ofSeconds(1))
                .filter(throwable -> throwable instanceof WebClientResponseException.ServiceUnavailable))
        );
}
```

**Timeout Configuration:**
```java
@Bean
@LoadBalanced
public RestTemplate restTemplate(RestTemplateBuilder builder) {
    return builder
        .setConnectTimeout(Duration.ofSeconds(5))
        .setReadTimeout(Duration.ofSeconds(10))
        .build();
}
```

**Circuit Breaker Integration:**
```java
@Service
public class ResilientOrderService {
    
    private final WebClient webClient;
    private final CircuitBreakerFactory circuitBreakerFactory;
    
    public Mono<Product> getProduct(Long productId) {
        CircuitBreaker circuitBreaker = circuitBreakerFactory.create("product-service");
        
        return webClient.get()
            .uri("http://product-service/api/products/{id}", productId)
            .retrieve()
            .bodyToMono(Product.class)
            .transform(it -> circuitBreaker.run(it, throwable -> 
                Mono.just(getFallbackProduct(productId))
            ));
    }
    
    private Product getFallbackProduct(Long productId) {
        return new Product(productId, "Fallback Product");
    }
}
```

**Health-Aware Load Balancing:**
```yaml
spring:
  cloud:
    loadbalancer:
      health-check:
        enabled: true
        interval: 5s
```

**Custom Load Balancer:**
```java
public class CustomLoadBalancer implements ReactorServiceInstanceLoadBalancer {
    
    private final ServiceInstanceListSupplier serviceInstanceListSupplier;
    
    @Override
    public Mono<Response<ServiceInstance>> choose(Request request) {
        return serviceInstanceListSupplier.get()
            .next()
            .map(instances -> {
                // Custom selection logic
                ServiceInstance instance = selectInstance(instances, request);
                return new DefaultResponse(instance);
            });
    }
    
    private ServiceInstance selectInstance(List<ServiceInstance> instances, Request request) {
        // Example: Select based on custom header
        String zone = request.getContext().get("zone");
        return instances.stream()
            .filter(i -> i.getMetadata().get("zone").equals(zone))
            .findFirst()
            .orElse(instances.get(0));
    }
}
```

**Monitoring & Debugging:**
```yaml
logging:
  level:
    org.springframework.cloud.client.loadbalancer: DEBUG
    org.springframework.web.reactive.function.client: DEBUG
```

**Best Practices:**
1. **Use WebClient** for new applications (reactive, better performance)
2. **Configure timeouts** to prevent hanging requests
3. **Add retry logic** for transient failures
4. **Implement circuit breakers** for fault tolerance
5. **Enable health checks** for load balancer awareness
6. **Monitor metrics** (request count, latency, errors)

---

## 8️⃣ Testing

### Q196: Difference between `@SpringBootTest` (full) and `@WebMvcTest` (slice).

**Simple Answer:**
`@SpringBootTest` loads the complete application context with all beans and configurations. `@WebMvcTest` loads only the web layer (controllers, filters, advice) and mocks everything else, making tests faster.

**Deep Dive:**

**`@SpringBootTest` - Full Integration Test:**

**Basic Usage:**
```java
@SpringBootTest
class FullApplicationTest {
    
    @Autowired
    private UserService userService;
    
    @Autowired
    private UserRepository userRepository;
    
    @Test
    void testCompleteFlow() {
        User user = new User("test@example.com", "password");
        User saved = userService.createUser(user);
        
        assertNotNull(saved.getId());
        assertTrue(userRepository.existsById(saved.getId()));
    }
}
```

**What Gets Loaded:**
- ✅ All `@Component`, `@Service`, `@Repository`, `@Controller` beans
- ✅ All `@Configuration` classes
- ✅ All auto-configurations
- ✅ Embedded database (if configured)
- ✅ Embedded web server (optional)
- ✅ Security filters
- ✅ JPA entities and repositories
- ✅ Message converters
- ✅ Validation
- ❌ External dependencies (unless configured)

**Web Environment Options:**
```java
// Option 1: MOCK (default) - MockMvc, no server
@SpringBootTest(webEnvironment = WebEnvironment.MOCK)
@AutoConfigureMockMvc
class MockWebTest {
    @Autowired
    private MockMvc mockMvc;
}

// Option 2: RANDOM_PORT - Real server on random port
@SpringBootTest(webEnvironment = WebEnvironment.RANDOM_PORT)
class RandomPortTest {
    @LocalServerPort
    private int port;
    
    @Autowired
    private TestRestTemplate restTemplate;
}

// Option 3: DEFINED_PORT - Real server on configured port
@SpringBootTest(webEnvironment = WebEnvironment.DEFINED_PORT)
class DefinedPortTest {
    // Uses server.port from application.properties
}

// Option 4: NONE - No web environment
@SpringBootTest(webEnvironment = WebEnvironment.NONE)
class NoWebTest {
    // For testing non-web components
}
```

**`@WebMvcTest` - Web Layer Slice Test:**

**Basic Usage:**
```java
@WebMvcTest(UserController.class)  // Only load UserController
class UserControllerTest {
    
    @Autowired
    private MockMvc mockMvc;
    
    @MockBean  // Mock the service layer
    private UserService userService;
    
    @Test
    void testGetUser() throws Exception {
        User user = new User(1L, "test@example.com");
        when(userService.findById(1L)).thenReturn(Optional.of(user));
        
        mockMvc.perform(get("/api/users/1"))
            .andExpect(status().isOk())
            .andExpect(jsonPath("$.email").value("test@example.com"));
    }
}
```

**What Gets Loaded:**
- ✅ `@Controller`, `@RestController`, `@ControllerAdvice`
- ✅ `@JsonComponent`
- ✅ Jackson converters
- ✅ Spring Security (if present)
- ✅ MockMvc
- ✅ Validation
- ❌ `@Service`, `@Repository`, `@Component` (must be mocked)
- ❌ Database
- ❌ JPA
- ❌ Embedded server

**Comparison Table:**

| Aspect | @SpringBootTest | @WebMvcTest |
|--------|----------------|-------------|
| **Context** | Full application | Web layer only |
| **Beans loaded** | All | Controllers + web infrastructure |
| **Test speed** | Slower (3-10s) | Faster (1-3s) |
| **Database** | Real (embedded) | Not loaded |
| **Services** | Real beans | Must mock |
| **Use case** | Integration tests | Controller unit tests |
| **MockMvc** | Optional (needs `@AutoConfigureMockMvc`) | Included |
| **Server** | Optional (real server) | Mock only |

**Other Test Slices:**

**1. `@DataJpaTest` - JPA Layer:**
```java
@DataJpaTest
class UserRepositoryTest {
    
    @Autowired
    private UserRepository userRepository;
    
    @Autowired
    private TestEntityManager entityManager;
    
    @Test
    void testFindByEmail() {
        User user = new User("test@example.com", "password");
        entityManager.persist(user);
        entityManager.flush();
        
        Optional<User> found = userRepository.findByEmail("test@example.com");
        
        assertTrue(found.isPresent());
        assertEquals(user.getEmail(), found.get().getEmail());
    }
}
```

**What Gets Loaded:**
- ✅ JPA repositories
- ✅ `TestEntityManager`
- ✅ Embedded database (H2 by default)
- ✅ JPA configuration
- ❌ Services, Controllers
- ❌ Full auto-configuration

**2. `@RestClientTest` - RestTemplate/WebClient:**
```java
@RestClientTest(ProductClient.class)
class ProductClientTest {
    
    @Autowired
    private ProductClient productClient;
    
    @Autowired
    private MockRestServiceServer server;
    
    @Test
    void testGetProduct() {
        server.expect(requestTo("/products/1"))
            .andRespond(withSuccess('{"id":1,"name":"Product"}', MediaType.APPLICATION_JSON));
        
        Product product = productClient.getProduct(1L);
        
        assertEquals("Product", product.getName());
    }
}
```

**3. `@JsonTest` - JSON Serialization:**
```java
@JsonTest
class UserJsonTest {
    
    @Autowired
    private JacksonTester<User> json;
    
    @Test
    void testSerialize() throws Exception {
        User user = new User(1L, "test@example.com");
        
        assertThat(json.write(user))
            .extractingJsonPathStringValue("$.email")
            .isEqualTo("test@example.com");
    }
    
    @Test
    void testDeserialize() throws Exception {
        String content = "{\"id\":1,\"email\":\"test@example.com\"}";
        
        assertThat(json.parse(content))
            .isEqualTo(new User(1L, "test@example.com"));
    }
}
```

**Complete Testing Strategy:**

**Unit Tests (Fast, Isolated):**
```java
class UserServiceUnitTest {
    
    private UserService userService;
    private UserRepository userRepository;
    
    @BeforeEach
    void setUp() {
        userRepository = mock(UserRepository.class);
        userService = new UserService(userRepository);
    }
    
    @Test
    void testCreateUser() {
        User user = new User("test@example.com", "password");
        when(userRepository.save(any())).thenReturn(user);
        
        User created = userService.createUser(user);
        
        assertNotNull(created);
        verify(userRepository).save(user);
    }
}
```

**Slice Tests (Fast, Focused):**
```java
@WebMvcTest(UserController.class)
class UserControllerSliceTest {
    @Autowired private MockMvc mockMvc;
    @MockBean private UserService userService;
    // Test controller layer only
}

@DataJpaTest
class UserRepositorySliceTest {
    @Autowired private UserRepository userRepository;
    // Test repository layer only
}
```

**Integration Tests (Slower, Comprehensive):**
```java
@SpringBootTest(webEnvironment = WebEnvironment.RANDOM_PORT)
class UserIntegrationTest {
    @Autowired private TestRestTemplate restTemplate;
    @Autowired private UserRepository userRepository;
    
    @Test
    void testEndToEnd() {
        // Test complete flow
    }
}
```

**Best Practices:**

**Test Pyramid:**
```
        /\
       /  \      Few Integration Tests (@SpringBootTest)
      /    \
     /      \
    /        \   More Slice Tests (@WebMvcTest, @DataJpaTest)
   /          \
  /            \
 /______________\ Many Unit Tests (plain JUnit)
```

**Example Test Suite:**
```java
// 1. Unit Test - Fast, No Spring
class UserServiceTest {
    // Pure unit tests with mocks
}

// 2. Slice Test - Fast, Partial Spring Context
@WebMvcTest(UserController.class)
class UserControllerTest {
    // Controller tests with MockMvc
}

@DataJpaTest
class UserRepositoryTest {
    // Repository tests with embedded DB
}

// 3. Integration Test - Slow, Full Context
@SpringBootTest
class UserIntegrationTest {
    // End-to-end tests
}
```

**Performance Optimization:**
```java
// Reuse context across tests
@SpringBootTest
@TestInstance(TestInstance.Lifecycle.PER_CLASS)
class FastIntegrationTest {
    // Context created once for all tests
}

// Exclude heavy auto-configurations
@SpringBootTest(
    properties = "spring.autoconfigure.exclude=" +
        "org.springframework.boot.autoconfigure.jdbc.DataSourceAutoConfiguration"
)
class LightweightTest {
    // Faster startup
}
```

**Common Mistakes:**

**❌ Bad - Using @SpringBootTest for everything:**
```java
@SpringBootTest  // Loads entire context unnecessarily
class UserControllerTest {
    @Autowired private UserController controller;
    // Just testing controller logic
}
```

**✅ Good - Use appropriate slice:**
```java
@WebMvcTest(UserController.class)  // Only loads web layer
class UserControllerTest {
    @Autowired private MockMvc mockMvc;
    @MockBean private UserService userService;
}
```

---

### Q199: Test a `@Transactional` service method without committing any data.

**Simple Answer:**
Annotate your test class or method with `@Transactional`, and Spring will automatically roll back the transaction after each test, leaving the database clean.

**Deep Dive:**

**Basic Approach:**

**Test with Auto-Rollback:**
```java
@SpringBootTest
@Transactional  // Automatically rolls back after each test
class UserServiceTest {
    
    @Autowired
    private UserService userService;
    
    @Autowired
    private UserRepository userRepository;
    
    @Test
    void testCreateUser() {
        // Arrange
        User user = new User("test@example.com", "password");
        
        // Act
        User created = userService.createUser(user);
        
        // Assert
        assertNotNull(created.getId());
        assertTrue(userRepository.existsById(created.getId()));
        
        // Database will be rolled back after this test
    }
    
    @Test
    void testFindUser() {
        // Database is clean - previous test was rolled back
        User user = new User("another@example.com", "password");
        userRepository.save(user);
        
        Optional<User> found = userService.findByEmail("another@example.com");
        
        assertTrue(found.isPresent());
        // Rolled back again
    }
}
```

**How It Works:**
```
Test starts
    ↓
@Transactional creates transaction
    ↓
Test method executes
    ↓
Database changes made
    ↓
Test method completes
    ↓
@Transactional rolls back transaction
    ↓
Database returns to original state
    ↓
Next test starts with clean database
```

**Controlling Rollback Behavior:**

**1. Force Commit (Override Default):**
```java
@SpringBootTest
@Transactional
class UserServiceTest {
    
    @Test
    @Commit  // Don't rollback this test
    void testDataThatShouldPersist() {
        User user = new User("persist@example.com", "password");
        userRepository.save(user);
        // Data WILL persist after test
    }
    
    @Test
    @Rollback  // Explicit rollback (default behavior)
    void testDataThatShouldRollback() {
        User user = new User("rollback@example.com", "password");
        userRepository.save(user);
        // Data will NOT persist
    }
}
```

**2. Conditional Rollback:**
```java
@SpringBootTest
@Transactional
class ConditionalRollbackTest {
    
    @Test
    @Rollback(value = false)  // Same as @Commit
    void testWithCommit() {
        // Data persists
    }
    
    @Test
    @Rollback(value = true)  // Explicit rollback
    void testWithRollback() {
        // Data rolled back
    }
}
```

**Testing Transactional Behavior:**

**Test Transaction Propagation:**
```java
@SpringBootTest
@Transactional
class TransactionPropagationTest {
    
    @Autowired
    private UserService userService;
    
    @Autowired
    private AuditService auditService;
    
    @Test
    void testRequiresNew() {
        User user = new User("test@example.com", "password");
        
        // This throws exception
        assertThrows(ValidationException.class, () -> {
            userService.createUserWithAudit(user);
        });
        
        // User creation rolled back
        assertFalse(userRepository.existsById(user.getId()));
        
        // But audit log was committed (REQUIRES_NEW)
        assertTrue(auditRepository.existsByAction("USER_CREATE_ATTEMPT"));
    }
}

@Service
class UserService {
    
    @Transactional
    public void createUserWithAudit(User user) {
        auditService.logAttempt("USER_CREATE_ATTEMPT");  // REQUIRES_NEW
        
        if (!isValid(user)) {
            throw new ValidationException();  // Rolls back user creation
        }
        
        userRepository.save(user);
    }
}

@Service
class AuditService {
    
    @Transactional(propagation = Propagation.REQUIRES_NEW)
    public void logAttempt(String action) {
        auditRepository.save(new AuditLog(action));
        // Commits independently
    }
}
```

**Advanced Testing Patterns:**

**1. Testing Rollback on Exception:**
```java
@SpringBootTest
@Transactional
class RollbackOnExceptionTest {
    
    @Test
    void testRollbackOnRuntimeException() {
        assertThrows(RuntimeException.class, () -> {
            userService.createUserThatFails();
        });
        
        // Verify nothing was saved
        assertEquals(0, userRepository.count());
    }
    
    @Test
    void testNoRollbackOnCheckedException() {
        assertThrows(Exception.class, () -> {
            userService.createUserWithCheckedException();
        });
        
        // Checked exceptions don't rollback by default
        assertEquals(1, userRepository.count());
    }
}

@Service
class UserService {
    
    @Transactional
    public void createUserThatFails() {
        userRepository.save(new User("test@example.com"));
        throw new RuntimeException("Rollback!");  // Triggers rollback
    }
    
    @Transactional
    public void createUserWithCheckedException() throws Exception {
        userRepository.save(new User("test@example.com"));
        throw new Exception("No rollback");  // NO rollback
    }
    
    @Transactional(rollbackFor = Exception.class)
    public void createUserWithRollbackOnChecked() throws Exception {
        userRepository.save(new User("test@example.com"));
        throw new Exception("Rollback!");  // NOW it rolls back
    }
}
```

**2. Programmatic Rollback:**
```java
@SpringBootTest
@Transactional
class ProgrammaticRollbackTest {
    
    @Autowired
    private TransactionTemplate transactionTemplate;
    
    @Test
    void testManualRollback() {
        User user = transactionTemplate.execute(status -> {
            User u = userRepository.save(new User("test@example.com"));
            
            if (someCondition()) {
                status.setRollbackOnly();  // Mark for rollback
            }
            
            return u;
        });
        
        // Verify rollback occurred
        assertNull(user);  // Transaction returned null due to rollback
    }
}
```

**3. Nested Transactions:**
```java
@SpringBootTest
@Transactional
class NestedTransactionTest {
    
    @Test
    void testNestedRollback() {
        User user1 = userRepository.save(new User("user1@example.com"));
        
        try {
            userService.createUserNested();  // NESTED propagation
        } catch (Exception e) {
            // Nested transaction rolled back
        }
        
        // Outer transaction still has user1
        assertEquals(1, userRepository.count());
        assertTrue(userRepository.existsById(user1.getId()));
    }
}
```

**Testing with Different Isolation Levels:**
```java
@SpringBootTest
class IsolationLevelTest {
    
    @Test
    @Transactional(isolation = Isolation.READ_UNCOMMITTED)
    void testReadUncommitted() {
        // Can read uncommitted data from other transactions
    }
    
    @Test
    @Transactional(isolation = Isolation.SERIALIZABLE)
    void testSerializable() {
        // Highest isolation, prevents phantom reads
    }
}
```

**Using TestEntityManager (JPA-specific):**
```java
@DataJpaTest
class UserRepositoryTest {
    
    @Autowired
    private TestEntityManager entityManager;
    
    @Autowired
    private UserRepository userRepository;
    
    @Test
    void testFindByEmail() {
        // Arrange
        User user = new User("test@example.com", "password");
        entityManager.persist(user);
        entityManager.flush();  // Force write to DB
        
        // Act
        Optional<User> found = userRepository.findByEmail("test@example.com");
        
        // Assert
        assertTrue(found.isPresent());
        assertEquals(user.getId(), found.get().getId());
        
        // Automatically rolled back
    }
    
    @Test
    void testFlushAndClear() {
        User user = new User("test@example.com", "password");
        entityManager.persist(user);
        entityManager.flush();  // Write to DB
        entityManager.clear();  // Clear persistence context
        
        // Now fetch from DB, not cache
        User fetched = entityManager.find(User.class, user.getId());
        assertNotSame(user, fetched);  // Different instances
    }
}
```

**Preventing Accidental Commits:**
```java
@SpringBootTest
@Transactional
@ActiveProfiles("test")
class SafeIntegrationTest {
    
    @BeforeEach
    void setUp() {
        // Verify we're in test mode
        assertTrue(TransactionSynchronizationManager.isActualTransactionActive());
        assertTrue(TransactionSynchronizationManager.isCurrentTransactionReadOnly() == false);
    }
    
    @AfterEach
    void tearDown() {
        // Verify transaction will rollback
        assertTrue(TransactionSynchronizationManager.isCurrentTransactionRollbackOnly());
    }
}
```

**Best Practices:**

1. **Always use `@Transactional` on test classes** that modify data
2. **Use `@DataJpaTest`** for repository tests (includes `@Transactional`)
3. **Explicitly `@Commit`** only when necessary (setup data)
4. **Test both success and failure** scenarios
5. **Verify rollback behavior** with assertions
6. **Use `TestEntityManager.flush()`** to force writes and catch constraint violations
7. **Clear persistence context** when testing cache behavior

**Common Pitfalls:**

**❌ Bad - No transaction, data persists:**
```java
@SpringBootTest  // Missing @Transactional
class LeakyTest {
    @Test
    void test1() {
        userRepository.save(new User("test@example.com"));
        // Data PERSISTS to next test!
    }
    
    @Test
    void test2() {
        assertEquals(1, userRepository.count());  // Fails intermittently
    }
}
```

**✅ Good - Transactional, clean between tests:**
```java
@SpringBootTest
@Transactional  // Each test isolated
class CleanTest {
    @Test
    void test1() {
        userRepository.save(new User("test@example.com"));
        // Rolled back
    }
    
    @Test
    void test2() {
        assertEquals(0, userRepository.count());  // Always passes
    }
}
```

---

## Summary

This comprehensive guide covers the most critical Spring Framework concepts with both simple explanations and deep technical details:

1. **Core Container**: Bean lifecycle, dependency injection, scoping, circular dependencies
2. **AOP**: Proxy mechanisms, self-invocation, advice ordering
3. **Transactions**: Propagation types, rollback rules, programmatic control
4. **Spring Boot**: Auto-configuration, properties binding, configuration classes
5. **Spring Data**: Query methods, EntityGraph, N+1 problem solutions
6. **Security**: JWT authentication, stateless sessions, filter chains
7. **Cloud**: Service discovery, load balancing, distributed patterns
8. **Testing**: Test slices, transactional tests, integration strategies

Each section provides:
- Clear, concise simple answers
- In-depth technical explanations
- Working code examples
- Best practices and anti-patterns
- Performance considerations
- Common pitfalls and solutions

Use this as a reference guide for interviews, troubleshooting, or deepening your Spring Framework knowledge.
