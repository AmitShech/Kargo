# Generic Kargo Pipeline

`generic-kargo-pipeline` is a reusable Helm chart for building a five-stage promotion pipeline on self-managed Kargo v1.10.

```text
Warehouse
   |
   v
Prepare release --> Dev --> Integration --> Pre-production --> Production
                    auto       auto              auto              manual
```

The chart creates Kargo resources and verification contracts. It does not build applications, create Argo CD Applications, install external services, or publish the dispatcher and Smooth images used by verification.

## What the chart creates

- One Kargo `Project`, `ProjectConfig`, and `Warehouse`.
- Prepare-release, Dev, Integration, Pre-production, and Production `Stage` resources.
- Git credential Secrets for chart Git and every enabled component developer/QA repository.
- HTTP credential Secrets for enabled authenticated services.
- Managed Argo Rollouts `AnalysisTemplate` resources for Smooth, Job, Prometheus, HTTP, and Elasticsearch checks.
- Dispatcher AnalysisTemplates and namespace-scoped RBAC for component fan-out, aggregation, and outcome handling.

## Release guarantees

- Every Freight is evaluated independently from its own artifacts.
- Prepare-release creates one immutable chart Git commit and records component evidence on Freight.
- Dev, Integration, and Production deploy that exact commit SHA.
- Development tags can pass Dev and Integration; Pre-production and Production require official tags.
- Component tag policies can only make a Stage policy stricter.
- Production is manual and merges the prepared GitLab MR before deployment when GitLab administration is enabled.
- Verification is optional. Disabled verification does not require provider-specific configuration.

## Prerequisites

- Helm 3.
- Self-managed Kargo v1.10.
- Argo Rollouts CRDs for `AnalysisTemplate` and `AnalysisRun`.
- One existing Argo CD Application for each deployment Stage, authorized for that Stage.
- Reachable Git repositories.
- A compatible, prebuilt dispatcher image whenever dispatcher-backed verification is enabled.
- Any enabled Smooth, Prometheus, Elasticsearch, AI, ServiceNow, GitLab, mail, or monitoring service.

The Argo CD Applications own their destination namespaces. This chart only needs each `argocd.applicationName`.

## Install

Start from the full example and replace every example endpoint, repository, credential, query, and field:

```powershell
Copy-Item .\generic-kargo-pipeline\examples\values-all-features.yaml .\my-values.yaml
helm lint .\generic-kargo-pipeline -f .\my-values.yaml
helm template my-system .\generic-kargo-pipeline --namespace my-system -f .\my-values.yaml
helm upgrade --install my-system .\generic-kargo-pipeline --namespace my-system --create-namespace -f .\my-values.yaml
```

The Helm release namespace is also the Kargo project name.

## Configuration map

| Values section | Purpose |
|---|---|
| `global` | System identity, common metadata, and dispatcher image |
| `warehouse` | Freight discovery behavior |
| `sources.chartGit` | GitOps/chart repository and source/production branches |
| `sources.components` | Component images, developer Git, QA Git, release paths, and selectors |
| `pipeline.notifications` | Shared email recipients and message defaults |
| `pipeline.stages` | Stage promotion, tag, verification, administration, and outcome settings |
| `services` | External endpoints and HTTP authentication |
| `analysisTemplates` | Reusable managed or external verification definitions |

HTTP authentication supports `none`, `basic`, and `apiKey`. Plain HTTP endpoints require `allowInsecureHttp: true`. Repository username and password must either both be set or both be empty.

Do not commit real credentials in a values file. Supply them through your protected deployment mechanism. The chart places configured credentials into Kubernetes Secrets and does not copy them into Stage or AnalysisRun arguments.

## Verification model

Definitions are declared once at the end of the values file and activated by name from a Stage:

```yaml
analysisTemplates:
  - name: production-health
    type: http
    target: stage
    retryAmount: 1
    timeout: 10m
    ttlAfterFinished: 6h
    mode: blocking
    service: monitoring
    checks:
      - name: health
        url: https://app.example.test/health
        expectedStatus: 200

pipeline:
  stages:
    production:
      verification:
        enabled: true
        analysisTemplates:
          - name: production-health
            enabled: true
```

Supported types are `smooth`, `job`, `prometheus`, `http`, `elasticsearch`, and `external`. External definitions reference an existing `AnalysisTemplate` or `ClusterAnalysisTemplate`; Helm does not create the referenced resource.

Dev can run Smooth only for components whose tags changed, or for every enabled component. Integration expands Prometheus and Elasticsearch checks for every enabled Flink component, applies label/filter precedence, waits the configured initial delay, and calculates measurement counts from duration and interval.

## Administration and outcomes

Pre-production can:

- request structured release content from an internal AI endpoint;
- create or reuse a ServiceNow change;
- create or reuse an independent GitLab merge request;
- operate ServiceNow and GitLab from fixed values when AI is disabled.

Production can merge the prepared MR, verify that the production branch contains the tested commit, deploy it, run post-validation, update the same ServiceNow change, send enabled email outcomes, and create a monitoring alert only for failed Production verification.

## Validate the chart

```powershell
powershell.exe -ExecutionPolicy Bypass -File .\generic-kargo-pipeline\tests\run.ps1
```

The suite performs Helm linting, default and full-feature rendering, negative validation checks, immutable-revision assertions, tag-policy checks, notification checks, and credential-isolation checks.

## Delivery boundary

The repository is intentionally chart-only. Runtime behavior of the dispatcher image and live integrations must be tested in the target environment. Customer output validation, automatic rollback, and environment/application cleanup are intentionally deferred. GitLab deletion of the temporary release branch after merge is the only configured cleanup.

Detailed design documents and the completeness audit are available in the repository's `project/` directory.
