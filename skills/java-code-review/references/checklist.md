# Java Review Checklist

Failure modes by category, with the specific shapes they take in Java. Scan the categories relevant to the code in front of you. This is a lookup table, not a script — do not walk it linearly in the output.

## Contents
1. Correctness
2. Null and Optional
3. Resource management
4. Concurrency
5. Exceptions
6. Collections and equality
7. API and class design
8. Streams and functional style
9. Persistence and transactions
10. Security
11. Performance
12. Tests
13. Modernization opportunities

---

## 1. Correctness

- **Money in `double` or `float`.** Binary floating point cannot represent decimal fractions exactly; totals drift. Use `BigDecimal` with an explicit scale and rounding mode, or a long count of minor units. Blocking in financial code.
- **`BigDecimal.equals` vs `compareTo`.** `equals` compares scale, so `2.0` does not equal `2.00`. Almost always a bug in comparisons and a subtle one in `Set` membership.
- **Integer division truncation.** `(a / b) * c` where all are `int`. Also `int` overflow in accumulators — `Math.addExact` throws instead of wrapping.
- **`==` on boxed types or strings.** Reference comparison. Works by accident inside the Integer cache range (−128..127) and for interned literals, then fails in production with larger values.
- **Off-by-one in loops and `subList`/`substring` bounds.** Especially where an inclusive bound is documented but an exclusive one is implemented.
- **Date/time correctness.** Legacy `Date`/`Calendar` are mutable and error-prone; prefer `java.time`. Watch for `LocalDateTime` used where an instant in time is meant — it has no timezone, so it is the wrong type for anything crossing zones. Check DST assumptions and whether "day" arithmetic uses `Period` (calendar-aware) or `Duration` (fixed 24h).
- **Locale-dependent operations.** `toLowerCase()` and `String.format` without an explicit `Locale` behave differently under a Turkish locale (the dotless-i problem) and in number formatting. Use `Locale.ROOT` for machine-facing strings.
- **Character encoding.** `new String(bytes)` and `getBytes()` without a charset use the platform default, which differs between a developer laptop and a container. Always specify `StandardCharsets.UTF_8`.
- **Mutating a collection while iterating it.** `ConcurrentModificationException`, or silent skips with index-based loops. Use `Iterator.remove` or `removeIf`.

## 2. Null and Optional

- **`Optional` as a field or parameter.** It is not `Serializable` and adds a wrapper allocation with no benefit. Designed for return types where absence is a meaningful outcome.
- **`optional.get()` without `isPresent()`.** Just a `NullPointerException` with more steps. Prefer `orElseThrow`, `orElse`, `map`, or `ifPresent`.
- **Returning `null` from a method whose return type is `Optional`.** The one thing an `Optional` return must never do.
- **Returning `null` instead of an empty collection.** Forces null checks on every caller forever. Return `List.of()`.
- **Unclear nullability contracts.** If the codebase uses `@Nullable`/`@NonNull` annotations, new code should too — partial adoption defeats the tooling that consumes them.
- **Unboxing NPEs.** `Map<String, Integer> m; int x = m.get(key);` throws on a missing key. Common and easy to miss in review.

## 3. Resource management

- **Anything `Closeable` acquired without try-with-resources.** Streams, readers, connections, statements, result sets, sockets, channels, `FileSystem` handles. A `finally` block is acceptable if pre-existing, but new code should use try-with-resources. Leaks surface as descriptor exhaustion under load, not in testing.
- **`Files.lines`, `Files.walk`, `Files.list`.** These return streams backed by open file handles and must be closed. `Files.readAllLines` does not have this problem but loads everything into memory.
- **Connection pool leaks.** A connection or `EntityManager` obtained manually and returned only on the success path. Under a pool, this deadlocks the application once the pool drains — a slow, confusing outage.
- **Thread pools never shut down.** An `ExecutorService` created but never `shutdown()`, especially in a request path or a `@Bean` without `destroyMethod`. Non-daemon threads also prevent JVM exit.
- **`ThreadLocal` not removed.** On a pooled thread, the value survives into the next unrelated request. This is both a memory leak and a data-crossover bug — the second is worse.
- **Unbounded caches or collections.** A `Map` used as a cache with no eviction is a memory leak with a slow fuse.
- **`InputStream` consumed twice** or passed to a method that closes it and then reused.

