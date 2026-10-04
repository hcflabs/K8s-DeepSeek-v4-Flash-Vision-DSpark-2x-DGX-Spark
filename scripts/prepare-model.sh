#!/usr/bin/env bash
# Host-side checkpoint download. Run from your workstation; SSHes to each Spark
# and downloads the FULL checkpoint on both (tensor parallelism shards tensors
# at load time, so neither node can hold half). ~157 GiB per node.
#
# Usage: scripts/prepare-model.sh [--lane LANE] [options] user@host [user@host ...]
#
# Lanes:
#   official     (default) deepseek-ai/DeepSeek-V4-Flash-Vision-Exp
#   ablation     official weights + a gated 18 KiB refusal direction, applied at
#                runtime (chart: ablation.enabled=true). Needs HF_TOKEN and
#                acceptance of the gated repo's terms.
#   custom       any other Hugging Face repo: requires --repo. For alternate or
#                fine-tuned checkpoints you have vetted yourself; see README "Safety".
#
# Options:
#   --models-dir DIR   weights root on each node (REQUIRED, e.g. /data/models)
#   --revision SHA     override the pinned revision (official/ablation lanes;
#                      pass "" to follow the tip of main)
#   --repo ID          repository id (required for the custom lane)
#   --pin-revision SHA alias of --revision
#   --dry-run          print what would run on each host and stop
#   -h, --help
#
# Env: HF_TOKEN (required for the ablation lane; optional otherwise). Sent to
# the host over stdin, never on a command line.
#
# Resumable: re-running continues a partial download. The chart's
# weights.hostPath.* must point at <models-dir>/<dir name printed below>.
set -euo pipefail

LANE=official
MODELS_DIR=""
REVISION_SET=0
REVISION=""
REPO=""
DRY=0
HOSTS=()

OFFICIAL_REPO="deepseek-ai/DeepSeek-V4-Flash-Vision-Exp"
OFFICIAL_REVISION="86f746b36186f0e567729a5c06a8c918caba82a9"
ABLATION_TERMS_REPO="drowzeys/keys-DeepSeekV4Flash-Vision-EXP-ablit"
ABLATION_DIR_REPO="drowzeys/keys-DeepSeekV4-Flash-GA-0731-Dspark-Abliterated-Anchored-Tensors"
ABLATION_DIR_FILE="ablit/refusal_direction_r1.pt"
ABLATION_SHA256="6e4d8a8f3aa9e21795faab2c5b14d29b019acdf2ddbfbd8238430458a5837fe0"

usage() { sed -n '2,/^set -euo/p' "${BASH_SOURCE[0]}" | sed '$d' | sed 's/^# \{0,1\}//'; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --lane) LANE="${2:?}"; shift 2 ;;
    --models-dir) MODELS_DIR="${2:?}"; shift 2 ;;
    --revision) REVISION="${2-}"; REVISION_SET=1; shift 2 ;;
    --repo) REPO="${2:?}"; shift 2 ;;
    --pin-revision) REVISION="${2-}"; REVISION_SET=1; shift 2 ;;
    --dry-run) DRY=1; shift ;;
    -h | --help) usage; exit 0 ;;
    -*) echo "unknown option: $1" >&2; usage >&2; exit 2 ;;
    *) HOSTS+=("$1"); shift ;;
  esac
done

[[ -n "${MODELS_DIR}" ]] || { echo "error: --models-dir is required" >&2; usage >&2; exit 2; }
[[ ${#HOSTS[@]} -ge 1 ]] || { echo "error: give at least one user@host (normally both Sparks)" >&2; usage >&2; exit 2; }

case "${LANE}" in
  official | ablation)
    REPO="${REPO:-${OFFICIAL_REPO}}"
    [[ "${REVISION_SET}" -eq 1 ]] || REVISION="${OFFICIAL_REVISION}"
    ;;
  custom)
    [[ -n "${REPO}" ]] || { echo "error: the custom lane requires --repo" >&2; exit 2; }
    ;;
  *) echo "error: unknown lane '${LANE}' (official | ablation | custom)" >&2; exit 2 ;;
