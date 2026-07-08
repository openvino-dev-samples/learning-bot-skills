---
name: openvino-pipeline-optimization
description: |
  A developer scaffold + reference standard for building multi-model OpenVINO pipeline demos on
  Intel AIPC, grounded in the openvino_notebooks repo (github.com/openvinotoolkit/openvino_notebooks).
  Given one or more notebook slugs (e.g. whisper-asr-genai, llm-rag-langchain, vlm-chatbot,
  openvoice2-and-melotts) OR a free-form goal (e.g. "local ASR -> LLM -> TTS"), it DISCOVERS the
  pipeline stages from the notebooks themselves, gives a per-stage optimization plan (device
  NPU/GPU/CPU + precision INT4/INT8 via NNCF), benchmarks end-to-end + per-stage, and provides a
  client+server template to deploy the demo as a local service. It is a runnable starting point and a
  set of conventions — not a turnkey auto-builder; unwired pipeline families return 501, never fake output.
  Use when a developer wants to build/scaffold a demo, compose/chain multiple models into one pipeline,
  place stages on devices, tune precision, benchmark, or serve a pipeline (client+server). Trigger on:
  build a demo / scaffold a pipeline / multi-model pipeline / chain models / ASR->LLM->TTS / RAG /
  vision chatbot / device placement / benchmark the pipeline / deploy as a service / serve a pipeline /
  client server / reference standard.
  Requires Intel AIPC hardware.
---

# OpenVINO Pipeline Optimization — developer scaffold & reference standard

This skill gives a developer a **runnable starting point and a set of conventions** for building a
multi-model OpenVINO pipeline demo on Intel AIPC. It is not a turnkey builder — it scaffolds the
pipeline (discovering stages from `openvino_notebooks`), proposes an optimization plan, benchmarks it,
and hands over a **client + server** template to serve it. The developer fills in stage-specific logic
where needed; the skill supplies structure, defaults, and honest reporting.

The spine, end to end:

**pick notebook(s) → discover & compose stages → optimize (device + precision) → benchmark → serve (client+server)**

> **Generic by design.** No model IDs are hardcoded — stages are discovered from the chosen notebooks.
> No model-family switch — IR export is task-agnostic (`optimum-cli export openvino`). A pipeline
> family without a wired runner returns HTTP 501; the skill never fabricates output.

---

## !! CRITICAL: environment / mirrors / persistence !!

| Need | Detail |
| --- | --- |
| Intel AIPC (LNL/ARL/PTL/WCL), Python 3.11, git | verify before running |
| `--china` | pip=tuna, HF=hf-mirror, notebooks=gitcode; no network probing |
| Persisted dirs (outside sandbox) | `%USERPROFILE%\.openvino\`: `venv-pipeopt\`, `openvino_notebooks\`, `ir\<slug>\`, `log\` |

Deps install into the persisted venv on first run: a **minimal core** the skill's own scripts need
(`openvino, openvino-genai, openvino-tokenizers, nncf, optimum-intel, fastapi, uvicorn, pydantic,
nbformat, numpy`) **plus each selected notebook's own `requirements.txt`** (`notebooks/<slug>/requirements.txt`),
so model-specific deps always match the chosen notebook. There is no static skill-level requirements
file — dependencies are resolved from the notebook(s) you build.

---

## Build & optimize

```powershell
# single notebook
run.ps1 --china --slug whisper-asr-genai
# compose multiple notebooks into one pipeline
run.ps1 --china --slug whisper-asr-genai,llm-rag-langchain,openvoice2-and-melotts
# by goal (matched against the repo's notebooks/README.md index)
run.ps1 --china --goal "local ASR to LLM to TTS"
# resolve + plan only (no downloads)
run.ps1 --dry-run --slug vlm-chatbot
```

Flow: **resolve** (`resolve_pipeline.py` — discover stages from `notebooks/<slug>/`) →
**optimize** (`optimize.py` — per-stage `optimum-cli export openvino` + NNCF precision + device →
`pipeline-plan.json`) → **benchmark** (`bench.py` — per-stage + e2e, bottleneck, `[SKILL_RESULT]`).

Default per-role policy (overridable via `--device` / `--precision`): LLM→GPU/INT4,
encoder→GPU/INT8, retriever→CPU/INT8, pre/post→CPU/FP16.

### `[SKILL_RESULT]` (build/benchmark contract)
```
[SKILL_RESULT]
status=ok|error|timeout
pipeline=<slug or a+b+c>
stages=asr:GPU/INT8/312ms; llm:GPU/INT4/540ms; tts:CPU/FP16/120ms
e2e_latency_ms=972
throughput=...
bottleneck=llm
ir_dir=%USERPROFILE%\.openvino\ir\<slug>
[/SKILL_RESULT]
```

---

## Serve the pipeline (client + server)

Deploy the built+optimized pipeline as a local HTTP service, then talk to it with the CLI client.

```powershell
run.ps1 --serve --slug whisper-asr-genai [--port 18790]   # build+optimize (reuse IR) then serve
```

`--serve` resolves → optimizes (reusing existing IR) → launches `server.py` in the background →
polls `/api/health` → emits a `[SKILL_RESULT]` with `service_url` and prints client usage.

**Architecture**
```
 CLI / HTTP client  ──HTTP :18790──▶  server.py (FastAPI)  ──▶  OpenVINO pipeline stages (from pipeline-plan.json)
   client.py / curl                     /api/run · /api/health · /v1/chat/completions · /api/shutdown
