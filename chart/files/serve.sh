#!/usr/bin/env bash
# Entrypoint for both ranks. Applies the vendored runtime hotfixes in the fixed
# order of the upstream Compose command block
# (MiaAI-Lab/DeepSeek-v4-Flash-DSpark-2x-DGX-Spark, docker-compose.dspark.yml),
# then execs `vllm serve`. Every parameter arrives as an environment variable
# rendered from the chart's values.yaml. See SYNC.md for the file mapping.
#
# Each hotfix is idempotent and anchored: a moved anchor makes the script exit
# non-zero, which fails this entrypoint (and the pod) instead of serving
# silently degraded.
#
# Extra modes (used by scripts/check-anchors.sh):
#   DSPARK_CHECK_ALL=1   treat every gate as enabled
#   DSPARK_APPLY_ONLY=1  stop after the hotfixes instead of starting vLLM
set -euo pipefail

export PATH="/usr/local/cuda/bin:/usr/local/bin:${PATH:-}"
export CUDA_HOME="${CUDA_HOME:-/usr/local/cuda}"
export LD_LIBRARY_PATH="/usr/local/cuda/lib64:${LD_LIBRARY_PATH:-}"

HF="${DSPARK_HOTFIX_DIR:-/etc/vllm-hotfixes}"
MODEL_DIR="${DSPARK_MODEL_DIR:-/models/model}"
CHECK_ALL="${DSPARK_CHECK_ALL:-0}"
APPLY_ONLY="${DSPARK_APPLY_ONLY:-0}"

# on VAR -> true when VAR=1 (or check-all mode).
on() { [ "${!1:-0}" = "1" ] || [ "${CHECK_ALL}" = "1" ]; }

# run LABEL CMD... -> run a hotfix, report applied / FAIL, abort on failure.
run() {
  local label="$1" rc=0
  shift
  "$@" || rc=$?
  if [ "${rc}" -ne 0 ]; then
    echo "[hotfix] FAIL    ${label} (exit ${rc})" >&2
    exit "${rc}"
  fi
  echo "[hotfix] applied ${label}"
}

skip() { echo "[hotfix] skip    $1 ($2)"; }

# gated VAR LABEL CMD... -> run only when the gate is on.
gated() {
  local var="$1" label="$2"
  shift 2
  if on "${var}"; then run "${label}" "$@"; else skip "${label}" "${var}!=1"; fi
}

# unless_skipped VAR LABEL CMD... -> run unless VAR=1 (opt-out hotfixes).
unless_skipped() {
  local var="$1" label="$2"
  shift 2
  if [ "${!var:-0}" = "1" ]; then skip "${label}" "${var}=1"; else run "${label}" "$@"; fi
}

# ── 1. Encoder copy + reasoning-effort mapping + issue #21 ──
ENC_SRC="${MODEL_DIR}/encoding/encoding_dsv4.py"
if [ -f "${ENC_SRC}" ]; then
  cp "${ENC_SRC}" \
    /usr/local/lib/python3.12/dist-packages/vllm/tokenizers/deepseek_v4_encoding.py
  run reasoning-effort-map python3 "${HF}/hotfix-dsv4-reasoning-effort-map.py"
  run issue21-encoding python3 "${HF}/hotfix-encoding-dsv4-issue21.py"
elif [ "${CHECK_ALL}" = "1" ]; then
  run reasoning-effort-map python3 "${HF}/hotfix-dsv4-reasoning-effort-map.py"
  skip issue21-encoding "no model encoder in check mode"
else
  echo "WARN: encoder not found at ${ENC_SRC} - vision + reasoning-effort skipped" >&2
fi

# ── 2. Issue #31 thinking-token budget (gated) ──
gated DSPARK_ENABLE_ISSUE31_GPU_HOTFIX issue31-thinking-budget \
  python3 "${HF}/hotfix-dsv4-issue31-v2-thinking-budget-gpu.py"

# ── 3. Issue #55 tool-call truncation (always) ──
run issue55-tool-truncation python3 "${HF}/hotfix-dsv4-issue55-tool-truncation.py"

