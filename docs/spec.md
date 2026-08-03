# Generic Kargo Promotion Pipeline Specification

Status: Chart implementation complete at the declared Helm boundary; external runtime validation required

Target: Self-managed Kargo v1.10

Artifact: Reusable, values-driven Helm chart

## Problem Statement

Application teams need a repeatable Kargo promotion pipeline without copying and modifying environment-specific Kubernetes resources for every system. The pipeline must prepare a release, deploy and validate it through Dev and Integration, prepare the administrative records required for Production, and then wait indefinitely for a user to approve the Production promotion.

Each release may contain new tags for one or more independently configured Flink components. Development tags must be testable without being eligible for Pre-production or Production. Every Freight must remain standalone, and every environment must deploy the exact immutable candidate represented by that Freight rather than deriving state from another Freight, a previous Stage, or the latest branch revision.

Verification requirements vary by Stage and system. Dev needs per-component Smooth QA from separate QA repositories. Integration needs threshold-based Prometheus checks and explicit Elasticsearch failure checks. Production may need post-deployment validation, ServiceNow updates, email notifications, and a monitoring alert on failure. Teams must be able to enable, disable, select, and configure these validations entirely through values without editing chart templates.

Release administration requires customer-facing change information, a ServiceNow change, and a GitLab merge request. AI may enrich the change information, but ServiceNow and GitLab can operate from values-defined fixed content when AI is disabled. These records must be idempotent and independent: neither GitLab nor ServiceNow should link to the other. Credentials and system-specific data must remain outside generated workload definitions and be represented safely in Kubernetes Secrets.

## Solution

Provide a generic Helm chart that renders a Kargo Project, Warehouse, five-Stage promotion flow, reusable verification definitions, dispatchers, RBAC, and credentials according to a single values interface.

The implementation boundary ends at validated Helm rendering. Dispatcher behavior is expressed as Job configuration and RBAC referencing a consumer-supplied, prebuilt image. Building or publishing that image, installing the chart, operating external services, and exercising live clusters or APIs are outside this repository's deliverable.

The Warehouse discovers standalone Freight. Prepare-release creates one immutable chart Git commit and records changed-component evidence. Dev deploys that commit and optionally dispatches Smooth QA. Integration deploys the same commit and optionally validates every enabled Flink component with Prometheus and Elasticsearch. Pre-production accepts only official tags, asks an internal AI agent to produce structured change fields, and independently creates or reuses ServiceNow and GitLab records. Production waits for explicit Freight selection, merges the prepared merge request, verifies that the tested commit is on the Production branch, deploys that exact commit, performs optional post-validation, and publishes configured outcomes.

The chart defines reusable AnalysisTemplate entries once and lets Stages reference them by name with compatible overrides. Disabled verification is a valid no-op. Enabling a template activates strict, type-specific validation. Values own all system-specific repositories, paths, tags, labels, queries, thresholds, prompts, endpoints, fixed fields, notification content, and credentials.

## User Stories

