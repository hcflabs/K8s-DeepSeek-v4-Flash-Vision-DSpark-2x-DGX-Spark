# Security policy

## Supported versions

Fixes land on `main` and in the newest published chart release. Only the latest
release is supported; upgrade with `helm upgrade --install` from
`oci://ghcr.io/<owner>/charts/dspark-vllm`.

## Reporting a vulnerability

Report privately through GitHub: **Security** -> **Report a vulnerability** on
this repository. Please do not open a public issue for anything exploitable.

Include what you need to make it reproducible: chart version, `values.yaml`
(site values redacted), manifests from `helm template`, and relevant pod logs.
Never include a real API key, k3s join token, or vault password.

This is a spare-time project, so responses are best-effort. You will get an
acknowledgement, and credit in the release notes if you would like it.

## Scope

In scope — anything this repository ships:

- **Chart templates and defaults** (`chart/`), including the Service, the
  optional Ingress, and the auth Secret handling.
- **Entrypoint and hotfix scripts** (`chart/files/`). These run as `privileged`
  with `hostNetwork: true` and the RDMA device mounted, so a defect here has
  host-level impact.
- **Ansible playbooks and scripts** (`ansible/`, `scripts/`), including secret
  handling and the vault workflow.
- **CI and release workflows** (`.github/workflows/`): supply-chain issues such
  as an unpinned or mutable action, or a path that could leak a token or
  publish an artifact that does not match its tag.
- **Image and hotfix provenance**: `SYNC.md` pins the upstream commit the
  hotfixes were vendored from. A way to get a pod to run a hotfix whose anchor
  no longer matches, instead of failing loudly, is a security-relevant bug.

Out of scope — please take these elsewhere:

- **Vulnerabilities in the serving image** (`ghcr.io/anemll/dspark-vllm-gx10`),
  the vLLM code it contains, or the upstream recipe. Report to that project;
  issues that are ours will be routed there.
- **Model behaviour and outputs.** This includes the refusal-direction ablation
  lane and any abliterated/uncensored checkpoint: a model producing unwanted
  output is a model-safety question, not a vulnerability in this chart. What
  *is* in scope is a defect that exposes the endpoint or the key material.
- **Your own cluster's exposure.** The chart ships `/v1` unauthenticated by
  default, deliberately, matching upstream. Publishing that Ingress to the
  internet is a deployment choice.

## Operator responsibilities

The defaults are upstream-shaped and not hardened for a hostile network:

- set `auth.existingSecret` or `auth.apiKey(s)` before exposing `/v1`; treat the
  key as a secret and know that `/health` stays unauthenticated by design;
- the pods run privileged with host networking because NCCL must bind the fabric
  device — keep the cluster and its node access trusted accordingly;
- the ablation and custom/alternate checkpoint lanes suppress or change refusal
  behaviour: they are explicit opt-ins, and you own how they are exposed and used;
- keep the fabric on its own isolated point-to-point link with no gateway or DNS,
  as the Ansible layer configures it.
