# Dev Stage Design

## Purpose

The `dev` Stage deploys the immutable release commit created by `prepare-release` and optionally runs component QA through native Kargo verification.

Dev accepts Freight only from `prepare-release` and normally uses `MatchUpstream` selection.

## Deployment

The Stage updates the configured Argo CD Application by name:

```yaml
argocd:
  applicationName: my-app-dev
```

The destination namespace remains owned by the Argo CD Application and is not repeated in chart values. Kargo sets the Application source revision to the exact release commit stored in Freight metadata. It does not rebuild or replace any application artifact.

The Application must authorize the Dev Stage, and its repository URL must match `sources.chartGit.repository.url`.

## Optional Verification

Verification is a bonus capability. When `verification.enabled` is false, Dev still deploys normally and relies on Argo CD health. Inactive AnalysisTemplates do not require QA values and do not fail Helm validation.

When the `smooth` template is active, every enabled component must resolve:

- QA repository URL
- QA repository branch, supplied on the component or through `componentDefaults`
- QA repository credentials, with username and password both set or both empty
- QA directory path, defaulting to `.`

The filename is fixed as `.smooth.yaml`. Smooth executes directly from the cloned QA branch using fixed chart-owned behavior equivalent to:

```text
smooth run --file .smooth.yaml --skip-install
```

`--skip-install` preserves Argo CD as the sole application deployment owner.

## Changed-component Selection

The chart-owned Dev dispatcher consumes `changedComponents` metadata produced by `prepare-release`.

```yaml
runForChangedComponentsOnly: true
```

creates child AnalysisRuns only for components whose selected tags differed from their tags in the Freight's chart Git input.

```yaml
runForChangedComponentsOnly: false
```

runs QA for every enabled component, including configuration-only Freight.

Smooth contains no change-selection logic. The dispatcher decides which component verifications to create.

## Dispatcher And Child AnalysisRuns

Kargo creates one parent verification AnalysisRun. Its dispatcher:

1. Resolves the selected component set.
2. Creates one child AnalysisRun per selected component.
3. Clones that component's configured QA branch.
4. Runs Smooth directly from `<qa.path>/.smooth.yaml`.
5. Limits simultaneous child runs with `parallelismLimit`.
6. Retries only failed components according to the effective template settings.
7. Waits for every child result, even after one fails.
8. Sends an enabled success or failure email after aggregation.
9. Returns success only when all required child runs succeed.

The dispatcher needs narrowly scoped permission to create, read, watch, and clean up AnalysisRuns in the project namespace.

QA branches are intentionally moving references. The application candidate remains immutable, but rerunning the same Freight may execute newer QA code from the configured branch.

## Failure Behavior

A failed component does not prevent newer Freight from being created or eventually promoted. It blocks only the failing Freight from moving downstream. Newer Freight may enter Dev after the current verification reaches a terminal state.

Promotion failures before verification use a conditional failure notification step. Verification outcomes use the dispatcher because they occur after promotion steps finish.

## Values Contract

```yaml
sources:
  componentDefaults:
    qa:
      repository:
        branch: main
      path: .

  components:
    - name: payment
      qa:
        repository:
          url: https://gitlab.example.com/qa/payment.git
          username: ""
          password: ""
        path: .

pipeline:
  stages:
    dev:
      name: dev
      autoPromotionEnabled: true
      freightSelectionPolicy: MatchUpstream
      argocd:
        applicationName: my-app-dev
      tagPolicy: {}
      verification:
        enabled: true
        mode: blocking
        analysisTemplates:
          - name: component-qa
            enabled: true
            runForChangedComponentsOnly: true
            parallelismLimit: 3
            mode: blocking
      outcomes: {}

analysisTemplates:
  - name: component-qa
    type: smooth
    target: components
    runForChangedComponentsOnly: true
    parallelismLimit: 3
    retryAmount: 1
    timeout: 30m
    ttlAfterFinished: 6h
    mode: blocking
```

Stage reference values override supported values on the reusable template definition. Unknown or type-incompatible overrides fail validation.

## Implementation Checklist

The chart-side items below are implemented and retained as maintenance checks.

- Validate the rendered dispatcher Job contract against the externally supplied dispatcher image interface.
- Add per-component QA Git configuration and Secrets.
- Read credentials from Secrets; never embed them in AnalysisTemplates or Jobs.
- Fix `.smooth.yaml` as the filename and validate safe relative QA directory paths.
- Implement `runForChangedComponentsOnly` and `parallelismLimit`.
- Implement child AnalysisRun aggregation and component-only retries.
- Wait for all selected child results before setting the parent result.
- Add conditional validation based on active template type.
- Add success/failure notification finalization without changing the original verification result.
- Verify the exact installed Smooth CLI syntax for direct execution and `--skip-install`.
- Add render and behavior tests for zero, one, and multiple changed components; disabled verification; failure aggregation; and Stage overrides.

## Acceptance Criteria

- Argo CD deploys the exact prepared commit.
- Smooth never installs the application.
- The dispatcher, not Smooth, selects changed components.
- All selected component results are retained and aggregated.
- Disabled verification imposes no QA configuration requirement.
- Failed Freight is blocked downstream without globally blocking newer Freight.

## References

- [Kargo: Verifying Freight in a Stage](https://docs.kargo.io/user-guide/how-to-guides/verification)
