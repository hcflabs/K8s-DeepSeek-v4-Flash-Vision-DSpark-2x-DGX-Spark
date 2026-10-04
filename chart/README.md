# dspark-vllm chart

Serves DeepSeek-V4-Flash-Vision tensor-parallel (TP=2) across two DGX Spark
nodes: a leader Deployment (rank 0, serves `:8000`) and a worker Deployment
(rank 1, `--headless`). Prerequisites: both nodes joined with the rank labels
and GPU taint, the fabric up, weights on both nodes, and the NVIDIA device
plugin installed. See the top-level README for the full flow.

Release name matters: resources are named `<release>-dspark-vllm-*` unless the
release name already contains `dspark-vllm` or `fullnameOverride` is set.

## Install

From a checkout:

```bash
helm upgrade --install dspark-vllm ./chart -n vllm --create-namespace -f my-values.yaml
```

From OCI (published on tag):

```bash
helm upgrade --install dspark-vllm oci://ghcr.io/<owner>/charts/dspark-vllm \
  --version <version> -n vllm --create-namespace -f my-values.yaml
helm pull oci://ghcr.io/<owner>/charts/dspark-vllm --version <version>
```

Via k3s's built-in helm-controller (apply on the cluster):

```yaml
apiVersion: helm.cattle.io/v1
kind: HelmChart
metadata:
  name: dspark-vllm
  namespace: kube-system
spec:
  chart: oci://ghcr.io/<owner>/charts/dspark-vllm
  version: <version>   # see RELEASING.md
  targetNamespace: vllm
  createNamespace: true
  valuesContent: |-
    topology:
      fabric: {masterAddr: <leader-ip>, workerAddr: <worker-ip>, interface: <netdev>, rdmaDevice: <rdma-dev>}
    weights:
      hostPath: {leader: <path>, worker: <path>}
```

## Minimal values

Fabric addressing and weights paths are **required** (no site-specific
defaults; rendering fails without them). Everything else has an upstream-derived
default (`values.yaml` documents every key):

```yaml
topology:
  fabric: {masterAddr: <leader-ip>, workerAddr: <worker-ip>, interface: <netdev>, rdmaDevice: <rdma-dev>}
weights:
  hostPath: {leader: <path-to-checkpoint>, worker: <path-to-checkpoint>}
auth:
  existingSecret: my-vllm-key      # omit for an unauthenticated /v1
ingress:
  className: traefik
  hosts: [vllm.example.com]        # omit for Service-only exposure
```

## Test

`scripts/check-anchors.sh --image <image>` (repo root) dry-runs every hotfix
against the image; CI runs it on each PR. Lint/template locally with
`helm lint chart -f chart/ci/test-values.yaml`.
