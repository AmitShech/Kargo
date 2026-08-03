$ErrorActionPreference = 'Continue'
$chart = Split-Path -Parent $PSScriptRoot

helm lint $chart | Out-Host
if ($LASTEXITCODE -ne 0) { throw 'helm lint failed' }
$fullExample = helm template all-features $chart --namespace payment-platform -f (Join-Path $chart 'examples/values-all-features.yaml')
if ($LASTEXITCODE -ne 0) { throw 'full-feature example render failed' }
$fullExampleText = $fullExample -join "`n"
foreach ($needle in @('kind: ProjectConfig', 'component-smooth', 'flink-metrics', 'flink-errors', 'integration-health', 'production-health', 'organization-dev-policy', 'production-policy', 'maintenance-proof-job', 'generate-ai-summary', 'create-or-reuse-servicenow', 'create-or-reuse-release-mr', 'production-dispatcher')) {
  if ($fullExampleText -notmatch [regex]::Escape($needle)) { throw "full-feature example is missing $needle" }
}
$rendered = helm template my-app-promotion $chart --namespace my-app-promotion
if ($LASTEXITCODE -ne 0) { throw 'default render failed' }
$renderedText = $rendered -join "`n"

$valuesLines = Get-Content (Join-Path $chart 'values.yaml')
$gitLabStart = ($valuesLines | Select-String '^      gitLab:$').LineNumber
$outcomesStart = ($valuesLines | Select-String '^      outcomes:$' | Where-Object LineNumber -gt $gitLabStart | Select-Object -First 1).LineNumber
$gitLabFixedFields = $valuesLines[($gitLabStart - 1)..($outcomesStart - 2)] | Select-String '^        fixedFields:$'
if ($gitLabFixedFields.Count -ne 1) { throw 'Pre-production GitLab must define fixedFields exactly once in values.yaml' }

