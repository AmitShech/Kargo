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
