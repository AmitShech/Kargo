# Production Stage Design

## Purpose

`production` is the only manually promoted Stage. A Freight may wait indefinitely after Pre-production. The user explicitly selects the prepared Freight; Production never resolves "latest" at execution time.

Production:

1. Rechecks official tag policy.
2. Approves/merges the merge request created by Pre-production.
3. Verifies the production branch contains the tested release commit.
4. Deploys that exact commit through Argo CD.
5. Optionally runs post-deployment verification.
6. Updates ServiceNow and sends outcome notifications.

## Manual Selection And Merge

The user-facing selection view should emphasize:

- Freight identity
- release commit SHA
- component tags and digests
- Dev and Integration verification history
- GitLab merge-request title and URL
- ServiceNow title, number, and URL

Automation uses GitLab project path/IID and ServiceNow `sys_id`.

Enabling either Production ServiceNow outcome requires Pre-production ServiceNow creation. Helm rejects the configuration otherwise, because Production must update the exact change record identified in Freight metadata.

On manual promotion, Production:

1. Confirms the merge request source revision equals the tested release commit.
2. Merges without squash or rebase.
3. Accepts an already merged MR only when it contains the expected commit.
4. Fails on a closed-unmerged MR, revision mismatch, merge conflict, or unsupported merge strategy.
5. Confirms the configured production branch contains the tested commit.

GitLab removes the temporary release branch after successful merge. Preserving the commit in the production branch keeps the exact SHA reachable without a separate release tag.

## Deployment

The Stage updates one existing Argo CD Application by `applicationName`. The Application owns its destination namespace. Desired revision is the exact prepared and tested release commit, never the branch head or newest commit.

Merge failure blocks deployment. Production does not rebuild, retag, or replace the application artifact.

## Optional Verification

Production verification is optional. When disabled, Production still waits for Argo CD health. When enabled, it references reusable templates such as an HTTP smoke-check definition.

The dispatcher waits for all Production checks, determines the original verification result, then performs outcome integrations.

Success:

- update the existing ServiceNow change with configured fields
- send email when enabled

Failure:

- update the existing ServiceNow change with configured fields
- send email when enabled
- create a monitoring-system HTTP alert when enabled

Verification failure does not automatically roll back. Notification, monitoring, or ServiceNow synchronization failure is retried and recorded but does not change an already successful deployment/verification result.

## Values Contract

```yaml
pipeline:
  stages:
    production:
      name: production
      autoPromotionEnabled: false
      freightSelectionPolicy: MatchUpstream
      argocd:
        applicationName: my-app-production
      tagPolicy: {}
      verification:
        enabled: true
        mode: blocking
        analysisTemplates:
          - name: production-health
            enabled: true
      outcomes:
        success:
          notifications:
            email:
              enabled: true
          serviceNow:
            enabled: true
            fixedFields: {}
        failure:
          notifications:
            email:
              enabled: true
            monitoringAlert:
              enabled: true
          serviceNow:
            enabled: true
            fixedFields: {}

services:
  mail: {}
  monitoring: {}
  serviceNow: {}

analysisTemplates:
  - name: production-health
    type: http
    target: stage
    retryAmount: 1
    timeout: 10m
    ttlAfterFinished: 6h
    mode: blocking
    checks:
      - name: application-health
        url: http://my-app-production/health
        expectedStatus: 200
        mode: blocking
```

The merge-request settings are not duplicated here. They belong to `pipeline.stages.preProduction.gitLab.mergeRequest`; Production consumes the prepared MR metadata.

## Implementation Checklist

The chart-side items below are implemented as promotion and dispatcher contracts and retained as maintenance checks. Dispatcher execution and live API compatibility remain deployment prerequisites.

- Add the Production Stage with auto-promotion disabled by default.
- Require explicit Freight selection and consume Pre-production metadata.
- Recheck official tag policy.
- Implement idempotent MR merge/verification before deployment.
- Verify the production branch contains the exact tested commit.
- Deploy only the immutable commit SHA through Argo CD.
- Implement generic HTTP verification and dispatcher aggregation.
- Implement ServiceNow success/failure updates against the stored `sys_id`.
- Implement Production-failure-only monitoring alert creation.
- Implement dispatcher-finalized email and integration retries.
- Preserve original deployment and verification results when secondary integrations fail.
- Add schema, render, manual-policy, merge-state, exact-revision, and outcome tests.

## Acceptance Criteria

- Production cannot auto-promote by default.
- No unpermitted tag reaches merge or deployment.
- Merge failure prevents deployment.
- Argo CD receives the exact Dev/Integration-tested commit.
- Success and failure update the same ServiceNow change.
- Monitoring alerts occur only for Production verification failure.
- No automatic rollback occurs.
