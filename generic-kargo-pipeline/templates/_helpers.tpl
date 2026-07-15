{{/*
Expand the chart name.
*/}}
{{- define "generic-kargo-pipeline.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Create a release-scoped chart name.
*/}}
{{- define "generic-kargo-pipeline.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- include "generic-kargo-pipeline.normalizeName" .Values.fullnameOverride -}}
{{- else -}}
{{- $name := default .Chart.Name .Values.nameOverride -}}
{{- if contains $name .Release.Name -}}
{{- include "generic-kargo-pipeline.normalizeName" .Release.Name -}}
{{- else -}}
{{- include "generic-kargo-pipeline.normalizeName" (printf "%s-%s" .Release.Name $name) -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{/*
Return the Kargo Project name. The project is bound to the Helm release namespace.
*/}}
{{- define "generic-kargo-pipeline.projectName" -}}
{{- include "generic-kargo-pipeline.normalizeName" .Release.Namespace -}}
{{- end -}}

{{/*
Secret containing credentials for the deployment configuration Git repository.
*/}}
{{- define "generic-kargo-pipeline.deploymentGitSecretName" -}}
deploymentgit
{{- end -}}

{{/*
Secret containing credentials for a component developer-owned Git repository.
*/}}
{{- define "generic-kargo-pipeline.componentDevGitSecretName" -}}
{{- printf "%s-devgit" .name | include "generic-kargo-pipeline.normalizeName" -}}
{{- end -}}

{{/*
Built-in component defaults keep values.yaml focused on application-specific inputs.
*/}}
{{- define "generic-kargo-pipeline.componentDefaults" -}}
image:
  selectionStrategy: NewestBuild
  allowedTags: ""
  semverConstraint: ""
  strictSemvers: false
  discoveryLimit: 20
releaseConfiguration:
  generationEnabled: false
{{- end -}}

{{/*
Validate that a Git credential pair is either complete or empty.
*/}}
{{- define "generic-kargo-pipeline.validateGitCredentialPair" -}}
{{- $scope := .scope -}}
{{- $username := default "" .username -}}
{{- $password := default "" .password -}}
{{- if or (and $username (not $password)) (and $password (not $username)) -}}
{{- fail (printf "%s credentials must set both username and password or leave both empty" $scope) -}}
{{- end -}}
{{- end -}}

{{/*
Wrap an expression body in Kargo's expression delimiters without nesting
Kargo delimiters directly inside a Helm template action.
*/}}
{{- define "generic-kargo-pipeline.kargoExpression" -}}
{{- printf "$%s %s %s" (repeat 2 "{") . (repeat 2 "}") -}}
{{- end -}}

{{/*
Validate a path that will be placed beneath a Kargo promotion workspace.
*/}}
{{- define "generic-kargo-pipeline.validateWorkspaceRelativePath" -}}
{{- $scope := .scope -}}
{{- $path := default "" .path -}}
{{- $normalizedPath := replace "\\" "/" $path -}}
{{- if or (not $path) (hasPrefix "/" $normalizedPath) (regexMatch "^[A-Za-z]:" $normalizedPath) (has ".." (splitList "/" $normalizedPath)) -}}
{{- fail (printf "%s must be a non-empty relative path without parent traversal" $scope) -}}
{{- end -}}
{{- end -}}

{{/*
Validate values that cannot be expressed cleanly in JSON Schema.
*/}}
{{- define "generic-kargo-pipeline.validateValues" -}}
{{- $componentNames := dict -}}
{{- $releaseOutputPaths := dict -}}
{{- $builtInComponentDefaults := include "generic-kargo-pipeline.componentDefaults" . | fromYaml -}}
{{- $componentDefaults := mergeOverwrite (deepCopy $builtInComponentDefaults) (default dict .Values.sources.componentDefaults) -}}
{{- range .Values.sources.components }}
{{- $component := mergeOverwrite (deepCopy $componentDefaults) . -}}
{{- $componentName := include "generic-kargo-pipeline.normalizeName" .name -}}
{{- if hasKey $componentNames $componentName -}}
{{- fail (printf "sources.components contains duplicate normalized component name %q" $componentName) -}}
{{- end -}}
{{- $_ := set $componentNames $componentName true -}}
{{- $gitRepository := default dict .git.repository -}}
{{- include "generic-kargo-pipeline.validateGitCredentialPair" (dict "scope" (printf "component %q developer Git" .name) "username" $gitRepository.username "password" $gitRepository.password) -}}
{{- if $component.enabled -}}
{{- $releaseConfiguration := default dict .releaseConfiguration -}}
{{- $resolvedOutputPath := replace "name" $componentName $releaseConfiguration.outputPath -}}
{{- include "generic-kargo-pipeline.validateWorkspaceRelativePath" (dict "scope" (printf "component %q releaseConfiguration.outputPath" .name) "path" $resolvedOutputPath) -}}
{{- $normalizedOutputPath := replace "\\" "/" $resolvedOutputPath -}}
{{- if hasKey $releaseOutputPaths $normalizedOutputPath -}}
{{- fail (printf "enabled components %q and %q resolve to the same releaseConfiguration.outputPath %q" (get $releaseOutputPaths $normalizedOutputPath) .name $resolvedOutputPath) -}}
{{- end -}}
{{- $_ := set $releaseOutputPaths $normalizedOutputPath .name -}}
{{- if $releaseConfiguration.generationEnabled -}}
{{- $resolvedDevPath := replace "name" $componentName $releaseConfiguration.devConfigurationPath -}}
{{- $resolvedOverlayPath := replace "name" $componentName $releaseConfiguration.deploymentOverlayPath -}}
{{- include "generic-kargo-pipeline.validateWorkspaceRelativePath" (dict "scope" (printf "component %q releaseConfiguration.devConfigurationPath" .name) "path" $resolvedDevPath) -}}
{{- include "generic-kargo-pipeline.validateWorkspaceRelativePath" (dict "scope" (printf "component %q releaseConfiguration.deploymentOverlayPath" .name) "path" $resolvedOverlayPath) -}}
{{- end -}}
{{- end -}}
{{- end -}}
{{- $deploymentRepository := default dict .Values.sources.deploymentGit.repository -}}
{{- include "generic-kargo-pipeline.validateGitCredentialPair" (dict "scope" "deployment Git" "username" $deploymentRepository.username "password" $deploymentRepository.password) -}}
{{- end -}}

{{/*
Normalize arbitrary input into a Kubernetes resource name.
*/}}
{{- define "generic-kargo-pipeline.normalizeName" -}}
{{- regexReplaceAll "[^a-z0-9-]" (. | lower) "-" | trimAll "-" | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Common chart labels.
*/}}
{{- define "generic-kargo-pipeline.labels" -}}
{{- with .Values.global.labels }}
{{- toYaml . }}
{{- end }}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | quote }}
app.kubernetes.io/name: {{ include "generic-kargo-pipeline.name" . | quote }}
app.kubernetes.io/instance: {{ .Release.Name | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service | quote }}
app.kubernetes.io/part-of: {{ include "generic-kargo-pipeline.name" . | quote }}
{{- with .Chart.AppVersion }}
app.kubernetes.io/version: {{ . | quote }}
{{- end }}
{{- end -}}

{{/*
Kargo identity labels.
*/}}
{{- define "generic-kargo-pipeline.applicationLabels" -}}
app.kubernetes.io/component: promotion-pipeline
kargo.akuity.io/project: {{ include "generic-kargo-pipeline.projectName" . | quote }}
{{- end -}}
