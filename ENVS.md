# Upstream knobs -> chart values

Upstream configures the Compose recipe through `.env.dspark`. Each knob below
maps to exactly one chart value. Gates are applied by `chart/files/serve.sh`
in the order shown (step numbers = position in the upstream command block;
see [`SYNC.md`](SYNC.md)).

## Serving and topology

| Upstream knob / flag | Chart value | Default |
| --- | --- | --- |
| `DSPARK_MODEL` | `model.repo` (download: `scripts/prepare-model.sh`) | `deepseek-ai/DeepSeek-V4-Flash-Vision-Exp` |
| `DSPARK_REVISION` | `prepare-model.sh --revision` | `86f746b3...` |
| `SERVED_MODEL_NAME` | `model.servedName` | `deepseek-v4-flash-vision-exp` |
| HF cache path | `weights.hostPath.leader` / `.worker` | **required** |
| `DSPARK_WORKER_HF_NFS=1` | `weights.nfs.{enabled,server,path}` | off |
| `MASTER_ADDR` | `topology.fabric.masterAddr` | **required** |
| worker fabric IP | `topology.fabric.workerAddr` | **required** |
| `NCCL_SOCKET_IFNAME` | `topology.fabric.interface` | **required** |
| `NCCL_IB_HCA` | `topology.fabric.rdmaDevice` | **required** |
| `--master-port` | `topology.fabric.port` | `25000` |
| rank node selection | `topology.rankLabels.*` | `node.dspark/rank=leader\|worker` |
| `--max-model-len` | `serving.maxModelLen` | `1048576` |
| `--kv-cache-dtype` | `serving.kvCacheDtype` | `nvfp4_ds_mla` |
| `--moe-backend` | `serving.moeBackend` | `flashinfer_b12x` |
| `--gpu-memory-utilization` | `serving.gpuMemoryUtilization` | `0.84` |
| `--max-num-seqs` | `serving.maxNumSeqs` | `6` |
| `--max-num-batched-tokens` | `serving.maxNumBatchedTokens` | `8192` |
| `--long-prefill-token-threshold` | `serving.longPrefillTokenThreshold` | `1024` |
| `--max-cudagraph-capture-size` | `serving.maxCudagraphCaptureSize` | `48` |
| `--block-size` | `serving.blockSize` | `256` |
| `DSPARK_ASYNC_SCHEDULING` | `serving.asyncScheduling` | `true` |
| `--enable-flashinfer-autotune` | `serving.flashinferAutotune` | `true` |
| `VLLM_PREFIX_CACHE_RETENTION_INTERVAL` | `serving.prefixCacheRetentionInterval` | `4096` |
| `VLLM_USE_BREAKABLE_CUDAGRAPH` | `serving.breakableCudagraph` | `false` |
| speculative `num_speculative_tokens` | `serving.speculative.numTokens` | `6` |
| `--limit-mm-per-prompt` | `serving.limitMmPerPrompt` | `{"image":8}` |
| `--default-chat-template-kwargs` | `serving.chatTemplateKwargs` | `{"thinking":true,"reasoning_effort":"low"}` |
| `shm_size` | `shm.sizeLimit` | `64Gi` |
| `DSPARK_API_KEYS` | `auth.apiKey(s)` / `auth.existingSecret` | none (unauthenticated) |
| anything else | `serving.extraArgs`, `serving.extraEnv` | empty |

`numTokens`: the checkpoint has `dspark_block_size=5` and
`num_nextn_predict_layers=3`; the stock rule needs `k % 3 == 0`, so the default
is 6. `k=5` only works with `hotfixes.enable.dsparkBlockK=true`; the chart
refuses to render other values without it.

## Hotfix gates

`enable.*` gates default off unless noted; `skip.*` opt out of hotfixes that run
by default. Always-on hotfixes (no gate): vision-exp (12), empty-encoder-output
(16), issue27 (17), issue43 (20), issue26 (21), issue133 (22), issue55 (3),
runtime-ablation (23, inert unless `ablation.enabled`).

