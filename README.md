# Kargo Promotion Pipeline

This repository contains a reusable, values-driven Helm chart for a five-stage promotion pipeline on self-managed Kargo v1.10.

```text
Warehouse -> Prepare release -> Dev -> Integration -> Pre-production -> Production
```

Everything before Production is automatic. Production waits for explicit Freight selection and deploys the exact commit that passed the earlier environments.

## Repository layout

```text
.
|-- AGENTS.md                     Project rules for maintainers and coding agents
|-- docs/                         Architecture, specification, audit, and Stage designs
`-- generic-kargo-pipeline/       Installable Helm chart
    |-- examples/                 Complete values examples
    |-- templates/
    |   |-- analysis-templates/   Managed and dispatcher AnalysisTemplates
    |   |-- rbac/                 Dispatcher permissions
    |   |-- secrets/              Git and HTTP credential Secrets
    |   `-- stages/               Five Kargo Stage resources
    |-- tests/
    |   |-- fixtures/             Focused render-test values
    |   `-- run.ps1               Chart acceptance suite
    |-- values.yaml               Default chart interface
    `-- values.schema.json        Helm values schema
```

## Start here

- [Chart usage](generic-kargo-pipeline/README.md)
- [Full-feature values example](generic-kargo-pipeline/examples/values-all-features.yaml)
- [Documentation index](docs/README.md)
- [Approved specification](docs/spec.md)
- [Chart completeness audit](docs/chart-completeness-audit.md)

## Quick validation

```powershell
helm lint .\generic-kargo-pipeline
helm template my-system .\generic-kargo-pipeline --namespace my-system
powershell.exe -ExecutionPolicy Bypass -File .\generic-kargo-pipeline\tests\run.ps1
```

The repository delivers Helm templates and static acceptance tests. The configured dispatcher image, Kargo/Argo Rollouts CRDs, Argo CD Applications, and live external services are deployment prerequisites.
