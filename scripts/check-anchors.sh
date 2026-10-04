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
#      DOCKER_ROOT      (default /var/lib/docker) where free space is measured
#      MIN_FREE_GIB     (default 20) required free space under DOCKER_ROOT
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
PLATFORM="${DOCKER_PLATFORM:-linux/arm64}"
MIN_FREE_GIB="${MIN_FREE_GIB:-20}"

# The image is ~9 GiB compressed and needs roughly twice that to pull and
# extract (Docker holds the blob, then the expanded layer). Check first: a
# mid-extract "no space left on device" is a confusing way to learn this.
# Measure the docker root, falling back to / when it does not exist yet.
space_path="${DOCKER_ROOT:-/var/lib/docker}"
[[ -d "${space_path}" ]] || space_path="/"
avail_kb="$(df -Pk "${space_path}" 2>/dev/null | awk 'NR==2 {print $4}')" || avail_kb=""
if [[ "${avail_kb}" =~ ^[0-9]+$ ]]; then
  avail_gib=$((avail_kb / 1048576))
  echo "anchor check: ${avail_gib} GiB free under ${space_path} (need >= ${MIN_FREE_GIB})"
  if ((avail_gib < MIN_FREE_GIB)); then
    echo "ERROR: not enough disk for ${IMAGE}." >&2
    echo "       It is ~9 GiB compressed and needs ~${MIN_FREE_GIB} GiB free to pull and extract." >&2
    echo "       GitHub's ubuntu runners start with ~14 GiB; free space before this step." >&2
    exit 1
  fi
fi

echo "anchor check: pulling ${IMAGE} (${PLATFORM})"
set +e
docker pull --platform "${PLATFORM}" "${IMAGE}" 2>&1 | tee "${tmp}/pull.log"
pull_rc=${PIPESTATUS[0]}
set -e
if [[ "${pull_rc}" -ne 0 ]]; then
  echo "ERROR: docker pull failed (exit ${pull_rc})" >&2
  grep -iE 'no space left|failed to register layer' "${tmp}/pull.log" >&2 || true
  exit 1
fi

log="${tmp}/anchors.log"
set +e
docker run --rm --platform "${PLATFORM}" --entrypoint bash \
  -e DSPARK_CHECK_ALL=1 -e DSPARK_APPLY_ONLY=1 \
  -e DSPARK_MODEL_DIR=/nonexistent -e VLLM_NODE_RANK=0 \
  -v "${FILES}/serve.sh:/etc/vllm/serve.sh:ro" \
  -v "${FILES}/hotfixes:/etc/vllm-hotfixes:ro" \
  -v "${FILES}/hotfixes/vision_exp:/opt/dspark-patches/vision_exp:ro" \
  "${IMAGE}" /etc/vllm/serve.sh 2>&1 | tee "${log}"
dock_rc=${PIPESTATUS[0]}
set -e

if grep -q '^\[hotfix\]' "${log}"; then
  summarize "${log}" || rc=1
else
  # Docker never got as far as starting the entrypoint (e.g. exit 125).
  echo "anchor check: the container produced no hotfix output" >&2
  rc=1
fi
if [[ "${dock_rc}" -ne 0 ]]; then
  if [[ "${dock_rc}" -eq 125 ]]; then
    echo "container exited 125: docker could not run the container (see above)" >&2
  else
    echo "container exited ${dock_rc}" >&2
  fi
  rc=1
fi
exit "${rc}"
