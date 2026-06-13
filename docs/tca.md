# Using with TCA

[The Composable Architecture](https://github.com/pointfreeco/swift-composable-architecture) organises Swift apps into feature modules — each module owns its `@Reducer`, `View`, and `@DependencyClient`. The key architectural rule: **features are peers and must not import each other**. Only the root `AppFeature` composer imports child features.

SolidLikeARock enforces this with the `isolatePeers: true` layer flag. New here? Start with the [README](../README.md).

## Three steps to adopt

**1. Generate a TCA-aware config:**

```bash
solid-like-a-rock init --tca .
```

`init --tca` scans your project, groups modules into `Models / Dependencies / Features / App` layers by naming convention and `@Reducer` / `@DependencyClient` content, and generates a `.solid.yml` with `isolatePeers: true` on the right layers. Re-run with `--force` when you add feature modules.

**2. Review and adjust** the generated config (rename layers, fix any unclassified modules).

**3. Run the linter:**

```bash
solid-like-a-rock --config .solid.yml Sources
```

A peer violation looks like this:

```
Sources/LoginFeature/LoginFeature.swift:3: error: SolidLikeARock: layer 'Features' has isolatePeers enabled — must not import peer module 'CounterFeature'
```

A ready-to-use config template is at [`examples/tca.solid.yml`](../examples/tca.solid.yml).

<p align="center">
  <img src="../demo/tca.gif" alt="Demo: a TCA feature imports a sibling feature, isolatePeers catches it, the import is removed, and the lint goes green" width="720">
</p>