## 4. Concurrency

- **Shared mutable state without a synchronization story.** For each mutable field reachable from more than one thread, there should be an identifiable mechanism: confinement, immutability, `volatile`, a lock, or a concurrent collection. "It has not broken yet" is not a mechanism.
- **Non-atomic compound actions.** `if (!map.containsKey(k)) map.put(k, v)` is a race even on a `ConcurrentHashMap`. Use `putIfAbsent` or `computeIfAbsent`. Same for check-then-act on any shared state.
- **`volatile` mistaken for atomicity.** It gives visibility, not compound-action safety. `count++` on a volatile field still loses updates. Use `AtomicInteger` or a lock.
- **Non-thread-safe objects shared as fields or singletons.** `SimpleDateFormat` is the classic — it is mutable and shared instances corrupt each other's output. Also `Random` (prefer `ThreadLocalRandom`), non-thread-safe `Matcher`, and most parsers. In Spring, remember every `@Component`, `@Service`, and `@Controller` is a singleton by default.
- **Synchronizing on a mutable, interned, or public field.** Locking on a `String` literal or a boxed `Integer` means locking on an object other code may also lock. Use a private final lock object.
- **Lock ordering.** Two locks acquired in different orders in different methods will eventually deadlock. Also: calling out to unknown code (a listener, a callback, an overridable method) while holding a lock.
- **Blocking inside async or reactive code.** `.block()`, `.join()`, or synchronous I/O inside a `Mono`/`Flux` chain or on an event loop thread stalls the whole loop. On virtual threads (Java 21+), `synchronized` blocks pin the carrier thread — prefer `ReentrantLock`.
- **`CompletableFuture` exceptions dropped.** A chain without `exceptionally` or `handle` swallows failures silently. Also check which executor async stages run on; the default `ForkJoinPool.commonPool()` is a poor place for blocking work.
- **Double-checked locking without `volatile`.** Broken. The field must be `volatile`, or use a holder class or enum singleton instead.

## 5. Exceptions

- **Empty catch blocks.** Always a finding. If ignoring is genuinely correct, it needs a comment saying why.
- **Catching `Exception`, `Throwable`, or `RuntimeException` broadly.** Hides `NullPointerException` and `IllegalStateException` alongside the one exception the author meant to handle. Catching `Throwable` additionally swallows `OutOfMemoryError` and `StackOverflowError`, which should never be handled.
- **Losing the cause.** `throw new ServiceException("failed")` inside a catch, discarding the caught exception, destroys the stack trace and makes the incident unresolvable. Pass the cause.
- **Logging and rethrowing.** Produces duplicate stack traces in logs. Do one or the other.
- **Exceptions for control flow.** Especially in loops — exception construction fills in the stack trace and is far more expensive than a conditional.
- **Swallowing `InterruptedException`.** Either propagate it or restore the flag with `Thread.currentThread().interrupt()`. Dropping it breaks cancellation and can hang shutdown.
- **`e.printStackTrace()` or `System.out` in production code.** Bypasses the logging infrastructure entirely.
- **Exception messages without context.** "Invalid input" versus "Invalid orderId: expected UUID, got 'abc123'". The second one ends the debugging session immediately.
- **Checked exceptions leaking implementation details** through an abstraction boundary (`SQLException` from a repository interface).

## 6. Collections and equality

- **`equals` without `hashCode`, or either inconsistent.** An object that violates the contract silently misbehaves in every `HashMap` and `HashSet` — lookups fail with the value visibly present.
- **Mutable objects as map keys or set elements.** Mutating a field used in `hashCode` after insertion makes the entry unreachable.
- **JPA entities with `equals`/`hashCode` based on a generated ID.** The ID is null before persist, so the object's hash changes when it is saved, corrupting any collection it was added to beforehand. Use a business key or the entity's identity.
- **`Arrays.asList` treated as mutable.** Fixed-size; `add` throws. Similarly `List.of` is fully immutable and rejects nulls.
- **Returning internal mutable collections directly from a getter.** Callers can mutate your state. Return a copy or an unmodifiable view.
- **Wrong collection for the access pattern.** Linear `contains` on a `List` inside a loop is quadratic; a `Set` makes it linear. `LinkedList` is almost never the right answer.
- **Relying on `HashMap` iteration order.** Unspecified and it changes across versions. Use `LinkedHashMap` or `TreeMap` if order matters.
- **Comparator contract violations.** A `compare` that is not transitive or not consistent with `equals` throws "Comparison method violates its general contract!" — non-deterministically, under load, only sometimes.

