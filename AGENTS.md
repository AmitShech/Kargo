# Project Knowledge

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

The chart currently creates:

- Kargo `Project`
- Kargo `ProjectConfig`
- Kargo `Warehouse`
- Kargo `prepare-release` `Stage`
- Kubernetes Git credential `Secret` resources

Do not add these until explicitly requested:

- Kargo `Stage` resources other than `prepare-release`
- Kargo verification resources or `AnalysisTemplate` resources
- native Kargo `spec.verification`
- Argo CD deployment promotion steps
- ServiceNow API integration
- GitLab merge request API integration
- cleanup or undeploy logic

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
- Verification must not be implemented as a promotion step.
- Each deployment environment has one Kargo Stage and one Argo CD Application:
  - `dev` Stage -> dev Argo CD Application
  - `integration` Stage -> integration Argo CD Application
  - `production` Stage -> production Argo CD Application
- `prepare-release` and `pre-production` do not control Argo CD Applications.
- Everything before Production should be automatic.
- Production auto-promotion must default to disabled.
- A user must manually promote prepared Freight to Production.
- The same immutable release candidate must move through all environments.
- Preserve image tag, image digest, release branch, release commit, and Helm/configuration revision.
- Environment-specific values may change, but the application artifact must not be rebuilt or replaced between environments.
- The chart must stay generic. Application-specific settings belong in values, not hard-coded templates.
- Component image tag equals component developer Git tag.
- Keep `valuesMapping.tagPath` literal.

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
    |-- secrets/
    |   |-- component-dev-git.yaml
    |   `-- deployment-git.yaml
    `-- stages/
        `-- prepare-release.yaml
```

Project knowledge files:

```text
AGENTS.md
project/
|-- prepare-release.md
|-- project.md
`-- warehouse.md
```

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
  componentDefaults: {}
  components: []
  deploymentGit: {}

pipeline:
  stages: {}
```

There is no top-level `application.name` and no top-level `integrations` section in the current foundation.

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

Deployment settings exist only under `dev`, `integration`, and `production`. Verification settings exist only under deployment stages and are placeholders for future resources. `prepareRelease.releaseBranch` is a literal Kargo expression used by the prepare-release Stage. Helm must not evaluate it.

## Validation Workflow

Run:

```bash
helm lint ./generic-kargo-pipeline
helm template my-app-promotion ./generic-kargo-pipeline --namespace my-app-promotion
```

Known benign Helm lint output:

```text
[INFO] Chart.yaml: icon is recommended
```

## User Preferences

- Keep the chart generic.
- Prefer values-driven configuration over hard-coded application settings.
- Use `sources.deploymentGit` for deployment/chart configuration Git.
- Use `sources.components` for component image and developer Git sources.
- Keep component defaults built into `_helpers.tpl`; allow optional `sources.componentDefaults` only for overrides.
- Allow an intentionally empty Warehouse.
- Do not add cleanup yet.
- Do not add the remaining Stages or verification templates until explicitly requested.
