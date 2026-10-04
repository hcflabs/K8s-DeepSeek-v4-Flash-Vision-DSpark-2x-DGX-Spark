#!/usr/bin/env python3
"""Raise a TCP beacon so rank 0's initContainer does not time out.

Rank 0 hosts the torch.distributed store; rank 1 connects to it. If rank 1
is still pulling or scheduling when rank 0 starts, rank 0 exhausts its
connect window and dies. This beacon lets rank 0 wait for rank 1 before
loading weights - the same ordering the upstream Docker Compose recipe
gets by starting the worker first.

Chart-authored (not vendored from upstream). Port: DSPARK_BEACON_PORT (25099).
"""
import os
import socket
import sys


def main() -> int:
    port = int(os.environ.get("DSPARK_BEACON_PORT", "25099"))
    s = socket.socket()
    s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    s.bind(("0.0.0.0", port))
    s.listen(16)
    print(f"worker beacon listening on :{port}", file=sys.stderr, flush=True)
    while True:
        conn, _ = s.accept()
        conn.close()


if __name__ == "__main__":
    sys.exit(main())
