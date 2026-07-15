# Prepare Release Stage Knowledge

The chart creates one Kargo `Stage` for `pipeline.stages.prepareRelease`. It requests Freight directly from the configured Warehouse and does not control an Argo CD Application.

## Immutable Inputs

The deployment repository is checked out at `commitFrom(deploymentRepo).ID` into a source worktree. The release branch is checked out separately with `create: true`, so Kargo creates it when it does not exist. Its worktree is cleared and repopulated by copying the complete deployment source tree before any component changes are applied.

Each enabled component uses the image selected into Freight. When configuration generation is enabled, the component developer repository is checked out at a Git tag equal to that image tag.

The promotion fails if a required Freight artifact, developer Git tag, base file, overlay file, or target file is missing. It must never commit a partial release candidate.

## Per-component Configuration

Every enabled component has a unique `releaseConfiguration.outputPath` in deployment Git.

When `generationEnabled` is true:

1. `releaseConfiguration.devConfigurationPath` supplies the base YAML from developer Git.
2. `releaseConfiguration.deploymentOverlayPath` supplies the overriding YAML from deployment Git.
3. `yaml-merge` writes the result to `releaseConfiguration.outputPath`.
4. `yaml-update` writes the Freight image tag to the literal `valuesMapping.tagPath`.

When generation is false, the first three operations are skipped and `yaml-update` changes the existing output file.

All paths are relative to their respective Git worktrees and may use `name` as the normalized component-name placeholder. Parent traversal and duplicate resolved output paths are rejected during Helm rendering.

## Commit And Branch

All enabled component updates are committed once. The commit message includes the Freight name, the deployment commit, and every `component=image-tag` pair.

The default branch expression remains literal through Helm rendering:

```text
release/${{ ctx.targetFreight.name }}
```

The Stage pushes without force. A divergent existing branch fails instead of replacing an immutable candidate.
