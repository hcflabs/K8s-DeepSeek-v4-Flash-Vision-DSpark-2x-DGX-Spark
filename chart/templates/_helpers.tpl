{{- define "dspark.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "dspark.fullname" -}}
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

{{- define "dspark.labels" -}}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
app.kubernetes.io/name: {{ include "dspark.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: dspark-vllm
{{- end -}}

{{- define "dspark.selectorLabels" -}}
app.kubernetes.io/name: {{ include "dspark.name" .root }}
app.kubernetes.io/instance: {{ .root.Release.Name }}
app.kubernetes.io/component: {{ .component }}
{{- end -}}

{{- define "dspark.image" -}}
{{- if .Values.image.digest -}}
{{- printf "%s:%s@%s" .Values.image.repository .Values.image.tag .Values.image.digest -}}
{{- else -}}
{{- printf "%s:%s" .Values.image.repository .Values.image.tag -}}
{{- end -}}
{{- end -}}

{{/* Secret holding the API keys, or empty when /v1 is unauthenticated. */}}
{{- define "dspark.authSecretName" -}}
{{- if .Values.auth.existingSecret -}}
{{- .Values.auth.existingSecret -}}
{{- else if or .Values.auth.apiKey .Values.auth.apiKeys -}}
{{- printf "%s-api-key" (include "dspark.fullname" .) -}}
{{- end -}}
{{- end -}}

{{/* Per-rank pod environment. Args: dict "root" . "rank" 0|1 */}}
{{- define "dspark.env" -}}
{{- $v := .root.Values -}}
{{- $hf := $v.hotfixes -}}
- {name: VLLM_NODE_RANK, value: {{ .rank | quote }}}
- {name: VLLM_MASTER_ADDR, value: {{ required "topology.fabric.masterAddr is required" $v.topology.fabric.masterAddr | quote }}}
- {name: DSPARK_WORKER_ADDR, value: {{ required "topology.fabric.workerAddr is required" $v.topology.fabric.workerAddr | quote }}}
- {name: DSPARK_BEACON_PORT, value: {{ $v.topology.fabric.beaconPort | quote }}}
- {name: DSPARK_MASTER_PORT, value: {{ $v.topology.fabric.port | quote }}}
- {name: DSPARK_MODEL_DIR, value: {{ printf "/models/%s" $v.model.dirName | quote }}}
- {name: DSPARK_SERVED_MODEL_NAME, value: {{ $v.model.servedName | quote }}}
- {name: DSPARK_MAX_MODEL_LEN, value: {{ $v.serving.maxModelLen | quote }}}
- {name: DSPARK_KV_CACHE_DTYPE, value: {{ $v.serving.kvCacheDtype | quote }}}
- {name: DSPARK_MOE_BACKEND, value: {{ $v.serving.moeBackend | quote }}}
- {name: DSPARK_BLOCK_SIZE, value: {{ $v.serving.blockSize | quote }}}
- {name: DSPARK_GPU_MEMORY_UTILIZATION, value: {{ $v.serving.gpuMemoryUtilization | quote }}}
- {name: DSPARK_MAX_NUM_SEQS, value: {{ $v.serving.maxNumSeqs | quote }}}
- {name: DSPARK_MAX_NUM_BATCHED_TOKENS, value: {{ $v.serving.maxNumBatchedTokens | quote }}}
- {name: DSPARK_LONG_PREFILL_TOKEN_THRESHOLD, value: {{ $v.serving.longPrefillTokenThreshold | quote }}}
- {name: DSPARK_MAX_CUDAGRAPH_CAPTURE_SIZE, value: {{ $v.serving.maxCudagraphCaptureSize | quote }}}
- {name: DSPARK_ASYNC_SCHEDULING, value: {{ ternary "1" "0" $v.serving.asyncScheduling | quote }}}
- {name: DSPARK_FLASHINFER_AUTOTUNE, value: {{ ternary "1" "0" $v.serving.flashinferAutotune | quote }}}
- {name: DSPARK_LIMIT_MM_PER_PROMPT, value: {{ $v.serving.limitMmPerPrompt | quote }}}
- {name: DSPARK_CHAT_TEMPLATE_KWARGS, value: {{ $v.serving.chatTemplateKwargs | quote }}}
- {name: DSPARK_SPEC_METHOD, value: {{ $v.serving.speculative.method | quote }}}
- {name: DSPARK_SPEC_TOKENS, value: {{ $v.serving.speculative.numTokens | quote }}}
- {name: DSPARK_SPEC_DRAFT_SAMPLE, value: {{ $v.serving.speculative.draftSampleMethod | quote }}}
- {name: DSPARK_EXTRA_ARGS, value: {{ $v.serving.extraArgs | quote }}}
- {name: NCCL_IB_HCA, value: {{ required "topology.fabric.rdmaDevice is required" $v.topology.fabric.rdmaDevice | quote }}}
- {name: NCCL_SOCKET_IFNAME, value: {{ required "topology.fabric.interface is required" $v.topology.fabric.interface | quote }}}
- {name: NCCL_DEBUG, value: {{ $v.serving.ncclDebug | quote }}}
- {name: NCCL_DEBUG_SUBSYS, value: "INIT,NET"}
- {name: VLLM_USE_BREAKABLE_CUDAGRAPH, value: {{ ternary "1" "0" $v.serving.breakableCudagraph | quote }}}
- {name: VLLM_PREFIX_CACHE_RETENTION_INTERVAL, value: {{ $v.serving.prefixCacheRetentionInterval | quote }}}
- {name: PYTORCH_CUDA_ALLOC_CONF, value: "expandable_segments:True"}
- {name: NVIDIA_DISABLE_FORWARD_COMPATIBILITY, value: "1"}
- {name: OMP_NUM_THREADS, value: {{ $v.serving.ompNumThreads | quote }}}
{{- range $key, $envName := dict "issue31ThinkingBudget" "DSPARK_ENABLE_ISSUE31_GPU_HOTFIX" "adaptiveChunk" "DSPARK_ENABLE_ADAPTIVE_CHUNK" "replicateMarkov" "DSPARK_ENABLE_REPLICATE_MARKOV" "spIndexer" "DSPARK_ENABLE_SP_INDEXER" "deepgemmSm121Alias" "DSPARK_ENABLE_DEEPGEMM_SM121_ALIAS" "issue141SparseMlaChunk" "DSPARK_ENABLE_ISSUE141_SPARSE_MLA_CHUNK" "assistantFinal" "DSPARK_ENABLE_ASSISTANT_FINAL_HOTFIX" "issue144EffortAlign" "DSPARK_ENABLE_ISSUE144_EFFORT_ALIGN" "issue136Xgrammar" "DSPARK_ENABLE_ISSUE136_XGRAMMAR_HOTFIX" "issue191ToolcallFailclosed" "DSPARK_ENABLE_ISSUE191_TOOLCALL_FAILCLOSED" "dsparkBlockK" "DSPARK_ENABLE_DSPARK_BLOCK_K" "ropeSwaFix" "DSPARK_ENABLE_ROPE_SWA_FIX" "dsparkSwaPrefix" "DSPARK_ENABLE_DSPARK_SWA_PREFIX" "dsmlRecovery" "DSPARK_ENABLE_DSML_RECOVERY" "mxfp4IndexerCache" "DSPARK_ENABLE_MXFP4_INDEXER_CACHE" "c128aPrefillCache" "DSPARK_ENABLE_C128A_PREFILL_CACHE" "issue138ResponsesHistory" "DSPARK_ENABLE_ISSUE138_RESPONSES_HISTORY_COMPAT" "codexAgentMessage" "DSPARK_ENABLE_CODEX_AGENT_MESSAGE_COMPAT" "responsesStore" "VLLM_ENABLE_RESPONSES_API_STORE" }}
- {name: {{ $envName }}, value: {{ ternary "1" "0" (index $hf.enable $key | default false) | quote }}}
{{- end }}
{{- range $key, $envName := dict "issue22" "DSPARK_SKIP_ISSUE22_HOTFIX" "spinWait" "DSPARK_SKIP_SPIN_WAIT_HOTFIX" "issue117Recheck" "DSPARK_SKIP_ISSUE117_RECHECK_HOTFIX" "batch" "DSPARK_SKIP_HOTFIX" "suppressStops" "DSPARK_SKIP_SUPPRESS_STOPS_HOTFIX" }}
- {name: {{ $envName }}, value: {{ ternary "1" "0" (index $hf.skip $key | default false) | quote }}}
{{- end }}
{{- if $v.ablation.enabled }}
- {name: DSPARK_ABLATE, value: "1"}
- {name: DSPARK_ABLATE_FILE, value: /opt/dspark-ablation/direction_r1.pt}
{{- if $v.ablation.lambda }}
- {name: DSV4_ABLATE_LAMBDA, value: {{ $v.ablation.lambda | quote }}}
{{- end }}
{{- if $v.ablation.layers }}
- {name: DSV4_ABLATE_LAYERS, value: {{ $v.ablation.layers | quote }}}
{{- end }}
{{- end }}
{{- with (include "dspark.authSecretName" .root) }}
- name: DSPARK_API_KEYS
  valueFrom:
    secretKeyRef:
      name: {{ . }}
      key: {{ if $v.auth.existingSecret }}{{ $v.auth.existingSecretKey }}{{ else }}token{{ end }}
{{- end }}
{{- with $v.serving.extraEnv }}
{{ toYaml . }}
{{- end }}
{{- end -}}

{{/* Pod spec shared by both ranks. Args: dict "root" . "rank" 0|1 "component" leader|worker */}}
{{- define "dspark.podSpec" -}}
{{- $v := .root.Values -}}
{{- $isLeader := eq (int .rank) 0 -}}
enableServiceLinks: false
hostNetwork: true
dnsPolicy: ClusterFirstWithHostNet
{{- with $v.runtimeClassName }}
runtimeClassName: {{ . }}
{{- end }}
{{- with $v.imagePullSecrets }}
imagePullSecrets:
{{ toYaml . | indent 2 }}
{{- end }}
nodeSelector:
  {{ $v.topology.rankLabels.key }}: {{ ternary $v.topology.rankLabels.leader $v.topology.rankLabels.worker $isLeader | quote }}
tolerations:
  - {{ toYaml $v.topology.gpuToleration | nindent 4 | trim }}
{{- if $isLeader }}
initContainers:
  - name: wait-for-worker
    image: {{ include "dspark.image" .root | quote }}
    imagePullPolicy: {{ $v.image.pullPolicy }}
    command: [bash, /etc/vllm/wait-for-worker.sh]
    env:
      - {name: DSPARK_WORKER_ADDR, value: {{ required "topology.fabric.workerAddr is required" $v.topology.fabric.workerAddr | quote }}}
      - {name: DSPARK_BEACON_PORT, value: {{ $v.topology.fabric.beaconPort | quote }}}
    volumeMounts:
      - {name: serve, mountPath: /etc/vllm}
{{- end }}
containers:
  - name: vllm
    image: {{ include "dspark.image" .root | quote }}
    imagePullPolicy: {{ $v.image.pullPolicy }}
    command: [bash, /etc/vllm/serve.sh]
{{- if $isLeader }}
    ports:
      - {name: http, containerPort: 8000}
{{- end }}
    env:
{{ include "dspark.env" . | indent 6 }}
    resources:
{{ toYaml $v.resources | indent 6 }}
    securityContext:
      privileged: true
    volumeMounts:
      - {name: models, mountPath: {{ printf "/models/%s" $v.model.dirName }}, readOnly: true}
      - {name: serve, mountPath: /etc/vllm}
      - {name: hotfixes, mountPath: /etc/vllm-hotfixes}
      - {name: vision-exp, mountPath: /opt/dspark-patches/vision_exp}
      - {name: rdma, mountPath: /dev/infiniband}
      - {name: shm, mountPath: /dev/shm}
{{- if $v.ablation.enabled }}
      - {name: ablation, mountPath: /opt/dspark-ablation/direction_r1.pt, readOnly: true}
{{- end }}
{{- if $isLeader }}
    startupProbe:
      httpGet: {path: /health, port: http}
{{ toYaml $v.probes.startup | indent 6 }}
    livenessProbe:
      httpGet: {path: /health, port: http}
{{ toYaml $v.probes.liveness | indent 6 }}
    readinessProbe:
      httpGet: {path: /health, port: http}
{{ toYaml $v.probes.readiness | indent 6 }}
{{- end }}
volumes:
  - name: models
{{- if and (not $isLeader) $v.weights.nfs.enabled }}
    nfs:
      server: {{ required "weights.nfs.server is required when weights.nfs.enabled" $v.weights.nfs.server | quote }}
      path: {{ required "weights.nfs.path is required when weights.nfs.enabled" $v.weights.nfs.path | quote }}
      readOnly: true
{{- else }}
    hostPath:
      path: {{ required (printf "weights.hostPath.%s is required" (ternary "leader" "worker" $isLeader)) (ternary $v.weights.hostPath.leader $v.weights.hostPath.worker $isLeader) | quote }}
      type: Directory
{{- end }}
  - name: serve
    configMap:
      name: {{ include "dspark.fullname" .root }}-serve
  - name: hotfixes
    configMap:
      name: {{ include "dspark.fullname" .root }}-hotfixes
  - name: vision-exp
    configMap:
      name: {{ include "dspark.fullname" .root }}-hotfixes-vision
  - name: rdma
    hostPath:
      path: /dev/infiniband
      type: Directory
  - name: shm
    emptyDir:
      medium: Memory
      sizeLimit: {{ $v.shm.sizeLimit }}
{{- if $v.ablation.enabled }}
  - name: ablation
    hostPath:
      path: {{ required "ablation.directionHostPath is required when ablation.enabled" $v.ablation.directionHostPath | quote }}
      type: File
{{- end }}
{{- end -}}
