{{/* ============================================================== */}}
{{/* Standard naming                                                  */}}
{{/* ============================================================== */}}

{{- define "bdgz.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "bdgz.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- $name := default .Chart.Name .Values.nameOverride -}}
{{- if contains $name .Release.Name -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{- define "bdgz.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/* ============================================================== */}}
{{/* Labels                                                           */}}
{{/* ============================================================== */}}

{{- define "bdgz.labels" -}}
helm.sh/chart: {{ include "bdgz.chart" . }}
{{ include "bdgz.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: wazuh
app.kubernetes.io/component: gravityzone-connector
{{- end -}}

{{- define "bdgz.selectorLabels" -}}
app.kubernetes.io/name: {{ include "bdgz.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{/* ============================================================== */}}
{{/* Resolved names of dependent objects                              */}}
{{/* ============================================================== */}}

{{- define "bdgz.serviceAccountName" -}}
{{- if .Values.serviceAccount.create -}}
{{- default (include "bdgz.fullname" .) .Values.serviceAccount.name -}}
{{- else -}}
{{- default "default" .Values.serviceAccount.name -}}
{{- end -}}
{{- end -}}

{{/* Name of the Secret holding the AUTH header (created OR referenced). */}}
{{- define "bdgz.authSecretName" -}}
{{- if and .Values.auth.existingSecret .Values.auth.existingSecret.name -}}
{{- .Values.auth.existingSecret.name -}}
{{- else -}}
{{- printf "%s-auth" (include "bdgz.fullname" .) -}}
{{- end -}}
{{- end -}}

{{- define "bdgz.authSecretKey" -}}
{{- if and .Values.auth.existingSecret .Values.auth.existingSecret.key -}}
{{- .Values.auth.existingSecret.key -}}
{{- else -}}
auth
{{- end -}}
{{- end -}}

{{/* Whether the chart should render its own AUTH Secret. */}}
{{- define "bdgz.createAuthSecret" -}}
{{- if and .Values.auth.existingSecret .Values.auth.existingSecret.name -}}
false
{{- else if .Values.auth.value -}}
true
{{- else -}}
false
{{- end -}}
{{- end -}}

{{/* TLS secret accessors. */}}
{{- define "bdgz.tlsSecretName" -}}
{{- if and (eq .Values.tls.mode "existingSecret") .Values.tls.existingSecret -}}
{{- .Values.tls.existingSecret.name -}}
{{- end -}}
{{- end -}}

{{/* Image reference — uses digest when set, otherwise tag, otherwise appVersion. */}}
{{- define "bdgz.image" -}}
{{- $repo := .Values.image.repository -}}
{{- if .Values.image.digest -}}
{{- printf "%s@%s" $repo .Values.image.digest -}}
{{- else -}}
{{- $tag := default .Chart.AppVersion .Values.image.tag -}}
{{- printf "%s:%s" $repo $tag -}}
{{- end -}}
{{- end -}}
