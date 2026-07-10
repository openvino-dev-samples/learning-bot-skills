<#
  Smoke test for the openvino-content-fetch skill.

  Offline & network-free where possible: exercises the fetcher's contract using stdlib-only
  paths and the built-in seeded fallbacks (used when GitHub/ModelScope/CSDN are unreachable).
  It does NOT create the venv, install bs4/modelscope, or require a live network.

  Usage:  powershell -ExecutionPolicy Bypass -File test_content_fetch.ps1
  Exit code 0 = all tests passed, 1 = one or more failed.
#>
[CmdletBinding()]
param()

# Test harness does its own pass/fail accounting; don't abort on native stderr writes.
$ErrorActionPreference = "Continue"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$Scripts   = Join-Path $ScriptDir "scripts"
$Fetch     = Join-Path $Scripts "fetch_content.py"

# Prefer the skill's persisted venv, else system python (the tested paths are stdlib-only).
$VenvPy = Join-Path $env:USERPROFILE ".openvino\venv-contentfetch\Scripts\python.exe"
$Py = if (Test-Path $VenvPy) { $VenvPy } else { "python" }

$pass = 0; $fail = 0
function Check($name, [scriptblock]$cond) {
  $ok = $false
  try { $ok = (& $cond) } catch { $ok = $false }
  if ($ok) { Write-Host "  PASS: $name" -ForegroundColor Green; $script:pass++ }
  else     { Write-Host "  FAIL: $name" -ForegroundColor Red;   $script:fail++ }
}

Write-Host "=== openvino-content-fetch smoke test ===" -ForegroundColor Cyan
Write-Host "python: $Py"

Write-Host ""
Write-Host "1. Script compiles & --help works (stdlib-only, no bs4 needed)" -ForegroundColor White
Check "py_compile fetch_content.py" { & $Py -m py_compile $Fetch; $LASTEXITCODE -eq 0 }
& $Py $Fetch --help | Out-Null
Check "--help exit 0"               { $LASTEXITCODE -eq 0 }

Write-Host ""
Write-Host "1b. Navigation metadata parsing and filtering" -ForegroundColor White
& $Py -m unittest discover -s $ScriptDir -p "test_fetch_content.py" | Out-Host
Check "selector metadata unit tests" { $LASTEXITCODE -eq 0 }

Write-Host ""
Write-Host "2. Content fetch emits a valid [SKILL_RESULT] (live or seeded fallback)" -ForegroundColor White
foreach ($src in @("github","modelscope","csdn")) {
  # Keep the rich navigation JSON small enough for reliable PowerShell capture.
  $fetchArgs = @($Fetch, "--source", $src)
  if ($src -eq "github") { $fetchArgs += @("--limit", "5") }
  $out = & $Py @fetchArgs 2>&1 | Out-String
  Check "source=$src SKILL_RESULT block" { $out -match "\[SKILL_RESULT\]" -and $out -match "\[/SKILL_RESULT\]" }
  Check "source=$src status=ok"          { $out -match "status=ok" }
  Check "source=$src count>0"            { ($out -match "count=(\d+)") -and ([int]$Matches[1] -gt 0) }
}

Write-Host ""
Write-Host "3. Download mode emits the download contract (graceful even offline / no SDK)" -ForegroundColor White
$Tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("cfetch-test-" + [System.Guid]::NewGuid().ToString("N").Substring(0,8))
$dl = & $Py $Fetch --download "OpenVINO/does-not-exist-smoke-test" --out-dir $Tmp 2>&1 | Out-String
Check "download SKILL_RESULT block" { $dl -match "\[SKILL_RESULT\]" -and $dl -match "\[/SKILL_RESULT\]" }
Check "download action field"       { $dl -match "action=download" }
Check "download has status field"   { $dl -match "status=(ok|error)" }
Remove-Item -Recurse -Force $Tmp -ErrorAction SilentlyContinue

Write-Host ""
Write-Host "=== Result: $pass passed, $fail failed ===" -ForegroundColor Cyan
exit ($(if ($fail -gt 0) { 1 } else { 0 }))
