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

## Project Goal

The pipeline starts when a release source changes. Kargo should prepare deployment configuration, promote the same immutable release candidate through Dev and Integration, run native Kargo verification after each deployment, prepare the production change, and wait for a user to manually trigger Production.

Release sources are:

- new component image tags
- relevant deployment Git configuration changes

The key technologies are Kargo, Argo CD, GitLab, Helm, Kubernetes/OpenShift, n8n, and ServiceNow.

## Current Scope

The chart currently creates only:

- Kargo `Project`
- Kargo `ProjectConfig`
- Kargo `Warehouse`
- Kubernetes Git credential `Secret` resources

Do not add these until explicitly requested:

- Kargo `Stage` resources
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
- The chart must stay generic. Application-specific settings belong in `values.yaml`, not hard-coded templates.
- Credentials remain in values because the user explicitly does not require additional credential-protection logic.
- Git credential Secrets render only when both username and password are non-empty.

## Current File Layout

```text
generic-kargo-pipeline/
|-- Chart.yaml
|-- README.md
|-- values.schema.json
|-- values.yaml
`-- templates/
    |-- _helpers.tpl
    |-- project-config.yaml
    |-- project.yaml
    |-- warehouse.yaml
    `-- secrets/
        |-- chart-git-secret.yaml
        `-- developers-git-secret.yaml
```

## Naming Decisions

The Kargo Project name is set directly from the Helm release namespace:

```gotemplate
{{ .Release.Namespace }}
```

Do not replace it with the helper. The helper `generic-kargo-pipeline.projectName` may still be used for labels and related resource names.

Explicit `metadata.namespace` fields were removed from templates. Namespaced resources should be installed into the Helm release namespace naturally.

## Values Model

The chart uses these top-level sections:

```yaml
global:
  labels: {}
  annotations: {}

application:
  name: my-app

warehouse:
  name: app-images
  interval: 10m
  freightCreationPolicy: Automatic

sources:
  components: []
  deploymentGit: {}

pipeline:
  stages: {}

integrations: {}
```

Previous top-level source, stage, and verification sections were consolidated into this model.

## Source Model

`sources.components` supports multiple components. Each component has:

- required unique `name`
- one image repository
- one developer-owned Git repository
- one developer configuration file path
- one values mapping for future deployment values updates
- an `enabled` flag that controls whether the component is active in current chart resources

Example:

```yaml
sources:
  components:
    - name: api
      enabled: true
      image:
        repository: registry.example.com/team/my-app-api
        selectionStrategy: NewestBuild
        allowedTags: ""
        semverConstraint: ""
        strictSemvers: false
        discoveryLimit: 20
      git:
        repository:
          url: https://gitlab.example.com/team/my-app-api.git
          username: ""
          password: ""
        configuration:
          path: src/main/resources/values.yaml
      valuesMapping:
        tagPath: "{{ .Values.application.name }}.components.{{ .name }}.image.tag"
```

The component image tag and developer Git tag are always identical. Do not add a configurable tag-mapping strategy unless the user changes this decision.

When `sources.components[].enabled` is `false`, the component remains configured for future use, but the chart does not render its Warehouse image subscription or component developer Git credential Secret.

`valuesMapping` is not used by the current Warehouse. It is reserved for the future `prepare-release` Stage, which will map Freight image repository, tag, and digest into deployment Helm values.

`valuesMapping.tagPath` is the default deployment values path template for the component image tag. Chart creation can override this field when an application uses a different values hierarchy. Future logic should evaluate it while iterating over a component, where `.Values.application.name` is the application name and `.name` is the current component name. For component `api`, future logic should derive:

```text
my-app.components.api.image.tag
```

## Deployment Git

`sources.deploymentGit` is the deployment/chart configuration repository managed by the promotion pipeline.

```yaml
sources:
  deploymentGit:
    repository:
      url: https://gitlab.example.com/team/my-app-deployment.git
      username: ""
      password: ""
    subscription:
      enabled: true
      branch: develop
      commitSelectionStrategy: NewestFromBranch
      discoveryLimit: 15
      includePaths:
        - values.yaml
        - values/**
      excludePaths:
        - kargo/**
        - release-metadata/**
    branches:
      source: develop
      production: master
    paths:
      valuesFiles:
        base: values.yaml
        environment: values/${{ vars.environment }}.yaml
```

The Warehouse subscription branch is `sources.deploymentGit.subscription.branch`. Do not derive it implicitly from `branches.source`.

Deployment Git remains subscribed because configuration-only releases can create Freight. Only paths matching `includePaths` should count as configuration changes. Pipeline-generated paths should be excluded to avoid recursive Freight creation.

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

`prepareRelease.releaseBranch` is a literal Kargo expression for future Stage logic. Helm must not evaluate it. The branch name no longer includes commit.

Deployment stages have:

```yaml
deployment:
  namespace: my-app-dev
  argocd:
    applicationName: my-app-dev
    namespace: argocd
```

Verification settings live only under deployment stages and are placeholders for future resources.

## Integrations

Future integrations are grouped under:

```yaml
integrations:
  serviceNow:
    enabled: false
    credentials:
      username: ""
      password: ""
  gitLab:
    mergeRequest:
      enabled: false
      credentials:
        token: ""
```

No integration Secrets or API calls are implemented yet.

## Secrets

Secret templates:

- `templates/secrets/chart-git-secret.yaml`
- `templates/secrets/developers-git-secret.yaml`

Deployment Git credentials come from `sources.deploymentGit.repository`.

Component developer Git credentials come from `sources.components[].git.repository`. The component Secret name includes the normalized component name, for example:

```text
api-componentdevgit
worker-componentdevgit
```

The deployment Git Secret name renders as `deploymentgit`.

The chart assumes each component has a separate developer repository. Shared developer repositories may render one Secret per component if both components provide credentials.

## Warehouse Behavior

The Warehouse renders:

- one deployment Git subscription when `sources.deploymentGit.subscription.enabled` is true
- one image subscription per enabled `sources.components[]`

Component names are not rendered inside Warehouse image subscriptions because Kargo image subscriptions do not need them.

Current default Warehouse values:

```yaml
warehouse:
  name: app-images
  interval: 10m
  freightCreationPolicy: Automatic
```

## Validation Workflow

Run:

```sh
helm lint ./generic-kargo-pipeline
helm template my-app-promotion ./generic-kargo-pipeline --namespace my-app-promotion
git status
```

Also validate `values.schema.json` as JSON before committing.

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
- `Warehouse.spec.subscriptions[].image.strictSemvers`
- `Warehouse.spec.subscriptions[].image.discoveryLimit`

## User Preferences Captured

- Keep the chart generic.
- Prefer values-driven configuration over hard-coded application settings.
- Use `sources.deploymentGit` for deployment/chart configuration Git.
- Use `sources.components` for component image and developer Git sources.
- Component image tag equals component developer Git tag.
- Do not add cleanup yet.
- Do not add Stages or verification templates until explicitly requested.
- Commit and push completed changes after validation when asked to implement.