```

**Endpoints** (server on `127.0.0.1:18790`)

| Endpoint | Method | Purpose |
| --- | --- | --- |
| `/api/health` | GET | status + per-stage load state |
| `/api/run` | POST | generic executor: `{input, params}` → `{output, per_stage_ms, e2e_ms}` |
| `/v1/chat/completions` | POST | OpenAI-compatible (chat/LLM & RAG families) |
| `/api/shutdown` | POST | graceful exit |

**Client**
```powershell
python scripts\client.py --health
python scripts\client.py --run --input "your input"
python scripts\client.py --chat "hello"          # chat/RAG pipelines
curl http://127.0.0.1:18790/api/health
```

**Honesty:** a pipeline family with no wired runner returns **HTTP 501** ("runner for family 'X' not
implemented yet") — the developer wires that family's runner in `server.py::PIPELINE_RUNNERS`. Nothing
is faked. `server.py --stub` returns canned outputs for wiring/testing the client without hardware.

---

## Lifecycle & parameters

| Param | Meaning |
| --- | --- |
| `--slug a[,b,c]` | one or more notebook slugs (comma = compose in order) |
| `--goal "…"` | free-form goal → matched to slug(s) via the repo index |
| `--device / --precision` | override the per-role defaults |
| `--serve [--port N]` | build+optimize, then serve (default port 18790) |
| `--china` | lock domestic mirrors |
| `--dry-run` | resolve + plan only |
| `--status` | venv / notebooks / last plan / **service** state (as `[SKILL_RESULT]`) |
| `--stop` | POST `/api/shutdown` then kill pidfile + residual |
| `--debug` | verbose diagnostics (venv, repo, devices, last log) |

Exit `0` ok / `1` error. Idempotent: re-runs reuse cloned repo + existing IR (`from IR` tag).

## Troubleshooting (brief)
- **repo-required / goal-unresolved** → let `--serve`/build clone the repo first; refine `--goal` or pass `--slug`.
- **no static model ids found** → the notebook fetches models dynamically; supply the stage model(s) explicitly or run the notebook once.
- **/api/run 501** → wire that family's runner in `server.py::PIPELINE_RUNNERS` (by design).
- **service not healthy** → `run.ps1 --debug`; check port, venv deps, last log under `%USERPROFILE%\.openvino\log\`.

## Does / does not
- **Does:** scaffold + benchmark + serve repo-based pipelines; per-stage device/precision; multi-notebook compose; offline/`--china`; provide the `[SKILL_RESULT]` + client/server conventions.
- **Does not:** invent model architectures; hardcode model IDs; cloud/non-Intel; fake outputs for unwired families.

## Testing
Run the offline smoke test (no models, no clone, no Intel hardware needed) to validate the
orchestration — resolve → optimize `--dry-run` → bench `--dry-run` → client `--help` → `--status`:
```powershell
powershell -ExecutionPolicy Bypass -File test_pipeline.ps1
```
Exit code `0` = all checks passed. It builds a tiny synthetic notebooks repo in a temp dir and
asserts the discovered stages, plan file, and `[SKILL_RESULT]` blocks.
