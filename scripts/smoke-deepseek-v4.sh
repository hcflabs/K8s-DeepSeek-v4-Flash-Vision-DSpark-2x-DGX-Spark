#!/usr/bin/env bash
# k8s-only smoke test: confirms /v1/models answers and reports the expected
# model and max_model_len. Uses a kubectl port-forward to the Service, so it
# needs no SSH and no pod exec. Exit 0 = healthy, non-zero otherwise.
#
# Usage: scripts/smoke-deepseek-v4.sh [-n NAMESPACE] [-s SERVICE] [--model NAME] [--max-model-len N]
# Env: API_KEY (bearer token if auth is enabled), LOCAL_PORT (default 18000)
set -euo pipefail

NAMESPACE=vllm
SERVICE=dspark-vllm
MODEL=deepseek-v4-flash-vision-exp
MAX_LEN=1048576
PORT="${LOCAL_PORT:-18000}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    -n) NAMESPACE="${2:?}"; shift 2 ;;
    -s) SERVICE="${2:?}"; shift 2 ;;
    --model) MODEL="${2:?}"; shift 2 ;;
    --max-model-len) MAX_LEN="${2:?}"; shift 2 ;;
    -h | --help) sed -n '2,8p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done

kubectl -n "${NAMESPACE}" port-forward "svc/${SERVICE}" "${PORT}:8000" >/dev/null 2>&1 &
PF=$!
trap 'kill ${PF} 2>/dev/null || true' EXIT
for _ in $(seq 1 20); do
  curl -fsS -o /dev/null --max-time 2 "http://127.0.0.1:${PORT}/health" 2>/dev/null && break
  sleep 1
done

auth=()
[[ -z "${API_KEY:-}" ]] || auth=(-H "Authorization: Bearer ${API_KEY}")
body="$(curl -fsS --max-time 10 ${auth[@]+"${auth[@]}"} "http://127.0.0.1:${PORT}/v1/models")" ||
  { echo "FAIL: /v1/models did not answer (not ready, or API_KEY needed)" >&2; exit 1; }

if python3 -c '
import json, sys
m, n = sys.argv[1], int(sys.argv[2])
sys.exit(0 if any(d.get("id") == m and d.get("max_model_len") == n for d in json.load(sys.stdin)["data"]) else 1)
' "${MODEL}" "${MAX_LEN}" <<<"${body}"; then
  echo "OK: ${MODEL} served with max_model_len=${MAX_LEN}"
else
  echo "FAIL: expected ${MODEL} @ ${MAX_LEN}, got: ${body}" >&2
  exit 1
fi
