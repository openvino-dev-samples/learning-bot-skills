<#
  Prepared Questions emitter (shared, identical across skills).

  Reads questions.json next to this script and emits a machine-parsable
  [SKILL_QUESTIONS] block for the requested type. Offline / no network, no deps.

  Types:
    preset     推荐问题（"你可以问我这些"）
    preflight  前置条件确认（多选；没勾的项 -> on_missing 指向应先跑的 skill）
    clarify    澄清追问（收敛意图）
    all        以上全部（默认）

  Usage:
    questions.ps1 -Type preflight
    questions.ps1                # = -Type all

  Contract:
    [SKILL_QUESTIONS]
    skill=<skill name>
    type=<preset|preflight|clarify|all>
    count=<number of question blocks>
    data=<compact JSON array of question blocks>
    [/SKILL_QUESTIONS]

  Each block: { type, id, prompt, multiselect, options:[
    { key, label, example?, exclusive?, on_missing? } ] }
    - exclusive  : selecting it clears the rest (e.g. "以上均完成，无需引导我")
    - on_missing : if this prereq is NOT checked, the skill/param to run first
                   (e.g. "openvino-content-fetch" or "self:-China")
#>
[CmdletBinding()]
param(
  [ValidateSet("preset","preflight","clarify","all")][string]$Type = "all"
)

$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$QFile = Join-Path $ScriptDir "questions.json"
if (-not (Test-Path $QFile)) {
  Write-Error "questions.json not found next to questions.ps1 ($QFile)"
  exit 1
}

$all = Get-Content $QFile -Raw | ConvertFrom-Json
$skill = $all.skill

if ($Type -eq "all") {
  $blocks = @($all.preset) + @($all.preflight) + @($all.clarify) | Where-Object { $_ }
} else {
  $blocks = @($all.$Type) | Where-Object { $_ }
}
$arr = @($blocks)

if ($arr.Count -eq 0) {
  $data = "[]"
} else {
  $j = $arr | ConvertTo-Json -Depth 12 -Compress
  # PowerShell 5.1 unwraps single-element arrays; force an array for a stable contract.
  if ($arr.Count -eq 1) { $data = "[$j]" } else { $data = $j }
}

Write-Host "[SKILL_QUESTIONS]"
Write-Host "skill=$skill"
Write-Host "type=$Type"
Write-Host "count=$($arr.Count)"
Write-Host "data=$data"
Write-Host "[/SKILL_QUESTIONS]"
exit 0
