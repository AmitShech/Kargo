# Project Knowledge

This repository contains a reusable Helm chart for a generic Kargo-based CD promotion pipeline. The chart owns release preparation, environment promotion, verification orchestration, and release-administration integrations. Application build and feature development remain outside this repository.

Repository:

```text
https://github.com/AmitShech/Kargo.git
```

Chart path:

```text
generic-kargo-pipeline/
```

## Implementation Status

Currently implemented chart resources include:

- Kargo `Project`
- Kargo `ProjectConfig`
- Kargo `Warehouse`
- all five pipeline Stages: Prepare-release, Dev, Integration, Pre-production, and Production
- managed Smooth, Job, Prometheus, HTTP, Elasticsearch, external-reference, and dispatcher `AnalysisTemplate` resources
- Git and HTTP credential Secrets
- chart-side AI, ServiceNow, GitLab, mail, and monitoring integration contracts

Dispatcher execution remains an external runtime prerequisite: the chart renders its Jobs, RBAC, and configuration contract but does not build the dispatcher image. Live external API and cluster compatibility are not proven by Helm rendering.

Do not claim a designed resource exists until its template and validation are present. Maintain Stage behavior against the design authorities under `docs/stages/`.

## Intended Flow

```text
Warehouse discovers standalone Freight
        |
        v
prepare-release
  build one immutable release commit
  record changed component tags
        |
        v
dev
  deploy exact commit through Argo CD
  optionally run Smooth QA for selected components
        |
        v
integration
  deploy the same commit through Argo CD
  optionally validate all Flink components with Prometheus and Elasticsearch
        |
        v
pre-production
  require official tags
  generate an AI release summary
  create independent ServiceNow and GitLab records
        |
        v
production
  manual Freight selection
  merge the prepared GitLab MR
  deploy the exact tested commit
  optionally run post-validation
  update ServiceNow and send outcome notifications
```

## Non-negotiable Architecture Rules

- Each Freight is standalone. Release preparation must use only artifacts in the target Freight, never another Freight or Stage history.
- The same immutable application candidate moves through environments. Do not rebuild or replace images between Stages.
- Preserve component tag, image digest, developer Git tag/commit, chart Git input commit, release branch, and release commit.
- A component image tag equals its developer Git tag.
- `valuesMapping.tagPath` is a literal YAML path. Helm must not evaluate it.
- Dev, Integration, and Production each control exactly one existing Argo CD Application by `applicationName`.
- Argo CD Applications own their destination namespaces; do not duplicate destination namespace values in this chart.
- `prepare-release` and `pre-production` do not control Argo CD Applications.
- Explicit verification uses native Kargo `spec.verification`, never a promotion step.
- Verification is optional. Disabled verification must not require template-specific values or fail rendering.
- Active templates trigger strict, type-specific validation.
- Everything before Production is automatic.
- Production auto-promotion defaults to false, and the user explicitly selects Freight.
- Production deploys the exact tested commit SHA, not a branch head or newest commit.
- Failed Freight is blocked downstream but does not prevent newer Freight from being created or promoted after the active verification terminates.
- The chart stays generic. System-specific repositories, labels, queries, thresholds, prompts, fields, endpoints, and credentials belong in values.

## Tag Lifecycle

Development tags such as `dev-2.4.0` may pass through Prepare-release, Dev, and Integration. Only official tags may pass Pre-production and Production.

After a development candidate succeeds, developers create:

- an official image tag pointing to the exact tested image digest
- an official developer Git tag pointing to the same source commit

The official tag creates new Freight and repeats Dev and Integration, giving the official candidate its own verification history. Kargo must not build images or invent official tags.

Every Stage supports a values-driven `tagPolicy`. Denied patterns win over allowed patterns. Component policies may add stricter restrictions.

## Prepare-release Rules

For each enabled component, read the tag from the chart Git commit contained in the same Freight at:

```text
releaseConfiguration.outputPath + valuesMapping.tagPath
```

Compare it with the selected Freight tag before merging or updating files. Store changed-component metadata on Freight. Missing files or tag paths fail preparation.

Use `sources.chartGit` as the approved target name for deployment/chart configuration Git. Existing `sources.deploymentGit` code is migration work and must be renamed consistently when implemented. Use `chartOverlayPath` instead of `deploymentOverlayPath` in the approved interface.

## Dev Verification Rules

- Smooth QA definitions are per component and live in separate QA Git repositories.
- QA uses a configured branch; it is intentionally not snapshotted.
- QA directory `path` defaults to `.`; the filename is always `.smooth.yaml`.
- Smooth runs directly with chart-owned behavior equivalent to `smooth run --file .smooth.yaml --skip-install`.
- Argo CD remains the sole application deployment owner.
- The Kargo dispatcher, not Smooth, selects components.
- `runForChangedComponentsOnly: true` runs only components recorded as changed by Prepare-release.
- `false` runs every enabled component.
- `parallelismLimit` bounds simultaneous child AnalysisRuns.
- Retry failed components individually, wait for all child results, and aggregate once.

## Integration Verification Rules

- Integration processes a copy of Production input and writes only to isolated Integration sinks.
- Validate every enabled Flink component for every Freight, including configuration-only Freight.
- Wait for Argo CD health, capture `verificationStartedAt`, then wait `initialDelay`.
- Run checks for configured `duration` at configured `interval`; calculate Argo measurement count internally.
- PromQL contains its aggregation. Do not add decorative aggregation fields.
- Merge Prometheus labels from service, template, target, and metric; the most specific value wins.
- Query only explicit Elasticsearch failure conditions; do not add a catch-all error query.
- Filter Elasticsearch from the fixed verification start timestamp through the current check time.
- Missing telemetry, authentication errors, provider errors, and invalid results fail blocking checks.
- Apply Stage-level failed-measurement tolerance with per-check overrides.
- Support blocking, dry-run, and Stage-level `dryRunAll` behavior.

