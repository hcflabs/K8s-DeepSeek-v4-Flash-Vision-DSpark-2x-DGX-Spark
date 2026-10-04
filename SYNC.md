# Upstream sync

Vendored from `MiaAI-Lab/DeepSeek-v4-Flash-DSpark-2x-DGX-Spark` (read-only git
remote `upstream`).

- **Pinned upstream SHA:** `a8b4636710068fd30edb98e1365d567086cc208e`
- **Policy:** snapshot, not live-follow. Re-vendor by hand when the image is
  bumped, then run `scripts/check-anchors.sh --image <new image>` and update the
  SHA here.

## Re-vendoring

```bash
git fetch upstream
git diff a8b4636 upstream/main -- patches/ docker-compose.dspark.yml
# copy changed files into chart/files/hotfixes/ (vision_exp/ -> chart/files/hotfixes/vision_exp/)
scripts/check-anchors.sh --image <image>
```

## Ordering and gating source of truth

Order and gates are those of the `command:` block in upstream
`docker-compose.dspark.yml` at the pinned SHA, ported to
`chart/files/serve.sh` as 34 numbered steps. Gate names (`DSPARK_ENABLE_*`,
`DSPARK_SKIP_*`) are upstream's unchanged and are mapped to chart values in
[`ENVS.md`](ENVS.md). Upstream defaults apply except where `ENVS.md` says otherwise.

## File mapping

Every hotfix is copied byte-for-byte to `chart/files/hotfixes/<same name>`;
`patches/vision_exp/*` goes to `chart/files/hotfixes/vision_exp/`.

| Chart file | Origin |
| --- | --- |
| `hotfix-deepgemm-sm121-mqa-header-alias.sh` | `patches/hotfix-deepgemm-sm121-mqa-header-alias.sh` |
| `hotfix-dsv4-adaptive-prefill-chunk.py` | `patches/hotfix-dsv4-adaptive-prefill-chunk.py` |
| `hotfix-dsv4-assistant-final-continuation.py` | `patches/hotfix-dsv4-assistant-final-continuation.py` |
| `hotfix-dsv4-dense-prefill-indexer-48407.sh` | `patches/hotfix-dsv4-dense-prefill-indexer-48407.sh` |
| `hotfix-dsv4-flashmla-workspace-50298.sh` | `patches/hotfix-dsv4-flashmla-workspace-50298.sh` |
| `hotfix-dsv4-grammar-advance.sh` | `patches/hotfix-dsv4-grammar-advance.sh` |
| `hotfix-dsv4-issue133-triton-specialization.py` | `patches/hotfix-dsv4-issue133-triton-specialization.py` |
| `hotfix-dsv4-issue141-sparse-mla-decode-chunk.py` | `patches/hotfix-dsv4-issue141-sparse-mla-decode-chunk.py` |
| `hotfix-dsv4-issue144-effort-align.py` | `patches/hotfix-dsv4-issue144-effort-align.py` |
| `hotfix-dsv4-issue26-hybrid-swa-min.py` | `patches/hotfix-dsv4-issue26-hybrid-swa-min.py` |
| `hotfix-dsv4-issue27-partial-prefill-concurrency.py` | `patches/hotfix-dsv4-issue27-partial-prefill-concurrency.py` |
| `hotfix-dsv4-issue31-v2-thinking-budget-gpu.py` | `patches/hotfix-dsv4-issue31-v2-thinking-budget-gpu.py` |
| `hotfix-dsv4-issue43-decode-fairness-and-diag.py` | `patches/hotfix-dsv4-issue43-decode-fairness-and-diag.py` |
| `hotfix-dsv4-issue55-tool-truncation.py` | `patches/hotfix-dsv4-issue55-tool-truncation.py` |
| `hotfix-dsv4-mtp-buffer-50312.sh` | `patches/hotfix-dsv4-mtp-buffer-50312.sh` |
| `hotfix-dsv4-reasoning-effort-map.py` | chart-authored |
| `hotfix-dsv4-replicate-markov-head.py` | `patches/hotfix-dsv4-replicate-markov-head.py` |
| `hotfix-dsv4-responses-store.py` | `patches/hotfix-dsv4-responses-store.py` |
| `hotfix-dsv4-runtime-ablation.py` | `patches/hotfix-dsv4-runtime-ablation.py` |
| `hotfix-dsv4-skip-empty-c128-48957.sh` | `patches/hotfix-dsv4-skip-empty-c128-48957.sh` |
| `hotfix-dsv4-skip-topk-49486.sh` | `patches/hotfix-dsv4-skip-topk-49486.sh` |
| `hotfix-dsv4-sp-indexer-prefill.py` | `patches/hotfix-dsv4-sp-indexer-prefill.py` |
| `hotfix-dsv4-suppress-stops-in-reasoning.py` | `patches/hotfix-dsv4-suppress-stops-in-reasoning.py` |
| `hotfix-dsv4-vision-exp.py` | `patches/hotfix-dsv4-vision-exp.py` |
| `hotfix-encoding-dsv4-issue21.py` | `patches/hotfix-encoding-dsv4-issue21.py` |
| `hotfix-gb10-spin-wait.sh` | `patches/hotfix-gb10-spin-wait.sh` |
| `hotfix-nvfp4-ds-mla-issue22.sh` | `patches/hotfix-nvfp4-ds-mla-issue22.sh` |
| `hotfix-vllm-c128a-prefill-cache.py` | `patches/hotfix-vllm-c128a-prefill-cache.py` |
| `hotfix-vllm-codex-agent-message.py` | `patches/hotfix-vllm-codex-agent-message.py` |
| `hotfix-vllm-dsml-recovery.py` | `patches/hotfix-vllm-dsml-recovery.py` |
| `hotfix-vllm-dspark-block-k.py` | `patches/hotfix-vllm-dspark-block-k.py` |
| `hotfix-vllm-dspark-swa-prefix.py` | `patches/hotfix-vllm-dspark-swa-prefix.py` |
| `hotfix-vllm-empty-encoder-output.py` | `patches/hotfix-vllm-empty-encoder-output.py` |
| `hotfix-vllm-issue117-shm-ring-buffer.py` | `patches/hotfix-vllm-issue117-shm-ring-buffer.py` |
| `hotfix-vllm-issue136-xgrammar-termination.py` | `patches/hotfix-vllm-issue136-xgrammar-termination.py` |
| `hotfix-vllm-issue138-responses-history.py` | `patches/hotfix-vllm-issue138-responses-history.py` |
| `hotfix-vllm-issue191-toolcall-failclosed.py` | `patches/hotfix-vllm-issue191-toolcall-failclosed.py` |
| `hotfix-vllm-mxfp4-indexer-cache.py` | `patches/hotfix-vllm-mxfp4-indexer-cache.py` |
| `hotfix-vllm-redact-api-key-log.sh` | `patches/hotfix-vllm-redact-api-key-log.sh` |
| `hotfix-vllm-rope-swa-fix.py` | `patches/hotfix-vllm-rope-swa-fix.py` |
| `hotfix-worker-beacon.py` | chart-authored |

Not vendored (non-goals): `*.patch` files, `dsv4_tp_pad.py`, `patches/tp3/`,
`recipe/`, `lmcache/`, the stage-C overlay, `results/`, and the dev scripts.
