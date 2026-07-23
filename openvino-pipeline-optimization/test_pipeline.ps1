<#
  Smoke test for the openvino-pipeline-optimization skill.

  Offline & hardware-free: exercises the orchestration logic (resolve -> optimize --dry-run ->
  bench --dry-run -> client --help) against a tiny synthetic openvino_notebooks repo. It does NOT
  download models, clone the real repo, or need Intel hardware / the heavy venv.

  Usage:  powershell -ExecutionPolicy Bypass -File test_pipeline.ps1
  Exit code 0 = all tests passed, 1 = one or more failed.
#>
[CmdletBinding()]
param([switch]$KeepTemp)

# Test harness does its own pass/fail accounting; don't abort on native stderr writes.
$ErrorActionPreference = "Continue"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$Scripts   = Join-Path $ScriptDir "scripts"

# Pick a python: prefer the skill's persisted venv, else system python (scripts under test are stdlib-only).
$VenvPy = Join-Path $env:USERPROFILE ".openvino\venv-pipeopt\Scripts\python.exe"
$Py = if (Test-Path $VenvPy) { $VenvPy } else { "python" }

$pass = 0; $fail = 0
function Check($name, [scriptblock]$cond) {
  $ok = $false
  try { $ok = (& $cond) } catch { $ok = $false }
  if ($ok) { Write-Host "  PASS: $name" -ForegroundColor Green; $script:pass++ }
  else     { Write-Host "  FAIL: $name" -ForegroundColor Red;   $script:fail++ }
}

Write-Host "=== openvino-pipeline-optimization smoke test ===" -ForegroundColor Cyan
Write-Host "python: $Py"

# ---- build a tiny synthetic notebooks repo (2 stages: encoder + llm) ----
$Tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("pipeopt-test-" + [System.Guid]::NewGuid().ToString("N").Substring(0,8))
$nbDir = Join-Path $Tmp "notebooks\mock-asr-llm"
New-Item -ItemType Directory -Force -Path $nbDir | Out-Null
@'
# synthetic notebook stage references (scanned by resolve_pipeline.py)
from transformers import AutoModelForCausalLM
asr = snapshot_download("Mock/whisper-tiny")
llm = AutoModelForCausalLM.from_pretrained("Mock/TinyLlama-Instruct")
'@ | Set-Content -Path (Join-Path $nbDir "app.py") -Encoding UTF8
# a per-notebook requirements.txt so the run.ps1 wiring has something to find (not installed here)
"transformers>=4.44`nlibrosa>=0.10" | Set-Content -Path (Join-Path $nbDir "requirements.txt") -Encoding UTF8

$plan = Join-Path $Tmp "plan.json"
$irDir = Join-Path $Tmp "ir"

Write-Host ""
Write-Host "1. Scripts compile" -ForegroundColor White
foreach ($s in @("resolve_pipeline.py","optimize.py","bench.py","server.py","client.py")) {
  Check "py_compile $s" { & $Py -m py_compile (Join-Path $Scripts $s); $LASTEXITCODE -eq 0 }
}

Write-Host ""
Write-Host "2. resolve_pipeline.py discovers stages from the synthetic repo" -ForegroundColor White
& $Py (Join-Path $Scripts "resolve_pipeline.py") --slug "mock-asr-llm" --repo $Tmp --out $plan | Out-Null
$resolveRc = $LASTEXITCODE
Check "resolve exit 0"                 { $resolveRc -eq 0 }
Check "plan.json written"             { Test-Path $plan }
$planObj = if (Test-Path $plan) { Get-Content $plan -Raw | ConvertFrom-Json } else { $null }
Check "resolve ok=true"               { $planObj -and $planObj.ok -eq $true }
Check "discovered 2 stages"           { $planObj -and $planObj.stages.Count -eq 2 }
Check "llm role present"              { $planObj -and ($planObj.stages.role -contains "llm") }
Check "encoder role present"          { $planObj -and ($planObj.stages.role -contains "encoder") }