esac

DIR_NAME="$(basename "${REPO}")"
DEST="${MODELS_DIR}/${DIR_NAME}"
ABLATION_DEST="${MODELS_DIR}/dspark-ablation/direction_r1.pt"

if [[ "${LANE}" == "ablation" && -z "${HF_TOKEN:-}" ]]; then
  echo "error: the ablation lane needs HF_TOKEN (agree to the terms at https://huggingface.co/${ABLATION_TERMS_REPO})" >&2
  exit 1
fi


# Script executed on each host (stdin line 1 = HF_TOKEN, may be empty).
remote_script() {
  cat <<REMOTE
set -euo pipefail
export HF_HUB_ENABLE_HF_TRANSFER=0
[ -n "\${HF_TOKEN:-}" ] || unset HF_TOKEN
sudo mkdir -p '${DEST}' '${MODELS_DIR}'
sudo chown -R "\$(id -u):\$(id -g)" '${DEST}'
if [ ! -x "\$HOME/.cache/dspark-hf-venv/bin/python" ]; then
  mkdir -p "\$HOME/.cache"
  python3 -m venv "\$HOME/.cache/dspark-hf-venv"
fi
"\$HOME/.cache/dspark-hf-venv/bin/pip" -q install -U huggingface_hub
HF="\$HOME/.cache/dspark-hf-venv/bin/hf"
if [ -n '${REVISION}' ]; then REVARG="--revision ${REVISION}"; else REVARG=""; fi
echo "[\$(hostname)] downloading ${REPO} -> ${DEST}"
\$HF download '${REPO}' \$REVARG --local-dir '${DEST}' --max-workers 16
test -f '${DEST}/config.json' || { echo "[\$(hostname)] config.json missing after download" >&2; exit 1; }
REMOTE
  if [[ "${LANE}" == "ablation" ]]; then
    cat <<REMOTE
echo "[\$(hostname)] fetching gated terms + refusal direction"
\$HF download '${ABLATION_TERMS_REPO}' RESPONSIBLE_USE.md --local-dir '${MODELS_DIR}/dspark-ablation/terms' >/dev/null
\$HF download '${ABLATION_DIR_REPO}' '${ABLATION_DIR_FILE}' --local-dir '${MODELS_DIR}/dspark-ablation/src' >/dev/null
mkdir -p '${MODELS_DIR}/dspark-ablation'
cp '${MODELS_DIR}/dspark-ablation/src/${ABLATION_DIR_FILE}' '${ABLATION_DEST}'
echo '${ABLATION_SHA256}  ${ABLATION_DEST}' | sha256sum -c -
REMOTE
  fi
  echo 'echo "[$(hostname)] done"'
}

echo "lane=${LANE} repo=${REPO} revision=${REVISION:-<tip of main>}"
echo "weights dir on each node: ${DEST}   (chart: weights.hostPath.* and model.dirName=${DIR_NAME})"
[[ "${LANE}" != "ablation" ]] || echo "direction file: ${ABLATION_DEST}   (chart: ablation.directionHostPath)"

if [[ "${DRY}" -eq 1 ]]; then
  for h in "${HOSTS[@]}"; do
    echo "--- would run on ${h} ---"
    remote_script
  done
  exit 0
fi

pids=()
for h in "${HOSTS[@]}"; do
  { printf '%s\n' "${HF_TOKEN:-}"; remote_script; } |
    ssh -o BatchMode=yes -o ConnectTimeout=10 "${h}" 'IFS= read -r HF_TOKEN; export HF_TOKEN; bash -s' 2>&1 |
    sed "s|^|${h}: |" &
  pids+=($!)
done

rc=0
for p in "${pids[@]}"; do wait "${p}" || rc=1; done
[[ "${rc}" -eq 0 ]] && echo "all hosts complete" || echo "one or more hosts failed (re-run to resume)" >&2
exit "${rc}"