Customer output validation is deferred for later design.

## Pre-production Rules

- Enforce official tag policy before any external call.
- AI enrichment is optional. When enabled, call an internal HTTP AI agent with structured, redacted release evidence and an explicit field-by-field prompt.
- ServiceNow and GitLab may be enabled without AI. In that mode ServiceNow uses values-defined `fixedFields`, while GitLab requires values-defined fixed `title` and `description`.
- AI output fields are `title`, `description`, `reason`, `impact`, `startTime`, and `endTime`.
- The AI proposes a change window three working days forward, skipping Friday, Saturday, and organizational holidays.
- Timezone, start time, and duration are values-driven; the pipeline validates returned timestamps.
- ServiceNow fixed fields are an open map. AI field mapping is optional and partial; unspecified names remain unchanged. Fixed values win.
- GitLab and ServiceNow records are independent and never cross-link.
- Create/reuse both records idempotently and store their titles, URLs, and machine identifiers on Freight.
- Pre-production creates the MR but does not wait for approval or merge.
- Configure squash off, require a commit-preserving merge, and request branch deletion after merge.

## Production Rules

- Production is manual and may wait indefinitely.
- The user explicitly selects the prepared Freight.
- Recheck official tag policy.
- Consume the MR metadata produced by Pre-production; do not duplicate MR lifecycle configuration under Production.
- Merge the MR before deployment, accept an already merged expected revision, and fail on mismatch, conflict, or closed-unmerged state.
- Verify the Production branch contains the tested commit.
- Deploy that exact commit SHA through Argo CD.
- Verification failure sends enabled email, updates ServiceNow, and creates a monitoring alert only in Production.
- Verification success sends enabled email and updates the same ServiceNow change.
- Do not implement automatic rollback yet.

## Notification Rules For Self-managed Kargo

The target environment is self-managed Kargo v1.10, not Akuity Platform. Do not depend on Akuity-only `EventRouter` or `MessageChannel` resources.

- Promotion-only Stages use conditional success/failure notification steps.
- Deployment Stages use chart-owned verification dispatchers to send enabled emails after result aggregation.
- Promotion failures occurring before verification use conditional failure steps.
- Notification delivery failures are retried and recorded but do not replace the original promotion or verification result.
- An outcome sends email only when `outcomes.<result>.notifications.email.enabled` is true.
- Resolve subject/body from the outcome first, then global success/failure message defaults. Enabled email with no resolvable subject/body fails Helm validation.

## Values Interface Direction

Approved top-level order:

```yaml
global: {}
warehouse: {}
sources: {}
pipeline: {}
services: {}
analysisTemplates: []
```

Key structure:

```yaml
global:
  system:
    name: my-system
    displayName: My System
    owner: application-team

sources:
  componentDefaults: {}
  components: []
  chartGit: {}

pipeline:
  notifications: {}
  stages:
    prepareRelease: {}
    dev: {}
    integration: {}
    preProduction: {}
    production: {}

services:
  prometheus: {}
  elasticsearch: {}
  ai: {}
  serviceNow: {}
  gitLab: {}
  mail: {}
  monitoring: {}

analysisTemplates: []
```

AnalysisTemplate entries use:

```yaml
- name: component-qa
  type: smooth # smooth, job, prometheus, http, elasticsearch, external
  target: components # or stage
  retryAmount: 1
  timeout: 30m
  ttlAfterFinished: 6h
  mode: blocking
```

Stages reference template names and may override fields supported by that template type. Stage overrides win. Unknown or incompatible overrides fail validation. External definitions reference existing `AnalysisTemplate` or `ClusterAnalysisTemplate` resources and are not created by Helm.

## Services And Credentials

HTTP service authentication types:

```text
none
basic
apiKey
```

An HTTP endpoint requires `allowInsecureHttp: true`; otherwise HTTP fails validation. `basic` requires username and password. `apiKey` requires header name and key, with an optional prefix.

Every configured Git repository receives a Kubernetes Git credential Secret:

- chart Git
- every component developer Git
- every component QA Git

Repository URL is always included. Username/password must both be set or both empty. Secrets render even when credentials are empty. Never place credentials directly in Stages, AnalysisTemplates, Jobs, logs, Freight metadata, or committed example values.

## Project Documentation

```text
docs/
|-- README.md
|-- architecture.md
|-- warehouse.md
|-- spec.md
|-- chart-completeness-audit.md
`-- stages/
    |-- prepare-release.md
    |-- dev.md
    |-- integration.md
    |-- pre-production.md
    `-- production.md
```

Each Stage file is the design and task authority for its implementation.

## Explicitly Deferred

Do not add these until requested in a later implementation task:

- customer output-validation automation
- automatic rollback
- application/environment undeploy or cleanup
- Stage resources beyond the implementation task currently authorized

The one approved cleanup is deletion of the temporary release branch by GitLab after its merge.

## Validation Workflow

Run after chart implementation changes:

```bash
helm lint ./generic-kargo-pipeline
helm template my-app-promotion ./generic-kargo-pipeline --namespace my-app-promotion
```

Known benign lint output:

```text
[INFO] Chart.yaml: icon is recommended
```
