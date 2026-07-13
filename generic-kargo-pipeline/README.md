# generic-kargo-pipeline

`generic-kargo-pipeline` is a reusable Helm chart foundation for a generic Kargo-based continuous delivery promotion pipeline. It is intended for teams that own deployment and promotion while application build and image publishing happen elsewhere.

## Intended Promotion Flow

```text
Warehouse detects a new image tag
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

## What This First Implementation Creates

This initial chart foundation creates:

- A Kargo `Project`.
- A Kargo `ProjectConfig` with configurable promotion policies for `prepare-release`, `dev`, `integration`, `pre-production`, and `production`.
- A Kargo `Warehouse` subscribed to one or more component image repositories.
- Default values and JSON Schema validation for important application, Git, image, and environment settings.

The Kargo Project name is derived from the Helm release namespace. Deploy the chart into the namespace that should own the Kargo project.

## Future Resources

Later chart iterations are expected to add:

- Kargo `Stage` resources for `prepare-release`, `dev`, `integration`, `pre-production`, and `production`.
- Native Kargo `spec.verification` configuration for Dev, Integration, and optionally Production.
- Analysis templates or equivalent verification resources required by the installed Kargo version.
- Argo CD promotion steps for deployment stages.
- ServiceNow change creation.
- GitLab merge request creation.

Environment cleanup and undeploy behavior are intentionally not included yet.

Release branch naming is configured under `git.branches.releaseTemplate`. The default shape is `release/{{ .ImageTag }}/{{ .Commit }}`; future promotion logic will fill those values from the current Freight.

`git.paths.valuesFile` describes Helm values files inside the deployment configuration repository. `base` points to the shared values file, and `environment` points to the environment-specific values file template. Future promotion steps can update the target environment file while keeping the same Freight image tag, digest, release branch, and commit moving through the pipeline.

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

Do not place passwords, tokens, or other secret values in `values.yaml`. Reference existing Kubernetes Secret names and keys instead.
