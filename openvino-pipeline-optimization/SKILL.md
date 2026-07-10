---
name: openvino-pipeline-optimization
description: |
  A developer scaffold + reference standard for building multi-model OpenVINO pipeline demos on
  Intel AIPC, grounded in the openvino_notebooks repo (github.com/openvinotoolkit/openvino_notebooks).
  Given one or more notebook slugs (e.g. whisper-asr-genai, llm-rag-langchain, vlm-chatbot,
  openvoice2-and-melotts) OR a free-form goal (e.g. "local ASR -> LLM -> TTS"), it DISCOVERS the
  pipeline stages from the notebooks themselves, suggests a per-stage optimization plan (device
  NPU/GPU/CPU + precision INT4/INT8 via NNCF), benchmarks end-to-end + per-stage, and provides a
  client+server template to deploy the demo as a local service. It is a direction + a set of
  conventions — NOT a turnkey auto-builder. The bundled scripts are REFERENCE implementations, not a
  mandatory path: model conversion and inference must follow the chosen notebook's own code, not a
  generic script. Unwired pipeline families return 501, never fake output.
  Use when a developer wants to build/scaffold a demo, compose/chain multiple models into one pipeline,
  place stages on devices, tune precision, benchmark, or serve a pipeline (client+server). Trigger on:
  build a demo / scaffold a pipeline / multi-model pipeline / chain models / ASR->LLM->TTS / RAG /
  vision chatbot / device placement / benchmark the pipeline / deploy as a service / serve a pipeline /
  client server / reference standard.
  Requires Intel AIPC hardware.
---

# OpenVINO Pipeline Optimization — developer scaffold & reference standard

This skill gives a developer a **direction and a set of conventions** for building a multi-model
OpenVINO pipeline demo on Intel AIPC — not a ready-made pipeline. It shows *how* to discover stages
from `openvino_notebooks`, *how* to place them on devices/precisions, *how* to benchmark, and *how*
to wrap them behind a **client + server**. The actual pipeline is assembled from the notebook(s) the
user chooses; the developer fills in stage-specific logic. The skill supplies structure, suggested
defaults, and honest reporting — never a canned pipeline.

The spine (a suggested path, trim/replace to fit the notebook):

**pick notebook(s) → discover & compose stages → optimize (device + precision) → benchmark → serve (client+server)**

### What is fixed vs. what you build

| Fixed (the conventions this skill standardizes) | You build (from the chosen notebook) |
| --- | --- |
| Directory layout, `[SKILL_RESULT]` contract, lifecycle flags | The stage graph and how stages connect |
| The client+server *pattern* (endpoints, health, 501 honesty) | Each stage's model load / conversion / inference code |
| Suggested device/precision heuristics (overridable) | The authoritative conversion + inference — copied/adapted from the notebook |

> **Scripts are reference, not law.** Everything under `scripts/` (`resolve_pipeline.py`,
> `optimize.py`, `bench.py`, `server.py`, `client.py`) is a **reference implementation** of these
> conventions. Use them as a starting point and adapt freely. Where a script's generic behaviour
> (e.g. a one-size `optimum-cli export openvino`) disagrees with the notebook, **the notebook wins** —
> its model loading, conversion, and inference are the source of truth.

> **Generic by design.** No model IDs are hardcoded — stages are discovered from the chosen notebooks.
> No model-family switch. A pipeline family without a wired runner returns HTTP 501; the skill never
> fabricates output.

---

## !! CRITICAL: environment / mirrors / persistence !!

| Need | Detail |
| --- | --- |
| Intel AIPC (LNL/ARL/PTL/WCL), git | verify before running |
| Python 3.x | **no hard pin** — use a version the chosen notebook supports (its `requirements.txt` decides). The venv is created with whatever `python` resolves to |
| `--china` | pip=tuna, HF=hf-mirror, notebooks=gitcode; no network probing |
| Persisted dirs (outside sandbox) | `%USERPROFILE%\.openvino\`: `venv-pipeopt\`, `openvino_notebooks\`, `ir\<slug>\`, `log\` |

Deps install into the persisted venv on first run: a **minimal core** the reference scripts need
(`openvino, nncf, optimum-intel, fastapi, uvicorn, pydantic, nbformat, numpy` — plus
`openvino-genai`/`openvino-tokenizers` only when a stage uses them) **plus each selected notebook's
own `requirements.txt`** (`notebooks/<slug>/requirements.txt`), so model-specific deps always match
the chosen notebook. There is no static skill-level requirements file, and no forced version pins —
dependencies are resolved from the notebook(s) you build. If a notebook pins its own OpenVINO/Python
version, follow the notebook.

---

## Build & optimize (reference flow)

The commands below drive the **reference** scripts. They are a convenient starting point; for real
conversion/inference, prefer the steps in the chosen notebook and adapt the scripts to match.

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
**optimize** (`optimize.py` — a reference exporter that calls `optimum-cli export openvino` + NNCF +
device → `pipeline-plan.json`) → **benchmark** (`bench.py` — per-stage + e2e, bottleneck,
`[SKILL_RESULT]`).

> The reference `optimize.py` uses a single generic `optimum-cli export openvino`. This works for many
> standard models but is **not authoritative**: if the notebook converts a model a specific way
> (custom export args, `ov.convert_model`, manual NNCF config, stateful/GenAI export, multiple
> sub-models), replace the export call with the notebook's own conversion. Same for inference — the
> notebook's runtime code is the reference, not `server.py`'s generic executor.

**Suggested** per-role device/precision heuristics (defaults only, always overridable via
`--device` / `--precision`, and superseded by whatever the notebook does): LLM→GPU/INT4,
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
implemented yet") — the developer wires that family's runner in `server.py::PIPELINE_RUNNERS` using
the **notebook's own inference code**. Nothing is faked. `server.py --stub` returns canned outputs for
wiring/testing the client without hardware. The generic `/api/run` executor is a convenience shell,
not a substitute for the notebook's pipeline logic.

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
- **Does:** give a direction + conventions for repo-based pipelines; discover stages from notebooks; suggest per-stage device/precision; benchmark; provide the `[SKILL_RESULT]` + client/server *pattern*; multi-notebook compose; offline/`--china`.
- **Does not:** ship a ready-made pipeline; force the bundled scripts as the execution path; invent model architectures; hardcode model IDs or a Python/OpenVINO version; override the notebook's conversion/inference; cloud/non-Intel; fake outputs for unwired families.

## Testing
Run the offline smoke test (no models, no clone, no Intel hardware needed) to validate the
orchestration — resolve → optimize `--dry-run` → bench `--dry-run` → client `--help` → `--status`:
```powershell
powershell -ExecutionPolicy Bypass -File test_pipeline.ps1
```
Exit code `0` = all checks passed. It builds a tiny synthetic notebooks repo in a temp dir and
asserts the discovered stages, plan file, and `[SKILL_RESULT]` blocks.
