# Credits

This repo is a Kubernetes/k3s variant of
[MiaAI-Lab/DeepSeek-v4-Flash-DSpark-2x-DGX-Spark](https://github.com/MiaAI-Lab/DeepSeek-v4-Flash-DSpark-2x-DGX-Spark)
(MIT, Copyright (c) Tony Deangelo). The runtime hotfix scripts and the
`vision_exp` package under `chart/files/hotfixes/` are vendored from that
repository at the commit pinned in [`SYNC.md`](SYNC.md); the upstream MIT
notice applies to them and is preserved here:

> MIT License. Copyright (c) Tony Deangelo. Permission is hereby granted, free
> of charge, to any person obtaining a copy of this software and associated
> documentation files, to deal in the Software without restriction, subject to
> the inclusion of the copyright notice and this permission notice in all copies
> or substantial portions of the Software. THE SOFTWARE IS PROVIDED "AS IS",
> WITHOUT WARRANTY OF ANY KIND. See the upstream `LICENSE` for the full text.

Upstream in turn credits (see its `CREDITS.md`):

- **Tony D** ([tonyd2wild](https://github.com/tonyd2wild/DeepSeek-v4-Flash-DSpark-1M-NVFP4-KV-2x-DGX-Spark)) - the original recipe and overlay.
- **drowzeys ("Keys")** - the DSpark concurrency patch, request-stable KV slot
  mapping, and the published refusal direction used by the opt-in ablation lane.
- **@u1tra_instinct** - the optional abliterated path (`ABLITERATED=1`).

## Dependencies

| Component | Used for | License / source |
| --- | --- | --- |
| [`k3s-io/k3s-ansible`](https://github.com/k3s-io/k3s-ansible) | agent-only node join (`prereq`, `k3s_agent`) | Apache-2.0 |
| [`ansible.posix`](https://github.com/ansible-collections/ansible.posix) | host config modules | GPL-3.0 |
| `ghcr.io/anemll/dspark-vllm-gx10` | prebuilt serving image (vLLM + GB10 kernels) | anemll, see image page |
| [NVIDIA k8s-device-plugin](https://github.com/NVIDIA/k8s-device-plugin) | advertises `nvidia.com/gpu` | Apache-2.0 |
| `deepseek-ai/DeepSeek-V4-Flash-Vision-Exp` | default checkpoint | see model card |

This repo's own files are MIT (see `LICENSE`).