1. As an application team, I want to configure a complete promotion pipeline through Helm values, so that I can reuse the chart without editing its templates.
2. As a release manager, I want each Freight to contain all evidence needed to interpret the release, so that promotion never depends on another Freight or Stage history.
3. As a release manager, I want the same immutable application candidate promoted through every environment, so that Production runs exactly what was tested.
4. As an auditor, I want component tags, image digests, source revisions, chart input revision, release branch, and release commit preserved, so that a deployed release is traceable.
5. As a developer, I want a component image tag to correspond to its developer Git tag, so that binaries and source are consistently identified.
6. As a developer, I want `dev-*` tags to pass Prepare-release, Dev, and Integration, so that candidate fixes can be tested before an official release exists.
7. As a release manager, I want Pre-production and Production to reject development tags before external calls, so that only official releases create administrative records or reach Production.
8. As a developer, I want an official tag to point to the exact digest and source commit already tested under a development tag, so that officialization does not change the candidate.
9. As a release manager, I want the official tag to create new standalone Freight and repeat Dev and Integration, so that it has its own verification history.
10. As a chart consumer, I want allowed and denied tag patterns configurable for every Stage, so that organizational naming policies are enforceable.
11. As a chart consumer, I want component tag policies to add stricter rules and denied patterns to win, so that local safety restrictions cannot be weakened accidentally.
12. As a release manager, I want Prepare-release to compare each selected Freight tag with the tag stored in that Freight's chart Git revision, so that changed components are detected without relying on deployed state.
13. As a release manager, I want missing release files or tag paths to fail preparation, so that incomplete candidates are not promoted.
14. As a release manager, I want all prepared component changes committed once without force-pushing, so that the immutable release commit is deterministic and reviewable.
15. As an operator, I want Dev, Integration, and Production each to control one existing Argo CD Application by name, so that Argo CD remains the deployment owner.
16. As an operator, I want Argo CD Applications to retain ownership of destination namespaces, so that namespace configuration is not duplicated by this chart.
17. As a QA engineer, I want Smooth definitions to remain in each component's separate QA repository and configured branch, so that QA code remains independently maintained.
18. As a QA engineer, I want Smooth to execute directly with `.smooth.yaml` and `--skip-install`, so that tests run without taking over application deployment.
19. As a QA engineer, I want the Kargo dispatcher to choose components, so that Smooth does not need release-comparison logic.
20. As a QA engineer, I want to run Smooth only for changed components or for all enabled components, so that each pipeline can trade speed for broader regression coverage.
21. As an operator, I want a configurable parallelism limit and per-component retries, so that QA load is bounded and transient failures can recover independently.
22. As a release manager, I want Dev to wait for all selected QA results and aggregate once, so that downstream promotion reflects the complete test outcome.
23. As an integration engineer, I want every enabled Flink component validated for every Integration Freight, so that configuration-only releases are covered too.
24. As an integration engineer, I want checks to begin after Argo CD health and a configurable initial delay, so that startup transients do not produce false failures.
25. As an integration engineer, I want validation to run for a configured duration and interval, so that health is observed over time instead of by a single sample.
26. As an integration engineer, I want each PromQL expression to define its own aggregation and threshold, so that checks are explicit and no decorative aggregation is applied twice.
27. As an integration engineer, I want common Prometheus labels merged with template, target, and metric labels using most-specific-wins precedence, so that shared configuration remains overridable.
28. As an integration engineer, I want Elasticsearch to query only named failure conditions since verification began, so that unrelated historical errors do not fail a release.
29. As an integration engineer, I want missing telemetry, authentication errors, provider errors, malformed queries, and invalid results to fail blocking checks, so that an unavailable signal is not treated as success.
30. As an integration engineer, I want blocking, dry-run, and whole-Stage dry-run modes, so that new checks can be observed before enforcement.
31. As a chart consumer, I want reusable Smooth, Job, Prometheus, HTTP, Elasticsearch, and external analysis definitions, so that Stages compose verification by name.
32. As a chart consumer, I want Stage references to override only fields supported by their template type, so that customization remains valid and predictable.
33. As a chart consumer, I want disabled verification to require no template-specific configuration, so that deployment can succeed without unused service settings.
34. As a chart consumer, I want enabled templates to validate every required parameter, so that configuration errors fail during Helm processing rather than during promotion.
35. As a platform engineer, I want external AnalysisTemplate and ClusterAnalysisTemplate resources referenceable without Helm creating them, so that organization-owned checks can be reused.
36. As a change manager, I want an internal AI agent to receive structured, redacted release evidence, so that it can create accurate customer-facing change content without seeing credentials.
37. As a change manager, I want the AI to return title, description, reason, impact, start time, and end time, so that the ServiceNow change contains every required generated field.
38. As a change manager, I want the title formatted around the component or system and the change being made, so that customers can identify the release quickly.
39. As a change manager, I want the AI to propose a configurable-duration window three working days forward while skipping Friday, Saturday, and organizational holidays, so that the change follows scheduling policy.
40. As a change manager, I want pipeline validation of AI timestamps and deterministic fallback content for invalid AI output, so that automation remains safe and explainable.
41. As a ServiceNow administrator, I want permanent request fields configured as an open values map, so that organization-specific fields require no chart changes.
42. As a ServiceNow administrator, I want optional partial AI-field renaming with unchanged names by default and fixed fields winning, so that API payloads are flexible but controlled.
43. As a release manager, I want ServiceNow creation to be idempotent and not wait for approval, so that Pre-production can finish without duplicate changes or an indefinite pause.
44. As a GitLab user, I want Pre-production to create or reuse a merge request containing AI-generated or values-defined fixed title and description, so that the release is ready for later Production approval.
45. As a GitLab user, I want the merge request to show its title and URL while retaining its machine IID internally, so that humans see meaningful context and automation has a stable identifier.
46. As a security stakeholder, I want the GitLab merge request and ServiceNow change to remain independent and not cross-link, so that the systems disclose only their intended information.
47. As a release manager, I want the merge request created without squash or rebase and its source branch deleted after merge, so that the tested commit is preserved and temporary branches are cleaned up.
48. As a release manager, I want Production promotion to be manual and able to wait indefinitely, so that deployment occurs only when an authorized user selects Freight.
49. As a release manager, I want Production to merge the exact merge request prepared earlier and accept an already merged request only at the expected revision, so that the administrative workflow cannot substitute another release.
50. As an operator, I want Production to verify that the Production branch contains the tested commit before deployment, so that Argo CD receives an approved immutable revision.
51. As an operator, I want successful Production verification to update ServiceNow and optionally send email, so that the release outcome is visible.
52. As an operator, I want failed Production verification to update ServiceNow, optionally send email, and optionally raise a monitoring alert, so that failure receives immediate operational attention.
53. As an operator, I want monitoring alerts restricted to Production verification failures, so that lower-environment test failures do not create operational incidents.
54. As a notification owner, I want email sent only when the relevant outcome explicitly enables it, so that notification behavior is intentional.
55. As a notification owner, I want outcome-specific subject and body to override global success or failure defaults, so that messages can be tailored without duplication.
56. As a chart consumer, I want enabled email without resolvable recipients, subject, or body to fail Helm validation, so that silent misconfiguration is prevented.
57. As an operator, I want notification delivery failures retried and recorded without replacing the original release outcome, so that reporting failures do not falsify deployment status.
58. As a security engineer, I want one Kubernetes Git credential Secret for every configured chart, developer, and QA repository, so that repository access is isolated and explicit.
59. As a security engineer, I want repository URLs always present and username/password either both set or both empty, so that Secrets are complete and consistently validated.
60. As a security engineer, I want HTTP services to support none, basic, or API-key authentication and require explicit opt-in for insecure HTTP, so that endpoints are configured deliberately.
61. As a security engineer, I want credentials excluded from Stages, AnalysisTemplates, Jobs, logs, Freight metadata, and committed examples, so that secrets are not leaked.
62. As a release manager, I want a failed Freight blocked downstream without stopping discovery or later Freight, so that one bad release does not freeze the pipeline.