# ── 4. Issue #22 nvfp4_ds_mla long-context decode ──
unless_skipped DSPARK_SKIP_ISSUE22_HOTFIX issue22-nvfp4-ds-mla \
  bash "${HF}/hotfix-nvfp4-ds-mla-issue22.sh"

# ── 5. Issue #79 spin-wait ──
unless_skipped DSPARK_SKIP_SPIN_WAIT_HOTFIX issue79-spin-wait \
  bash "${HF}/hotfix-gb10-spin-wait.sh"

# ── 6. Issue #117 SHM ring buffer ──
if [ "${DSPARK_SKIP_ISSUE117_RECHECK_HOTFIX:-0}" != "1" ]; then
  run issue117-shm-ring-buffer python3 "${HF}/hotfix-vllm-issue117-shm-ring-buffer.py"
  run issue117-shm-ring-buffer-status python3 "${HF}/hotfix-vllm-issue117-shm-ring-buffer.py" --status
else
  skip issue117-shm-ring-buffer "DSPARK_SKIP_ISSUE117_RECHECK_HOTFIX=1"
fi

# ── 7. Batch shell hotfixes (unless DSPARK_SKIP_HOTFIX=1) ──
if [ "${DSPARK_SKIP_HOTFIX:-0}" != "1" ]; then
  for _hf in hotfix-dsv4-mtp-buffer-50312.sh \
             hotfix-dsv4-skip-topk-49486.sh \
             hotfix-dsv4-dense-prefill-indexer-48407.sh \
             hotfix-dsv4-skip-empty-c128-48957.sh \
             hotfix-dsv4-flashmla-workspace-50298.sh \
             hotfix-dsv4-grammar-advance.sh; do
    run "${_hf%.sh}" bash "${HF}/${_hf}"
  done
else
  skip batch-shell-hotfixes "DSPARK_SKIP_HOTFIX=1"
fi

# ── 8. API-key redact (when keys are set) ──
if [ -n "${DSPARK_API_KEYS:-}" ] || [ "${CHECK_ALL}" = "1" ]; then
  run redact-api-key-log bash "${HF}/hotfix-vllm-redact-api-key-log.sh"
  run redact-api-key-log-status bash "${HF}/hotfix-vllm-redact-api-key-log.sh" --status
else
  skip redact-api-key-log "no API keys configured"
fi

# ── 9. Responses store (gated) ──
gated VLLM_ENABLE_RESPONSES_API_STORE responses-store \
  python3 "${HF}/hotfix-dsv4-responses-store.py"

# ── 10. Issue #138 Responses history compat (gated) ──
gated DSPARK_ENABLE_ISSUE138_RESPONSES_HISTORY_COMPAT issue138-responses-history \
  python3 "${HF}/hotfix-vllm-issue138-responses-history.py"

# ── 11. Codex agent_message compat (gated) ──
gated DSPARK_ENABLE_CODEX_AGENT_MESSAGE_COMPAT codex-agent-message \
  python3 "${HF}/hotfix-vllm-codex-agent-message.py"

# ── 12. Vision-Exp native image support (always) ──
run vision-exp python3 "${HF}/hotfix-dsv4-vision-exp.py"

# ── 13. Issue #141 sparse MLA decode chunk (gated) ──
gated DSPARK_ENABLE_ISSUE141_SPARSE_MLA_CHUNK issue141-sparse-mla-chunk \
  python3 "${HF}/hotfix-dsv4-issue141-sparse-mla-decode-chunk.py"

# ── 14. SP indexer prefill (gated) ──
gated DSPARK_ENABLE_SP_INDEXER sp-indexer-prefill \
  python3 "${HF}/hotfix-dsv4-sp-indexer-prefill.py"

# ── 15. DeepGEMM sm121 alias (gated) ──
gated DSPARK_ENABLE_DEEPGEMM_SM121_ALIAS deepgemm-sm121-alias \
  bash "${HF}/hotfix-deepgemm-sm121-mqa-header-alias.sh"

# ── 16. Empty encoder output (always) ──
run empty-encoder-output python3 "${HF}/hotfix-vllm-empty-encoder-output.py"

# ── 17. Issue #27 partial-prefill concurrency (always) ──
run issue27-partial-prefill python3 "${HF}/hotfix-dsv4-issue27-partial-prefill-concurrency.py"

