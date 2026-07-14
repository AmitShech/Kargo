# Project And Secret Knowledge

This file tracks chart knowledge related to Kargo `Project`, Kargo `ProjectConfig`, labels, naming, and Git credential `Secret` resources.

## Project Resource

Template:

```text
generic-kargo-pipeline/templates/project.yaml
```

The Kargo Project name is set directly from the Helm release namespace:

```gotemplate
{{ .Release.Namespace }}
```

Do not replace this with the `generic-kargo-pipeline.projectName` helper in `project.yaml`. The helper may still be used for labels and related resource names.

Explicit `metadata.namespace` fields are intentionally not used. Namespaced resources should be installed into the Helm release namespace naturally.

Install only one chart instance in a Kargo project namespace. The chart intentionally uses stable project-scoped names for the Warehouse, ProjectConfig, and Git credential Secrets.

## ProjectConfig Resource

Template:

```text
generic-kargo-pipeline/templates/project-config.yaml
```

`ProjectConfig` uses the normalized release namespace for its name:

```gotemplate
{{ include "generic-kargo-pipeline.projectName" . }}
```

Promotion policies are generated from `pipeline.stages`:

```yaml
promotionPolicies:
  - stage: prepare-release
    autoPromotionEnabled: true
  - stage: dev
    autoPromotionEnabled: true
  - stage: integration
    autoPromotionEnabled: true
  - stage: pre-production
    autoPromotionEnabled: true
  - stage: production
    autoPromotionEnabled: false
```

Production auto-promotion must default to disabled. A user must manually promote prepared Freight to Production.

## Labels And Annotations

Common labels are rendered by:

```gotemplate
{{ include "generic-kargo-pipeline.labels" . }}
```

Kargo identity labels are rendered by:

```gotemplate
{{ include "generic-kargo-pipeline.applicationLabels" . }}
```

In the labels helper, user-defined labels render first and mandatory Helm/chart labels render afterward. This prevents user labels from overriding:

```text
helm.sh/chart
app.kubernetes.io/name
app.kubernetes.io/instance
app.kubernetes.io/managed-by
app.kubernetes.io/part-of
app.kubernetes.io/version
```

Global annotations come from:

```yaml
global:
  annotations: {}
```

## Name Helpers

Reusable helpers must be preserved for future Stage templates:

```text
generic-kargo-pipeline.deploymentGitSecretName
generic-kargo-pipeline.componentDevGitSecretName
generic-kargo-pipeline.normalizeName
generic-kargo-pipeline.projectName
```

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

## Git Credential Secrets

Secret templates:

```text
generic-kargo-pipeline/templates/secrets/deployment-git.yaml
generic-kargo-pipeline/templates/secrets/component-dev-git.yaml
```

Deployment Git credentials come from:

```yaml
sources:
  deploymentGit:
    repository:
      url: https://gitlab.example.com/team/my-app-deployment.git
      username: ""
      password: ""
```

Component developer Git credentials come from:

```yaml
sources:
  components:
    - name: main
      git:
        repository:
          url: https://gitlab.example.com/team/my-app.git
          username: ""
          password: ""
```

A Secret renders only when both `username` and `password` are non-empty.

Helm validation fails if exactly one field is provided. This validation applies to deployment Git and every configured component developer Git credential pair.

Disabled components do not render component developer Git credential Secrets.

The chart assumes each component has a separate developer repository. Shared developer repositories may render one Secret per component if both components provide credentials.

Do not commit real passwords, tokens, or other secret values.

## Secret Content

Secrets use:

```yaml
type: Opaque
```

Kargo Git credential Secrets include:

```yaml
metadata:
  labels:
    kargo.akuity.io/cred-type: git
stringData:
  repoURL: ...
  username: ...
  password: ...
```

## Schema Rules

`values.schema.json` should reject stale fields, including:

- top-level `application`
- top-level `integrations`
- `sources.deploymentGit.subscription.branch`
- old `chartGit` or `developersGit` fields
- templated `valuesMapping.tagPath` values containing `{` or `}`
- `image.repository`; the current image source field is `image.artifactory`

The schema keeps labels and annotations extensible while chart-owned structures use `additionalProperties: false` where practical.

## ProjectConfig API Fields To Verify Later

Before installing into a real cluster, verify these fields against the installed Kargo version:

- `ProjectConfig.spec.promotionPolicies[].stage`
- `ProjectConfig.spec.promotionPolicies[].autoPromotionEnabled`