$requiredStages = @('prepare-release', 'dev', 'integration', 'pre-production', 'production')
foreach ($stage in $requiredStages) {
  if ($renderedText -notmatch "name: `"$([regex]::Escape($stage))`"") { throw "missing Stage $stage" }
}
foreach ($secret in @('chartgit', 'main-devgit', 'main-qagit')) {
  if ($renderedText -notmatch "name: `"$secret`"") { throw "missing Secret $secret" }
}
if ($renderedText -match 'deploymentGit|deploymentOverlayPath') { throw 'legacy vocabulary leaked into render' }
if (($rendered | Select-String 'desiredRevision:.*release-commit').Count -ne 3) { throw 'exact release commit is not deployed by all three deployment Stages' }
if ($renderedText -match '(?m)^kind: (Application|Deployment|Service|StatefulSet|DaemonSet)$') { throw 'chart deployed an external application or backing service' }
if (($rendered | Select-String 'stageSelector:').Count -ne 5 -or ($rendered | Select-String '(?m)^\s+- stage:').Count -ne 0) { throw 'ProjectConfig does not use Kargo stageSelector promotion policies' }
if (($rendered | Select-String 'selectionPolicy:').Count -ne 5) { throw 'not every Stage renders its Freight auto-promotion selection policy' }
if ($renderedText -notmatch 'selectionPolicy: "NewestFreight"' -or (($rendered | Select-String 'selectionPolicy: "MatchUpstream"').Count -ne 4)) { throw 'Stage Freight selection policies are incorrect' }

$strictTags = helm template strict-tags $chart -f (Join-Path $PSScriptRoot 'fixtures/enabled-values.yaml') --set-string 'sources.components[0].tagPolicy.allowedPatterns[0]=^dev-'
if ($LASTEXITCODE -ne 0) { throw 'strict component tag-policy render failed' }
$strictTagsText = $strictTags -join "`n"
foreach ($needle in @('pre-production-main-not-stage-allowed', 'pre-production-main-not-component-allowed')) {
  if ($strictTagsText -notmatch $needle) { throw "Stage and component allowed tag policies are not independently enforced: missing $needle" }
}

$enabled = helm template enabled $chart --namespace enabled -f (Join-Path $PSScriptRoot 'fixtures/enabled-values.yaml')
if ($LASTEXITCODE -ne 0) { throw 'enabled-feature render failed' }
$enabledText = $enabled -join "`n"
foreach ($needle in @('kind: AnalysisTemplate', '--skip-install', 'flink_restarts', 'verificationStartedAt')) {
  if ($enabledText -notmatch [regex]::Escape($needle)) { throw "enabled render is missing $needle" }
}
foreach ($needle in @(
  'image: "registry.example.com/platform/kargo-analysis-dispatcher:1.0.0"',
  'kind: ServiceAccount',
  'kind: Role',
  'resources: \[analysisruns, analysistemplates\]',
  'verbs: \[create, get, list, watch\]',
  '"parallelism":',
  '"changedOnly":',
  '"components":'
)) {
  if ($enabledText -notmatch $needle) { throw "dispatcher rendering contract is missing $needle" }
}
foreach ($needle in @(
  '\"count\":4',
  '\"count\":3',
  '\"failureLimit\":3',
  'billing-target',
  'billing-integration-*',
  '\"mode\":\"dry-run\"',
  '\"dryRun\":[{\"metricName\":\"checkpoint-failure\"}]',
  '\"duration\":\"10m\"',
  '\"initialDelay\":\"0s\"'
)) {
  if (-not $enabledText.Contains($needle)) { throw "Integration dispatcher contract is missing $needle" }
}

$externalText = $enabledText
foreach ($needle in @('"qaGitSecretName":"main-qagit"', '"qaGitBranch":"main"', '"qaGitPath":"."')) {
  if ($externalText -notmatch [regex]::Escape($needle)) { throw "supported QA dispatcher wiring is missing $needle" }
}
if ($externalText -match 'name: (username|password), value:') { throw 'QA credentials leaked into Dev Stage arguments' }
foreach ($needle in @('name: "dev-smooth-main"', 'name: prepare-qa', 'QA_GIT_REPOSITORY', 'QA_GIT_USERNAME', 'QA_GIT_PASSWORD', 'dev-dispatcher')) {
  if ($enabledText -notmatch [regex]::Escape($needle)) { throw "supported QA AnalysisTemplate is missing $needle" }
}

$external = helm template external $chart -f (Join-Path $PSScriptRoot 'fixtures/external-values.yaml')
if ($LASTEXITCODE -ne 0) { throw 'external AnalysisTemplate render failed' }
$externalText = $external -join "`n"
foreach ($needle in @('dev-external-dispatcher', '\"resourceName\":\"existing-organization-qa\"', '\"kind\":\"ClusterAnalysisTemplate\"', '\"retryAmount\":0', '\"timeout\":\"10m\"', '\"ttlAfterFinished\":\"2h\"', '\"mode\":\"dry-run\"', '\"allowedFailedMeasurements\":1', 'name: "environment"', 'value: "dev"', 'name: "region"', 'value: "eu"')) {
  if (-not $externalText.Contains($needle)) { throw "external AnalysisTemplate contract is missing $needle" }
}
if ($externalText -match 'name: "existing-organization-qa"') { throw 'external AnalysisTemplate resource was created instead of only referenced' }

$negative = (helm template invalid-external $chart -f (Join-Path $PSScriptRoot 'fixtures/external-values.yaml') `
  --set 'pipeline.stages.dev.verification.analysisTemplates[0].arguments[0].name=region' `
  --set 'pipeline.stages.dev.verification.analysisTemplates[0].arguments[0].value=us' 2>&1) -join "`n"
if ($LASTEXITCODE -eq 0 -or $negative -notmatch 'requires Stage argument "environment"') { throw 'missing external required argument was accepted' }

$negative = (helm template invalid $chart --set pipeline.stages.production.autoPromotionEnabled=true 2>&1) -join "`n"
if ($LASTEXITCODE -eq 0 -or $negative -notmatch 'requires explicit Freight selection') { throw 'manual Production validation did not fail as expected' }

$negative = (helm template invalid $chart --set sources.chartGit.repository.username=user 2>&1) -join "`n"
if ($LASTEXITCODE -eq 0 -or $negative -notmatch 'must set both username and password') { throw 'credential-pair validation did not fail as expected' }

$negative = (helm template invalid $chart --set services.ai.endpoint=http://ai.local 2>&1) -join "`n"
if ($LASTEXITCODE -eq 0 -or $negative -notmatch 'allowInsecureHttp') { throw 'insecure HTTP validation did not fail as expected' }

$negative = (helm template invalid $chart --set pipeline.stages.preProduction.serviceNow.enabled=true 2>&1) -join "`n"
if ($LASTEXITCODE -eq 0 -or $negative -notmatch 'services.serviceNow.endpoint is required') { throw 'ServiceNow without an endpoint was accepted' }

$negative = (helm template invalid $chart `
  --set pipeline.stages.preProduction.gitLab.enabled=true `
  --set pipeline.stages.preProduction.gitLab.projectPath=team/app `
  --set services.gitLab.endpoint=https://gitlab.example 2>&1) -join "`n"
if ($LASTEXITCODE -eq 0 -or $negative -notmatch 'fixedFields.title and description are required') { throw 'GitLab without AI or fixed content was accepted' }

$fixedServiceNow = helm template fixed-servicenow $chart `
  --set pipeline.stages.preProduction.serviceNow.enabled=true `
  --set pipeline.stages.preProduction.serviceNow.fixedFields.short_description='Fixed release' `
  --set services.serviceNow.endpoint=https://servicenow.example
if ($LASTEXITCODE -ne 0) { throw 'fixed-only ServiceNow render failed' }
$fixedServiceNowText = $fixedServiceNow -join "`n"
if ($fixedServiceNowText -match "outputs\['generate-ai-summary'\]") { throw 'fixed-only ServiceNow render depends on AI output' }

$fixedGitLab = helm template fixed-gitlab $chart `
  --set pipeline.stages.preProduction.gitLab.enabled=true `
  --set pipeline.stages.preProduction.gitLab.projectPath=team/app `
  --set pipeline.stages.preProduction.gitLab.fixedFields.title='Fixed release' `
  --set pipeline.stages.preProduction.gitLab.fixedFields.description='Fixed description' `
  --set services.gitLab.endpoint=https://gitlab.example
if ($LASTEXITCODE -ne 0) { throw 'fixed-only GitLab render failed' }
$fixedGitLabText = $fixedGitLab -join "`n"
if ($fixedGitLabText -notmatch 'title: "Fixed release"' -or $fixedGitLabText -notmatch 'description: "Fixed description"') { throw 'fixed-only GitLab content was not rendered' }
if ($fixedGitLabText -match "outputs\['generate-ai-summary'\]") { throw 'fixed-only GitLab render depends on AI output' }

$negative = (helm template invalid $chart --set pipeline.stages.dev.verification.enabled=true 2>&1) -join "`n"
if ($LASTEXITCODE -eq 0 -or $negative -notmatch 'dispatcher is a prebuilt external prerequisite') { throw 'missing external dispatcher image validation did not fail as expected' }

$negative = (helm template invalid $chart --set global.dispatcher.image.pullPolicy=Sometimes 2>&1) -join "`n"
if ($LASTEXITCODE -eq 0 -or $negative -notmatch 'pullPolicy') { throw 'invalid dispatcher pull policy was accepted' }

$negative = (helm template invalid $chart `
  -f (Join-Path $PSScriptRoot 'fixtures/enabled-values.yaml') `
  --set pipeline.stages.integration.verification.duration=0s 2>&1) -join "`n"
if ($LASTEXITCODE -eq 0 -or $negative -notmatch 'duration must be greater than zero') { throw 'zero Integration duration was accepted' }

$negative = (helm template invalid $chart `
  -f (Join-Path $PSScriptRoot 'fixtures/enabled-values.yaml') `
  --set pipeline.stages.integration.verification.maxMeasurements=2 2>&1) -join "`n"
if ($LASTEXITCODE -eq 0 -or $negative -notmatch 'exceeding maxMeasurements') { throw 'Integration measurement upper bound was not enforced' }

$negative = (helm template invalid $chart `
  -f (Join-Path $PSScriptRoot 'fixtures/enabled-values.yaml') `
  --set pipeline.stages.integration.verification.initialDelay=soon 2>&1) -join "`n"
if ($LASTEXITCODE -eq 0 -or $negative -notmatch 'must be a non-negative integer') { throw 'invalid Integration initial delay was accepted' }

$dryRunAll = helm template dry-run-all $chart -f (Join-Path $PSScriptRoot 'fixtures/enabled-values.yaml') --set pipeline.stages.integration.verification.dryRunAll=true
if ($LASTEXITCODE -ne 0) { throw 'Integration dryRunAll render failed' }
if (-not (($dryRunAll -join "`n").Contains('\"dryRun\":[{\"metricName\":\"*\"}]'))) { throw 'dryRunAll did not render the native all-metrics selector' }

$negative = (helm template invalid $chart --set pipeline.stages.dev.unknownField=true 2>&1) -join "`n"
if ($LASTEXITCODE -eq 0 -or $negative -notmatch 'contains unknown field') { throw 'unknown Stage field was accepted' }

$negative = (helm template invalid $chart --set services.ai.unknownField=true 2>&1) -join "`n"
if ($LASTEXITCODE -eq 0 -or $negative -notmatch 'contains unknown field') { throw 'unknown service field was accepted' }

$negative = (helm template invalid $chart -f (Join-Path $PSScriptRoot 'fixtures/enabled-values.yaml') --set analysisTemplates[0].unknownField=true 2>&1) -join "`n"
if ($LASTEXITCODE -eq 0 -or $negative -notmatch 'contains incompatible field') { throw 'type-incompatible AnalysisTemplate field was accepted' }

$negative = (helm template invalid $chart --set sources.componentDefaults.unknownField=true 2>&1) -join "`n"
if ($LASTEXITCODE -eq 0 -or $negative -notmatch 'sources.componentDefaults contains unknown field') { throw 'unknown componentDefaults field was accepted' }

$negative = (helm template invalid $chart -f (Join-Path $PSScriptRoot 'fixtures/enabled-values.yaml') --set-string 'analysisTemplates[1].targets[0].component=missing' 2>&1) -join "`n"
if ($LASTEXITCODE -eq 0 -or $negative -notmatch 'targets unknown component') { throw 'unknown AnalysisTemplate target component was accepted' }

$negative = (helm template invalid $chart -f (Join-Path $PSScriptRoot 'fixtures/enabled-values.yaml') `
  --set pipeline.stages.integration.verification.analysisTemplates[0].name=dev-smooth `
  --set pipeline.stages.integration.verification.analysisTemplates[0].enabled=true `
  --set pipeline.stages.integration.verification.analysisTemplates[1].enabled=false 2>&1) -join "`n"
if ($LASTEXITCODE -eq 0 -or $negative -notmatch 'Integration supports prometheus, elasticsearch, or external') { throw 'incompatible Integration component template was accepted' }

$negative = (helm template invalid $chart --set pipeline.stages.preProduction.ai.requiredFields[0]=title 2>&1) -join "`n"
if ($LASTEXITCODE -eq 0 -or $negative -notmatch 'must contain exactly') { throw 'incomplete AI requiredFields contract was accepted' }

$negative = (helm template invalid $chart `
  --set pipeline.stages.preProduction.gitLab.enabled=true `
  --set pipeline.stages.preProduction.gitLab.projectPath=team/app `
  --set pipeline.stages.preProduction.gitLab.fixedFields.title=title `
  --set pipeline.stages.preProduction.gitLab.fixedFields.description=description `
  --set pipeline.stages.preProduction.gitLab.mergeRequest.requireCommitPreservingMerge=false `
  --set services.gitLab.endpoint=https://gitlab.example 2>&1) -join "`n"
if ($LASTEXITCODE -eq 0 -or $negative -notmatch 'requireCommitPreservingMerge must be true') { throw 'unsafe GitLab merge configuration was accepted' }

$negative = (helm template invalid $chart -f (Join-Path $PSScriptRoot 'fixtures/enabled-values.yaml') --set pipeline.stages.production.verification.enabled=true 2>&1) -join "`n"
if ($LASTEXITCODE -eq 0 -or $negative -notmatch 'requires at least one enabled analysisTemplate reference') { throw 'enabled Production verification without templates was accepted' }

$inactive = helm template inactive $chart -f (Join-Path $PSScriptRoot 'fixtures/inactive-values.yaml')
if ($LASTEXITCODE -ne 0) { throw 'inactive incomplete provider definition failed rendering' }
if (($inactive -join "`n") -match 'name: "future-job"') { throw 'inactive managed AnalysisTemplate was rendered' }

$aiRender = helm template ai-contract $chart `
  --set pipeline.stages.preProduction.ai.enabled=true `
  --set services.ai.endpoint=https://ai.example
if ($LASTEXITCODE -ne 0) { throw 'AI contract render failed' }
$aiText = $aiRender -join "`n"
foreach ($needle in @('continueOnError: true', 'as: release-content', 'as: reject-invalid-ai-release-content', 'external administration was not created', 'HUMAN REVIEW', 'fromExpression: "response.body.title"', "Format('15:04')", '.Minutes()', '.Weekday().String()', 'time.LoadLocation(')) {
  if ($aiText -notmatch [regex]::Escape($needle)) { throw "AI validation/fallback contract is missing $needle" }
}

$administration = helm template administration-contract $chart `
  --set pipeline.stages.preProduction.ai.enabled=true `
  --set pipeline.stages.preProduction.serviceNow.enabled=true `
  --set-string pipeline.stages.preProduction.serviceNow.fixedFields.assignment_group=release-team `
  --set pipeline.stages.preProduction.gitLab.enabled=true `
  --set-string pipeline.stages.preProduction.gitLab.projectPath=team/app `
  --set services.ai.endpoint=https://ai.example `
  --set services.serviceNow.endpoint=https://servicenow.example `
  --set services.gitLab.endpoint=https://gitlab.example
if ($LASTEXITCODE -ne 0) { throw 'full Pre-production administration render failed' }
$administrationText = $administration -join "`n"
foreach ($needle in @(
  'as: enforce-release-mr-lifecycle',
  'as: reject-stale-release-mr',
  'as: reject-closed-release-mr',
  'state=all',
  "outputs['gitlab-record'].state == 'opened'",
  'remove_source_branch',
  'squash',
  'servicenow-title:',
  'servicenow-number:',
  'servicenow-url:',
  'servicenow-sys-id:',
  'gitlab-expected-revision:',
  'gitlab-api-project: "team%2Fapp"',
  '"team%2Fapp"',
  'external-administration-complete: "true"'
)) {
  if ($administrationText -notmatch [regex]::Escape($needle)) { throw "administration contract is missing $needle" }
}
if ($administrationText -match 'fixedFields:|aiFieldMapping:|servicenow-record:') { throw 'wrapper or combined ServiceNow data leaked into the final administration contract' }

foreach ($needle in @(
  "response.body.state in ['opened', 'merged']",
  "outputs['verify-prepared-mr-revision'].state == 'opened'",
  'name: state, fromExpression: response.body.state',
  "freightMetadata(ctx.targetFreight.name)['gitlab-expected-revision']",
  'as: verify-production-branch-contains-tested-commit',
  'as: deploy-exact-tested-commit'
)) {
  if ($administrationText -notmatch [regex]::Escape($needle)) { throw "Production MR contract is missing $needle" }
}
$mergeIndex = $administrationText.IndexOf('as: merge-prepared-mr')
$deployIndex = $administrationText.IndexOf('as: deploy-exact-tested-commit')
if ($mergeIndex -lt 0 -or $deployIndex -le $mergeIndex) { throw 'Production deploy is not ordered after the conditional MR merge' }

$productionNoVerification = helm template production-no-verification $chart `
  --set pipeline.stages.preProduction.serviceNow.enabled=true `
  --set-string pipeline.stages.preProduction.serviceNow.fixedFields.short_description='Fixed release' `
  --set services.mail.endpoint=https://mail.example `
  --set-string 'pipeline.notifications.email.recipients[0]=ops@example.com' `
  --set pipeline.stages.production.outcomes.success.notifications.email.enabled=true `
  --set-string pipeline.stages.production.outcomes.success.notifications.email.subject='Production succeeded' `
  --set-string pipeline.stages.production.outcomes.success.notifications.email.body='Deployment completed' `
  --set pipeline.stages.production.outcomes.success.serviceNow.enabled=true `
  --set-string pipeline.stages.production.outcomes.success.serviceNow.fields.state=completed `
  --set services.serviceNow.endpoint=https://servicenow.example
if ($LASTEXITCODE -ne 0) { throw 'Production success finalization without verification failed rendering' }
$productionNoVerificationText = $productionNoVerification -join "`n"
foreach ($needle in @('as: production-success-servicenow', 'as: "production-email-success"')) {
  if ($productionNoVerificationText -notmatch [regex]::Escape($needle)) { throw "Production success finalization is missing $needle" }
}

$negative = (helm template invalid $chart `
  --set pipeline.stages.production.outcomes.success.serviceNow.enabled=true `
  --set services.serviceNow.endpoint=https://servicenow.example 2>&1) -join "`n"
if ($LASTEXITCODE -eq 0 -or $negative -notmatch 'requires pipeline.stages.preProduction.serviceNow.enabled') { throw 'Production ServiceNow finalization without Pre-production record creation was accepted' }

$noGeneration = helm template no-generation $chart -f (Join-Path $PSScriptRoot 'fixtures/enabled-values.yaml') --set sources.components[0].releaseConfiguration.generationEnabled=false
if ($LASTEXITCODE -ne 0) { throw 'component without generated configuration failed rendering' }
$noGenerationText = $noGeneration -join "`n"
if ($noGenerationText -notmatch 'as: "clone-main-config"' -or $noGenerationText -match 'as: "merge-main-config"') { throw 'developer Git evidence is not preserved independently of configuration generation' }

$emailRender = helm template email-contract $chart `
  --set services.mail.endpoint=https://mail.example `
  --set-string 'pipeline.notifications.email.recipients[0]=ops@example.com' `
  --set pipeline.stages.prepareRelease.outcomes.success.notifications.email.enabled=true `
  --set-string pipeline.stages.prepareRelease.outcomes.success.notifications.email.subject='Release ready' `
  --set-string pipeline.stages.prepareRelease.outcomes.success.notifications.email.body='Prepared successfully'
if ($LASTEXITCODE -ne 0) { throw 'email outcome render failed' }
$emailText = $emailRender -join "`n"
foreach ($needle in @('as: "prepare-release-email-success"', 'if: "${{ success() }}"', 'continueOnError: true', 'https://mail.example')) {
  if ($emailText -notmatch [regex]::Escape($needle)) { throw "email outcome contract is missing $needle" }
}

$deploymentEmail = helm template deployment-email $chart `
  -f (Join-Path $PSScriptRoot 'fixtures/enabled-values.yaml') `
  --set services.mail.endpoint=https://mail.example `
  --set-string 'pipeline.notifications.email.recipients[0]=ops@example.com' `
  --set pipeline.stages.dev.outcomes.success.notifications.email.enabled=true `
  --set-string pipeline.stages.dev.outcomes.success.notifications.email.subject='Dev verified' `
  --set-string pipeline.stages.dev.outcomes.success.notifications.email.body='Dev checks passed' `
  --set pipeline.stages.integration.outcomes.failure.notifications.email.enabled=true `
  --set-string pipeline.stages.integration.outcomes.failure.notifications.email.subject='Integration failed' `
  --set-string pipeline.stages.integration.outcomes.failure.notifications.email.body='Integration checks failed'
if ($LASTEXITCODE -ne 0) { throw 'deployment dispatcher email render failed' }
$deploymentEmailText = $deploymentEmail -join "`n"
foreach ($needle in @('https://mail.example', 'Dev verified', 'Integration failed', '\"mail\":')) {
  if (-not $deploymentEmailText.Contains($needle)) { throw "deployment dispatcher email contract is missing $needle" }
}

$productionFinalizer = helm template production-finalizer $chart `
  -f (Join-Path $PSScriptRoot 'fixtures/enabled-values.yaml') `
  --set pipeline.stages.production.verification.enabled=true `
  --set 'pipeline.stages.production.verification.analysisTemplates[0].name=flink-metrics' `
  --set 'pipeline.stages.production.verification.analysisTemplates[0].enabled=true' `
  --set pipeline.stages.production.outcomes.failure.monitoring.enabled=true `
  --set services.monitoring.endpoint=https://monitoring.example
if ($LASTEXITCODE -ne 0) { throw 'Production finalizer render failed' }
$productionText = $productionFinalizer -join "`n"
foreach ($needle in @('production-dispatcher', 'serviceNowSysId', '\"monitoring\":{\"enabled\":true', 'servicenow-sys-id')) {
  if (-not $productionText.Contains($needle)) { throw "Production finalization contract is missing $needle" }
}

$secretRender = helm template auth $chart `
  --set services.ai.endpoint=https://ai.example `
  --set services.ai.authentication.type=basic `
  --set services.ai.authentication.username=chart-user `
  --set services.ai.authentication.password=chart-password
if ($LASTEXITCODE -ne 0) { throw 'authenticated service render failed' }
$secretText = $secretRender -join "`n"
if ($secretText -notmatch 'name: "ai-http"') { throw 'AI authentication Secret was not rendered' }
if ($secretText -notmatch 'username: "chart-user"' -or $secretText -notmatch 'password: "chart-password"') { throw 'AI credentials were not isolated in Secret stringData' }

$documents = $secretText -split '(?m)^---\s*$'
foreach ($document in $documents) {
  if ($document -notmatch '(?m)^kind: Secret\s*$' -and $document -match 'chart-password|chart-user') {
    throw 'credentials leaked outside a Secret resource'
  }
}

if (Test-Path (Join-Path (Split-Path $chart -Parent) 'dispatcher')) { throw 'dispatcher source/build assets remain in chart scope' }
$forbiddenAssets = Get-ChildItem -Path (Split-Path $chart -Parent) -Recurse -File | Where-Object {
  $_.Name -in @('Dockerfile', 'go.mod', 'go.sum') -or $_.Extension -eq '.go'
}
if ($forbiddenAssets) { throw "chart-only scope contains runtime build assets: $($forbiddenAssets.FullName -join ', ')" }

Write-Host 'All chart acceptance checks passed.'
