"""client.py — short-lived CLI client (template).

Ensures the server is running, talks to it over a named pipe, prints the
result. Replace SKILL_NAME / request payload / output formatting for your skill.
"""
import json
import sys
import time
from multiprocessing.connection import Client

SKILL_NAME = "local-<skill-name>"
PIPE_ADDRESS = rf"\\.\pipe\{SKILL_NAME}"
AUTHKEY = SKILL_NAME.encode("utf-8")

DOWNLOAD_WAIT_TIMEOUT = 8 * 60  # seconds before saving pending-request


def _configure_stream_encoding(stream) -> None:
    reconfigure = getattr(stream, "reconfigure", None)
    if callable(reconfigure):
        reconfigure(encoding="utf-8")


_configure_stream_encoding(sys.stdout)
_configure_stream_encoding(sys.stderr)


def _send(payload: dict) -> dict:
    with Client(PIPE_ADDRESS, authkey=AUTHKEY) as conn:
        conn.send(payload)
        return conn.recv()


def _ensure_server() -> None:
    """Start the server if not running.

    In a Marvis host: ask server-dog via its pipe with a `start_server` payload.
    Standalone: spawn server.py yourself and wait for its pipe.
    """
    raise NotImplementedError("Wire up server start for your host.")


def _wait_ready() -> None:
    deadline = time.time() + DOWNLOAD_WAIT_TIMEOUT
    while time.time() < deadline:
        try:
            st = _send({"op": "status"})
        except Exception:
            time.sleep(1.0)
            continue
        state = st.get("state")
        if state == "running":
            return
        if state == "error":
            print(f"服务初始化失败: {st.get('error')}")
            sys.exit(1)
        time.sleep(1.0)
    # timed out — save pending request and ask for --continue
    print("模型正在下载, 请用命令 'scripts\\run.ps1 --continue' 继续运行")
    sys.exit(3)


def main(argv: list[str]) -> int:
    _ensure_server()
    _wait_ready()
    resp = _send({"op": "request", "args": argv})
    if not resp.get("ok"):
        print(f"错误: {resp.get('error')}")
        return 1
    print(resp.get("result", ""))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
