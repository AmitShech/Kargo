# Codex Project Knowledge

This repository contains a reusable Helm chart for a generic Kargo-based CD promotion pipeline. The chart is intended for deployment and promotion ownership only; application build and development stay outside this project.

## Project Goal

The pipeline starts when a new application image tag is published. Kargo should prepare deployment configuration, promote the same immutable release candidate through Dev and Integration, run native Kargo verification after each deployment, prepare the production change, and wait for a user to manually trigger Production.

The key technologies are Kargo, Argo CD, GitLab, Helm, Kubernetes/OpenShift, n8n, and ServiceNow.

## Intended Flow

```text
Warehouse detects a new image tag
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

There is no environment cleanup or undeploy step yet. Do not add cleanup unless explicitly requested.

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
- Templates should use helpers for names and labels where practical.

## Repository And Chart

The GitHub repository is:

```text
https://github.com/AmitShech/Kargo.git
```

The Helm chart is in:

```text
generic-kargo-pipeline/
```

Current chart resources:

- Kargo `Project`
- Kargo `ProjectConfig`
- Kargo `Warehouse`
- Kubernetes `Secret` resources for Git credentials

Resources intentionally not implemented yet:

- Kargo `Stage` resources
- Kargo verification resources / AnalysisTemplates
- Argo CD deployment promotion steps
- ServiceNow API integration
- GitLab merge request API integration
- Cleanup / undeploy

## Current File Layout

```text
generic-kargo-pipeline/
├── Chart.yaml
├── README.md
├── values.schema.json
├── values.yaml
└── templates/
    ├── _helpers.tpl
    ├── project-config.yaml
    ├── project.yaml
    ├── secrets.yaml
    └── warehouse.yaml
```

## Naming Decisions

The Kargo Project name is set directly from the Helm release namespace:

```gotemplate
{{ .Release.Namespace }}
```

The user specifically asked that `Project.metadata.name` should not use:

```gotemplate
{{ include "generic-kargo-pipeline.projectName" . }}
```

The helper `generic-kargo-pipeline.projectName` still exists and currently normalizes `.Release.Namespace` for labels and related resource names. Project resource metadata name itself should remain direct `.Release.Namespace` unless the user changes this decision.

Explicit `metadata.namespace` fields were removed from templates. Namespaced resources should be installed into the Helm release namespace naturally.

## Values Hierarchy

The chart currently separates Git configuration by job:

```yaml
chartGit:
  repository:
    url: https://gitlab.example.com/team/my-app-deployment.git
    username: username
    password: password
  branches:
    source: develop
    production: master
    releaseTemplate: "release/{{ .ImageTag }}/{{ .Commit }}"
  paths:
    valuesFile:
      base: values.yaml
      environment: "values/{{ .Environment }}.yaml"

developersGit:
  repository:
    url: https://gitlab.example.com/team/my-app.git
    username: username
    password: password
  configurationPathFile: src/main/resources/values.yaml
```

`chartGit` is the deployment/chart configuration repository managed by the promotion pipeline.

`developersGit` is the developer-owned repository. `configurationPathFile` is the file that future chart creation logic should copy from the developer repository tag associated with the current Freight.

The user wanted credentials merged into the repository details instead of a separate `credentialsSecret` value. The chart creates Kubernetes `Secret` resources from these repository username/password fields.

Important safety note: current defaults leave repository usernames and passwords empty so placeholder credential Secrets are not rendered. Do not commit real credentials in values files.

## Artifact Model

Artifacts support multiple components:

```yaml
artifact:
  components:
    - name: my-app
      image:
        repository: registry.example.com/team/my-app
        selectionStrategy: NewestBuild
        allowedTags: ""
        semverConstraint: ""
        discoveryLimit: 20
