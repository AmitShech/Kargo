{{- define "generic-kargo-pipeline.normalizeName" -}}{{- regexReplaceAll "[^a-z0-9-]" (. | lower) "-" | trimAll "-" | trunc 63 | trimSuffix "-" -}}{{- end -}}
{{- define "generic-kargo-pipeline.name" -}}{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}{{- end -}}
{{- define "generic-kargo-pipeline.fullname" -}}{{- include "generic-kargo-pipeline.normalizeName" (default (printf "%s-%s" .Release.Name (include "generic-kargo-pipeline.name" .)) .Values.fullnameOverride) -}}{{- end -}}
{{- define "generic-kargo-pipeline.projectName" -}}{{- include "generic-kargo-pipeline.normalizeName" .Release.Namespace -}}{{- end -}}
{{- define "generic-kargo-pipeline.chartGitSecretName" -}}chartgit{{- end -}}
{{- define "generic-kargo-pipeline.componentDevGitSecretName" -}}{{- printf "%s-devgit" .name | include "generic-kargo-pipeline.normalizeName" -}}{{- end -}}
{{- define "generic-kargo-pipeline.componentQaGitSecretName" -}}{{- printf "%s-qagit" .name | include "generic-kargo-pipeline.normalizeName" -}}{{- end -}}
{{- define "generic-kargo-pipeline.httpServiceSecretName" -}}{{- printf "%s-http" . | include "generic-kargo-pipeline.normalizeName" -}}{{- end -}}
{{- define "generic-kargo-pipeline.promotionAuthHeaders" -}}
{{- $name := .name -}}{{- $service := .service -}}{{- $type := default "none" $service.authentication.type -}}
{{- if ne $type "none" }}
- name: {{ include "generic-kargo-pipeline.kargoExpression" (printf "secret(%q).headerName" (include "generic-kargo-pipeline.httpServiceSecretName" $name)) | quote }}
  value: {{ include "generic-kargo-pipeline.kargoExpression" (printf "secret(%q).headerValue" (include "generic-kargo-pipeline.httpServiceSecretName" $name)) | quote }}
{{- end -}}
{{- end -}}
{{- define "generic-kargo-pipeline.kargoExpression" -}}{{- printf "$%s %s %s" (repeat 2 "{") . (repeat 2 "}") -}}{{- end -}}
{{- define "generic-kargo-pipeline.durationSeconds" -}}
{{- $value := toString . -}}
{{- if not (regexMatch "^[0-9]+(s|m|h)$" $value) -}}{{ fail (printf "duration %q must be a non-negative integer followed by s, m, or h" $value) }}{{- end -}}
{{- $amount := regexFind "^[0-9]+" $value | int64 -}}
{{- if hasSuffix "h" $value -}}{{ mul $amount 3600 }}{{- else if hasSuffix "m" $value -}}{{ mul $amount 60 }}{{- else -}}{{ $amount }}{{- end -}}
{{- end -}}
{{- define "generic-kargo-pipeline.measurementCount" -}}
{{- $duration := include "generic-kargo-pipeline.durationSeconds" .duration | int64 -}}
{{- $interval := include "generic-kargo-pipeline.durationSeconds" .interval | int64 -}}
{{- if le $duration 0 }}{{ fail (printf "%s duration must be greater than zero" .scope) }}{{ end -}}
{{- if le $interval 0 }}{{ fail (printf "%s interval must be greater than zero" .scope) }}{{ end -}}
{{- $count := div (add $duration (sub $interval 1)) $interval -}}
{{- if gt $count (int64 .max) }}{{ fail (printf "%s requires %d measurements, exceeding maxMeasurements %d" .scope $count (int64 .max)) }}{{ end -}}
{{- $count -}}
{{- end -}}
{{- define "generic-kargo-pipeline.tagPolicySteps" -}}
{{- $stageKey := .stageKey -}}{{- $stage := .stage -}}
{{- range $component := .components -}}{{- if $component.enabled -}}
{{- range $index, $pattern := concat (default list $stage.tagPolicy.deniedPatterns) (default list $component.tagPolicy.deniedPatterns) }}
- uses: fail
  as: {{ printf "%s-%s-denied-%d" $stageKey $component.name $index | include "generic-kargo-pipeline.normalizeName" | quote }}
  if: {{ include "generic-kargo-pipeline.kargoExpression" (printf "imageFrom(%q).Tag.matches(%q)" $component.image.repository $pattern) | quote }}
  config: { message: {{ printf "%s rejected component %s tag by denied pattern" $stageKey $component.name | quote }} }
{{- end -}}
{{- $stageAllowed := default list $stage.tagPolicy.allowedPatterns -}}
{{- if $stageAllowed }}
- uses: fail
  as: {{ printf "%s-%s-not-stage-allowed" $stageKey $component.name | include "generic-kargo-pipeline.normalizeName" | quote }}
  if: {{ include "generic-kargo-pipeline.kargoExpression" (printf "!imageFrom(%q).Tag.matches(%q)" $component.image.repository (printf "(%s)" (join ")|(" $stageAllowed))) | quote }}
  config: { message: {{ printf "%s rejected component %s tag because it matches no Stage allowed pattern" $stageKey $component.name | quote }} }
{{- end -}}
{{- $componentAllowed := default list $component.tagPolicy.allowedPatterns -}}
{{- if $componentAllowed }}
- uses: fail
  as: {{ printf "%s-%s-not-component-allowed" $stageKey $component.name | include "generic-kargo-pipeline.normalizeName" | quote }}
  if: {{ include "generic-kargo-pipeline.kargoExpression" (printf "!imageFrom(%q).Tag.matches(%q)" $component.image.repository (printf "(%s)" (join ")|(" $componentAllowed))) | quote }}
  config: { message: {{ printf "%s rejected component %s tag because it matches no component allowed pattern" $stageKey $component.name | quote }} }
{{ end }}{{ end }}{{ end }}
{{- end -}}
{{- define "generic-kargo-pipeline.outcomeEmailSteps" -}}
{{- $stage := .stage -}}{{- $key := .stageKey -}}{{- $includeSuccess := .includeSuccess -}}
{{- range $result := list "success" "failure" -}}{{- if or (eq $result "failure") $includeSuccess -}}
{{- $outcome := default dict (get (default dict $stage.outcomes) $result) -}}{{- $email := default dict (get (default dict $outcome.notifications) "email") -}}
{{- if $email.enabled -}}{{- $global := default dict (get $.root.Values.pipeline.notifications.email.defaults $result) -}}
- uses: http
  as: {{ printf "%s-email-%s" $key $result | include "generic-kargo-pipeline.normalizeName" | quote }}
  if: {{ include "generic-kargo-pipeline.kargoExpression" (ternary "success()" "failure()" (eq $result "success")) | quote }}
  continueOnError: true
  retry: { errorThreshold: 3, timeout: 2m }
  config:
    method: POST
    url: {{ $.root.Values.services.mail.endpoint | quote }}
    headers:
      - { name: Content-Type, value: application/json }
{{ include "generic-kargo-pipeline.promotionAuthHeaders" (dict "name" "mail" "service" $.root.Values.services.mail) | nindent 6 }}
    body: {{ include "generic-kargo-pipeline.kargoExpression" (printf "quote({recipients: %s, subject: %q, body: %q, stage: %q, result: %q, freight: ctx.targetFreight.name})" (toJson $.root.Values.pipeline.notifications.email.recipients) (default $global.subject $email.subject) (default $global.body $email.body) $stage.name $result) | quote }}
{{ end }}{{ end }}{{ end }}
{{- end -}}
{{- define "generic-kargo-pipeline.externalStageArgs" -}}
{{- $definitions := .definitions -}}{{- $values := dict -}}{{- $owners := dict -}}{{- $reserved := list "freightName" "releaseCommit" "changedComponents" "runForChangedComponentsOnly" "parallelismLimit" "verificationStartedAt" "initialDelay" "duration" "interval" "allowedFailedMeasurements" "dryRunAll" "serviceNowSysId" -}}
{{- range $reference := .references -}}{{- if $reference.enabled -}}{{- $definition := get $definitions $reference.name -}}{{- if and $definition (eq $definition.type "external") -}}
{{- $provided := dict -}}{{- range $argument := default list $reference.arguments -}}{{- $_ := set $provided $argument.name $argument.value -}}{{- end -}}
{{- range $argument := default list $definition.arguments -}}{{- if not (has $argument.name $reserved) -}}
{{- $hasValue := false -}}{{- $value := "" -}}{{- if hasKey $argument "default" -}}{{- $hasValue = true -}}{{- $value = $argument.default -}}{{- end -}}{{- if hasKey $provided $argument.name -}}{{- $hasValue = true -}}{{- $value = get $provided $argument.name -}}{{- end -}}
{{- if $hasValue -}}{{- if and (hasKey $values $argument.name) (ne (toJson (get $values $argument.name)) (toJson $value)) }}{{ fail (printf "external analysisTemplates %q and %q provide conflicting values for flat Stage argument %q" (get $owners $argument.name) $definition.name $argument.name) }}{{ end -}}{{- $_ := set $values $argument.name $value -}}{{- $_ := set $owners $argument.name $definition.name -}}{{- end -}}
{{- end -}}{{- end -}}{{- end -}}{{- end -}}{{- end -}}
{{- range $name := keys $values | sortAlpha }}
- name: {{ $name | quote }}
  value: {{ get $values $name | quote }}
{{- end -}}
{{- end -}}
{{- define "generic-kargo-pipeline.componentDefaults" -}}
enabled: true
tagPolicy: {allowedPatterns: [], deniedPatterns: []}
{{- end -}}
{{- define "generic-kargo-pipeline.components" -}}
{{- $builtIn := include "generic-kargo-pipeline.componentDefaults" . | fromYaml -}}
{{- $defaults := mergeOverwrite (deepCopy $builtIn) (default dict .Values.sources.componentDefaults) -}}
{{- $components := list -}}{{- range .Values.sources.components -}}{{- $components = append $components (mergeOverwrite (deepCopy $defaults) .) -}}{{- end -}}
{{- toYaml $components -}}
{{- end -}}
{{- define "generic-kargo-pipeline.labels" -}}
{{- with .Values.global.labels }}{{ toYaml . }}{{ end }}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | quote }}
app.kubernetes.io/name: {{ include "generic-kargo-pipeline.name" . | quote }}
app.kubernetes.io/instance: {{ .Release.Name | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service | quote }}
app.kubernetes.io/part-of: {{ include "generic-kargo-pipeline.name" . | quote }}
{{- end -}}
{{- define "generic-kargo-pipeline.applicationLabels" -}}
app.kubernetes.io/component: promotion-pipeline
kargo.akuity.io/project: {{ include "generic-kargo-pipeline.projectName" . | quote }}
{{- end -}}
{{- define "generic-kargo-pipeline.validateGitCredentialPair" -}}
{{- $u := default "" .username -}}{{- $p := default "" .password -}}
{{- if ne (empty $u) (empty $p) -}}{{ fail (printf "%s credentials must set both username and password or leave both empty" .scope) }}{{- end -}}
{{- end -}}
{{- define "generic-kargo-pipeline.validatePath" -}}
{{- $p := replace "\\" "/" (default "" .path) -}}
{{- if or (empty $p) (hasPrefix "/" $p) (regexMatch "^[A-Za-z]:" $p) (has ".." (splitList "/" $p)) -}}{{ fail (printf "%s must be a non-empty workspace-relative path without parent traversal" .scope) }}{{- end -}}
{{- end -}}
{{- define "generic-kargo-pipeline.validateService" -}}
{{- $s := .service -}}{{- $a := default dict $s.authentication -}}{{- $t := default "none" $a.type -}}
{{- if and $s.endpoint (hasPrefix "http://" $s.endpoint) (not $s.allowInsecureHttp) -}}{{ fail (printf "services.%s.endpoint uses HTTP; set allowInsecureHttp=true explicitly" .name) }}{{- end -}}
{{- if eq $t "basic" -}}{{ include "generic-kargo-pipeline.validateGitCredentialPair" (dict "scope" (printf "services.%s basic authentication" .name) "username" $a.username "password" $a.password) }}{{- if or (empty $a.username) (empty $a.password) }}{{ fail (printf "services.%s basic authentication requires username and password" .name) }}{{ end }}{{- end -}}
{{- if eq $t "apiKey" -}}{{- if or (empty $a.headerName) (empty $a.key) -}}{{ fail (printf "services.%s apiKey authentication requires headerName and key" .name) }}{{- end -}}{{- end -}}
{{- end -}}
{{- define "generic-kargo-pipeline.validateValues" -}}
{{- $components := include "generic-kargo-pipeline.components" . | fromYamlArray -}}
{{- $componentAllowed := list "enabled" "tagPolicy" "name" "image" "developerGit" "qaGit" "releaseConfiguration" "valuesMapping" "verification" -}}
{{- range $field := keys .Values.sources.componentDefaults -}}{{- if not (has $field $componentAllowed) }}{{ fail (printf "sources.componentDefaults contains unknown field %q" $field) }}{{ end -}}{{- end -}}
{{- $stageAllowed := dict "prepareRelease" (list "name" "autoPromotionEnabled" "freightSelectionPolicy" "releaseBranch" "tagPolicy" "outcomes") "dev" (list "name" "autoPromotionEnabled" "freightSelectionPolicy" "argocd" "tagPolicy" "verification" "outcomes") "integration" (list "name" "autoPromotionEnabled" "freightSelectionPolicy" "argocd" "tagPolicy" "verification" "outcomes") "preProduction" (list "name" "autoPromotionEnabled" "freightSelectionPolicy" "tagPolicy" "ai" "serviceNow" "gitLab" "outcomes") "production" (list "name" "autoPromotionEnabled" "freightSelectionPolicy" "argocd" "tagPolicy" "verification" "outcomes") -}}
{{- range $key, $stage := .Values.pipeline.stages -}}{{- range $field := keys $stage -}}{{- if not (has $field (get $stageAllowed $key)) }}{{ fail (printf "pipeline.stages.%s contains unknown field %q" $key $field) }}{{ end -}}{{- end -}}{{- end -}}
{{- $verificationAllowed := dict "dev" (list "enabled" "mode" "parallelismLimit" "runForChangedComponentsOnly" "analysisTemplates") "integration" (list "enabled" "mode" "initialDelay" "duration" "interval" "maxMeasurements" "allowedFailedMeasurements" "dryRunAll" "analysisTemplates") "production" (list "enabled" "mode" "analysisTemplates") -}}
{{- range $key := list "dev" "integration" "production" -}}{{- $verification := get (get $.Values.pipeline.stages $key) "verification" -}}{{- range $field := keys $verification -}}{{- if not (has $field (get $verificationAllowed $key)) }}{{ fail (printf "pipeline.stages.%s.verification contains unknown field %q" $key $field) }}{{ end -}}{{- end -}}{{- end -}}
{{- if lt (int .Values.pipeline.stages.dev.verification.parallelismLimit) 1 }}{{ fail "pipeline.stages.dev.verification.parallelismLimit must be at least 1" }}{{ end -}}
{{- $serviceAllowed := list "endpoint" "allowInsecureHttp" "authentication" "labels" "filters" "index" "timeField" -}}{{- range $name, $service := .Values.services -}}{{- range $field := keys $service -}}{{- if not (has $field $serviceAllowed) }}{{ fail (printf "services.%s contains unknown field %q" $name $field) }}{{ end -}}{{- end -}}{{- end -}}
{{- $analysisCommon := list "name" "type" "target" "retryAmount" "timeout" "ttlAfterFinished" "mode" -}}
{{- $analysisFields := dict "smooth" (list "image" "initContainer") "job" (list "job") "prometheus" (list "labels" "targets" "metrics") "http" (list "service" "checks") "elasticsearch" (list "filters" "targets" "checks") "external" (list "resourceName" "kind" "arguments") -}}
{{- range $definition := .Values.analysisTemplates -}}{{- $allowed := concat $analysisCommon (default list (get $analysisFields $definition.type)) -}}{{- range $field := keys $definition -}}{{- if not (has $field $allowed) }}{{ fail (printf "analysisTemplate %q of type %s contains incompatible field %q" $definition.name $definition.type $field) }}{{ end -}}{{- end -}}{{- end -}}
{{- range $definition := .Values.analysisTemplates -}}
{{- $targetAllowed := list "component" "labels" "filters" "index" -}}{{- range $target := default list $definition.targets -}}{{- range $field := keys $target -}}{{- if not (has $field $targetAllowed) }}{{ fail (printf "analysisTemplate %q target contains unknown field %q" $definition.name $field) }}{{ end -}}{{- end -}}{{- end -}}
{{- $targetComponents := dict -}}{{- range $target := default list $definition.targets -}}{{- if empty $target.component }}{{ fail (printf "analysisTemplate %q target requires component" $definition.name) }}{{ end -}}{{- if hasKey $targetComponents $target.component }}{{ fail (printf "analysisTemplate %q contains duplicate target for component %q" $definition.name $target.component) }}{{ end -}}{{- $_ := set $targetComponents $target.component true -}}{{- $matched := dict -}}{{- range $component := $components -}}{{- if eq $component.name $target.component }}{{- $matched = $component -}}{{- end -}}{{- end -}}{{- if empty $matched.name }}{{ fail (printf "analysisTemplate %q targets unknown component %q" $definition.name $target.component) }}{{ end -}}{{- if not $matched.enabled }}{{ fail (printf "analysisTemplate %q targets disabled component %q" $definition.name $target.component) }}{{ end -}}{{- end -}}
{{- if eq $definition.type "prometheus" -}}{{- $allowed := list "name" "query" "minimum" "maximum" "failureCondition" "labels" "window" "interval" "count" "allowedFailedMeasurements" "mode" -}}{{- range $item := default list $definition.metrics -}}{{- range $field := keys $item -}}{{- if not (has $field $allowed) }}{{ fail (printf "analysisTemplate %q metric %q contains unknown field %q" $definition.name $item.name $field) }}{{ end -}}{{- end -}}{{- end -}}{{- end -}}
{{- if eq $definition.type "elasticsearch" -}}{{- $allowed := list "name" "query" "filters" "index" "interval" "allowedFailedMeasurements" "maximumCount" "mode" -}}{{- range $item := default list $definition.checks -}}{{- range $field := keys $item -}}{{- if not (has $field $allowed) }}{{ fail (printf "analysisTemplate %q Elasticsearch check %q contains unknown field %q" $definition.name $item.name $field) }}{{ end -}}{{- end -}}{{- end -}}{{- end -}}
{{- if eq $definition.type "http" -}}{{- $allowed := list "name" "url" "method" "timeoutSeconds" "expectedStatus" "successCondition" -}}{{- range $item := default list $definition.checks -}}{{- range $field := keys $item -}}{{- if not (has $field $allowed) }}{{ fail (printf "analysisTemplate %q HTTP check %q contains unknown field %q" $definition.name $item.name $field) }}{{ end -}}{{- end -}}{{- end -}}{{- end -}}
{{- end -}}
{{- range $definition := .Values.analysisTemplates -}}
{{- if not (regexMatch "^[1-9][0-9]*(s|m|h)$" $definition.timeout) }}{{ fail (printf "analysisTemplate %q timeout must be a positive duration using s, m, or h" $definition.name) }}{{ end -}}
{{- if not (regexMatch "^[1-9][0-9]*(s|m|h)$" $definition.ttlAfterFinished) }}{{ fail (printf "analysisTemplate %q ttlAfterFinished must be a positive duration using s, m, or h" $definition.name) }}{{ end -}}
{{- end -}}
{{- include "generic-kargo-pipeline.validateGitCredentialPair" (dict "scope" "chart Git" "username" .Values.sources.chartGit.repository.username "password" .Values.sources.chartGit.repository.password) -}}
{{- $names := dict -}}{{- $paths := dict -}}
{{- range .Values.sources.components -}}{{- $c := mergeOverwrite (include "generic-kargo-pipeline.componentDefaults" $ | fromYaml) . -}}{{- $n := include "generic-kargo-pipeline.normalizeName" $c.name -}}
{{- if hasKey $names $n }}{{ fail (printf "sources.components contains duplicate normalized name %q" $n) }}{{ end -}}{{- $_ := set $names $n true -}}
{{- include "generic-kargo-pipeline.validateGitCredentialPair" (dict "scope" (printf "component %q developer Git" $c.name) "username" $c.developerGit.repository.username "password" $c.developerGit.repository.password) -}}
{{- with $c.qaGit }}{{ include "generic-kargo-pipeline.validateGitCredentialPair" (dict "scope" (printf "component %q QA Git" $c.name) "username" .repository.username "password" .repository.password) }}{{ end -}}
{{- if $c.enabled -}}{{- $out := replace "name" $n $c.releaseConfiguration.outputPath -}}{{ include "generic-kargo-pipeline.validatePath" (dict "scope" (printf "component %q releaseConfiguration.outputPath" $c.name) "path" $out) }}
{{- if hasKey $paths $out }}{{ fail (printf "enabled components %q and %q resolve to outputPath %q" (get $paths $out) $c.name $out) }}{{ end -}}{{- $_ := set $paths $out $c.name -}}
{{- if $c.releaseConfiguration.generationEnabled -}}{{ include "generic-kargo-pipeline.validatePath" (dict "scope" (printf "component %q devConfigurationPath" $c.name) "path" $c.releaseConfiguration.devConfigurationPath) }}{{ include "generic-kargo-pipeline.validatePath" (dict "scope" (printf "component %q chartOverlayPath" $c.name) "path" $c.releaseConfiguration.chartOverlayPath) }}{{ end -}}{{- end -}}{{- end -}}
{{- range $key, $stage := .Values.pipeline.stages -}}{{- range $pattern := concat (default list $stage.tagPolicy.allowedPatterns) (default list $stage.tagPolicy.deniedPatterns) -}}{{- $_ := regexMatch $pattern "" -}}{{- end -}}{{- end -}}
{{- range $component := $components -}}{{- range $pattern := concat (default list $component.tagPolicy.allowedPatterns) (default list $component.tagPolicy.deniedPatterns) -}}{{- $_ := regexMatch $pattern "" -}}{{- end -}}{{- end -}}
{{- if .Values.pipeline.stages.production.autoPromotionEnabled }}{{ fail "pipeline.stages.production.autoPromotionEnabled must be false; Production requires explicit Freight selection" }}{{ end -}}
{{- if or .Values.pipeline.stages.dev.verification.enabled .Values.pipeline.stages.integration.verification.enabled -}}
{{- if or (empty .Values.global.dispatcher.image.repository) (empty .Values.global.dispatcher.image.tag) }}{{ fail "global.dispatcher.image.repository and tag are required when Dev or Integration verification is enabled; the dispatcher is a prebuilt external prerequisite" }}{{ end -}}
{{- end -}}
{{- if .Values.pipeline.stages.production.verification.enabled -}}{{- if or (empty .Values.global.dispatcher.image.repository) (empty .Values.global.dispatcher.image.tag) }}{{ fail "global.dispatcher.image.repository and tag are required when Production verification is enabled; the dispatcher is a prebuilt external prerequisite" }}{{ end -}}{{- end -}}
{{- $production := .Values.pipeline.stages.production -}}{{- $success := default dict $production.outcomes.success -}}{{- $failure := default dict $production.outcomes.failure -}}
{{- if and (default false $success.serviceNow.enabled) (empty .Values.services.serviceNow.endpoint) }}{{ fail "services.serviceNow.endpoint is required when Production success ServiceNow finalization is enabled" }}{{ end -}}
{{- if and (default false $failure.serviceNow.enabled) (empty .Values.services.serviceNow.endpoint) }}{{ fail "services.serviceNow.endpoint is required when Production failure ServiceNow finalization is enabled" }}{{ end -}}
{{- if and (or (default false $success.serviceNow.enabled) (default false $failure.serviceNow.enabled)) (not .Values.pipeline.stages.preProduction.serviceNow.enabled) }}{{ fail "Production ServiceNow finalization requires pipeline.stages.preProduction.serviceNow.enabled so Freight contains a ServiceNow record identifier" }}{{ end -}}
{{- if and (default false $failure.monitoring.enabled) (empty .Values.services.monitoring.endpoint) }}{{ fail "services.monitoring.endpoint is required when Production failure monitoring is enabled" }}{{ end -}}
{{- with .Values.pipeline.stages.integration.verification -}}{{- if .enabled -}}
{{- $max := int64 (default 1000 .maxMeasurements) -}}{{- if le $max 0 }}{{ fail "pipeline.stages.integration.verification.maxMeasurements must be greater than zero" }}{{ end -}}
{{- $_ := include "generic-kargo-pipeline.durationSeconds" .initialDelay -}}
{{- if lt (int .allowedFailedMeasurements) 0 }}{{ fail "pipeline.stages.integration.verification.allowedFailedMeasurements cannot be negative" }}{{ end -}}
{{- $_ := include "generic-kargo-pipeline.measurementCount" (dict "scope" "pipeline.stages.integration.verification" "duration" .duration "interval" .interval "max" $max) -}}
{{- end -}}{{- end -}}
{{- if and .Values.pipeline.stages.preProduction.gitLab.enabled (empty .Values.pipeline.stages.preProduction.gitLab.projectPath) }}{{ fail "pipeline.stages.preProduction.gitLab.projectPath is required when GitLab MR creation is enabled" }}{{ end -}}
{{- $pre := .Values.pipeline.stages.preProduction -}}
{{- if empty $pre.ai.schedule.timezone }}{{ fail "pipeline.stages.preProduction.ai.schedule.timezone is required" }}{{ end -}}
{{- if not (regexMatch "^([01][0-9]|2[0-3]):[0-5][0-9]$" $pre.ai.schedule.startTime) }}{{ fail "pipeline.stages.preProduction.ai.schedule.startTime must be HH:mm" }}{{ end -}}
{{- if lt (int $pre.ai.schedule.workingDaysAhead) 1 }}{{ fail "pipeline.stages.preProduction.ai.schedule.workingDaysAhead must be at least 1" }}{{ end -}}
{{- if lt (int $pre.ai.schedule.durationMinutes) 1 }}{{ fail "pipeline.stages.preProduction.ai.schedule.durationMinutes must be at least 1" }}{{ end -}}
{{- $requiredAiFields := list "title" "description" "reason" "impact" "startTime" "endTime" -}}{{- if ne (len $pre.ai.requiredFields) (len $requiredAiFields) }}{{ fail "pipeline.stages.preProduction.ai.requiredFields must contain exactly title, description, reason, impact, startTime, and endTime" }}{{ end -}}{{- range $field := $requiredAiFields -}}{{- if not (has $field $pre.ai.requiredFields) }}{{ fail "pipeline.stages.preProduction.ai.requiredFields must contain exactly title, description, reason, impact, startTime, and endTime" }}{{ end -}}{{- end -}}
{{- if and $pre.ai.enabled (empty .Values.services.ai.endpoint) }}{{ fail "services.ai.endpoint is required when Pre-production AI is enabled" }}{{ end -}}
{{- if and $pre.serviceNow.enabled (empty .Values.services.serviceNow.endpoint) }}{{ fail "services.serviceNow.endpoint is required when Pre-production ServiceNow is enabled" }}{{ end -}}
{{- if and $pre.gitLab.enabled (empty .Values.services.gitLab.endpoint) }}{{ fail "services.gitLab.endpoint is required when Pre-production GitLab is enabled" }}{{ end -}}
{{- if and $pre.gitLab.enabled (not $pre.ai.enabled) (or (empty $pre.gitLab.fixedFields.title) (empty $pre.gitLab.fixedFields.description)) }}{{ fail "pipeline.stages.preProduction.gitLab.fixedFields.title and description are required when GitLab is enabled without AI" }}{{ end -}}
{{- if $pre.gitLab.enabled -}}{{- if $pre.gitLab.mergeRequest.squash }}{{ fail "pipeline.stages.preProduction.gitLab.mergeRequest.squash must be false to preserve the tested commit" }}{{ end -}}{{- if not $pre.gitLab.mergeRequest.requireCommitPreservingMerge }}{{ fail "pipeline.stages.preProduction.gitLab.mergeRequest.requireCommitPreservingMerge must be true" }}{{ end -}}{{- end -}}
{{- $destinations := dict -}}{{- range $source, $destination := $pre.serviceNow.aiFieldMapping -}}{{- if hasKey $destinations $destination }}{{ fail (printf "pipeline.stages.preProduction.serviceNow.aiFieldMapping resolves %q and %q to duplicate destination %q" (get $destinations $destination) $source $destination) }}{{ end -}}{{- $_ := set $destinations $destination $source -}}{{- end -}}
{{- if and $pre.serviceNow.enabled (not $pre.ai.enabled) (empty $pre.serviceNow.fixedFields) }}{{ fail "pipeline.stages.preProduction.serviceNow.fixedFields must not be empty when ServiceNow is enabled without AI" }}{{ end -}}
{{- $ats := dict -}}{{- range .Values.analysisTemplates -}}{{- if hasKey $ats .name }}{{ fail (printf "analysisTemplates contains duplicate name %q" .name) }}{{ end -}}{{- $_ := set $ats .name . -}}{{- end -}}
{{- range $key, $stage := .Values.pipeline.stages -}}{{- with $stage.verification -}}{{- if .enabled -}}{{- $activeReferences := 0 -}}{{- range .analysisTemplates -}}{{- if .enabled -}}{{- $activeReferences = add1 $activeReferences -}}{{- end -}}{{- end -}}{{- if eq (int $activeReferences) 0 }}{{ fail (printf "pipeline.stages.%s.verification.enabled requires at least one enabled analysisTemplate reference" $key) }}{{ end -}}{{- range .analysisTemplates -}}{{- if .enabled -}}{{- if not (hasKey $ats .name) }}{{ fail (printf "pipeline.stages.%s references unknown analysisTemplate %q" $key .name) }}{{ end -}}
{{- $definition := get $ats .name -}}{{- $type := $definition.type -}}
{{- if and (eq $definition.target "components") (eq $key "dev") (not (has $type (list "smooth" "external"))) }}{{ fail (printf "pipeline.stages.dev cannot use component-targeted analysisTemplate %q of type %s; Dev supports smooth or external" .name $type) }}{{ end -}}
{{- if and (eq $definition.target "components") (eq $key "integration") (not (has $type (list "prometheus" "elasticsearch" "external"))) }}{{ fail (printf "pipeline.stages.integration cannot use component-targeted analysisTemplate %q of type %s; Integration supports prometheus, elasticsearch, or external" .name $type) }}{{ end -}}
{{- if and (eq $type "smooth") (ne $definition.target "components") }}{{ fail (printf "smooth analysisTemplate %q must target components" .name) }}{{ end -}}
{{- if and (eq $type "smooth") (empty $definition.image) }}{{ fail (printf "active smooth analysisTemplate %q requires image" .name) }}{{ end -}}
{{- if and (eq $type "job") (empty $definition.job) }}{{ fail (printf "active job analysisTemplate %q requires job" .name) }}{{ end -}}
{{- if and (eq $type "prometheus") (empty $.Values.services.prometheus.endpoint) }}{{ fail (printf "active prometheus analysisTemplate %q requires services.prometheus.endpoint" .name) }}{{ end -}}
{{- if eq $type "prometheus" -}}{{- if empty $definition.metrics }}{{ fail (printf "active prometheus analysisTemplate %q requires metrics" .name) }}{{ end -}}{{- range $metric := $definition.metrics }}{{- if or (empty $metric.name) (empty $metric.query) }}{{ fail (printf "prometheus analysisTemplate %q metrics require name and query" $definition.name) }}{{ end -}}{{- if and (not (hasKey $metric "minimum")) (not (hasKey $metric "maximum")) (empty $metric.failureCondition) }}{{ fail (printf "prometheus analysisTemplate %q metric %q requires minimum, maximum, or failureCondition" $definition.name $metric.name) }}{{ end -}}{{- end -}}{{- end -}}
{{- if and (eq $type "elasticsearch") (empty $.Values.services.elasticsearch.endpoint) }}{{ fail (printf "active elasticsearch analysisTemplate %q requires services.elasticsearch.endpoint" .name) }}{{ end -}}
{{- if eq $type "elasticsearch" -}}{{- if empty $definition.checks }}{{ fail (printf "active elasticsearch analysisTemplate %q requires checks" .name) }}{{ end -}}{{- range $check := $definition.checks }}{{- if or (empty $check.name) (empty $check.query) }}{{ fail (printf "elasticsearch analysisTemplate %q checks require name and explicit query" $definition.name) }}{{ end -}}{{- end -}}{{- end -}}
{{- if eq $type "http" -}}{{- if or (empty $definition.service) (not (hasKey $.Values.services $definition.service)) }}{{ fail (printf "active http analysisTemplate %q requires a known service" .name) }}{{ end -}}{{- $httpService := get $.Values.services $definition.service -}}{{- if empty $httpService.endpoint }}{{ fail (printf "active http analysisTemplate %q requires services.%s.endpoint" .name $definition.service) }}{{ end -}}{{- if empty $definition.checks }}{{ fail (printf "active http analysisTemplate %q requires checks" .name) }}{{ end -}}{{- end -}}
{{- if eq $type "external" -}}
{{- $kind := default $definition.kind .kind -}}{{- if not (has $kind (list "AnalysisTemplate" "ClusterAnalysisTemplate")) }}{{ fail (printf "external analysisTemplate %q requires kind AnalysisTemplate or ClusterAnalysisTemplate" .name) }}{{ end -}}
{{- $reservedArgs := list "freightName" "releaseCommit" "changedComponents" "runForChangedComponentsOnly" "parallelismLimit" "verificationStartedAt" "initialDelay" "duration" "interval" "allowedFailedMeasurements" "dryRunAll" "serviceNowSysId" -}}
{{- $provided := dict -}}{{- range $argument := default list .arguments -}}{{- if has $argument.name $reservedArgs }}{{ fail (printf "external analysisTemplate %q Stage argument %q conflicts with a chart-owned flat argument" $definition.name $argument.name) }}{{ end -}}{{- if hasKey $provided $argument.name }}{{ fail (printf "external analysisTemplate %q has duplicate Stage argument %q" $definition.name $argument.name) }}{{ end -}}{{- $_ := set $provided $argument.name $argument.value -}}{{- end -}}
{{- $declared := dict -}}{{- range $argument := default list $definition.arguments -}}{{- if hasKey $declared $argument.name }}{{ fail (printf "external analysisTemplate %q declares duplicate argument %q" $definition.name $argument.name) }}{{ end -}}{{- $_ := set $declared $argument.name true -}}{{- if and $argument.required (not (has $argument.name $reservedArgs)) (not (hasKey $provided $argument.name)) (not (hasKey $argument "default")) }}{{ fail (printf "external analysisTemplate %q requires Stage argument %q" $definition.name $argument.name) }}{{ end -}}{{- end -}}
{{- range $argument := default list .arguments -}}{{- if not (hasKey $declared $argument.name) }}{{ fail (printf "external analysisTemplate %q received undeclared argument %q" $definition.name $argument.name) }}{{ end -}}{{- end -}}
{{- end -}}
{{- if and (eq $key "dev") (eq $type "external") (eq $definition.target "components") -}}
{{- $reference := . -}}
{{- if empty .component }}{{ fail (printf "Dev component AnalysisTemplate reference %q requires component" .name) }}{{ end -}}
{{- $matchedComponent := dict -}}{{- range $candidate := $components -}}{{- if eq $candidate.name $reference.component }}{{- $matchedComponent = $candidate -}}{{- end -}}{{- end -}}
{{- if empty $matchedComponent.name }}{{ fail (printf "Dev AnalysisTemplate reference %q selects unknown component %q" $reference.name $reference.component) }}{{ end -}}
{{- if or (not $matchedComponent.enabled) (empty $matchedComponent.qaGit.repository.url) }}{{ fail (printf "Dev AnalysisTemplate reference %q requires enabled component %q with qaGit.repository.url" $reference.name $reference.component) }}{{ end -}}
{{- end -}}
{{- with .overrides -}}{{- $allowedOverrides := dict "retryAmount" true "timeout" true "ttlAfterFinished" true "mode" true "allowedFailedMeasurements" true -}}{{- range $overrideKey, $_ := . -}}{{- if not (hasKey $allowedOverrides $overrideKey) }}{{ fail (printf "pipeline.stages.%s analysisTemplate %q has unknown or incompatible override %q" $key $definition.name $overrideKey) }}{{ end -}}{{- end -}}{{- end -}}
{{- end -}}{{- end -}}{{- end -}}{{- end -}}{{- end -}}
{{- range $name, $svc := .Values.services }}{{ include "generic-kargo-pipeline.validateService" (dict "name" $name "service" $svc) }}{{ end -}}
{{- range $result := list "success" "failure" -}}{{- $global := default dict (get $.Values.pipeline.notifications.email.defaults $result) -}}{{- range $key, $stage := $.Values.pipeline.stages -}}{{- $outcome := default dict (get (default dict $stage.outcomes) $result) -}}{{- $email := default dict (get (default dict $outcome.notifications) "email") -}}{{- if $email.enabled -}}{{- if empty $.Values.pipeline.notifications.email.recipients }}{{ fail (printf "pipeline.stages.%s.outcomes.%s email is enabled but no recipients are configured" $key $result) }}{{ end -}}{{- if and (empty $email.subject) (empty $global.subject) }}{{ fail (printf "pipeline.stages.%s.outcomes.%s email has no resolvable subject" $key $result) }}{{ end -}}{{- if and (empty $email.body) (empty $global.body) }}{{ fail (printf "pipeline.stages.%s.outcomes.%s email has no resolvable body" $key $result) }}{{ end -}}{{- end -}}{{- end -}}{{- end -}}
{{- range $result := list "success" "failure" -}}{{- range $key, $stage := $.Values.pipeline.stages -}}{{- $outcome := default dict (get (default dict $stage.outcomes) $result) -}}{{- $email := default dict (get (default dict $outcome.notifications) "email") -}}{{- if and $email.enabled (empty $.Values.services.mail.endpoint) }}{{ fail (printf "services.mail.endpoint is required when pipeline.stages.%s.outcomes.%s email is enabled" $key $result) }}{{ end -}}{{- end -}}{{- end -}}
{{- end -}}