## 7. API and class design

- **Constructors with many parameters of the same type.** `new Order(customerId, addressId, productId)` — three strings in any order compiles fine. Use a builder or distinct types.
- **Leaking `this` from a constructor.** Registering a listener or starting a thread before construction completes exposes a partially initialized object.
- **Calling an overridable method from a constructor.** The subclass override runs before the subclass fields are initialized.
- **Mutable public static fields.** Global shared state with no synchronization.
- **Missing `final` on fields that never change.** Not just style — it is the cheapest thread-safety guarantee available and documents intent.
- **Deep inheritance where composition fits.** Especially inheritance used for code reuse rather than substitutability.
- **Interfaces with a single implementation created reflexively.** Adds indirection with no seam. Worth a Consider, not more.
- **God classes and long methods.** Judge by responsibility count, not line count. A 400-line method with one responsibility beats four 100-line methods that all know about each other.
- **Static utility methods holding hidden dependencies.** Untestable without a rewrite.

## 8. Streams and functional style

- **Side effects inside `map` or `filter`.** Mutating external state mid-pipeline; correctness depends on evaluation order and breaks under parallelism. `forEach` is the place for effects.
- **`parallelStream()` without justification.** Uses the shared common pool, so one slow parallel stream degrades unrelated work across the JVM. Rarely wins below tens of thousands of elements, and never for I/O-bound work.
- **Streams that are harder to read than the loop.** Three nested `flatMap`s with a ternary inside are a readability regression. Not every loop needs converting.
- **Reusing a consumed stream.** Throws `IllegalStateException`.
- **`Collectors.toMap` with duplicate keys.** Throws at runtime; supply a merge function or make the uniqueness assumption explicit.
- **`peek` used for logic.** It is a debugging hook and may be skipped entirely when the pipeline is optimized.
- **Infinite streams without a limit,** or unclosed streams over I/O sources (see Resources).

## 9. Persistence and transactions

- **N+1 queries.** Iterating entities and touching a lazy association issues one query per row. Look for a loop over query results that dereferences a `@OneToMany` or `@ManyToOne`. Fix with a fetch join, an entity graph, or batch fetching.
- **`@Transactional` on a private, protected, or self-invoked method.** Spring's proxy-based AOP means the annotation does nothing — no transaction, silently. One of the most common Spring bugs in existence.
- **`@Transactional` around remote calls.** Holds a database connection open for the duration of an HTTP call; a slow dependency drains the pool.
- **Missing `readOnly = true` on read paths.** Loses a meaningful optimization and lets accidental writes through.
- **`LazyInitializationException` risk.** A lazy association touched after the session closes — typically during JSON serialization in the controller. Symptom of entities escaping the transactional boundary.
- **Entities used as request or response bodies.** Couples the wire contract to the schema, risks mass-assignment on the input side, and triggers lazy loading on the output side. Map to DTOs.
- **`@Data` from Lombok on a JPA entity.** Generates `equals`/`hashCode` over all fields including lazy associations, and `toString` that triggers loading them. A known footgun.
- **Cascade settings, especially `CascadeType.REMOVE` and `orphanRemoval`.** Verify the deletion semantics are intended; accidental cascading deletes are unrecoverable.
- **String-concatenated JPQL or SQL.** See Security.
- **Missing indexes implied by new query patterns,** and migrations that lock large tables without a stated plan.

## 10. Security

