# Java

Brik detects a Java project from `pom.xml` (Maven) or `build.gradle` /
`build.gradle.kts` (Gradle). The runner image is based on Eclipse
Temurin and ships with Maven. Supported runner image tags: `21`, `25`.

## Minimum brik.yml

```yaml
version: 1
project:
  name: my-app
  stack: java
```

With nothing else, Brik:

- runs Maven in batch mode (`mvn -B package -DskipTests`) when
  `pom.xml` is present, or `./gradlew build -x test` when a Gradle
  wrapper is present;
- runs `mvn -B test` (or `./gradlew test`);
- runs `checkstyle` for the lint sub-stage;
- emits a `jacoco` coverage report when `test.reports.enabled: true`.

## Typical brik.yml

```yaml
version: 1
project:
  name: my-app
  stack: java
  stack_version: "21"
build:
  command: mvn -B clean verify
test:
  framework: junit
  coverage:
    threshold: 80
  reports:
    enabled: true
publish:
  maven:
    repository: https://nexus.example.com/repository/maven-releases/
    username_var: MAVEN_USERNAME
    password_var: MAVEN_PASSWORD
```

## Stack defaults

| Concern | Default |
|---------|---------|
| Build | `mvn -B package -DskipTests` or `./gradlew build -x test` |
| Test | `mvn -B test` or `./gradlew test` |
| Lint | `checkstyle` |
| Format | `google-java-format` (declared, not yet implemented) |
| Coverage format (`auto`) | `jacoco` |

## Gotchas

- **Format step is a no-op today.** `google-java-format` is the
  declared default but the runtime currently logs a warning and skips
  it. Set `quality.format.command` explicitly if format checking is
  required.
- **Gradle wrapper is preferred.** When both `gradlew` and a system
  `gradle` exist, Brik prefers the wrapper. Ensure the wrapper is
  committed and executable; otherwise the stage falls back to the
  system `gradle` binary if available.
- **Maven runs in batch mode (`-B`).** Logs are verbose and not
  coloured; that is intentional for CI parsing.
- **`stack_version`** must be a string (`"21"`, not `21`).

## See also

- [`reference/build.md`](../reference/build.md)
- [`reference/test.md`](../reference/test.md)
- [`reference/quality.md`](../reference/quality.md)
- [`reference/publish.md`](../reference/publish.md)
