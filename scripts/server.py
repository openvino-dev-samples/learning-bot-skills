# -*- coding: utf-8 -*-
"""Serve a composed OpenVINO pipeline over HTTP (127.0.0.1:18790).

Loads <ir-dir>/pipeline-plan.json and exposes a generic API:
  GET  /api/health           status + per-stage load state
  POST /api/run              generic executor: {input, params} -> {output, per_stage_ms, e2e_ms}
  POST /v1/chat/completions  OpenAI-compatible (LLM/chat pipelines only)
  POST /api/shutdown         graceful exit

Generic by design: a stage family without a wired runner returns HTTP 501 (never fake
output). --stub skips real IR load and returns canned timings so the client+server
contract is testable without Intel hardware.
"""
import argparse, json, os, sys, threading, time, traceback

from fastapi import FastAPI, HTTPException
from pydantic import BaseModel
import uvicorn

HOST = "127.0.0.1"
LOG_DIR = os.path.join(os.environ.get("USERPROFILE", os.path.expanduser("~")), ".openvino", "log")
os.makedirs(LOG_DIR, exist_ok=True)
_logf = os.path.join(LOG_DIR, "pipeopt-server-%s.log" % time.strftime("%Y%m%d-%H%M%S"))


def log(m):
    line = "[%s] [server pid=%d] %s" % (time.strftime("%H:%M:%S"), os.getpid(), m)
    print(line, flush=True)
    try:
        open(_logf, "a", encoding="utf-8").write(line + "\n")
    except Exception:
        pass


class State:
    def __init__(self):
        self.status = "starting"      # starting|loading|ok|error
        self.error = None
        self.plan = {}
        self.stages = []              # [{name,role,device,precision,loaded,handle}]
        self.stub = False
        self.t0 = time.time()

    @property
    def uptime(self):
        return int(time.time() - self.t0)


S = State()


def _load_pipeline(ir_dir):
    S.status = "loading"
    plan_path = os.path.join(ir_dir, "pipeline-plan.json")
    if not os.path.isfile(plan_path):
        S.status = "error"; S.error = "pipeline-plan.json not found in %s" % ir_dir
        log(S.error); return
    S.plan = json.load(open(plan_path, encoding="utf-8"))
    for st in S.plan.get("stages", []):
        entry = {"name": st["name"], "role": st["role"], "device": st["device"],
                 "precision": st["precision"], "ir_path": st.get("ir_path"),
                 "loaded": False, "handle": None}
        if S.stub:
            entry["loaded"] = True
        else:
            try:
                import openvino as ov
                if entry["ir_path"] and os.path.isfile(entry["ir_path"]):
                    entry["handle"] = ov.Core().compile_model(entry["ir_path"], entry["device"])
                    entry["loaded"] = True
                else:
                    log("stage %s: no IR at %s (skipped load)" % (entry["name"], entry["ir_path"]))
            except Exception as e:
                log("stage %s load failed: %s" % (entry["name"], e))
        S.stages.append(entry)
    S.status = "ok"
    log("pipeline '%s' ready (%d stages, stub=%s)" % (S.plan.get("pipeline"), len(S.stages), S.stub))


# ── generic executor: family -> runner. Only wire what's real; else honest 501. ──
def _run_stub(payload):
    per = {st["name"]: 100 + 40 * i for i, st in enumerate(S.stages)}
    return {"output": "[stub] echo: %s" % payload.get("input"), "per_stage_ms": per,
            "e2e_ms": sum(per.values())}


PIPELINE_RUNNERS = {
    # family_key: callable(payload)->dict. Empty by default: real runners are wired
    # per family as they are implemented; unwired families return 501 (never fake).
}


def _family():
    roles = [s["role"] for s in S.stages]
    if "llm" in roles and "retriever" in roles:
        return "rag"
    if "llm" in roles:
        return "chat"
    if roles == ["encoder"] or (roles and all(r == "encoder" for r in roles)):
        return "encoder"
    return "+".join(dict.fromkeys(roles)) or "unknown"


app = FastAPI(title="OpenVINO Pipeline Server")


@app.get("/api/health")
def health():
    return {"ok": S.status == "ok", "status": S.status, "pipeline": S.plan.get("pipeline"),
            "family": _family() if S.stages else None, "stub": S.stub, "pid": os.getpid(),
            "uptime_s": S.uptime, "error": S.error,
            "stages": [{"name": s["name"], "role": s["role"], "device": s["device"],
                        "precision": s["precision"], "loaded": s["loaded"]} for s in S.stages]}


class RunReq(BaseModel):
    input: str = ""
    params: dict = {}


@app.post("/api/run")
def run(req: RunReq):
    if S.status != "ok":
        raise HTTPException(503, "pipeline not ready (status=%s)" % S.status)
    payload = {"input": req.input, "params": req.params}
    if S.stub:
        return _run_stub(payload)
    fam = _family()
    runner = PIPELINE_RUNNERS.get(fam)
    if runner is None:
        log("no runner wired for family '%s' -> 501" % fam)
        raise HTTPException(501, "runner for pipeline family '%s' not implemented yet" % fam)
    return runner(payload)


class ChatMsg(BaseModel):
    role: str
    content: str


class ChatReq(BaseModel):
    model: str = "openvino-pipeline"
    messages: list[ChatMsg]
    max_tokens: int = 512
    temperature: float = 0.7


@app.post("/v1/chat/completions")
def chat(req: ChatReq):
    if S.status != "ok":
        raise HTTPException(503, "pipeline not ready (status=%s)" % S.status)
    if _family() not in ("chat", "rag") and not S.stub:
        raise HTTPException(501, "this pipeline is not a chat/LLM family")
    user = next((m.content for m in reversed(req.messages) if m.role == "user"), "")
    if S.stub:
        content = "[stub] " + user
    else:
        runner = PIPELINE_RUNNERS.get(_family())
        if runner is None:
            raise HTTPException(501, "chat runner not implemented yet")
        content = runner({"input": user, "params": {"max_tokens": req.max_tokens}})["output"]
    return {"id": "chatcmpl-%d" % int(time.time()), "object": "chat.completion",
            "created": int(time.time()), "model": req.model,
            "choices": [{"index": 0, "message": {"role": "assistant", "content": content},
                         "finish_reason": "stop"}]}


@app.post("/api/shutdown")
def shutdown():
    log("shutdown requested")
    threading.Timer(0.5, lambda: os._exit(0)).start()
    return {"ok": True}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--ir-dir", required=True)
    ap.add_argument("--port", type=int, default=18790)
    ap.add_argument("--stub", action="store_true", help="skip real IR load; canned outputs")
    args = ap.parse_args()
    S.stub = args.stub
    log("starting on %s:%d (ir-dir=%s, stub=%s)" % (HOST, args.port, args.ir_dir, S.stub))
    threading.Thread(target=_load_pipeline, args=(args.ir_dir,), daemon=True).start()
    uvicorn.run(app, host=HOST, port=args.port, log_level="warning")


if __name__ == "__main__":
    try:
        main()
    except Exception as e:
        log("fatal: %s\n%s" % (e, traceback.format_exc()))
        sys.exit(1)