| Step | Hotfix | Chart value | Env var | Default |
| --- | --- | --- | --- | --- |
| 2 | issue31 thinking budget | `hotfixes.enable.issue31ThinkingBudget` | `DSPARK_ENABLE_ISSUE31_GPU_HOTFIX` | **on** (validated profile) |
| 4 | issue22 nvfp4_ds_mla decode | `hotfixes.skip.issue22` | `DSPARK_SKIP_ISSUE22_HOTFIX` | run |
| 5 | issue79 spin-wait | `hotfixes.skip.spinWait` | `DSPARK_SKIP_SPIN_WAIT_HOTFIX` | run |
| 6 | issue117 shm ring buffer | `hotfixes.skip.issue117Recheck` | `DSPARK_SKIP_ISSUE117_RECHECK_HOTFIX` | run |
| 7 | batch shell hotfixes (6 files) | `hotfixes.skip.batch` | `DSPARK_SKIP_HOTFIX` | run |
| 8 | API-key log redaction | (automatic when keys are set) | - | - |
| 9 | responses store | `hotfixes.enable.responsesStore` | `VLLM_ENABLE_RESPONSES_API_STORE` | off |
| 10 | issue138 responses history | `hotfixes.enable.issue138ResponsesHistory` | `DSPARK_ENABLE_ISSUE138_RESPONSES_HISTORY_COMPAT` | off |
| 11 | codex agent_message | `hotfixes.enable.codexAgentMessage` | `DSPARK_ENABLE_CODEX_AGENT_MESSAGE_COMPAT` | off |
| 13 | issue141 sparse MLA chunk | `hotfixes.enable.issue141SparseMlaChunk` | `DSPARK_ENABLE_ISSUE141_SPARSE_MLA_CHUNK` | off |
| 14 | SP indexer prefill | `hotfixes.enable.spIndexer` | `DSPARK_ENABLE_SP_INDEXER` | off |
| 15 | DeepGEMM sm121 alias | `hotfixes.enable.deepgemmSm121Alias` | `DSPARK_ENABLE_DEEPGEMM_SM121_ALIAS` | off |
| 18 | adaptive prefill chunk | `hotfixes.enable.adaptiveChunk` | `DSPARK_ENABLE_ADAPTIVE_CHUNK` | off |
| 19 | replicate Markov head | `hotfixes.enable.replicateMarkov` | `DSPARK_ENABLE_REPLICATE_MARKOV` | off |
| 23 | runtime ablation | `ablation.enabled` | `DSPARK_ABLATE` (-> `DSV4_ABLATE_FILE`) | off |
| 24 | suppress stops in reasoning | `hotfixes.skip.suppressStops` | `DSPARK_SKIP_SUPPRESS_STOPS_HOTFIX` | run |
| 25 | assistant final continuation | `hotfixes.enable.assistantFinal` | `DSPARK_ENABLE_ASSISTANT_FINAL_HOTFIX` | off |
| 26 | issue144 effort align | `hotfixes.enable.issue144EffortAlign` | `DSPARK_ENABLE_ISSUE144_EFFORT_ALIGN` | off |
| 27 | issue136 xgrammar termination | `hotfixes.enable.issue136Xgrammar` | `DSPARK_ENABLE_ISSUE136_XGRAMMAR_HOTFIX` | off |
| 28 | issue191 toolcall fail-closed | `hotfixes.enable.issue191ToolcallFailclosed` | `DSPARK_ENABLE_ISSUE191_TOOLCALL_FAILCLOSED` | off |
| 29 | DSpark block-k | `hotfixes.enable.dsparkBlockK` | `DSPARK_ENABLE_DSPARK_BLOCK_K` | off |
| 30 | RoPE SWA fix | `hotfixes.enable.ropeSwaFix` | `DSPARK_ENABLE_ROPE_SWA_FIX` | off |
| 31 | DSpark SWA prefix | `hotfixes.enable.dsparkSwaPrefix` | `DSPARK_ENABLE_DSPARK_SWA_PREFIX` | off |
| 32 | DSML recovery | `hotfixes.enable.dsmlRecovery` | `DSPARK_ENABLE_DSML_RECOVERY` | off |
| 33 | MXFP4 indexer cache | `hotfixes.enable.mxfp4IndexerCache` | `DSPARK_ENABLE_MXFP4_INDEXER_CACHE` | off |
| 34 | C128A prefill cache | `hotfixes.enable.c128aPrefillCache` | `DSPARK_ENABLE_C128A_PREFILL_CACHE` | off |

## Ansible inventory <-> chart values

| Inventory var | Chart value |
| --- | --- |
| `gpu_fabric_interface` | `topology.fabric.interface` |
| `gpu_fabric_rdma_device` | `topology.fabric.rdmaDevice` |
| `gpu_fabric_address` (host) | `topology.fabric.masterAddr` (leader) / `workerAddr` (worker), without `/30` |
| `gpu_rank_label_key` + `gpu_rank` | `topology.rankLabels.key` + `.leader`/`.worker` |
| `gpu_models_dir` | parent of `weights.hostPath.*` |
