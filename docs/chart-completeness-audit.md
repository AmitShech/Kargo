# Chart Completeness Audit

## Boundary

Completion is measured at the Helm boundary: values schema processing, template validation, rendered Kargo/Kubernetes resources, and static render assertions. The repository does not build dispatcher or Smooth images, install the chart, create Argo CD Applications, operate external services, or call live clusters and APIs.

## Requirement map

| Contract | Chart implementation | Acceptance evidence |
|---|---|---|
| Integration timing and request bound | `durationSeconds` and `measurementCount` helpers; Integration dispatcher configuration | Exact and rounded counts, zero duration, and maximum-count fixtures |
| Component Integration configuration | Prometheus label and Elasticsearch filter/index merging in the Integration dispatcher template | Two-component fixture with different selectors and index |
| Tolerance and dry-run precedence | Effective `failureLimit`, check mode, and `dryRunAll` dispatcher fields | Blocking and dry-run render assertions |
| External analysis resources | External dispatcher AnalysisTemplate, flat Stage arguments, kind/resource identity, and per-reference lifecycle overrides | Cluster template, zero-retry override, mode/tolerance overrides, defaults, required arguments, and no external-resource ownership assertions |
| Optional AI enrichment | Pre-production HTTP outputs, exact required-field contract, schedule validation expressions, and a terminal guard that prevents invalid AI fallback schedules from reaching external administration | AI, invalid-field, schedule-expression, failure-guard, and fixed-only fixtures |
| ServiceNow idempotency | Freight-correlated lookup, conditional create, normalized record output, final field map | Separate title/number/URL/sys_id and wrapper-leak assertions |
| GitLab MR lifecycle | URL-encoded project identity, existing-MR lookup, conditional create, normalized MR output, and commit-preserving/source-branch lifecycle policy | Content, encoded path, unsafe-policy rejection, independence, lifecycle, and metadata assertions |
| Truthful Pre-production state | Final metadata step after enabled operations; explicit enabled/completed and `administration-mode` values | Enabled combinations and fixed-only fixtures |
| Unified tag policies | Shared `tagPolicySteps` helper used by all five Stages | Default and enabled Stage renders |
| Freight selection | Kargo `stageSelector` promotion policies and per-request `autoPromotionOptions.selectionPolicy` | Five-policy and five-Stage selection assertions |
| Production MR paths | Expected-revision check with explicit HTTP outputs, conditional open-MR merge, accepted already-merged path, branch containment | Ordering, output, and expression assertions |
| Self-managed email | Conditional HTTP promotion steps and post-verification dispatcher mail contracts | Promotion-only and deployment fixtures |
| Production finalization | Production dispatcher outcome contract plus no-verification success ServiceNow/email handling and promotion-failure handling; failure-only monitoring | Verified and no-verification Production finalizer fixtures |
| Conditional validation | JSON schema plus `validateValues` cross-object/type checks | Missing endpoints, credentials, timing, component defaults/targets, active references, unknown fields, and inactive-definition fixtures |
| Credential isolation | Repository and HTTP Secrets; expression/Secret references in Stages and AnalysisTemplates | Static per-document credential scan |
| Immutable Freight | Release evidence metadata, unconditional developer Git tag resolution, and exact `release-commit` deployment in Dev, Integration, and Production | Generation-disabled evidence fixture and three exact-revision render assertions |

## External runtime prerequisites

- Self-managed Kargo v1.10 and the Kargo/Argo Rollouts CRDs.
- Existing Argo CD Applications named by each deployment Stage.
- A prebuilt dispatcher image implementing the rendered `DISPATCHER_CONFIG` contracts.
- Smooth and QA preparation images for active Smooth verification.
- Reachable Git repositories and any enabled Prometheus, Elasticsearch, AI, ServiceNow, GitLab, mail, and monitoring endpoints.
- External `AnalysisTemplate` or `ClusterAnalysisTemplate` resources referenced by external definitions.

These prerequisites are deployment concerns, not resources owned by this chart. Runtime compatibility still must be verified by the chart consumer against its installed images, APIs, credentials, and CRDs.

The AI service owns organizational holiday knowledge and the calculation of three working days. The chart supplies that policy in the request and validates the returned field set, timestamp ordering, configured clock, duration, and excluded weekdays. Live holiday correctness cannot be proven by Helm rendering alone.

## Audit commands

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\generic-kargo-pipeline\tests\run.ps1
git diff --check
```

The suite performs Helm lint, default rendering, enabled multi-component rendering, external-reference rendering, negative validation, outcome rendering, exact-revision assertions, and static credential checks without Kubernetes, Argo CD, Go, Docker, a registry, or live external APIs.
