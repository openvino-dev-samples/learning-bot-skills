<#
  OpenVINO Pipeline Optimization — orchestrator.

  Resolves a pipeline (slug or goal), clones openvino_notebooks, sets up a persisted
  venv, optimizes each stage (IR + NNCF + device), benchmarks end-to-end, and emits a
  [SKILL_RESULT] block.

  Usage:
    run.ps1 --slug whisper-asr-genai [--china] [--device GPU] [--precision INT4]
    run.ps1 --slug whisper-asr-genai,llm-rag-langchain   # compose multiple notebooks
    run.ps1 --goal "local ASR to LLM to TTS" [--china]
    run.ps1 --serve --slug vlm-chatbot [--port 18790]    # build+optimize, then serve
    run.ps1 --dry-run --slug vlm-chatbot     # resolve + plan only, no downloads
    run.ps1 --questions preflight            # prepared questions (preset/preflight/clarify/all)
    run.ps1 --status | --stop | --debug
#>
param(
  [string]$slug,
  [string]$goal,
  [ValidateSet("NPU","GPU","CPU")][string]$device,
  [ValidateSet("INT4","INT8","FP16")][string]$precision,
  [switch]$china,
  [switch]$dryrun,
  [switch]$serve,
  [int]$port = 18790,
  [ValidateSet("preset","preflight","clarify","all")][string]$questions,
  [switch]$status,
  [switch]$stop,
  [switch]$debug
)

$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$Base      = Join-Path $env:USERPROFILE ".openvino"
$VenvDir   = Join-Path $Base "venv-pipeopt"
$RepoDir   = Join-Path $Base "openvino_notebooks"
$IrRoot    = Join-Path $Base "ir"
$LogDir    = Join-Path $Base "log"
$PidFile   = Join-Path $Base "pipeopt.pid"
$ServePid  = Join-Path $Base "pipeopt-serve.pid"
New-Item -ItemType Directory -Force -Path $Base,$IrRoot,$LogDir | Out-Null

function Invoke-Health($p) {
  try { return Invoke-RestMethod -Uri "http://127.0.0.1:$p/api/health" -TimeoutSec 3 } catch { return $null }
}

function Log($m) { Write-Host "[run] $m" }

function Emit-Result($kv) {
  Write-Host "[SKILL_RESULT]"
  foreach ($k in $kv.Keys) { Write-Host ("{0}={1}" -f $k, $kv[$k]) }
  Write-Host "[/SKILL_RESULT]"
}

function Get-Python {
  if (Test-Path (Join-Path $VenvDir "Scripts\python.exe")) {
    return (Join-Path $VenvDir "Scripts\python.exe")
  }
  return "python"
}

# ---------------- prepared questions (offline; no venv / clone needed) ----------------
if ($questions) {
  & powershell -ExecutionPolicy Bypass -File (Join-Path $ScriptDir "questions.ps1") -Type $questions
  exit $LASTEXITCODE
}

# ---------------- lifecycle: status / stop / debug ----------------
if ($status) {
  $venvOk = Test-Path (Join-Path $VenvDir "Scripts\python.exe")
  $repoOk = Test-Path (Join-Path $RepoDir "notebooks")
  $lastPlan = Get-ChildItem -Path $IrRoot -Recurse -Filter "pipeline-plan.json" -ErrorAction SilentlyContinue |
              Sort-Object LastWriteTime -Descending | Select-Object -First 1
  $h = Invoke-Health $port
  Emit-Result([ordered]@{
    status      = "ok"
    venv        = ($(if ($venvOk) {"ready"} else {"missing"}))
    notebooks   = ($(if ($repoOk) {"cloned"} else {"missing"}))
    last_plan   = ($(if ($lastPlan) { $lastPlan.FullName } else {"none"}))
    service     = ($(if ($h) { "running ($($h.status), $($h.pipeline))" } else {"not_running"}))
    service_url = "http://127.0.0.1:$port"
    ir_root     = $IrRoot
  })
  exit 0
}

