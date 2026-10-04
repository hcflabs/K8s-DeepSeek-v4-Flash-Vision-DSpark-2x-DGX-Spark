#!/usr/bin/env bash
# Hotfix anchor check: catches an image bump that moves a patch line before a
# pod crash-loops on it.
#
#   scripts/check-anchors.sh                 offline: syntax-check every embedded script
#   scripts/check-anchors.sh --image REF     also dry-run all 34 steps inside REF (docker)
#   scripts/check-anchors.sh --log FILE      summarize the output of a previous run
#
# The image run executes serve.sh with every gate enabled (DSPARK_CHECK_ALL=1)
# and stops before `vllm serve` (DSPARK_APPLY_ONLY=1). Each step is reported as
# applied / skip / FAIL; a missing anchor exits non-zero. The container
# filesystem is thrown away, so nothing persists. No GPU needed.
#
# Env: DOCKER_PLATFORM (default linux/arm64; the image is arm64-only)
set -euo pipefail

CHART="$(cd "$(dirname "${BASH_SOURCE[0]}")/../chart" && pwd)"
FILES="${CHART}/files"
IMAGE=""
LOG=""

usage() { sed -n '2,13p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --image) IMAGE="${2:?--image needs a value}"; shift 2 ;;
    --log) LOG="${2:?--log needs a file}"; shift 2 ;;
    -h | --help) usage; exit 0 ;;
    *) echo "unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

summarize() {
  local log="$1" applied skipped failed
  applied="$(grep -c '^\[hotfix\] applied' "${log}" || true)"
  skipped="$(grep -c '^\[hotfix\] skip' "${log}" || true)"
  failed="$(grep -c '^\[hotfix\] FAIL' "${log}" || true)"
  echo "anchor check: applied=${applied} skip=${skipped} FAIL=${failed}"
  if [[ "${failed}" -gt 0 ]]; then
    grep '^\[hotfix\] FAIL' "${log}" >&2
    return 1
  fi
  if ! grep -q 'all hotfixes processed' "${log}"; then
    echo "anchor check: run did not reach the end of the hotfix sequence" >&2
    return 1
  fi
}

if [[ -n "${LOG}" ]]; then
  summarize "${LOG}"
  exit $?
fi

# ── Offline: every embedded script must parse ──
rc=0
tmp="$(mktemp -d)"
trap 'rm -rf "${tmp}"' EXIT
while IFS= read -r -d '' f; do
  case "${f}" in
    *.py) python3 -c 'import sys; compile(open(sys.argv[1]).read(), sys.argv[1], "exec")' "${f}" \
      || { echo "[FAIL] ${f#"${FILES}"/}" >&2; rc=1; } ;;
    *.sh) bash -n "${f}" || { echo "[FAIL] ${f#"${FILES}"/}" >&2; rc=1; } ;;
  esac
done < <(find "${FILES}" -type f \( -name '*.py' -o -name '*.sh' \) -print0)
[[ "${rc}" -eq 0 ]] && echo "syntax: all embedded scripts parse"
[[ "${rc}" -eq 0 ]] || exit 1
[[ -n "${IMAGE}" ]] || exit 0

# ── Image dry-run ──
command -v docker >/dev/null 2>&1 || { echo "docker is required for --image" >&2; exit 2; }
log="${tmp}/anchors.log"
set +e
docker run --rm --platform "${DOCKER_PLATFORM:-linux/arm64}" --entrypoint bash \
  -e DSPARK_CHECK_ALL=1 -e DSPARK_APPLY_ONLY=1 \
  -e DSPARK_MODEL_DIR=/nonexistent -e VLLM_NODE_RANK=0 \
  -v "${FILES}/serve.sh:/etc/vllm/serve.sh:ro" \
  -v "${FILES}/hotfixes:/etc/vllm-hotfixes:ro" \
  -v "${FILES}/hotfixes/vision_exp:/opt/dspark-patches/vision_exp:ro" \
  "${IMAGE}" /etc/vllm/serve.sh 2>&1 | tee "${log}"
dock_rc=${PIPESTATUS[0]}
set -e
summarize "${log}" || rc=1
[[ "${dock_rc}" -eq 0 ]] || { echo "container exited ${dock_rc}" >&2; rc=1; }
exit "${rc}"
