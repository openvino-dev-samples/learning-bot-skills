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
                   (e.g. "openvino-environment-management" or "self:--dry-run")
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

# questions.json 是 UTF-8 无 BOM（Python 侧用 encoding="utf-8" 读，加 BOM 会让 json.load 失败），
# 所以 PowerShell 这边必须显式声明编码：Windows PowerShell 5.1 的 Get-Content 默认按系统 ANSI
# 代码页读取，在 cp1252 / cp936 机器上会把中文读成乱码，输出的问题清单随之全部损坏。
$all = Get-Content $QFile -Raw -Encoding UTF8 | ConvertFrom-Json
$skill = $all.skill

# 同理，控制台输出也要强制 UTF-8，否则中文在送出时会被系统代码页再转一次。
try {
  $OutputEncoding = [System.Text.Encoding]::UTF8
  [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
} catch { }

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
