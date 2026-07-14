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
enabled: true
image:
  selectionStrategy: NewestBuild
  allowedTags: ""
  semverConstraint: ""
  strictSemvers: false
  discoveryLimit: 20
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
Validate values that cannot be expressed cleanly in JSON Schema.
*/}}
{{- define "generic-kargo-pipeline.validateValues" -}}
{{- $componentNames := dict -}}
{{- range .Values.sources.components }}
{{- $componentName := include "generic-kargo-pipeline.normalizeName" .name -}}
{{- if hasKey $componentNames $componentName -}}
{{- fail (printf "sources.components contains duplicate normalized component name %q" $componentName) -}}
{{- end -}}
{{- $_ := set $componentNames $componentName true -}}
{{- $gitRepository := default dict .git.repository -}}
{{- include "generic-kargo-pipeline.validateGitCredentialPair" (dict "scope" (printf "component %q developer Git" .name) "username" $gitRepository.username "password" $gitRepository.password) -}}
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
