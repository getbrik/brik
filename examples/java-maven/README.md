# java-maven

`java 21` · **CI** · starter

> [!NOTE]
> A Java / Maven service with an explicit build command and a quality stage.

## When to use this
A JVM project where you want to pin the build command and enforce style and
dependency checks, without configuring the whole pipeline.

## What it configures
- **build** `command: mvn package -DskipTests` overrides the stack default.
- **quality** Checkstyle lint (with a config file) and google-java-format in
  check mode.
- **security** a dependency-scan severity floor (`deps.severity: high`) and
  secret scanning with defaults (`secrets: {}`).

## Try it
```bash
brik validate --config examples/java-maven/brik.yml
```

## Reference
- [`build`](../../docs/reference/configuration/build.md) - command and tool overrides
- [`quality`](../../docs/reference/configuration/quality.md) - lint and format
- [`security`](../../docs/reference/configuration/security.md) - dependency and secret scans
