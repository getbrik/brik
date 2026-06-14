# mono-dotnet

`dotnet 9.0` · **CI** · starter

> [!NOTE]
> A .NET service built in Release configuration with formatting enforced.

## When to use this
A .NET project where you pin the build command and enforce dotnet-format from
your `.editorconfig`.

## What it configures
- **build** `command: dotnet build --configuration Release`.
- **test** `framework: xunit`.
- **quality** lint and format both via `dotnet-format` (config from
  `.editorconfig`).

## Try it
```bash
brik validate --config examples/mono-dotnet/brik.yml
```

## Reference
- [`build`](../../docs/reference/configuration/build.md) - command and tool overrides
- [`quality`](../../docs/reference/configuration/quality.md) - lint and format
