#!/usr/bin/env python3
"""Map reasoning-effort fallback so "low" is the default (upstream encoder).

The stock deepseek_v4.py maps every unrecognized effort to "high".
Upstream's docker-compose inlines this edit before the container starts.
Anchor-fail-closed: if the target block moves, this script exits non-zero
and the pod fails rather than silently serving with the wrong default.
"""
import sys
from pathlib import Path

TARGET = Path(
    "/usr/local/lib/python3.12/dist-packages/vllm/tokenizers/deepseek_v4.py"
)

OLD = (
    'elif reasoning_effort in ("max", "xhigh"):\n'
    '                reasoning_effort = "max"\n'
    '            else:\n'
    '                reasoning_effort = "high"'
)

NEW = (
    'elif reasoning_effort in ("max", "xhigh"):\n'
    '                reasoning_effort = "max"\n'
    '            elif reasoning_effort == "high":\n'
    '                reasoning_effort = "high"\n'
    '            else:\n'
    '                reasoning_effort = "low"'
)


def main() -> int:
    if not TARGET.exists():
        print(f"WARN: {TARGET} not found — reasoning-effort mapping skipped",
              file=sys.stderr)
        return 0
    s = TARGET.read_text()
    if NEW in s:
        print("reasoning-effort map already present, skip")
        return 0
    if OLD not in s:
        print(f"FATAL: reasoning-effort anchor not found in {TARGET}",
              file=sys.stderr)
        return 1
    updated = s.replace(OLD, NEW)
    assert NEW in updated
    TARGET.write_text(updated)
    print("reasoning-effort map applied")
    return 0


if __name__ == "__main__":
    sys.exit(main())