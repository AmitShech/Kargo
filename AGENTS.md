# Codex Project Knowledge

This repository contains a reusable Helm chart for a generic Kargo-based CD promotion pipeline. The chart is intended for deployment and promotion ownership only; application build and development stay outside this project.

Repository:

```text
https://github.com/AmitShech/Kargo.git
```

Chart path:

```text
generic-kargo-pipeline/
```

## Current Scope

The chart currently creates only:

- Kargo `Project`
- Kargo `ProjectConfig`
- Kargo `Warehouse`
- Kubernetes Git credential `Secret` resources


## Intended Flow

```text
Warehouse detects a release source
        |
        v
prepare-release
        |
        v
dev
  deploy through Argo CD
  run native Kargo verification using an OpenShift QA Job
        |
        v
integration
  deploy through Argo CD
  run native Kargo verification using integration tests, metrics, logs, and health checks
        |
        v
pre-production
  create ServiceNow change
  create GitLab merge request to master
        |
        v
production
  manual promotion only
  deploy through Argo CD
  run production smoke verification
```

There is no environment cleanup or undeploy step yet.

## Architecture Rules

- Use native Kargo `spec.verification` after Dev, Integration, and optionally Production promotions when Stages are added.
- Each deployment environment has one Kargo Stage and one Argo CD Application:
  - `dev` Stage -> dev Argo CD Application
  - `integration` Stage -> integration Argo CD Application
  - `production` Stage -> production Argo CD Application
- `prepare-release` and `pre-production` do not control Argo CD Applications.
- Everything before Production should be automatic.
- A user must manually promote prepared Freight to Production.
- The same immutable release candidate must move through all environments.
- The chart must stay generic. Application-specific settings belong in values, not hard-coded templates.
- Component image tag equals component developer Git tag. Do not add a configurable tag mapping strategy unless the user changes this decision.

## Current File Layout

```text
generic-kargo-pipeline/
|-- Chart.yaml
|-- README.md
|-- values.schema.json
|-- values.yaml
`-- templates/
    |-- NOTES.txt
    |-- _helpers.tpl
    |-- project-config.yaml
    |-- project.yaml
    |-- warehouse.yaml
    `-- secrets/
        |-- component-dev-git.yaml
        `-- deployment-git.yaml
```

## Naming Decisions

The Kargo Project name is set directly from the Helm release namespace:

```gotemplate
{{ .Release.Namespace }}
```
Explicit `metadata.namespace` fields were removed from templates. Namespaced resources should be installed into the Helm release namespace naturally.

Install only one chart instance in a Kargo project namespace. The chart intentionally uses stable project-scoped names for the Warehouse, ProjectConfig, and Git credential Secrets.

## Values Model

The chart uses these top-level sections:

```yaml
global:
  labels: {}
  annotations: {}

warehouse:
  name: app-images
  interval: 10m
  freightCreationPolicy: Automatic

sources:
  components: []
  deploymentGit: {}

pipeline:
  stages: {}
```


## Component Defaults

Image-selection defaults are built into `_helpers.tpl`, and the default `values.yaml` also writes those values under the example component so the component shape is easy to copy. `sources.componentDefaults` is an optional override hook; set only the shared defaults you want to change. Templates must use a deep copy before merge so the original values are not mutated. The developer Git configuration path is not a built-in default; set it on each component that needs it.

Pattern:

```gotemplate
{{- $builtInDefaults := include "generic-kargo-pipeline.componentDefaults" . | fromYaml -}}
{{- $defaults := mergeOverwrite (deepCopy $builtInDefaults) (default dict $.Values.sources.componentDefaults) -}}
{{- $component := mergeOverwrite $defaults . -}}
```

Default component values:

```yaml
sources:
  componentDefaults:
    image:
      discoveryLimit: 50
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
        configuration:
          path: src/main/resources/values.yaml
      valuesMapping:
        tagPath: image.tag