```

Warehouse renders one image subscription per component.

`artifact.components[].name` is reserved for future stage logic that maps Freight images into chart/configuration updates. The current Warehouse template does not emit this name because Kargo image subscriptions do not require it.

Default selection strategy is `NewestBuild`.

`allowedTags` and `semverConstraint` are optional and omitted from the rendered Warehouse when empty.

## Environment Model

Configured environments:

- `dev`
- `integration`
- `preProduction`
- `production`

Promotion policy defaults:

- `prepare-release`: automatic
- `dev`: automatic
- `integration`: automatic
- `pre-production`: automatic
- `production`: manual (`autoPromotionEnabled: false`)

Each deployment environment contains an Argo CD Application name, Argo CD namespace, deployment namespace, auto-promotion setting, and verification enablement.

## Git Branching Model

Release branch naming is under:

```yaml
chartGit:
  branches:
    releaseTemplate: "release/{{ .ImageTag }}/{{ .Commit }}"
```

The image tag and commit will be populated later from the current Freight.

The source and production branches are:

```yaml
chartGit:
  branches:
    source: develop
    production: master
```

## Secrets

`templates/secrets.yaml` creates two `Secret` resources when username and password values are present:

- chart Git credentials
- developers Git credentials

The Secret names are generated by helpers:

- `generic-kargo-pipeline.chartGitSecretName`
- `generic-kargo-pipeline.developersGitSecretName`

Secrets render only when both username and password are supplied. They use `stringData.username` and `stringData.password`.

## Validation Workflow

Helm is available at:

```text
C:\Users\taik0704\AppData\Local\helm.exe
```

Run lint:

```powershell
& 'C:\Users\taik0704\AppData\Local\helm.exe' lint .\generic-kargo-pipeline --namespace my-app-promotion
```

Run template:

```powershell
& 'C:\Users\taik0704\AppData\Local\helm.exe' template my-app-promotion .\generic-kargo-pipeline --namespace my-app-promotion
```

Also parse the schema:

```powershell
Get-Content .\generic-kargo-pipeline\values.schema.json -Raw | ConvertFrom-Json | Out-Null
```

Known benign Helm lint output:

```text
[INFO] Chart.yaml: icon is recommended
```

## Git Workflow

Git is available at:

```text
C:\Users\taik0704\AppData\Local\Programs\Git\cmd\git.exe
```

The repository is on `main` and pushes to:

```text
origin https://github.com/AmitShech/Kargo.git
```

After changes, run status, validate Helm, commit, and push.

Use focused commit messages. Prior commits include:

- `Add generic Kargo pipeline Helm chart foundation`
- `Fix Helm resource name normalization`
- `Support multiple artifact images in Warehouse`
- `Derive Kargo project name from release namespace`
- `Move release branch template under git branches`
- `Remove git author config and document paths`
- `Split values file paths into base and environment`
- `Add developer configuration Git source`
- `Move developer configuration outside deployment git`
- `Add Git credential secrets and split Git config`
- `Set Kargo Project name from release namespace`
- `Remove explicit metadata namespaces`

## Open Kargo API Fields To Verify Later

Before installing into a real cluster, verify these fields against the installed Kargo version:

- `ProjectConfig.spec.promotionPolicies[].stage`
- `ProjectConfig.spec.promotionPolicies[].autoPromotionEnabled`
- `Warehouse.spec.subscriptions[].image.repoURL`
- `Warehouse.spec.subscriptions[].image.imageSelectionStrategy`
- `Warehouse.spec.subscriptions[].image.allowTags`
- `Warehouse.spec.subscriptions[].image.semverConstraint`
- `Warehouse.spec.subscriptions[].image.discoveryLimit`

## User Preferences Captured

- Keep the chart generic.
- Prefer values-driven configuration over hard-coded application settings.
- Keep deployment Git (`chartGit`) and developer Git (`developersGit`) separate because they have different jobs.
- `configurationPathFile` means the developer repo file that will be copied later during chart creation.
- Do not add cleanup yet.
- Do not add Stages or verification templates until explicitly requested.
- Commit and push completed changes after validation when asked to implement.
