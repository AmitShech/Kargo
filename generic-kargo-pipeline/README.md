# generic-kargo-pipeline

`generic-kargo-pipeline` is a reusable Helm chart for a generic Kargo-based continuous delivery promotion pipeline. It is for teams that own deployment and promotion while application build and image publishing happen elsewhere.

Install only one chart instance per Kargo project namespace. The chart intentionally creates project-scoped resources with stable names.

## Current Scope

This chart currently creates:

- Kargo `Project`
- Kargo `ProjectConfig`
- Kargo `Warehouse`
- the Kargo `prepare-release` `Stage`
- Kubernetes Git credential `Secret` resources

It does not create the Dev, Integration, Pre-production, or Production `Stage` resources, `AnalysisTemplate` resources, native Kargo `spec.verification`, Argo CD promotion steps, ServiceNow API calls, GitLab merge request API calls, cleanup, or undeploy logic yet.

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

Everything before Production is intended to be automatic. Production auto-promotion defaults to disabled so a user must manually promote prepared Freight.

## Component Defaults

Image-selection defaults are built into the chart, and the default `values.yaml` also writes those values under the example component so the component shape is easy to copy. `sources.componentDefaults` is an optional override hook; set only the shared defaults you want to change. Helm merges built-in defaults, optional `sources.componentDefaults`, and then each component; component-specific values win. `releaseConfiguration.devConfigurationPath` is not a built-in default; set it when component configuration generation is enabled.

```yaml
sources:
  componentDefaults:
    image:
      discoveryLimit: 50
```

The default chart values include one example component named `main`:

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

## Multiple Components

Applications can replace the component list with their own components. Each component can rely on defaults or override them.

```yaml
sources:
  components:
    - name: api
      image:
        artifactory: registry.example.com/team/my-app-api
        selectionStrategy: SemVer
        semverConstraint: ">=1.0.0 <2.0.0"
      git:
        repository:
          url: https://gitlab.example.com/team/my-app-api.git
      releaseConfiguration:
        generationEnabled: true
        devConfigurationPath: config/values.yaml
        deploymentOverlayPath: values/overrides/api.yaml
        outputPath: values/releases/api.yaml
      valuesMapping:
        tagPath: services.backend.api.image.tag

    - name: worker
      enabled: false
      image:
        artifactory: registry.example.com/team/my-app-worker
      git:
        repository:
          url: https://gitlab.example.com/team/my-app-worker.git
      releaseConfiguration:
        generationEnabled: false
        outputPath: values/releases/worker.yaml
      valuesMapping:
        tagPath: workloads.orders.imageTag
```

Disabled components do not create Warehouse image subscriptions or component developer Git credential Secrets. They are still validated for duplicate normalized names and incomplete credentials.

Component names must be unique after Kubernetes-name normalization. For example, `API_Service` and `api-service` both normalize to `api-service` and will fail rendering.

## Literal Values Path

`valuesMapping.tagPath` is a final application-specific YAML path that future `prepare-release` logic will pass directly to a Kargo YAML update operation. It is not a Helm template.

Examples:

```text
image.tag
services.backend.api.image.tag
workloads.orders.imageTag
```

Do not use nested template expressions such as `{{ .Values.application.name }}` in this field.

## Prepare Release

The `prepare-release` Stage requests Freight directly from the Warehouse and prepares one deployment configuration file per enabled component. The deployment repository is checked out twice: the exact commit carried by Freight becomes the source worktree, and `release/<Freight name>` becomes a separate output worktree. Kargo creates the release branch when it does not exist, clears its worktree, and copies the complete deployment source tree into it before applying component changes.

Each enabled component must define its release output:

```yaml
sources:
  components:
    - name: main
      # image and Git repository settings omitted
      releaseConfiguration:
        generationEnabled: true
        devConfigurationPath: src/main/resources/values.yaml
        deploymentOverlayPath: values/overrides/main.yaml
        outputPath: values/releases/main.yaml
      valuesMapping:
        tagPath: image.tag
```