```

Component-specific values override defaults. Disabled components do not render Warehouse image subscriptions or component developer Git credential Secrets. Future Stage logic should also skip disabled components.

## Component Values Mapping

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

## Component Validation

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

## Deployment Git

`sources.deploymentGit` is the deployment/chart configuration repository managed by the promotion pipeline.

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

The Warehouse Git subscription uses `sources.deploymentGit.branches.source`. This is both the Warehouse-watched branch and the future release branch base.

Deployment Git remains subscribed because configuration-only releases can create Freight. Only paths matching `includePaths` should count as configuration changes. Pipeline-generated paths should be excluded to avoid recursive Freight creation.

## Warehouse Behavior

The Warehouse renders:

- one deployment Git subscription when `sources.deploymentGit.subscription.enabled` is true
- one image subscription per enabled component

The Warehouse name defaults to `app-images`.

Empty Warehouse behavior is intentional. If deployment Git subscription is disabled and all components are disabled, rendering still succeeds and the Warehouse renders with no active subscriptions. `templates/NOTES.txt` displays:

```text
WARNING:
The Kargo Warehouse currently has no active subscriptions.
Enable at least one component or the deployment Git subscription before expecting Freight creation.
```

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

`allowedTags` renders as Warehouse `allowTags` when non-empty. `semverConstraint` renders when non-empty. `strictSemvers` must render as a boolean, including explicit `false`; do not use `with` for this field. `strictSemvers` has been verified against the installed Kargo CRD.

## Pipeline Model

Promotion configuration is under `pipeline.stages`.

```yaml
pipeline:
  stages:
    prepareRelease:
      name: prepare-release
      autoPromotionEnabled: true
      releaseBranch: release/${{ imageFrom(vars.imageRepository).Tag }}
    dev:
      name: dev
      autoPromotionEnabled: true
      deployment: {}
      verification: {}
    integration:
      name: integration
      autoPromotionEnabled: true
      deployment: {}
      verification: {}
    preProduction:
      name: pre-production
      autoPromotionEnabled: true
    production:
      name: production
      autoPromotionEnabled: false
      deployment: {}
      verification: {}
```

Deployment settings exist only under `dev`, `integration`, and `production`. Verification settings exist only under deployment stages and are placeholders for future resources. `prepareRelease.releaseBranch` is a literal Kargo expression for future Stage logic. Helm must not evaluate it.

No ServiceNow or GitLab API calls are implemented yet.

## Secrets

Secret templates:

- `templates/secrets/deployment-git.yaml`
- `templates/secrets/component-dev-git.yaml`

Deployment Git credentials come from `sources.deploymentGit.repository` and render as:

```text
deploymentgit
```

Component developer Git credentials come from `sources.components[].git.repository`. Component Secret names include the normalized component name:

```text
main-devgit
api-devgit
worker-devgit
```

Reusable helpers must be preserved for future Stage templates:

- `generic-kargo-pipeline.deploymentGitSecretName`
- `generic-kargo-pipeline.componentDevGitSecretName`

A Secret renders only when both `username` and `password` are non-empty. Helm validation fails if exactly one field is provided. This validation applies to deployment Git and every configured component developer Git credential pair.

The chart assumes each component has a separate developer repository. Shared developer repositories may render one Secret per component if both components provide credentials.

## Schema Rules

`values.schema.json` should reject stale fields, including:

- top-level `application`
- `sources.deploymentGit.subscription.branch`
- old `chartGit` or `developersGit` fields
- templated `valuesMapping.tagPath` values containing `{` or `}`

The schema keeps labels and annotations extensible while chart-owned structures use `additionalProperties: false` where practical.

## Validation Workflow

Run:

```bash
helm lint ./generic-kargo-pipeline
helm template my-app-promotion ./generic-kargo-pipeline --namespace my-app-promotion
```

Also validate these scenarios before committing foundation changes:

- default values: one deployment Git subscription, one `main` image subscription, no Secrets, no Stages, no AnalysisTemplates
- multiple components: two image subscriptions, defaults applied, overrides win, literal tag paths preserved in values
- credentials enabled: `deploymentgit`, `api-devgit`, and `worker-devgit` render
- disabled component: no image subscription and no developer Git Secret for that component
- duplicate normalized names: rendering fails with a clear duplicate normalized name message
- incomplete credentials: rendering fails when exactly one of username/password is set
- empty Warehouse: rendering succeeds and NOTES warning appears for install/upgrade output
- schema: JSON parses, removed fields are rejected, defaults and overrides validate

Known benign Helm lint output:

```text
[INFO] Chart.yaml: icon is recommended
```

## Open Kargo API Fields To Verify Later

Before installing into a real cluster, verify these fields against the installed Kargo version:

- `ProjectConfig.spec.promotionPolicies[].stage`
- `ProjectConfig.spec.promotionPolicies[].autoPromotionEnabled`
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

## User Preferences Captured

- Keep the chart generic.
- Prefer values-driven configuration over hard-coded application settings.
- Use `sources.deploymentGit` for deployment/chart configuration Git.
- Use `sources.components` for component image and developer Git sources.
- Keep component defaults built into `_helpers.tpl`; allow optional `sources.componentDefaults` only for overrides.
- Component image tag equals component developer Git tag.
- Keep `valuesMapping.tagPath` literal.
- Allow an intentionally empty Warehouse.
- Do not add cleanup yet.
- Do not add Stages or verification templates until explicitly requested.
- Commit and push completed changes after validation when asked to implement.