# ── 18. Adaptive prefill chunk (gated) ──
gated DSPARK_ENABLE_ADAPTIVE_CHUNK adaptive-prefill-chunk \
  python3 "${HF}/hotfix-dsv4-adaptive-prefill-chunk.py"

# ── 19. Replicate Markov head (gated) ──
gated DSPARK_ENABLE_REPLICATE_MARKOV replicate-markov-head \
  python3 "${HF}/hotfix-dsv4-replicate-markov-head.py"

# ── 20. Issue #43 decode fairness + diag (always) ──
run issue43-decode-fairness python3 "${HF}/hotfix-dsv4-issue43-decode-fairness-and-diag.py"

# ── 21. Issue #26 hybrid SWA min (always) ──
run issue26-hybrid-swa-min python3 "${HF}/hotfix-dsv4-issue26-hybrid-swa-min.py"

# ── 22. Issue #133 Triton specialization (always) ──
run issue133-triton-specialization python3 "${HF}/hotfix-dsv4-issue133-triton-specialization.py"

# ── 23. Runtime ablation (always; inert unless DSPARK_ABLATE=1) ──
if [ "${DSPARK_ABLATE:-0}" = "1" ]; then
  : "${DSPARK_ABLATE_FILE:?DSPARK_ABLATE_FILE is required when ablation is enabled}"
  [ -f "${DSPARK_ABLATE_FILE}" ] || {
    echo "FATAL: ablation direction file ${DSPARK_ABLATE_FILE} not found" >&2
    exit 1
  }
  export DSV4_ABLATE_FILE="${DSPARK_ABLATE_FILE}"
else
  unset DSV4_ABLATE_FILE
fi
run runtime-ablation python3 "${HF}/hotfix-dsv4-runtime-ablation.py"

# ── 24. Suppress stops in reasoning ──
unless_skipped DSPARK_SKIP_SUPPRESS_STOPS_HOTFIX suppress-stops-in-reasoning \
  python3 "${HF}/hotfix-dsv4-suppress-stops-in-reasoning.py"

# ── 25. Assistant final continuation (gated) ──
gated DSPARK_ENABLE_ASSISTANT_FINAL_HOTFIX assistant-final-continuation \
  python3 "${HF}/hotfix-dsv4-assistant-final-continuation.py"

# ── 26. Issue #144 effort align (gated) ──
gated DSPARK_ENABLE_ISSUE144_EFFORT_ALIGN issue144-effort-align \
  python3 "${HF}/hotfix-dsv4-issue144-effort-align.py"

# ── 27. Issue #136 XGrammar termination (gated) ──
gated DSPARK_ENABLE_ISSUE136_XGRAMMAR_HOTFIX issue136-xgrammar-termination \
  python3 "${HF}/hotfix-vllm-issue136-xgrammar-termination.py"

# ── 28. Issue #191 toolcall fail-closed (gated) ──
gated DSPARK_ENABLE_ISSUE191_TOOLCALL_FAILCLOSED issue191-toolcall-failclosed \
  python3 "${HF}/hotfix-vllm-issue191-toolcall-failclosed.py"

# ── 29. DSpark block-k (gated) ──
gated DSPARK_ENABLE_DSPARK_BLOCK_K dspark-block-k \
  python3 "${HF}/hotfix-vllm-dspark-block-k.py"

# ── 30. RoPE SWA fix (gated) ──
gated DSPARK_ENABLE_ROPE_SWA_FIX rope-swa-fix \
  python3 "${HF}/hotfix-vllm-rope-swa-fix.py"

# ── 31. DSpark SWA prefix (gated) ──
gated DSPARK_ENABLE_DSPARK_SWA_PREFIX dspark-swa-prefix \
  python3 "${HF}/hotfix-vllm-dspark-swa-prefix.py"

# ── 32. DSML recovery (gated) ──
gated DSPARK_ENABLE_DSML_RECOVERY dsml-recovery \
  python3 "${HF}/hotfix-vllm-dsml-recovery.py"

# ── 33. MXFP4 indexer cache (gated) ──
gated DSPARK_ENABLE_MXFP4_INDEXER_CACHE mxfp4-indexer-cache \
  python3 "${HF}/hotfix-vllm-mxfp4-indexer-cache.py"

