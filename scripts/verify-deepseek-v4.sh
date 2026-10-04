#!/usr/bin/env bash
# One-shot readiness report for the two-node deployment: weights, image, fabric,
# rank labels, pods, and the served model. Read-only. Reports every prerequisite
# and points at the first one that is not ready.
#
# The Sparks are reached over SSH because their kubelets are usually unreachable
# from the API server (:10250), so `kubectl logs/exec` may not work either.
#
# Usage: scripts/verify-deepseek-v4.sh --leader user@host --worker user@host [options]
#   --leader / --worker USER@HOST  SSH targets (or env LEADER_SSH / WORKER_SSH)
#   --leader-fabric-ip IP          REQUIRED (chart topology.fabric.masterAddr)
#   --worker-fabric-ip IP          REQUIRED (chart topology.fabric.workerAddr)
#   --fabric-if NAME               REQUIRED (chart topology.fabric.interface)
#   --rdma-dev NAME                REQUIRED (chart topology.fabric.rdmaDevice)
#   --model-dir PATH               REQUIRED: weights dir on each node (chart weights.hostPath.*)
#   --min-gib N                    weights are "complete" at >= N GiB (default 150)
#   --model NAME                   served model name (default deepseek-v4-flash-vision-exp)
#   --max-model-len N              default 1048576
#   --image-ref TEXT               substring identifying the image in `crictl images` (optional)
#   --rank-label-key KEY           default node.dspark/rank
#   -n NAMESPACE                   default vllm
#   --api-url URL                  default http://<leader host>:8000
#   --watch [SECONDS]              refresh until Ctrl-C (default 30)
#   --bench                        also run ib_write_bw across the fabric
# Env: the REQUIRED values above may also be set as LEADER_FABRIC_IP, WORKER_FABRIC_IP,
#      FABRIC_IF, RDMA_DEV, MODEL_DIR, LEADER_SSH, WORKER_SSH; API_KEY (bearer token for /v1 when auth is enabled)
set -euo pipefail

LEADER_SSH="${LEADER_SSH:-}"
WORKER_SSH="${WORKER_SSH:-}"
LEADER_FABRIC_IP="${LEADER_FABRIC_IP:-}"
WORKER_FABRIC_IP="${WORKER_FABRIC_IP:-}"
FABRIC_IF="${FABRIC_IF:-}"
RDMA_DEV="${RDMA_DEV:-}"
MODEL_DIR="${MODEL_DIR:-}"
MIN_GIB=150
SERVED_MODEL=deepseek-v4-flash-vision-exp
MAX_MODEL_LEN=1048576
IMAGE_REF="dspark-vllm"
RANK_KEY=node.dspark/rank
NAMESPACE=vllm
API_URL=""
WATCH=0
WATCH_INTERVAL=30
BENCH=0

usage() { sed -n '2,/^set -euo/p' "${BASH_SOURCE[0]}" | sed '$d' | sed 's/^# \{0,1\}//'; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --leader) LEADER_SSH="${2:?}"; shift 2 ;;
    --worker) WORKER_SSH="${2:?}"; shift 2 ;;
    --leader-fabric-ip) LEADER_FABRIC_IP="${2:?}"; shift 2 ;;
    --worker-fabric-ip) WORKER_FABRIC_IP="${2:?}"; shift 2 ;;
    --fabric-if) FABRIC_IF="${2:?}"; shift 2 ;;
    --rdma-dev) RDMA_DEV="${2:?}"; shift 2 ;;
    --model-dir) MODEL_DIR="${2:?}"; shift 2 ;;
    --min-gib) MIN_GIB="${2:?}"; shift 2 ;;
    --model) SERVED_MODEL="${2:?}"; shift 2 ;;
    --max-model-len) MAX_MODEL_LEN="${2:?}"; shift 2 ;;
    --image-ref) IMAGE_REF="${2:?}"; shift 2 ;;
    --rank-label-key) RANK_KEY="${2:?}"; shift 2 ;;
    -n) NAMESPACE="${2:?}"; shift 2 ;;
    --api-url) API_URL="${2:?}"; shift 2 ;;
    --watch)
      WATCH=1
      if [[ "${2:-}" =~ ^[0-9]+$ ]]; then WATCH_INTERVAL="$2"; shift; fi
      shift
      ;;
    --bench) BENCH=1; shift ;;
    -h | --help) usage; exit 0 ;;
    *) echo "unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

[[ -n "${LEADER_SSH}" && -n "${WORKER_SSH}" && -n "${LEADER_FABRIC_IP}" && -n "${WORKER_FABRIC_IP}" &&
  -n "${FABRIC_IF}" && -n "${RDMA_DEV}" && -n "${MODEL_DIR}" ]] || {
  echo "error: --leader --worker --leader-fabric-ip --worker-fabric-ip --fabric-if --rdma-dev --model-dir are required" >&2
  usage >&2
  exit 2
}
LEADER_HOST="${LEADER_SSH##*@}"
API_URL="${API_URL:-http://${LEADER_HOST}:8000}"