if ($stop) {
  $h = Invoke-Health $port
  if ($h) { try { Invoke-RestMethod -Uri "http://127.0.0.1:$port/api/shutdown" -Method Post -TimeoutSec 3 | Out-Null } catch {} }
  foreach ($pf in @($ServePid, $PidFile)) {
    if (Test-Path $pf) {
      $procId = Get-Content $pf -ErrorAction SilentlyContinue
      if ($procId) { Stop-Process -Id $procId -Force -ErrorAction SilentlyContinue }
      Remove-Item $pf -ErrorAction SilentlyContinue
    }
  }
  Get-Process -Name "python" -ErrorAction SilentlyContinue |
    Where-Object { $_.Path -and $_.Path.StartsWith($VenvDir) } |
    Stop-Process -Force -ErrorAction SilentlyContinue
  Emit-Result([ordered]@{ status="ok"; note="stopped pipeline + service processes" })
  exit 0
}

if ($debug) {
  Log "Base dir      : $Base"
  Log "venv          : $VenvDir  (exists=$(Test-Path $VenvDir))"
  Log "notebooks repo: $RepoDir  (exists=$(Test-Path $RepoDir))"
  Log "IR root       : $IrRoot"
  $py = Get-Python
  Log "python        : $py"
  try { & $py -c "import openvino as ov; print('[debug] devices:', ov.Core().available_devices)" } catch { Log "openvino not importable: $_" }
  Get-ChildItem -Path $LogDir -Filter "*.log" -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending | Select-Object -First 1 |
    ForEach-Object { Log "last log: $($_.FullName)"; Get-Content $_.FullName -Tail 40 }
  exit 0
}

# ---------------- inputs ----------------
if (-not $slug -and -not $goal) {
  Emit-Result([ordered]@{ status="error"; note="provide --slug <name> or --goal ""<text>""" })
  exit 1
}

# ---------------- pip / git index config (China mirrors) ----------------
$PipArgs = @()
if ($china) {
  $PipArgs = @("-i","https://mirrors.tuna.tsinghua.edu.cn/pypi/web/simple")
  $env:HF_ENDPOINT = "https://hf-mirror.com"
  $RepoUrl = "https://gitcode.com/openvinotoolkit/openvino_notebooks.git"
  Log "China mode: pip=tuna, HF=hf-mirror, notebooks=gitcode"
} else {
  $RepoUrl = "https://github.com/openvinotoolkit/openvino_notebooks.git"
}

# ---------------- clone / update notebooks repo (needed BEFORE resolve) ----------------
# Resolve discovers stages from notebooks/<slug>/, and deps come from each notebook's own
# requirements.txt, so the repo must exist first. Shallow clone; LFS blobs skipped.
$env:GIT_LFS_SKIP_SMUDGE = "1"
if (-not (Test-Path (Join-Path $RepoDir "notebooks"))) {
  Log "Cloning openvino_notebooks (shallow, latest) ..."
  & git clone --depth 1 --branch latest $RepoUrl $RepoDir
} else {
  Log "Updating notebooks repo ..."
  & git -C $RepoDir pull --ff-only 2>$null
}

# ---------------- resolve (always; dry-run stops here) ----------------
$py0 = Get-Python
$PlanJson = Join-Path $IrRoot "_resolved.json"
$resolveArgs = @((Join-Path $ScriptDir "resolve_pipeline.py"))
if ($slug)      { $resolveArgs += @("--slug", $slug) }
if ($goal)      { $resolveArgs += @("--goal", $goal) }
if ($device)    { $resolveArgs += @("--device", $device) }
if ($precision) { $resolveArgs += @("--precision", $precision) }
if (Test-Path (Join-Path $RepoDir "notebooks")) { $resolveArgs += @("--repo", $RepoDir) }
$resolveArgs += @("--out", $PlanJson)
if ($dryrun)    { $resolveArgs += @("--dry-run") }

Log "Resolving pipeline..."
& $py0 @resolveArgs
if ($LASTEXITCODE -ne 0) {
  Emit-Result([ordered]@{ status="error"; note="could not resolve pipeline (see above)" })
  exit 1
}

$resolved = Get-Content $PlanJson -Raw | ConvertFrom-Json
$Slug = $resolved.pipeline
$IrDir = Join-Path $IrRoot $Slug

