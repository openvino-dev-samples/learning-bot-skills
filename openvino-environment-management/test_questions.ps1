<#
  Smoke test for the openvino-environment-management prepared questions.

  Offline & network-free: validates that questions.ps1 emits a well-formed [SKILL_QUESTIONS]
  block for every type (preset / preflight / clarify / all) and that questions.json parses.

  Usage:  powershell -ExecutionPolicy Bypass -File test_questions.ps1
  Exit code 0 = all tests passed, 1 = one or more failed.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = "Continue"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$QPs       = Join-Path $ScriptDir "questions.ps1"
$QJson     = Join-Path $ScriptDir "questions.json"

$pass = 0; $fail = 0
function Check($name, [scriptblock]$cond) {
  $ok = $false
  try { $ok = (& $cond) } catch { $ok = $false }
  if ($ok) { Write-Host "  PASS: $name" -ForegroundColor Green; $script:pass++ }
  else     { Write-Host "  FAIL: $name" -ForegroundColor Red;   $script:fail++ }
}

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

Write-Host "=== openvino-environment-management questions smoke test ===" -ForegroundColor Cyan

Write-Host ""
Write-Host "1. questions.json / questions.ps1 present & well-formed" -ForegroundColor White
Check "questions.ps1 exists"   { Test-Path $QPs }
Check "questions.json parses"  { try { Get-Content -Raw -Encoding UTF8 $QJson | ConvertFrom-Json | Out-Null; $true } catch { $false } }

Write-Host ""
Write-Host "2. Prepared questions ([SKILL_QUESTIONS] contract, offline)" -ForegroundColor White
foreach ($t in @("preset","preflight","clarify","all")) {
  $qo = & powershell -ExecutionPolicy Bypass -File $QPs -Type $t 2>&1 | Out-String
  Check "questions -Type $t valid block" { Test-Questions "openvino-environment-management" $qo }
}

Write-Host ""
Write-Host "=== Result: $pass passed, $fail failed ===" -ForegroundColor Cyan
if ($fail -gt 0) { exit 1 } else { exit 0 }
