# Java Codebase Recon Reference

Fingerprints and commands for mapping a JVM codebase. Read this during Phases 1–4 when the repo is Java, Kotlin, Groovy, or Scala on the JVM.

## Contents
- Build system identification
- Language version
- Framework fingerprints
- Project layout conventions
- Entry point discovery
- Persistence discovery
- Configuration and environments
- Signals worth flagging

## Build system identification

| File present | Build tool | Module graph lives in |
|---|---|---|
| `pom.xml` | Maven | `<modules>` in the parent POM |
| `build.gradle` / `build.gradle.kts` | Gradle | `settings.gradle{.kts}` → `include(...)` |
| `build.xml` | Ant | `<target>` definitions; often legacy |
| `BUILD` / `BUILD.bazel` | Bazel | `deps` in each target |
| `.mvn/wrapper/` or `gradlew` | Wrapper present | Use `./mvnw` / `./gradlew`, not system binaries |

Always prefer the wrapper if one exists — it pins the build tool version and is what CI uses.

**Maven module graph:**
```bash
grep -A50 '<modules>' pom.xml
find . -name pom.xml -not -path '*/target/*' | head -50
./mvnw -q dependency:tree -DoutputType=text 2>/dev/null | head -100
```

**Gradle module graph:**
```bash
cat settings.gradle settings.gradle.kts 2>/dev/null
./gradlew projects 2>/dev/null
./gradlew :app:dependencies --configuration runtimeClasspath 2>/dev/null | head -100
```

Gradle commands can be slow on a cold cache and may attempt downloads. If the environment is offline or the build is large, read the build files directly rather than invoking the tool.

## Language version

Check in this order — later sources override earlier ones:
- Maven: `maven.compiler.source` / `.target` / `.release` properties, or the `maven-compiler-plugin` config
- Gradle: `sourceCompatibility`, `targetCompatibility`, or `java { toolchain { languageVersion } }`
- `.sdkmanrc`, `.java-version`, or a `Dockerfile` base image
- CI config (`setup-java` action version, Docker image tag)

The version ceiling determines what the reader may write. Java 8 means no `var`, no records, no sealed types, no pattern matching. Java 17 unlocks records and sealed types. Java 21 unlocks virtual threads and pattern matching for switch. Note discrepancies between the declared target and the runtime image — they are common and cause real bugs.

## Framework fingerprints

Identify by dependency coordinates plus a corroborating file:

| Framework | Dependency signal | Corroborating signal |
|---|---|---|
| Spring Boot | `spring-boot-starter-*` | `@SpringBootApplication`, `application.yml` |
| Spring MVC | `spring-boot-starter-web` (Boot ≤3) or `spring-boot-starter-webmvc` (Boot 4+) | `@RestController`, `@RequestMapping` |
| Spring WebFlux | `spring-boot-starter-webflux` | `Mono`/`Flux` return types, `@RestController` |
| Jakarta EE / Java EE | `jakarta.*` or `javax.*` APIs | `beans.xml`, `web.xml`, `@Stateless` |
| Quarkus | `quarkus-*` | `application.properties`, `@Path` |
| Micronaut | `micronaut-*` | `@Controller`, AOT config |
| Dropwizard | `dropwizard-core` | `Application` subclass, YAML config |
| JAX-RS | `jakarta.ws.rs` / `jersey` / `resteasy` | `@Path`, `@GET` |
| Struts / older MVC | `struts2-core` | `struts.xml` — legacy, note prominently |

Note the `javax.*` → `jakarta.*` namespace migration. A codebase mixing both is mid-migration; that is a significant finding for the brief, since it constrains which library versions can be added.

## Project layout conventions

Standard Maven/Gradle layout:
```
src/main/java/       production sources
src/main/resources/  config, templates, static assets, migrations
src/test/java/       tests, mirroring the main package structure
src/it/java/         integration tests (sometimes; also src/integrationTest/)
target/ or build/    build output — always exclude from analysis
```

Determine whether packages are organized **by layer** (`com.co.controller`, `com.co.service`, `com.co.repository`) or **by feature** (`com.co.billing`, `com.co.shipping`). This single fact predicts most of what a newcomer needs to know about where new code goes. Mixed organization — usually a partial migration — is worth calling out explicitly.

Note the base package and whether it is consistent across modules. Inconsistency here often marks code that arrived by acquisition or copy-paste.

## Entry point discovery

