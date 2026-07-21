"""server.py — long-lived model server (template).

Listens on a named pipe, loads the model in a background thread, keeps it
resident, and serves status/request/shutdown. Replace model loading and the
`request` handler for your skill.
"""
import json
import sys
import threading
import time
import traceback
from multiprocessing.connection import Listener

SKILL_NAME = "local-<skill-name>"
PIPE_ADDRESS = rf"\\.\pipe\{SKILL_NAME}"
AUTHKEY = SKILL_NAME.encode("utf-8")


def _configure_stream_encoding(stream) -> None:
    reconfigure = getattr(stream, "reconfigure", None)
    if callable(reconfigure):
        reconfigure(encoding="utf-8")


_configure_stream_encoding(sys.stdout)
_configure_stream_encoding(sys.stderr)


class Server:
    def __init__(self) -> None:
        self.state = "starting"
        self.error = ""
        self.started_at = time.time()
        self.model = None

    def init_async(self) -> None:
        threading.Thread(target=self._init, daemon=True).start()

    def _init(self) -> None:
        try:
            self.state = "downloading"
            # ensure_models(...)  # atomic .partial download + required_files check
            self.state = "loading"
            # self.model = load_openvino_pipeline(...)  # GPU-first, CPU fallback
            self.state = "running"
        except Exception:
            self.error = traceback.format_exc()
            self.state = "error"

    def handle(self, msg: dict) -> dict:
        op = msg.get("op")
        if op == "status":
            return {
                "ok": True,
                "state": self.state,
                "pid": __import__("os").getpid(),
                "uptime_s": time.time() - self.started_at,
                "error": self.error,
            }
        if op == "request":
            if self.state != "running":
                return {"ok": False, "error": f"not ready: {self.state}"}
            try:
                result = self._infer(msg.get("args", []))
                return {"ok": True, "result": result}
            except Exception as exc:
                return {"ok": False, "error": str(exc)}
        if op == "shutdown":
            return {"ok": True, "state": "shutting_down"}
        return {"ok": False, "error": f"unknown op: {op}"}

    def _infer(self, args: list) -> str:
        raise NotImplementedError("Implement inference for your skill.")


def main() -> int:
    srv = Server()
    srv.init_async()
    with Listener(PIPE_ADDRESS, authkey=AUTHKEY) as listener:
        while True:
            with listener.accept() as conn:
                msg = conn.recv()
                resp = srv.handle(msg)
                conn.send(resp)
                if msg.get("op") == "shutdown":
                    return 0


if __name__ == "__main__":
    sys.exit(main())