When `generationEnabled` is `true`, the Stage checks out the component developer repository at the Git tag matching the Freight image tag. It merges `devConfigurationPath` as the base with `deploymentOverlayPath` from deployment Git as the override, writes the result to `outputPath`, and then updates the literal `valuesMapping.tagPath` with the selected image tag. These paths may contain the `name` placeholder, which the chart replaces with the normalized component name.

When `generationEnabled` is `false`, the clone and merge steps are omitted. `outputPath` must already exist at the deployment Git Freight commit, and the Stage still updates its image tag. Missing tags or configured files fail the promotion before any commit or push.

Output paths must be unique among enabled components. All configuration paths must be relative workspace paths without `..` traversal.

All component changes are committed together and pushed without force. The default branch is a literal Kargo expression:

```yaml
pipeline:
  stages:
    prepareRelease:
      releaseBranch: release/${{ ctx.targetFreight.name }}
```

The commit message records the Freight name, deployment commit, and every enabled component image tag.

## Release Sources

The Warehouse can create Freight from:

- the deployment Git repository, when `sources.deploymentGit.subscription.enabled` is true
- one image artifactory source per enabled component

An empty Warehouse is allowed intentionally. If deployment Git is disabled and no component is enabled, Helm install/upgrade notes show this warning:

```text
WARNING:
The Kargo Warehouse currently has no active subscriptions.
Enable at least one component or the deployment Git subscription before expecting Freight creation.
```

## Deployment Git Branches

`sources.deploymentGit.branches.source` is the Warehouse-watched branch. The deployment commit selected into Freight is the immutable base for the release branch.

```yaml
sources:
  deploymentGit:
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
```

Only commits matching `includePaths` are considered configuration release changes. Pipeline-generated paths should be listed in `excludePaths` to avoid recursive Freight creation.

## Image Selection

Each component can configure:

- `selectionStrategy`: `NewestBuild`, `SemVer`, or `Lexical`
- `allowedTags`: optional regular expression rendered as Warehouse `allowTags` when non-empty
- `semverConstraint`: optional SemVer constraint rendered when non-empty
- `strictSemvers`: boolean rendered explicitly, including `false`
- `discoveryLimit`: integer greater than or equal to 1

`strictSemvers` has been verified against the installed Kargo CRD for this project.

## Pipeline Structure

Promotion settings live under `pipeline.stages`. Deployment settings exist only under `dev`, `integration`, and `production`. Verification settings also live only under deployment stages and are placeholders for future Kargo verification resources.

`prepareRelease` and `preProduction` do not control Argo CD Applications. Production `autoPromotionEnabled` defaults to `false`.

## Credentials

Git credentials are kept directly in values and are optional. Do not commit real passwords, tokens, or other secret values.

A Git credential Secret renders only when both `username` and `password` are non-empty. Helm rendering fails when exactly one field is provided.

Generated Secret names are stable:

```text
deploymentgit
<normalized-component-name>-devgit
```

Examples:

```text
main-devgit
api-devgit
worker-devgit
```

## File Layout

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

## Future Resources

Later chart iterations are expected to add:

- Kargo `Stage` resources for `dev`, `integration`, `pre-production`, and `production`
- native Kargo `spec.verification` configuration for Dev, Integration, and optionally Production
- verification resources required by the installed Kargo version
- Argo CD promotion steps for deployment stages
- production-change and merge-request preparation when those designs are added

Environment cleanup and undeploy behavior are intentionally not included yet.

## Validate The Chart

Run Helm lint:

```bash
helm lint ./generic-kargo-pipeline
```

Render the chart:

```bash
helm template my-app-promotion ./generic-kargo-pipeline \
  --namespace my-app-promotion
```

Render with an application-specific values file:

```bash
helm template my-app-promotion ./generic-kargo-pipeline \
  --namespace my-app-promotion \
  --values ./my-app-values.yaml
```

Render with credentials and multiple components by adding an override file that sets deployment Git credentials and component repository credentials. The chart will render `deploymentgit` plus one `<component>-devgit` Secret per enabled component with complete credentials.

Install or upgrade with an application-specific values file:

```bash
helm upgrade --install my-app-promotion ./generic-kargo-pipeline \
  --namespace my-app-promotion \
  --create-namespace \
  --values ./my-app-values.yaml
```
