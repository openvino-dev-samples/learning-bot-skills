# Model Download & Environment Reference

> Imported from `local-ai-skill-authoring`. Applies when packaging the pipeline
> as a distributable local AI skill (model download + resume, venv, device,
> memory). For the *dev/serving* workflow, the pipeline skill instead resolves
> deps from each notebook's own `requirements.txt` (see main SKILL.md).

## Download flow

```
first run of run.ps1
  → client.py starts server
    → server.py background thread: ensure_models()
      → download to <dir_name>.partial/
      → validate required_files
      → atomic rename .partial → <dir_name>
    → model loaded, state = "running"
```

Always download into a `.partial` dir and atomically rename only after all `required_files` validate — this prevents a half-finished download being mistaken for a complete model. For a multi-stage pipeline, repeat this per stage IR.

## Resume protocol (`--continue`)

Hosts commonly cap each `run.ps1` call (Marvis: 10 minutes). When the model isn't downloaded yet:

1. `client.py` waits up to a download timeout (Marvis: 8 min, `DOWNLOAD_WAIT_TIMEOUT`).
2. On timeout, save the request to a pending file (Marvis: `~/.openvino/<skill>-pending-request.json`).
3. Print: `模型正在下载, 请用命令 'scripts\run.ps1 --continue' 继续运行`.
4. Exit with code `3`.
5. The user/host calls `run.ps1 --continue`, which reads the pending request and resumes.

## Model config requirements

- `model_id`: publicly accessible repo ID (e.g. ModelScope).
- `dir_name`: local folder name (match the model name).
- `required_files`: every file that must exist for the download to count as complete.
- Prefer models pre-quantized to INT4/INT8 OpenVINO IR.
- Keep model size reasonable (first download completes within 1–2 `--continue` cycles).

## Environment layout (Marvis reference)

```
%USERPROFILE%\.openvino\
├── venv\<name>\      # per-skill virtual env
├── models\<dir_name> # downloaded models
├── temp\<skill>\     # runtime script copies
├── log\              # logs
└── <skill>-pending-request.json
```

This is the same persistent tree the pipeline skill uses (`venv-pipeopt\`,
`openvino_notebooks\`, `ir\<slug>\`, `log\`). For other hosts, use that host's
equivalent base directory; keep the same sub-structure semantics.

## requirements.txt

```txt
openvino>=2026.0
numpy<2.0
soundfile
modelscope
```

- Must include the model downloader (`modelscope`) and `openvino`.
- Pin critical versions (see best-practices for OpenVINO version pitfalls).
- A domestic mirror line helps mainland-China users.
- When packaging a notebook-based pipeline, fold in that notebook's own
  `requirements.txt` so model-side deps match exactly.

## Prebuilt wheels

Put custom/unpublished wheels in `wheels/`. `install-env.ps1` compares versions and installs only when newer.

## Device selection

```python
import openvino as ov

def _pick_device(log_path) -> str:
    for d in ov.Core().available_devices:
        if "GPU" in d:
            return d
    return "CPU"
```

Prefer Intel GPU, fall back to CPU. (The pipeline skill's per-role device policy
in `info.json` refines this per stage.)

## Memory

- Declare `mem_need_gb` honestly (model + inference peak). For a pipeline, sum
  the resident footprint of all concurrently-loaded stages.
- Underestimating causes OOM / system stalls; the process manager evicts based on this value.
