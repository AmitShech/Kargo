# generic-kargo-pipeline

`generic-kargo-pipeline` is a reusable Helm chart foundation for a generic Kargo-based continuous delivery promotion pipeline. It is intended for teams that own deployment and promotion while application build and image publishing happen elsewhere.

## Current Scope

This chart currently creates only:

- Kargo `Project`
- Kargo `ProjectConfig`
- Kargo `Warehouse`
- Kubernetes Git credential `Secret` resources

It does not create Kargo `Stage` resources, `AnalysisTemplate` resources, `spec.verification`, Argo CD promotion steps, ServiceNow API calls, GitLab merge request API calls, cleanup, or undeploy logic yet.

## Intended Promotion Flow

```text
Warehouse detects a release source
        |
        v
prepare-release
        |
        v
dev
  deployment through Argo CD
  native Kargo verification using an OpenShift QA Job
        |
        v
integration
  deployment through Argo CD
  native Kargo verification using integration tests, metrics, logs, and health checks
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

Everything before Production is intended to be automatic. Production auto-promotion defaults to disabled so a user must manually promote the prepared Freight.

Install only one instance of this chart in a Kargo project namespace. The chart creates project-scoped resources such as the Warehouse, ProjectConfig, and Git credential Secrets with stable names.

## Multi-Component Sources

Release inputs are configured under `sources.components`. Each component represents one deployable application component and contains:

- image repository watched by the Warehouse
- developer-owned Git repository
- developer configuration file path
- Helm values mapping for future `prepare-release` logic

The component image tag and developer Git tag are intentionally the same value. For example, image tag `2.5.1` maps to developer Git tag `2.5.1`; there is no configurable tag mapping strategy.

```yaml
sources:
  components:
    - name: api
      enabled: true
      image:
        repository: registry.example.com/team/my-app-api
        selectionStrategy: NewestBuild
        strictSemvers: false
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

The component `name` is required because future stages will use it to map Freight artifacts into deployment values.

`enabled` controls whether the component source is active. When `enabled: false`, the component remains configured for future use, but the chart does not render its Warehouse image subscription or component developer Git credential Secret.

`valuesMapping.tagPath` is the default deployment values path template for the component image tag. Chart creation can override this field when an application uses a different values hierarchy. Future logic should evaluate it while iterating over a component, where `.Values.application.name` is the application name and `.name` is the current component name. For example, component `api` resolves to:

```text
my-app.components.api.image.tag
```

## Release Sources

The Warehouse can create Freight from two kinds of release triggers:

1. A new component image tag.
2. A relevant deployment Git configuration change.

The deployment Git repository is configured under `sources.deploymentGit`. Its Warehouse subscription follows the explicit `sources.deploymentGit.subscription.branch` value.

```yaml
sources:
  deploymentGit:
    subscription:
      enabled: true
      branch: develop
      includePaths:
        - values.yaml
        - values/**
      excludePaths:
        - kargo/**
        - release-metadata/**
```

Only commits matching `includePaths` are considered configuration release changes. Pipeline-generated files should be listed in `excludePaths` to avoid recursive Freight creation when Kargo writes metadata or release artifacts back to Git.

## Pipeline Structure

Promotion settings live under `pipeline.stages`.

Deployment stages (`dev`, `integration`, and `production`) have a `deployment` block with the target namespace and Argo CD Application identity. They also have verification settings that are placeholders for future Kargo verification resources.

Non-deployment stages (`prepareRelease` and `preProduction`) do not have Argo CD deployment settings.

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
      deployment:
        namespace: my-app-dev
        argocd:
          applicationName: my-app-dev
          namespace: argocd
      verification:
        enabled: true
        templateName: my-app-dev-qa
        timeout: 30m
```

The release branch value is a literal Kargo expression for future Stage logic; Helm does not evaluate it.

## Git Credential Secrets

Git credentials are kept in values and are optional. A Secret renders only when both `username` and `password` are non-empty.

The chart creates one deployment Git credential Secret from `sources.deploymentGit.repository` and one component developer Git credential Secret per component with credentials. The deployment Git Secret renders as `deploymentgit`. Component Secret names include the normalized component name, for example `api-devgit`.

The chart assumes each component uses a separate developer Git repository. If two components share the same developer repository and both provide credentials, the current template renders one Secret per component.

Do not commit real passwords, tokens, or other secret values to Git.

## Chart Structure

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

## Future Resources

Later chart iterations are expected to add:

- Kargo `Stage` resources for `prepare-release`, `dev`, `integration`, `pre-production`, and `production`
- native Kargo `spec.verification` configuration for Dev, Integration, and optionally Production
- verification resources required by the installed Kargo version
- Argo CD promotion steps for deployment stages
- ServiceNow change creation
- GitLab merge request creation

Environment cleanup and undeploy behavior are intentionally not included yet.

## Validate The Chart

Run Helm lint:

```sh
helm lint ./generic-kargo-pipeline
```

Render the chart:

```sh
helm template my-app-promotion ./generic-kargo-pipeline \
  --namespace my-app-promotion
```

Render with an application-specific values file:

```sh
helm template my-app-promotion ./generic-kargo-pipeline \
  --namespace my-app-promotion \
  --values ./my-app-values.yaml
```

Install or upgrade with an application-specific values file:

```sh
helm upgrade --install my-app-promotion ./generic-kargo-pipeline \
  --namespace my-app-promotion \
  --create-namespace \
  --values ./my-app-values.yaml
```