## Implementation Decisions

- The deployment flow consists of Warehouse, Prepare-release, Dev, Integration, Pre-production, and Production. Everything before Production is automatic; Production auto-promotion defaults to disabled.
- Freight is the immutable release contract. Preparation uses only artifacts in the selected Freight and records all revisions and changed-component evidence needed downstream.
- The approved configuration-repository term is `chartGit`. The approved overlay term is `chartOverlayPath`. Older deployment-oriented names are migration work.
- Component change detection compares the selected image tag with the tag at the configured literal YAML path in the target Freight's chart Git input revision before any file update.
- The tag mapping is a literal YAML path and is never evaluated as a Helm template expression.
- Dev, Integration, and Production update exactly one existing Argo CD Application each. Prepare-release and Pre-production do not control Argo CD Applications.
- Explicit validation uses native Kargo Stage verification rather than promotion steps.
- Reusable analysis definitions are declared once and referenced by name. Supported types are Smooth, Job, Prometheus, HTTP, Elasticsearch, and external.
- Analysis definitions target either a Stage or its enabled components. Component targets expand through a chart-owned dispatcher.
- Each analysis definition owns its retry count, timeout, retention duration, mode, and type-specific configuration. There is no shared default block for these lifecycle fields.
- Stage-level overrides win over definition values. Unknown or type-incompatible overrides are rejected.
- External definitions refer to existing namespace or cluster analysis resources and are not rendered by Helm.
- Dev Smooth execution uses the configured QA branch and directory; the filename and command behavior are fixed. The QA branch is intentionally not snapshotted as part of Freight.
- Dev changed-component selection uses metadata produced during release preparation. The selection feature can be enabled or disabled per Smooth Stage reference.
- Integration always targets every enabled component, including configuration-only Freight, and waits for both Prometheus and Elasticsearch results.
- Integration captures one verification start timestamp after Argo CD health. Elasticsearch time filters use that fixed lower bound and the current measurement time.
- PromQL owns aggregation. Prometheus labels merge from service, definition, component target, and metric, with the value closest to the metric winning.
- Elasticsearch contains only explicit error conditions; no implicit catch-all error query is generated.
- Blocking checks treat missing or invalid telemetry as failure. Dry-run checks report the same condition without blocking promotion.
- Pre-production enforces official tags before making external calls.
- The AI prompt asks for structured fields and instructs the agent to calculate the work window. The pipeline validates the returned window rather than implementing the holiday calculation itself.
- AI evidence can describe both component tag changes and configuration changes. Unsupported claims are prohibited, and deterministic fallback output is marked for human review.
- AI enrichment is optional. ServiceNow can use only its fixed fields, and GitLab can use fixed title and description when AI is disabled.
- ServiceNow fixed fields are configured independently of AI-generated fields. Partial renaming is optional, unchanged field names are implicit, and fixed values take precedence.
- ServiceNow and GitLab records use Freight-derived idempotency keys, are created independently, and store their human titles, URLs, and machine identifiers as Freight metadata.
- Pre-production creates but does not merge the GitLab merge request and does not wait for ServiceNow approval.
- Production consumes merge-request metadata from Pre-production, merges before deployment, and verifies the exact tested revision. Merge lifecycle settings are not duplicated in Production configuration.
- Email is delivered through the configured HTTP mail API. Production monitoring alerts are delivered through the configured HTTP monitoring endpoint.
- Self-managed Kargo v1.10 is the platform target. The solution does not depend on Akuity-only notification resources.
- Promotion-only Stages use conditional success and failure notification steps. Deployment Stages use chart-owned verification dispatchers to notify after aggregation, with a conditional failure path for failures before verification.
- Git and authenticated HTTP credentials are rendered as Kubernetes Secrets. They are referenced by workloads rather than embedded in generated resources.
- Validation is conditional: disabled features do not require their configuration, while enabled features activate strict schema and Helm validation.
- A failed Freight remains blocked downstream, but Warehouse discovery and later Freight continue after the active verification terminates.