Write-Host ""
Write-Host "3. optimize.py --dry-run plans without downloading" -ForegroundColor White
& $Py (Join-Path $Scripts "optimize.py") --plan $plan --ir-dir $irDir --dry-run | Out-Null
Check "optimize exit 0"               { $LASTEXITCODE -eq 0 }
$pipePlan = Join-Path $irDir "pipeline-plan.json"
Check "pipeline-plan.json written"    { Test-Path $pipePlan }
$ppObj = if (Test-Path $pipePlan) { Get-Content $pipePlan -Raw | ConvertFrom-Json } else { $null }
Check "stages marked would-build"     { $ppObj -and ($ppObj.stages.status -contains "would-build") }

Write-Host ""
Write-Host "4. bench.py --dry-run emits a well-formed [SKILL_RESULT]" -ForegroundColor White
$benchOut = & $Py (Join-Path $Scripts "bench.py") --ir-dir $irDir --dry-run 2>&1 | Out-String
Check "bench exit 0"                  { $LASTEXITCODE -eq 0 }
Check "SKILL_RESULT block present"    { $benchOut -match "\[SKILL_RESULT\]" -and $benchOut -match "\[/SKILL_RESULT\]" }
Check "status=ok in result"           { $benchOut -match "status=ok" }
Check "pipeline field present"        { $benchOut -match "pipeline=mock-asr-llm" }

Write-Host ""
Write-Host "5. client.py --help works (stdlib-only client)" -ForegroundColor White
& $Py (Join-Path $Scripts "client.py") --help | Out-Null
Check "client --help exit 0"          { $LASTEXITCODE -eq 0 }

Write-Host ""
Write-Host "6. run.ps1 --status emits a [SKILL_RESULT]" -ForegroundColor White
$statusOut = & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Scripts "run.ps1") --status 2>&1 | Out-String
Check "run.ps1 --status SKILL_RESULT" { $statusOut -match "\[SKILL_RESULT\]" }

Write-Host ""
Write-Host "7. Prepared questions ([SKILL_QUESTIONS] contract, offline)" -ForegroundColor White
function Test-Questions($expectSkill, $out) {
  $lines = $out -split "`r?`n"
  if ($lines -notcontains "[SKILL_QUESTIONS]" -or $lines -notcontains "[/SKILL_QUESTIONS]") { return $false }
  $sk = ($lines | Where-Object { $_ -like "skill=*" } | Select-Object -First 1)
  $cn = ($lines | Where-Object { $_ -like "count=*" } | Select-Object -First 1)
  $dt = ($lines | Where-Object { $_ -like "data=*" } | Select-Object -First 1)
  if (-not $sk -or -not $cn -or -not $dt) { return $false }
  if ($sk -ne "skill=$expectSkill") { return $false }
  try { $arr = $dt.Substring(5) | ConvertFrom-Json } catch { return $false }
  return (@($arr).Count -eq [int]$cn.Substring(6)) -and (@($arr).Count -gt 0)
}
$QPs = Join-Path $Scripts "questions.ps1"
Check "questions.ps1 exists" { Test-Path $QPs }
foreach ($t in @("preset","preflight","clarify","all")) {
  $qo = & powershell -ExecutionPolicy Bypass -File $QPs -Type $t 2>&1 | Out-String
  Check "questions -Type $t valid block" { Test-Questions "openvino-pipeline-optimization" $qo }
}

# ---- cleanup ----
if (-not $KeepTemp) { Remove-Item -Recurse -Force $Tmp -ErrorAction SilentlyContinue }
else { Write-Host "`n(kept temp repo at $Tmp)" -ForegroundColor Gray }

Write-Host ""
Write-Host "=== Result: $pass passed, $fail failed ===" -ForegroundColor Cyan
exit ($(if ($fail -gt 0) { 1 } else { 0 }))
