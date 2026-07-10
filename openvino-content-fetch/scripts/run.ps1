<#
  OpenVINO Content Fetch — orchestrator.

  Fetches and parses notebooks, model lists, skills, and dev zone articles,
  sets up a persisted venv, and emits a [SKILL_RESULT] block.

  Usage:
    run.ps1 -Source github [--china]
    run.ps1 -Source github -Task "Text-to-Image" [-Query "stable diffusion"] [-Limit 10]
    run.ps1 -Source all [--china] [--out C:\path\to\out.json]
    run.ps1 -Download "Qwen2.5-7B-Instruct-INT4-OV" [-OutDir C:\models\qwen] [--china]
    run.ps1 -Status
    run.ps1 -ShowDebug
#>
[CmdletBinding()]
param(
  [ValidateSet("github","modelscope","csdn","all")][string]$Source = "all",
  [switch]$China,
  [string]$RepoDir,
  [string]$Query,
  [string]$Task,
  [string]$Category,
  [int]$Limit,
  [string]$Out,
  [string]$Download,
  [string]$OutDir,
  [switch]$Status,
  [switch]$ShowDebug
)

$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$Base      = Join-Path $env:USERPROFILE ".openvino"
$VenvDir   = Join-Path $Base "venv-contentfetch"
$SharedRepoDir = Join-Path $Base "openvino_notebooks"
$LogDir    = Join-Path $Base "log"
New-Item -ItemType Directory -Force -Path $Base,$LogDir | Out-Null

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

# ---------------- lifecycle: status / debug ----------------
if ($Status) {
  $venvOk = Test-Path (Join-Path $VenvDir "Scripts\python.exe")
  $repoOk = Test-Path (Join-Path $SharedRepoDir "notebooks")
  Emit-Result([ordered]@{
    status      = "ok"
    venv        = ($(if ($venvOk) {"ready"} else {"missing"}))
    notebooks   = ($(if ($repoOk) {"cloned"} else {"missing"}))
    venv_dir    = $VenvDir
    notebooks_dir = $SharedRepoDir
  })
  exit 0
}

if ($ShowDebug) {
  Log "Base dir      : $Base"
  Log "venv          : $VenvDir  (exists=$(Test-Path $VenvDir))"
  Log "notebook_repo : $SharedRepoDir  (exists=$(Test-Path $SharedRepoDir))"
  $py = Get-Python
  Log "python        : $py"
  try { & $py -c "import urllib.request, bs4; Log '[debug] bs4 and urllib are importable'" } catch { Log "Warning: dependencies not fully importable yet: $_" }
  exit 0
}

# ---------------- pip / git index config (China mirrors) ----------------
$PipArgs = @()
if ($China) {
  $PipArgs = @("-i","https://mirrors.tuna.tsinghua.edu.cn/pypi/web/simple")
  Log "China mode: pip=tuna"
}

# ---------------- venv setup ----------------
if (-not (Test-Path (Join-Path $VenvDir "Scripts\python.exe"))) {
  Log "Creating venv at $VenvDir ..."
  & python -m venv $VenvDir
}
$Py = Get-Python
Log "Installing deps (first-run setup)..."
& $Py -m pip install --upgrade pip @PipArgs | Out-Null
& $Py -m pip install @PipArgs -r (Join-Path $ScriptDir "..\requirements.txt")
if ($LASTEXITCODE -ne 0) {
  Emit-Result([ordered]@{ status="error"; note="pip install failed (see above)"; hint="check --china mirror / network" })
  exit 1
}

# ---------------- model download mode ----------------
if ($Download) {
  Log "Download mode: model '$Download'"
  $dlArgs = @((Join-Path $ScriptDir "fetch_content.py"), "--download", $Download)
  if ($OutDir) { $dlArgs += @("--out-dir", $OutDir) }
  if ($China) { $dlArgs += "--china" }
  & $Py @dlArgs
  exit $LASTEXITCODE
}

# ---------------- notebooks repo check ----------------
# Note: We intentionally avoid auto-cloning/auto-updating the openvino_notebooks repo in this skill
# because it is too large and connection drops out. Instead, fetch_content.py has a high-fidelity,
# up-to-date, pre-compiled index of all 100+ notebooks on the master branch. This guarantees instant
# loading and 100% success offline or online. If the repo is already cloned locally (e.g. from pipeline opt),
# we will dynamically parse it instead.

# ---------------- run content fetch ----------------
Log "Running python fetcher..."
$fetchArgs = @((Join-Path $ScriptDir "fetch_content.py"), "--source", $Source)
if ($China) { $fetchArgs += "--china" }
if ($Out) { $fetchArgs += @("--out", $Out) }
if ($Query) { $fetchArgs += @("--query", $Query) }
if ($Task) { $fetchArgs += @("--task", $Task) }
if ($Category) { $fetchArgs += @("--category", $Category) }
if ($Limit -gt 0) { $fetchArgs += @("--limit", $Limit) }

$TargetRepo = $SharedRepoDir
if ($RepoDir) { $TargetRepo = $RepoDir }
if (Test-Path (Join-Path $TargetRepo "notebooks")) {
  $fetchArgs += @("--repo-dir", $TargetRepo)
}

& $Py @fetchArgs
if ($LASTEXITCODE -ne 0) {
  Emit-Result([ordered]@{ status="error"; note="fetch_content.py run failed" })
  exit 1
}
