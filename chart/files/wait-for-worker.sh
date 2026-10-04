#!/usr/bin/env bash
# Leader initContainer: block until the rank-1 beacon answers.
set -euo pipefail
: "${DSPARK_WORKER_ADDR:?DSPARK_WORKER_ADDR is required}"
PORT="${DSPARK_BEACON_PORT:-25099}"
echo "waiting for rank 1 beacon at ${DSPARK_WORKER_ADDR}:${PORT}"
until (exec 3<>"/dev/tcp/${DSPARK_WORKER_ADDR}/${PORT}") 2>/dev/null; do
  sleep 5
done
echo "rank 1 is up"