if [[ -t 1 ]]; then
  BOLD=$'\033[1m' DIM=$'\033[2m' GREEN=$'\033[32m' YELLOW=$'\033[33m' RED=$'\033[31m' RESET=$'\033[0m'
else
  BOLD='' DIM='' GREEN='' YELLOW='' RED='' RESET=''
fi

FIRST_PROBLEM=""
ok() { printf '%s\n' "  ${GREEN}ok${RESET}      $*"; }
warn() { printf '%s\n' "  ${YELLOW}pending${RESET} $*"; [[ -n "${FIRST_PROBLEM}" ]] || FIRST_PROBLEM="$*"; }
bad() { printf '%s\n' "  ${RED}problem${RESET} $*"; [[ -n "${FIRST_PROBLEM}" ]] || FIRST_PROBLEM="$*"; }
note() { printf '%s\n' "  ${DIM}$*${RESET}"; }
heading() { printf '\n%s\n' "${BOLD}$*${RESET}"; }

# Non-interactive: a missing key fails fast instead of prompting.
on_node() { ssh -o ConnectTimeout=5 -o BatchMode=yes "$1" "$2" 2>/dev/null; }

nodes() { printf '%s\n' "leader:${LEADER_SSH}:${WORKER_FABRIC_IP}:${LEADER_FABRIC_IP}" "worker:${WORKER_SSH}:${LEADER_FABRIC_IP}:${WORKER_FABRIC_IP}"; }

report_weights() {
  heading "Weights (${MODEL_DIR})"
  local name ssh_t peer me out gib files
  while IFS=: read -r name ssh_t peer me; do
    out="$(on_node "${ssh_t}" "
      if [ -f ${MODEL_DIR}/config.json ]; then
        du -sb ${MODEL_DIR} | cut -f1
        find ${MODEL_DIR} -name '*.safetensors' | wc -l
      else echo missing; fi")" || { bad "${name}: unreachable over SSH"; continue; }
    if [[ -z "${out}" || "${out}" == "missing" ]]; then
      bad "${name}: no config.json in ${MODEL_DIR} (run scripts/prepare-model.sh)"
      continue
    fi
    gib="$(awk -v b="$(sed -n 1p <<<"${out}")" 'BEGIN { printf "%.1f", b / 1073741824 }')"
    files="$(sed -n 2p <<<"${out}")"
    if awk -v g="${gib}" -v m="${MIN_GIB}" 'BEGIN { exit !(g >= m) }'; then
      ok "${name}: ${gib} GiB, ${files} safetensors"
    else
      bad "${name}: only ${gib} GiB (< ${MIN_GIB}); download incomplete? re-run prepare-model.sh"
    fi
  done < <(nodes)
}

report_image() {
  heading "Container image (${IMAGE_REF})"
  local name ssh_t _p _m found
  while IFS=: read -r name ssh_t _p _m; do
    found="$(on_node "${ssh_t}" "sudo k3s crictl images --digests 2>/dev/null | grep -c '${IMAGE_REF}' || true")" || found=0
    if [[ "${found:-0}" -gt 0 ]]; then
      ok "${name}: present in containerd"
    else
      warn "${name}: not pulled yet (kubelet pulls ~10 GB on first start)"
    fi
  done < <(nodes)
}

report_fabric() {
  heading "Fabric (${FABRIC_IF} / ${RDMA_DEV})"
  local name ssh_t peer me out addr state ping_rc
  while IFS=: read -r name ssh_t peer me; do
    out="$(on_node "${ssh_t}" "
      ip -4 -brief address show ${FABRIC_IF} 2>/dev/null | awk '{print \$3}'
      cat /sys/class/infiniband/${RDMA_DEV}/ports/1/state 2>/dev/null | awk '{print \$NF}'
      ping -c 1 -W 2 -I ${FABRIC_IF} ${peer} >/dev/null 2>&1 && echo up || echo down")" ||
      { bad "${name}: unreachable over SSH"; continue; }
    addr="$(sed -n 1p <<<"${out}")"
    state="$(sed -n 2p <<<"${out}")"
    ping_rc="$(sed -n 3p <<<"${out}")"
    if [[ "${addr%%/*}" != "${me}" ]]; then
      bad "${name}: expected ${me} on ${FABRIC_IF}, found '${addr:-nothing}' (run: ansible-playbook playbooks/site.yml --tags gpu_fabric)"
    elif [[ "${state}" != "ACTIVE" ]]; then
      bad "${name}: RDMA device ${RDMA_DEV} is '${state:-missing}', not ACTIVE - NCCL would fall back to TCP"
    elif [[ "${ping_rc}" != "up" ]]; then
      bad "${name}: ${me} is up but peer ${peer} does not answer"
    else
      ok "${name}: ${addr}, RDMA ACTIVE, peer ${peer} reachable"
    fi
  done < <(nodes)

  if [[ "${BENCH}" -eq 1 ]]; then
    note "running ib_write_bw (a few seconds)..."
    on_node "${WORKER_SSH}" "nohup ib_write_bw -d ${RDMA_DEV} -x 3 --report_gbits >/tmp/ibbw-server.log 2>&1 &" || true
    sleep 2
    local bw
    bw="$(on_node "${LEADER_SSH}" "ib_write_bw -d ${RDMA_DEV} -x 3 --report_gbits ${WORKER_FABRIC_IP} 2>/dev/null | awk '/^ [0-9]/ {print \$4}'")" || true
    if [[ -n "${bw:-}" ]]; then ok "RDMA bandwidth: ${bw} Gb/s (single queue pair)"; else warn "ib_write_bw produced no result"; fi
  fi
}