## Testing Decisions

- Tests verify externally observable rendered resources and promotion contracts rather than private helper implementation details.
- The highest static seam is Helm input-to-rendered-output: representative values are rendered and the resulting Kubernetes and Kargo resources are asserted.
- The highest behavioral seam is one standalone Freight moving through the complete promotion contract: preparation metadata, exact revision deployment, verification aggregation, external-record correlation, manual Production selection, and final outcomes.
- JSON Schema tests cover accepted values, rejected values, conditional requirements, enums, formats, and authentication combinations.
- Helm validation tests cover cross-field rules that JSON Schema cannot express, including unique normalized names, reference compatibility, paired credentials, resolved path collisions, notification fallback, and argument conflicts.
- Rendering tests cover every generated resource kind, naming and labels, Stage origins, requested Freight behavior, exact commit arguments, Secret references, AnalysisTemplate references, and disabled-feature omission.
- Prepare-release tests cover standalone Freight input, initial and subsequent releases, one and multiple changed tags, unchanged tags, missing files, missing tag paths, divergent branches, and no-force-push behavior.
- Dev tests cover changed-only and all-component selection, zero selected components, parallelism limits, individual retry, wait-for-all aggregation, QA defaults, fixed Smooth execution, and disabled verification.
- Integration tests cover initial delay, duration-to-measurement calculation, label precedence, per-check threshold and tolerance overrides, timestamp filtering, explicit Elasticsearch conditions, missing telemetry, blocking mode, individual dry-run, and whole-Stage dry-run.
- Pre-production tests cover official-tag rejection before external calls, structured and redacted AI input, valid and invalid AI output, fallback generation, timestamp validation, partial field mapping, fixed-field precedence, idempotent ServiceNow and GitLab retries, and partial external failure.
- Production tests cover manual promotion, expected MR revision, already-merged acceptance, mismatch, conflict, closed-unmerged state, Production-branch ancestry, exact commit deployment, success updates, failure updates, and Production-only monitoring alerts.
- Notification tests cover explicit enablement, outcome-to-global message fallback, missing message rejection, API retry, and preservation of the original release result when delivery fails.
- Security tests inspect every rendered non-Secret resource for credential leakage and verify one valid credential Secret per configured repository.
- Regression gates run Helm lint and a default Helm render. The chart icon recommendation is accepted as benign lint output.
- Each implementation phase adds focused positive and negative tests before that phase is considered complete.

## Out of Scope

- Building application images or creating developer Git tags
- Inventing or automatically creating official tags
- Customer output-validation automation
- Automatic rollback
- Application or environment undeploy and cleanup
- Deleting resources for failed or superseded Freight
- Linking GitLab merge requests to ServiceNow changes
- Waiting for ServiceNow approval during Pre-production
- Waiting for or automatically approving Production promotion
- Akuity Platform-only notification resources

The sole approved cleanup is deletion of the temporary release branch by GitLab after its successful merge.

## Further Notes

- Implementation is incremental. A capability described here must not be presented as implemented until its chart templates and validation exist.
- Current chart implementation includes all five Stages, managed and external AnalysisTemplate contracts, repository and HTTP Secrets, and values-driven administration and notification integrations. Dispatcher execution, live API behavior, CRD admission, and cluster deployment remain external validation work.
- The detailed Stage design documents remain the implementation authorities for Prepare-release, Dev, Integration, Pre-production, and Production.
- The top-level values order is `global`, `warehouse`, `sources`, `pipeline`, `services`, and `analysisTemplates`.
- System-specific repositories, labels, queries, thresholds, prompts, fixed fields, endpoints, and credentials belong in values rather than chart templates.
- This specification is stored in the repository as the project specification. It has not been published to an external issue tracker because no issue-tracker target or integration was supplied.