if ($dryrun) {
  Log "--dry-run: resolved '$Slug'. No download/optimize/bench performed."
  exit 0
}

# ---------------- venv + deps (minimal core + per-notebook requirements) ----------------
if (-not (Test-Path (Join-Path $VenvDir "Scripts\python.exe"))) {
  Log "Creating venv at $VenvDir ..."
  & python -m venv $VenvDir
}
$Py = Get-Python
& $Py -m pip install --upgrade pip @PipArgs | Out-Null

# Minimal core framework deps the skill's OWN scripts need (export IR / NNCF / serve).
# Everything model-specific is pulled from the selected notebook(s)' own requirements.txt,
# so the skill stays generic and never pins model libs the chosen notebook doesn't use.
$CoreDeps = @(
  "openvino>=2025.0", "openvino-genai>=2025.0", "openvino-tokenizers>=2025.0",
  "nncf>=2.14", "optimum-intel[openvino]>=1.21",
  "nbformat>=5.10", "numpy>=1.26",
  "fastapi>=0.115", "uvicorn>=0.30", "pydantic>=2.7"
)
Log "Installing minimal core framework deps ..."
& $Py -m pip install @PipArgs @CoreDeps
if ($LASTEXITCODE -ne 0) {
  Emit-Result([ordered]@{ status="error"; note="core dep install failed (see above)"; hint="check --china mirror / network" })
  exit 1
}

# Install each selected notebook's own requirements.txt so model-specific deps match the notebook.
foreach ($sl in $resolved.slugs) {
  $req = Join-Path $RepoDir "notebooks\$sl\requirements.txt"
  if (Test-Path $req) {
    Log "Installing notebook requirements for '$sl' -> $req"
    & $Py -m pip install @PipArgs -r $req
    if ($LASTEXITCODE -ne 0) {
      Log "WARN: some deps in '$sl' requirements.txt failed to install; continuing (notebook may pin conflicting versions)."
    }
  } else {
    Log "No requirements.txt for notebook '$sl' (skipping)."
  }
}

# ---------------- optimize ----------------
New-Item -ItemType Directory -Force -Path $IrDir | Out-Null
Log "Optimizing stages -> $IrDir"
& $Py (Join-Path $ScriptDir "optimize.py") --plan $PlanJson --ir-dir $IrDir
if ($LASTEXITCODE -ne 0) {
  Emit-Result([ordered]@{ status="error"; pipeline=$Slug; note="optimization failed (see above)"; ir_dir=$IrDir })
  exit 1
}

# ---------------- benchmark (emits its own [SKILL_RESULT]) ----------------
Log "Benchmarking pipeline ..."
& $Py (Join-Path $ScriptDir "bench.py") --ir-dir $IrDir
$rc = $LASTEXITCODE

# ---------------- serve (optional deploy step) ----------------
if ($serve) {
  Log "Launching pipeline service on port $port ..."
  $srv = Start-Process -FilePath $Py `
    -ArgumentList @((Join-Path $ScriptDir "server.py"), "--ir-dir", $IrDir, "--port", "$port") `
    -PassThru -WindowStyle Hidden
  Set-Content -Path $ServePid -Value $srv.Id
  # poll health up to ~60s
  $h = $null
  for ($i = 0; $i -lt 30; $i++) {
    Start-Sleep -Seconds 2
    $h = Invoke-Health $port
    if ($h -and $h.status -eq "ok") { break }
  }
  if ($h -and $h.status -eq "ok") {
    Emit-Result([ordered]@{
      status      = "ok"
      pipeline    = $Slug
      service_url = "http://127.0.0.1:$port"
      health      = "ok"
      pid         = $srv.Id
    })
    Log "Service is up. Try the client:"
    Log "  python `"$ScriptDir\client.py`" --health --port $port"
    Log "  python `"$ScriptDir\client.py`" --run --input `"...`" --port $port"
    Log "  curl http://127.0.0.1:$port/api/health"
    Log "Stop with: run.ps1 --stop"
    exit 0
  } else {
    Emit-Result([ordered]@{ status="error"; pipeline=$Slug; note="service did not become healthy; see --debug"; service_url="http://127.0.0.1:$port" })
    exit 1
  }
}

exit $rc