report_kubernetes() {
  heading "Kubernetes (namespace ${NAMESPACE})"
  if ! command -v kubectl >/dev/null 2>&1; then warn "kubectl not on PATH, skipping"; return; fi
  local labels
  labels="$(kubectl get nodes -L "${RANK_KEY}" --no-headers 2>/dev/null | awk '$NF=="leader"||$NF=="worker"{print $1, $NF}')" || true
  if grep -q ' leader$' <<<"${labels}" && grep -q ' worker$' <<<"${labels}"; then
    ok "rank labels (${RANK_KEY}): $(tr '\n' ';' <<<"${labels}")"
  else
    bad "rank labels ${RANK_KEY}=leader|worker missing (found: ${labels:-none}); re-run the Ansible join or label nodes by hand"
  fi
  if ! kubectl get namespace "${NAMESPACE}" >/dev/null 2>&1; then
    warn "namespace ${NAMESPACE} does not exist - chart not applied (scripts/apply.sh)"
    return
  fi
  local pods
  pods="$(kubectl -n "${NAMESPACE}" get pods -o wide --no-headers 2>/dev/null)" || true
  if [[ -z "${pods}" ]]; then
    warn "no pods in ${NAMESPACE} yet"
  else
    while IFS= read -r line; do note "${line}"; done <<<"${pods}"
    if grep -q 'Running' <<<"${pods}" && [[ "$(grep -c ' 1/1 \| 1/1  ' <<<"${pods}")" -ge 2 ]]; then
      ok "both ranks Ready"
    else
      warn "ranks not both Ready yet (cold start takes tens of minutes up to ~2h)"
    fi
  fi
}

report_api() {
  heading "API (${API_URL})"
  local auth=() models
  [[ -z "${API_KEY:-}" ]] || auth=(-H "Authorization: Bearer ${API_KEY}")
  models="$(curl -fsS --max-time 5 ${auth[@]+"${auth[@]}"} "${API_URL}/v1/models" 2>/dev/null)" || true
  if [[ -z "${models}" ]]; then
    if curl -fsS --max-time 5 -o /dev/null "${API_URL}/health" 2>/dev/null; then
      warn "/health answers but /v1/models did not - set API_KEY if auth is enabled"
    else
      warn "not serving yet on ${API_URL}"
    fi
    return
  fi
  local parsed
  parsed="$(python3 -c '
import json, sys
for m in json.load(sys.stdin).get("data", []):
    print(m.get("id"), m.get("max_model_len"))' <<<"${models}" 2>/dev/null)" || true
  if grep -q "^${SERVED_MODEL} ${MAX_MODEL_LEN}$" <<<"${parsed}"; then
    ok "serving: ${parsed}"
  else
    bad "expected '${SERVED_MODEL} ${MAX_MODEL_LEN}', got: ${parsed:-unparseable}"
  fi
}

run_report() {
  FIRST_PROBLEM=""
  printf '%s\n' "${BOLD}DeepSeek-V4 two-node status - $(date '+%Y-%m-%d %H:%M:%S')${RESET}"
  report_weights
  report_image
  report_fabric
  report_kubernetes
  report_api
  printf '\n'
  if [[ -n "${FIRST_PROBLEM}" ]]; then
    printf '%s\n' "${BOLD}First thing not ready:${RESET} ${FIRST_PROBLEM}"
  else
    printf '%s\n' "${BOLD}All checks passed.${RESET}"
  fi
}

if [[ "${WATCH}" -eq 1 ]]; then
  while true; do
    clear
    run_report
    printf '%s\n' "${DIM}refreshing every ${WATCH_INTERVAL}s - Ctrl-C to stop${RESET}"
    sleep "${WATCH_INTERVAL}"
  done
else
  run_report
  [[ -z "${FIRST_PROBLEM}" ]]
fi