```bash
# HTTP handlers
grep -rl "@RestController\|@Controller\|@Path" --include=*.java src/

# Route inventory with locations
grep -rn "@RequestMapping\|@GetMapping\|@PostMapping\|@PutMapping\|@DeleteMapping\|@PatchMapping" \
  --include=*.java src/ | head -60

# Async and event-driven consumers
grep -rn "@KafkaListener\|@RabbitListener\|@JmsListener\|@SqsListener\|@StreamListener" \
  --include=*.java src/

# Scheduled work
grep -rn "@Scheduled\|Quartz\|TimerTask\|ScheduledExecutorService" --include=*.java src/

# Process entry points
grep -rn "public static void main" --include=*.java src/

# Servlet-era configuration
find . -name web.xml -not -path '*/target/*'
```

Also check for gRPC (`.proto` files plus a `protobuf` build plugin), GraphQL (`.graphqls` schema files), and Spring Cloud Stream bindings in configuration.

## Persistence discovery

```bash
# JPA / Hibernate entities
grep -rl "@Entity\|@Table" --include=*.java src/ | head -40

# Spring Data repositories
grep -rn "extends JpaRepository\|extends CrudRepository\|extends MongoRepository" --include=*.java src/

# Raw SQL and JDBC
grep -rn "JdbcTemplate\|PreparedStatement\|createQuery\|@Query" --include=*.java src/ | head -40

# Migration tooling
find . \( -path '*db/migration*' -o -path '*db/changelog*' -o -name 'liquibase*' -o -name 'flyway*' \) \
  -not -path '*/target/*' | head -30

# MyBatis
find . -name '*Mapper.xml' -not -path '*/target/*' | head -20
```

Flyway migrations live in `src/main/resources/db/migration` as `V<n>__<name>.sql`. Liquibase uses a changelog master file in XML, YAML, or SQL. The presence of neither, combined with entities, may mean `hibernate.hbm2ddl.auto` is generating schema — check for that setting and flag it if it is anything other than `validate` or `none` outside of tests.

For the brief's entity/DTO boundary section, check whether `@Entity` classes appear as parameters or return types in `@RestController` methods. If they do, persistence types are leaking to the API surface — worth noting, since it couples the schema to the wire contract.

## Configuration and environments

```bash
find . \( -name 'application*.yml' -o -name 'application*.yaml' -o -name 'application*.properties' \) \
  -not -path '*/target/*'
```

Spring profile suffixes (`application-prod.yml`, `application-local.yml`) enumerate the deployment environments. Read them to learn what infrastructure the service expects. Note which values come from environment variables — `${VAR}` placeholders map the operational surface.

Check for externalized config: Spring Cloud Config, Consul, AWS Parameter Store, Vault. If config is external, the repo alone will not tell the reader how the service behaves in production, and the brief should say so.

Look for committed secrets while you are here. If you find any, report the file and line to the user directly and immediately — do not reproduce the value in the brief, and note that rotation, not just deletion, is required since git history retains it.

## Signals worth flagging

Things that materially change how a newcomer should approach the code:

- **Spring Boot major version** — determine it from the `spring-boot-starter-parent` version or the Gradle plugin version, because starter coordinates changed in Boot 4: `spring-boot-starter-web` became `spring-boot-starter-webmvc`, and testing moved from the single `spring-boot-starter-test` to per-slice starters like `spring-boot-starter-webmvc-test`. Do not conclude "no test dependencies" from the absence of `spring-boot-starter-test` on a Boot 4 project.
- **Mixed `javax.*` and `jakarta.*`** — incomplete migration; constrains dependency upgrades.
- **Lombok present** — generated getters, setters, constructors, and builders will not appear in source. Note it so the reader is not confused by "missing" methods. Check for `@Data` on entities, which is a known hazard with JPA.
- **Multiple competing utility or client wrappers** — signals abandoned consolidation efforts.
- **`hibernate.hbm2ddl.auto` set to `update` or `create` outside tests** — schema managed implicitly.
- **Reflection-heavy or classpath-scanning code** — static analysis and IDE navigation will mislead; call graphs are incomplete.
- **Shaded or relocated dependencies in the build** — usually resolving a version conflict; find out which.
- **`@SuppressWarnings` clusters or a `checkstyle-suppressions.xml`** — shows where the codebase knowingly diverges from its own standards.
- **Very large classes** (over ~1000 lines) — find them with a line-count sort and list the top offenders; they are usually the load-bearing ones.
- **Test source trees far smaller than main** — quantify the ratio rather than editorializing.