- **SQL and JPQL injection.** Any query built by concatenating input. Parameterized queries or named parameters only. `@Query` with string concatenation counts.
- **Command injection.** `Runtime.exec` or `ProcessBuilder` with user-influenced arguments, especially via a shell.
- **Path traversal.** User input in a file path without canonicalizing and verifying it stays under the intended root. `../` is still effective in 2026.
- **Unsafe deserialization.** Java native deserialization of untrusted data is remote code execution. Also check Jackson polymorphic typing (`enableDefaultTyping`, unrestricted `@JsonTypeInfo`) and unsafe SnakeYAML constructors.
- **XXE in XML parsing.** `DocumentBuilderFactory`, `SAXParserFactory`, and `XMLInputFactory` need external entity processing explicitly disabled; the defaults are unsafe in older versions.
- **Secrets in source or logs.** Hardcoded credentials, tokens, keys. Also full request or entity dumps in log statements — these leak PII and tokens into log aggregation, which usually has weaker access controls than the database.
- **Missing authorization checks.** Authentication is not authorization. New endpoints need an explicit answer to "who can call this?" Object-level checks matter too: verifying the caller is logged in but not that the record belongs to them.
- **`Random` for anything security-relevant.** Tokens, session IDs, password resets, nonces. Use `SecureRandom`.
- **Non-constant-time comparison of secrets.** `String.equals` on tokens or HMACs is timing-attack-prone; use `MessageDigest.isEqual`.
- **Weak or misused cryptography.** MD5 or SHA-1 for security purposes, ECB mode, a static or reused IV, or a hand-rolled construction. Password hashing needs bcrypt, scrypt, or Argon2 — not a general-purpose digest.
- **Disabled TLS verification.** A trust-all `TrustManager` or hostname verifier, common as a leftover from local debugging.
- **SSRF.** User-supplied URLs fetched server-side without an allowlist.

## 11. Performance

Only flag with a plausible path to real impact — a hot path, an unbounded input, or a superlinear complexity class. Speculative micro-optimization is noise.

- **Repeated work in a loop** that could be hoisted: recompiled `Pattern`, re-created `ObjectMapper`, repeated map lookups, a query inside the loop body.
- **String concatenation in a loop.** Quadratic allocation. `StringBuilder`, or `String.join`.
- **Unbounded result sets.** A `findAll()` on a table that grows, or a query with no pagination. Fine at 100 rows, an outage at 10 million.
- **Loading entire files into memory** where streaming would do.
- **Missing pagination on a new list endpoint.**
- **Logging expensive expressions unguarded.** With SLF4J parameterized logging this is mostly solved, but string concatenation or `toString()` on a large object inside a `log.debug(...)` call still evaluates unconditionally.

## 12. Tests

- **New branching logic with no test covering the new branch.**
- **Tests asserting nothing,** or only that no exception was thrown, or only on mock interactions rather than outcomes.
- **Over-mocking.** Mocking the class under test, or mocking value objects. Tests that mirror the implementation break on every refactor and prove nothing.
- **Missing edge cases:** null, empty, boundary values, unicode, negative numbers, concurrent access where relevant.
- **Order-dependent or time-dependent tests.** Shared mutable static state between tests; `LocalDateTime.now()` without an injectable `Clock`. These produce flakes that erode trust in the whole suite.
- **`Thread.sleep` in tests.** Slow and flaky; use awaitility or a deterministic latch.
- **Unclear test names.** `test1` versus `shouldRejectOrderWhenInventoryInsufficient`. The name should state the contract, since it is what appears in the failure output.
- **Tests that never fail.** If deleting the implementation would leave the test green, it is not testing anything.

## 13. Modernization opportunities

Suggest only when the project's language level supports it and the codebase is not consistently doing otherwise. These are Consider-level unless they fix an actual bug.

- **Java 8+**: `java.time` over `Date`/`Calendar`; try-with-resources; `StandardCharsets`.
- **Java 9+**: `List.of`/`Map.of` for immutable literals; `Optional.stream`; private interface methods.
- **Java 10+**: `var` for obvious local types — helps when it removes redundancy, hurts when it hides the type.
- **Java 11+**: `String.isBlank`, `strip`, `lines`, `repeat`; `Files.readString`/`writeString`; the standard `HttpClient` over `HttpURLConnection`.
- **Java 14+**: records for data carriers — free `equals`, `hashCode`, `toString`, and immutability; switch expressions with arrow syntax, which are exhaustive and cannot fall through.
- **Java 15+**: text blocks for embedded SQL, JSON, and XML.
- **Java 17+**: sealed interfaces for closed hierarchies; pattern matching for `instanceof`.
- **Java 21+**: pattern matching for switch with exhaustiveness checking; record patterns; virtual threads for I/O-bound concurrency (with the `synchronized`-pinning caveat noted above); sequenced collections.
