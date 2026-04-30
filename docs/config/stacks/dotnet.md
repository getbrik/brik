# .NET

Brik detects a .NET project from `*.csproj` or `*.sln`. The runner
image is the official Microsoft .NET SDK image. Supported runner image
tags: `9.0`, `10.0`.

## Minimum brik.yml

```yaml
version: 1
project:
  name: my-lib
  stack: dotnet
```

With nothing else, Brik:

- runs `dotnet build`;
- runs `dotnet test`;
- runs `dotnet-format` for both lint and format sub-stages;
- emits a `cobertura` coverage report when `test.reports.enabled: true`.

## Typical brik.yml

```yaml
version: 1
project:
  name: my-lib
  stack: dotnet
  stack_version: "9.0"
build:
  command: dotnet build --configuration Release
test:
  framework: dotnet
  coverage:
    threshold: 80
  reports:
    enabled: true
publish:
  nuget:
    token_var: NUGET_TOKEN
```

## Stack defaults

| Concern | Default |
|---------|---------|
| Build | `dotnet build` |
| Test | `dotnet test` |
| Lint | `dotnet-format` |
| Format | `dotnet-format` |
| Coverage format (`auto`) | `cobertura` |

## Gotchas

- **Solution vs project.** When both `*.sln` and `*.csproj` exist at
  the workspace root, `dotnet build` resolves to the solution. Use
  `build.command` to scope the build to a specific project.
- **`dotnet-format` covers lint AND format.** Brik wires the same tool
  into both sub-stages. Use `quality.lint.tool` / `quality.format.tool`
  if you want to swap one for an alternative analyzer.
- **Supported frameworks: `dotnet`, `xunit`, `nunit`.** All three
  emit the same `dotnet test` invocation -- the runner is auto-detected
  from the `<PackageReference>` declared by the test project, so the
  three values are aliases for the same command.
- **`stack_version`** must be a string with the explicit minor
  (`"9.0"`, not `9.0` or `"9"`).

## See also

- [`reference/build.md`](../reference/build.md)
- [`reference/test.md`](../reference/test.md)
- [`reference/quality.md`](../reference/quality.md)
- [`reference/publish.md`](../reference/publish.md)
