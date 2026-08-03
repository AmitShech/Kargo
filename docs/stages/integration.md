# Integration Stage Design

## Purpose

The `integration` Stage deploys the same immutable release commit after Dev and validates every enabled Flink component through Prometheus metrics and explicit Elasticsearch failure queries.

Integration receives a copy of Production input data and writes only to isolated Integration sinks. It must not modify, acknowledge, remove, or duplicate Production outputs.

Integration accepts Freight from Dev and uses `MatchUpstream` selection.

## Deployment And Timing

The Stage updates one existing Argo CD Application by `applicationName`. Kargo waits for the Application to become Healthy before explicit verification begins.

At verification start, the dispatcher captures one immutable `verificationStartedAt` timestamp. It then waits the configured `initialDelay` and evaluates checks repeatedly for `duration` at `interval`.

Users configure duration rather than Argo Rollouts `count`. The chart calculates the required measurement count, rounding up when needed. Invalid or excessive schedules fail Helm validation.

## Prometheus Validation

Prometheus checks run for every enabled component on every Freight, including configuration-only Freight.

Each metric defines its PromQL directly. There is no decorative aggregation field; PromQL is the authority for aggregation. Each check provides a minimum, maximum, or acceptable range and a blocking or dry-run mode.

Labels merge from least to most specific:

```text
service labels < template labels < target labels < metric labels
```

The more specific value wins. `{{ labels }}` is replaced with the safely escaped merged selector and `{{ window }}` with the effective query window.

Initial Flink checks include job running time, restarts, failed checkpoints, checkpoint duration, checkpoint age, backpressure, and other system-selected metrics. Exact exported series names must be verified against the installed Flink Prometheus reporter scope.

Missing Prometheus data, connection errors, authentication errors, or invalid result shapes count as failures for blocking checks.

## Elasticsearch Validation

Elasticsearch validation contains only explicit, named failure conditions. There is no catch-all `ERROR` query.

Each component target may set an index and filters. Service filters, template filters, target filters, and check filters merge with the most specific value winning.

Every query automatically adds a timestamp range:

```text
@timestamp >= verificationStartedAt
@timestamp <= current check time
```

The configured `services.elasticsearch.timeField` replaces `@timestamp` when needed. A fixed verification-start timestamp prevents old release errors from failing the candidate and prevents earlier validation errors from falling out of a moving window.

Missing indices/data or Elasticsearch API errors count as failures for blocking checks.

## Result Aggregation

Prometheus and Elasticsearch child AnalysisRuns start in parallel after the initial delay. Checks repeat for the configured duration. The Stage-level `allowedFailedMeasurements` applies unless a metric or check overrides it.

The dispatcher waits for all results. Any blocking result beyond its tolerance fails Integration. Dry-run results remain visible but do not block. Stage-level `dryRunAll` makes every metric advisory and removes the need to enumerate metric names.

After aggregation, the dispatcher sends the enabled outcome email and returns the original result. Notification delivery failure does not turn a successful validation into a failure.

Customer output approval automation is deferred. A future `output-validation` template may automate deterministic sink comparisons, while subjective acceptance remains manual.

## Values Contract

```yaml
pipeline:
  stages:
    integration:
      name: integration
      autoPromotionEnabled: true
      freightSelectionPolicy: MatchUpstream
      argocd:
        applicationName: my-app-integration
      tagPolicy: {}
      verification:
        enabled: true
        mode: blocking
        initialDelay: 15m
        duration: 10m
        interval: 1m
        allowedFailedMeasurements: 1
        analysisTemplates:
          - name: flink-metrics
            enabled: true
          - name: flink-errors
            enabled: true
      outcomes: {}

services:
  prometheus:
    endpoint: http://prometheus.monitoring:9090
    labels: {}
    authentication:
      type: none
  elasticsearch:
    endpoint: http://elasticsearch.logging:9200
    index: flink-integration-*
    timeField: "@timestamp"
    filters: {}
    authentication:
      type: basic
      username: ""
      password: ""

analysisTemplates:
  - name: flink-metrics
    type: prometheus
    target: components
    retryAmount: 1
    timeout: 30m
    ttlAfterFinished: 6h
    mode: blocking
    targets:
      - component: payment
        labels:
          job_name: payment-stream
    metrics:
      - name: flink-job-restarts
        query: >-
          max(flink_jobmanager_job_numRestarts{ {{ labels }} })
        maximum: 0
        mode: blocking

  - name: flink-errors
    type: elasticsearch
    target: components
    retryAmount: 1
    timeout: 30m
    ttlAfterFinished: 6h
    mode: blocking
    targets:
      - component: payment
        index: payment-integration-*
        filters:
          component.keyword: payment
    checks:
      - name: checkpoint-failure
        query:
          bool:
            filter:
              - term:
                  event.code: FLINK_CHECKPOINT_FAILED
        maximumCount: 0
        mode: blocking
```

## Implementation Checklist

The chart-side items below are implemented as rendered dispatcher contracts and retained as maintenance checks. Their execution requires the configured external dispatcher image.

- Add the Integration Stage with exact-commit Argo CD deployment.
- Implement generic `prometheus` and `elasticsearch` template types.
- Implement target expansion for every enabled component.
- Implement label/filter precedence and safe query rendering.
- Capture and reuse `verificationStartedAt`.
- Calculate measurement count from duration and interval.
- Implement global and per-check failed-measurement tolerances.
- Treat missing telemetry and provider errors as failures for blocking checks.
- Implement parallel child runs, complete aggregation, dry-run, and `dryRunAll`.
- Validate dispatcher-based success/failure email arguments against the externally supplied dispatcher image interface.
- Validate provider services only when their templates are active.
- Verify Flink metric series names in the target Prometheus installation.
- Add schema, Helm validation, render, and failure-mode tests.

## Acceptance Criteria

- Every enabled Flink component is checked for every Integration Freight.
- Checks begin only after Argo CD health and the configured delay.
- No old-release logs enter the validation window.
- Only explicit Elasticsearch conditions block promotion.
- Missing telemetry cannot be interpreted as a successful zero value.
- All blocking checks must pass within their configured tolerance.

## References

- [Kargo: Verifying Freight in a Stage](https://docs.kargo.io/user-guide/how-to-guides/verification)
- [Apache Flink metrics](https://nightlies.apache.org/flink/flink-docs-stable/docs/ops/metrics/)
