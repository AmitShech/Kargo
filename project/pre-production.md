# Pre-production Stage Design

## Purpose

`pre-production` performs release-administration work after Integration verification. It does not control an Argo CD Application.

The Stage:

1. Enforces official tag policy.
2. Optionally produces a structured AI release summary, or uses values-defined fixed content.
3. Creates or reuses a ServiceNow change.
4. Creates or reuses a GitLab merge request for the prepared release branch.
5. Records human-readable titles, URLs, and immutable identifiers in Freight metadata.

The ServiceNow change and GitLab merge request are independent and must not cross-link each other.

## Official Tag Gate

Pre-production accepts only tags matching its configured allowed patterns and rejects development, snapshot, release-candidate, and other configured patterns. Every enabled component must pass before any external record is created.

Development tags may pass through Dev and Integration. After successful validation, developers publish an official image tag pointing to the exact same image digest and a matching developer Git tag pointing to the same source commit. The official Freight repeats Dev and Integration, then becomes eligible for Pre-production.

Configuration-only Freight may proceed when all referenced component tags are already official.

## AI Release Summary

AI enrichment is optional. When enabled, the Stage calls an internal HTTP AI agent. Connection settings and authentication live under `services.ai`; the field-by-field prompt and schedule live under `preProduction.ai`.

ServiceNow and GitLab do not depend on AI. With AI disabled, ServiceNow uses its values-defined `fixedFields`, and GitLab uses required values-defined fixed `title` and `description`.

The request contains only approved evidence:

- system and changed-component identities
- selected tags and digests
- tag/release messages
- changed chart paths and bounded, redacted configuration differences
- Dev and Integration validation results
- current date and configured timezone

The AI returns JSON fields:

```text
title
description
reason
impact
startTime
endTime
```

For one changed component, the title begins with the component display name. For multi-component or system-wide changes, it begins with `global.system.displayName`.

The AI schedules the change three working days forward, skipping Friday, Saturday, and organizational holidays. The AI owns holiday knowledge. The pipeline validates field presence, timestamp format, weekday, configured start time, ordering, and configured duration.

The AI does not approve a release, change immutable artifacts, select risk policy, or invent unsupported facts. Invalid or unavailable AI output produces deterministic diagnostic fallback text, then a terminal guard fails Pre-production before ServiceNow or GitLab is called. To operate without AI, disable AI and provide the required fixed values explicitly.

## ServiceNow Creation

`fixedFields` is an open values-driven map for permanent organization fields. AI fields keep their names by default. Optional partial `aiFieldMapping` renames only listed fields. Fixed fields win over generated fields.

The Stage uses a Freight-derived correlation key so retry reuses an existing change instead of creating a duplicate. It records ServiceNow title, number, URL, and `sys_id` in Freight metadata. Automation uses `sys_id`; users see title, number, and URL.

Pre-production only creates the change. It does not wait for ServiceNow approval.

## GitLab Merge Request Creation

The Stage creates a merge request from the prepared release branch to `sources.chartGit.branches.production`. It derives the GitLab project path from the chart Git repository URL; an explicit override is required only if the URL cannot be parsed.

The merge request:

- uses the AI title and description when AI is enabled, otherwise its configured fixed title and description
- contains no ServiceNow identifiers or links
- disables squash
- requires a commit-preserving merge strategy
- requests source-branch removal after merge

Retry reuses the merge request correlated with the Freight/source branch. Freight metadata stores the title, URL, project path, and IID. Production consumes those identifiers.

Pre-production does not wait for approval or merge. Manual Production promotion performs the merge.

## Partial Failure And Notification

Both ServiceNow and GitLab records are required for successful Pre-production completion. If one is created before the other fails, retry must discover and reuse the existing record.

Success and failure emails run through conditional promotion steps because Pre-production has no verification dispatcher. Notification delivery failure does not replace the underlying promotion result.

## Values Contract

```yaml
pipeline:
  stages:
    preProduction:
      name: pre-production
      autoPromotionEnabled: true
      freightSelectionPolicy: MatchUpstream
      tagPolicy: {}
      ai:
        enabled: true
        schedule:
          timezone: Asia/Jerusalem
          workingDaysAhead: 3
          startTime: "13:00"
          durationMinutes: 15
          excludedWeekdays: [Friday, Saturday]
        requiredFields: [title, description, reason, impact, startTime, endTime]
        prompt: |-
          Return JSON only.
          Populate every required field from supplied release evidence.
      serviceNow:
        enabled: true
        fixedFields: {}
        aiFieldMapping: {}
      gitLab:
        enabled: true
        mergeRequest:
          squash: false
          removeSourceBranchWhenMerged: true
          requireCommitPreservingMerge: true
      outcomes: {}

services:
  ai: {}
  serviceNow: {}
  gitLab:
    authentication:
      type: none
```

## Implementation Checklist

The chart-side items below are implemented and retained as maintenance checks. Live API compatibility remains a deployment prerequisite.

- Add the Pre-production Stage requesting verified Integration Freight.
- Add reusable HTTP service authentication types: `none`, `basic`, and `apiKey`.
- Add explicit `allowInsecureHttp` validation for HTTP endpoints.
- Implement official tag-policy checks before external calls.
- Define and validate the AI request/response schema and prompt.
- Implement schedule validation and deterministic fallback content.
- Implement ServiceNow create-or-reuse behavior with fixed fields and partial field mapping.
- Implement GitLab MR create-or-reuse behavior without ServiceNow cross-links.
- Validate commit-preserving merge settings against GitLab when supported.
- Store complete ServiceNow and GitLab metadata on Freight.
- Implement idempotent partial-failure recovery.
- Add conditional outcome email steps and templates.
- Add schema, secret, render, idempotency, and failure-mode tests.

## Acceptance Criteria

- No development/unpermitted tag can create external records.
- Repeated promotion does not create duplicate records.
- AI output is structured, validated, bounded by evidence, and non-authoritative.
- ServiceNow contains customer-facing feature, downtime, impact, and reason information without GitLab links.
- GitLab contains no ServiceNow identifiers.
- Production receives stable identifiers for both prepared records.