# ── 34. C128A prefill cache (gated) ──
gated DSPARK_ENABLE_C128A_PREFILL_CACHE c128a-prefill-cache \
  python3 "${HF}/hotfix-vllm-c128a-prefill-cache.py"

if [ "${APPLY_ONLY}" = "1" ]; then
  echo "[hotfix] all hotfixes processed (DSPARK_APPLY_ONLY=1, not starting vLLM)"
  exit 0
fi

# ── Chart-specific: rank-1 beacon + headless ──
extra_args=()
if [ "${VLLM_NODE_RANK}" != "0" ]; then
  python3 "${HF}/hotfix-worker-beacon.py" &
  extra_args+=(--headless)
fi

# ── API keys (space-separated list; vLLM's --api-key accepts several) ──
api_key_args=()
if [ -n "${DSPARK_API_KEYS:-}" ]; then
  read -r -a _keys <<<"${DSPARK_API_KEYS}"
  api_key_args=(--api-key "${_keys[@]}")
fi

# ── Serve flags ──
speculative_config="{\"method\":\"${DSPARK_SPEC_METHOD}\",\"num_speculative_tokens\":${DSPARK_SPEC_TOKENS},\"draft_sample_method\":\"${DSPARK_SPEC_DRAFT_SAMPLE}\"}"
reasoning_config='{"reasoning_parser":"deepseek_v4","reasoning_start_str":" thinking","reasoning_end_str":" response"}'

opt_args=()
[ "${DSPARK_ASYNC_SCHEDULING:-1}" = "1" ] && opt_args+=(--async-scheduling)
[ "${DSPARK_FLASHINFER_AUTOTUNE:-1}" = "1" ] && opt_args+=(--enable-flashinfer-autotune)
# Free-form extra flags, whitespace-separated.
if [ -n "${DSPARK_EXTRA_ARGS:-}" ]; then
  read -r -a _extra <<<"${DSPARK_EXTRA_ARGS}"
  opt_args+=("${_extra[@]}")
fi

exec vllm serve "${MODEL_DIR}" \
  --served-model-name "${DSPARK_SERVED_MODEL_NAME}" \
  --host 0.0.0.0 --port 8000 \
  --trust-remote-code \
  --tensor-parallel-size 2 \
  --pipeline-parallel-size 1 \
  --distributed-executor-backend mp \
  --nnodes 2 \
  --node-rank "${VLLM_NODE_RANK}" \
  --master-addr "${VLLM_MASTER_ADDR}" \
  --master-port "${DSPARK_MASTER_PORT}" \
  --moe-backend "${DSPARK_MOE_BACKEND}" \
  --max-model-len "${DSPARK_MAX_MODEL_LEN}" \
  --kv-cache-dtype "${DSPARK_KV_CACHE_DTYPE}" \
  --block-size "${DSPARK_BLOCK_SIZE}" \
  --gpu-memory-utilization "${DSPARK_GPU_MEMORY_UTILIZATION}" \
  --max-num-seqs "${DSPARK_MAX_NUM_SEQS}" \
  --max-num-batched-tokens "${DSPARK_MAX_NUM_BATCHED_TOKENS}" \
  --long-prefill-token-threshold "${DSPARK_LONG_PREFILL_TOKEN_THRESHOLD}" \
  --max-cudagraph-capture-size "${DSPARK_MAX_CUDAGRAPH_CAPTURE_SIZE}" \
  --enable-prefix-caching \
  --enable-prompt-tokens-details \
  --enable-chunked-prefill \
  --speculative-config "${speculative_config}" \
  --tokenizer-mode deepseek_v4 \
  --limit-mm-per-prompt "${DSPARK_LIMIT_MM_PER_PROMPT}" \
  --reasoning-parser deepseek_v4 \
  --tool-call-parser deepseek_v4 \
  --enable-auto-tool-choice \
  --reasoning-config "${reasoning_config}" \
  --default-chat-template-kwargs "${DSPARK_CHAT_TEMPLATE_KWARGS}" \
  --generation-config vllm \
  "${opt_args[@]}" \
  "${extra_args[@]}" \
  "${api_key_args[@]}"
