# Prepare Release Stage Design

## Purpose

`prepare-release` turns one standalone Warehouse Freight into one immutable deployment candidate. It does not deploy an Argo CD Application.

The Stage must derive every result from artifacts contained in the target Freight. It must not inspect another Freight, Stage history, or the currently deployed environment.

## Inputs

The Freight contains:

- the selected `sources.chartGit` commit
- one selected image tag and digest per enabled component
- the matching developer Git tag for each component; the developer Git tag equals the image tag

The chart Git commit is the comparison baseline. For each enabled component, the Stage reads the existing tag at:

```text
releaseConfiguration.outputPath + valuesMapping.tagPath
```

It compares that value with the component tag in the same Freight. This comparison happens before `yaml-merge` or `yaml-update` changes the file.

```text
changed component = chart Git input tag != selected Freight tag
```

A missing output file or tag path is an error. The Stage must not silently classify an incomplete component as changed.

## Release Generation

The Stage checks out the Freight's exact chart Git commit and creates the configured release branch, normally:

```text
release/${{ ctx.targetFreight.name }}
```

The expression remains literal through Helm rendering.

For every enabled component, the Stage checks out developer Git at the tag equal to the selected image tag. This resolves and preserves the developer Git commit even when configuration generation is disabled.

When `generationEnabled` is true for a component:

1. Read `releaseConfiguration.devConfigurationPath` from the checked-out developer Git tree.
2. Read `releaseConfiguration.chartOverlayPath` from chart Git.
3. Merge both files into `releaseConfiguration.outputPath`.
4. Write the selected tag at the literal `valuesMapping.tagPath`.

When generation is false, the Stage updates the existing output file without generating it.

All enabled component changes are committed once. The Stage pushes without force and records at least:

- Freight name
- chart Git input commit
- immutable release commit
- release branch
- component tags and digests
- the changed-component list with previous and selected tags

The release commit is stored in Freight metadata for downstream Argo CD deployments.

## Tag Policy

`prepare-release` supports the common Stage `tagPolicy` interface. Its usual policy permits both development and official tags while rejecting configured disallowed patterns such as snapshots.

Denied patterns win over allowed patterns. Every enabled component must pass when `requireAllComponents` is true.

## Failure And Retry

The promotion fails before commit or push if any required artifact, tag, path, merge input, or credential is invalid. A retry must reuse the same Freight inputs. A divergent existing release branch fails instead of being force-replaced.

Success and failure emails are sent only when enabled under the corresponding `outcomes` entry. Notification delivery failure is recorded and retried but does not change an already determined promotion result.

## Values Contract

Relevant values:

```yaml
sources:
  chartGit:
    repository: {}
    branches:
      source: develop
      production: main
    subscription: {}

  components:
    - name: payment
      image: {}
      developerGit:
        repository: {}
      releaseConfiguration:
        generationEnabled: true
        devConfigurationPath: src/main/resources/dev-configuration.yaml
        chartOverlayPath: configurations/components/payment/kargo/config.yaml
        outputPath: configurations/components/payment/base/config.yaml
      valuesMapping:
        tagPath: image.tag

pipeline:
  stages:
    prepareRelease:
      name: prepare-release
      autoPromotionEnabled: true
      releaseBranch: release/${{ ctx.targetFreight.name }}
      tagPolicy: {}
      outcomes: {}
```

`sources.chartGit.branches.production` is required and has no built-in branch-name default.

## Implementation Checklist

The chart-side items below are implemented and retained as maintenance checks.

- Rename the current deployment/configuration Git values and helpers to `chartGit` consistently.
- Add pre-update YAML reads for every component's current chart tag.
- Build and validate changed-component metadata solely from target Freight inputs.
- Rename `deploymentOverlayPath` to `chartOverlayPath` in values, schema, helpers, templates, and documentation.
- Preserve literal Kargo expressions and literal `valuesMapping.tagPath` values.
- Add Stage-level tag-policy validation.
- Make commit and metadata content deterministic and complete.
- Add conditional outcome notification steps for self-managed Kargo.
- Add unit/render cases for unchanged tags, changed tags, missing tag paths, multiple components, and configuration-only Freight.
- Run Helm lint and template validation.

## Acceptance Criteria

- Re-rendering from the same Freight inputs produces the same candidate content.
- No downstream Stage needs another Freight to understand the candidate.
- Only selected tag differences appear in `changedComponents`.
- Missing or partial inputs fail before any partial release is pushed.
- Downstream Stages receive the exact immutable release commit.
