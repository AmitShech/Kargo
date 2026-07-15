# Warehouse Knowledge

This file tracks chart knowledge related to Kargo `Warehouse`, release sources, component image subscriptions, and source validation.

## Warehouse Resource

Template:

```text
generic-kargo-pipeline/templates/warehouse.yaml
```

The Warehouse renders:

- one deployment Git subscription when `sources.deploymentGit.subscription.enabled` is true
- one image subscription per enabled component

Current default Warehouse values:

```yaml
warehouse:
  name: app-images
  interval: 10m
  freightCreationPolicy: Automatic
```

The rendered Warehouse name is normalized through:

```gotemplate
{{ include "generic-kargo-pipeline.normalizeName" .Values.warehouse.name }}
```

## Empty Warehouse

Empty Warehouse behavior is intentional. If deployment Git subscription is disabled and all components are disabled, rendering still succeeds and the Warehouse renders with no active subscriptions:

```yaml
subscriptions: []
```

`templates/NOTES.txt` displays:

```text
WARNING:
The Kargo Warehouse currently has no active subscriptions.
Enable at least one component or the deployment Git subscription before expecting Freight creation.
```

## Component Sources

Component source values live under:

```yaml
sources:
  componentDefaults: {}
  components: []
```

The default `values.yaml` contains one example component named `main`:

```yaml
sources:
  components:
    - name: main
      enabled: true
      image:
        artifactory: registry.example.com/team/my-app
        selectionStrategy: NewestBuild
        allowedTags: ""
        semverConstraint: ""
        strictSemvers: false
        discoveryLimit: 20
      git:
        repository:
          url: https://gitlab.example.com/team/my-app.git
          username: ""
          password: ""
      releaseConfiguration:
        generationEnabled: true
        devConfigurationPath: src/main/resources/values.yaml
        deploymentOverlayPath: values/overrides/main.yaml
        outputPath: values/releases/main.yaml
      valuesMapping:
        tagPath: image.tag
```

Disabled components do not render Warehouse image subscriptions or `prepare-release` promotion steps.

## Component Defaults

Image-selection defaults are built into `_helpers.tpl`, and `values.yaml` also writes the values under the example component so the component shape is easy to copy.

Built-in defaults:

```yaml
enabled: true
image:
  selectionStrategy: NewestBuild
  allowedTags: ""
  semverConstraint: ""
  strictSemvers: false
  discoveryLimit: 20
```

`sources.componentDefaults` is an optional override hook. Set only the shared defaults that should change:

```yaml
sources:
  componentDefaults:
    image:
      discoveryLimit: 50
```

Merge order:

```text
built-in component defaults
optional sources.componentDefaults
current component values
```

Component-specific values win.

Template pattern:

```gotemplate
{{- $builtInComponentDefaults := include "generic-kargo-pipeline.componentDefaults" . | fromYaml -}}
{{- $componentDefaults := mergeOverwrite (deepCopy $builtInComponentDefaults) (default dict .Values.sources.componentDefaults) -}}
{{- $component := mergeOverwrite (deepCopy $componentDefaults) . -}}
```

The developer Git configuration path is not a built-in default. Set `releaseConfiguration.devConfigurationPath` on each component whose `prepare-release` configuration generation is enabled.

## Image Selection

Supported image fields:

```yaml
image:
  artifactory: registry.example.com/team/my-app
  selectionStrategy: NewestBuild
  allowedTags: ""
  semverConstraint: ""
  strictSemvers: false
  discoveryLimit: 20
```

Supported selection strategies:

```text
NewestBuild
SemVer
Lexical
```

Rendering rules:

- `image.artifactory` renders as Warehouse `repoURL`.
- `allowedTags` renders as Warehouse `allowTags` when non-empty.
- `semverConstraint` renders when non-empty.
- `strictSemvers` renders as a boolean, including explicit `false`.
- Do not use `with` for `strictSemvers`; it would omit `false`.
- `discoveryLimit` must be an integer greater than or equal to 1.

`strictSemvers` has been verified against the installed Kargo CRD.

## Values Mapping

Every component has a `valuesMapping` block with a final literal YAML path:

```yaml
valuesMapping:
  tagPath: image.tag
```

Other valid examples:

```text
services.backend.api.image.tag
workloads.consumers.orders.imageTag
```

`valuesMapping.tagPath` is not a Helm template and must not contain nested expressions such as `{{ .Values.application.name }}`. The `prepare-release` Stage passes this literal path directly to a Kargo YAML update operation.

## Deployment Git Source

Deployment Git values live under:

```yaml
sources:
  deploymentGit:
    repository:
      url: https://gitlab.example.com/team/my-app-deployment.git
      username: ""
      password: ""
    branches:
      source: develop
      production: master
    subscription:
      enabled: true
      commitSelectionStrategy: NewestFromBranch
      discoveryLimit: 15
      includePaths:
        - values.yaml
        - values/**
      excludePaths:
        - kargo/**
        - release-metadata/**
    paths:
      valuesFiles:
        base: values.yaml
        environment: values/${{ vars.environment }}.yaml
```

The Warehouse Git subscription uses `sources.deploymentGit.branches.source`. The exact deployment commit selected into Freight becomes the immutable base for the generated release branch.

Only commits matching `includePaths` should count as configuration changes. Pipeline-generated paths should be excluded to avoid recursive Freight creation.

## Warehouse Validation

Helm helper validation rejects duplicate component names after Kubernetes-name normalization. Examples that collide:

```text
API_Service
api-service
```

Both normalize to:

```text
api-service
```

This validation runs for all configured components, including disabled components, because duplicate normalized names would create Secret name collisions, future Stage mapping ambiguity, and duplicate logical components.

## Kargo API Fields To Verify Later

Before installing into a real cluster, verify these fields against the installed Kargo version:

- `Warehouse.spec.interval`
- `Warehouse.spec.freightCreationPolicy`
- `Warehouse.spec.subscriptions[].git.repoURL`
- `Warehouse.spec.subscriptions[].git.branch`
- `Warehouse.spec.subscriptions[].git.commitSelectionStrategy`
- `Warehouse.spec.subscriptions[].git.discoveryLimit`
- `Warehouse.spec.subscriptions[].git.includePaths`
- `Warehouse.spec.subscriptions[].git.excludePaths`
- `Warehouse.spec.subscriptions[].image.repoURL`
- `Warehouse.spec.subscriptions[].image.imageSelectionStrategy`
- `Warehouse.spec.subscriptions[].image.allowTags`
- `Warehouse.spec.subscriptions[].image.semverConstraint`
- `Warehouse.spec.subscriptions[].image.discoveryLimit`

`Warehouse.spec.subscriptions[].image.strictSemvers` is intentionally not listed because it has been verified.
