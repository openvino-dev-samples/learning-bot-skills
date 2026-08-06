<#
  Learning Bot launcher - orchestrator entry point.

  Starts the Learning Bot: recommends the preset questions, routes a user utterance to a
  preset local skill (14 aipc-skills) or a dev skill (ENV/FETCH/PIPE), and can install a
  preset skill locally. All logic lives in scripts/learning_bot.py (stdlib only; menu and
  routing are offline, only -Install touches the network).

  Usage:
    run.ps1 -Menu                         # 打印推荐给用户的预设问题
    run.ps1 -Questions preflight          # 输出准备好的问题（preset/preflight/clarify/all）
    run.ps1 -Route "帮我把录音转成文字"    # 对一句用户输入给出路由建议
    run.ps1 -Install asr [-OutDir C:\path] # 下载并解压对应的 aipc-skill
#>
[CmdletBinding()]
param(
  [switch]$Menu,
  [ValidateSet("preset","preflight","clarify","all")][string]$Questions,
  [string]$Route,
  [string]$Install,
  [string]$OutDir,
  [Parameter(ValueFromRemainingArguments=$true)][string[]]$Rest
)

$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$Bot = Join-Path $ScriptDir "learning_bot.py"

# ---------------- 未知参数守卫 ----------------
# 没有这一段时，PowerShell 会静默丢弃它不认识的参数写法，脚本落到默认分支（打印菜单）并返回 0。
# 对 agent 来说这看起来像「命令成功了」，实际它要的动作根本没发生。这里显式报错并停下。
if ($Rest -and $Rest.Count -gt 0) {
  Write-Host "[SKILL_RESULT]"
  Write-Host "status=error"
  Write-Host "skill=learning-bot"
  Write-Host "reason=unknown-argument"
  Write-Host ("unknown=" + ($Rest -join " "))
  Write-Host "valid_params=-Menu | -Questions preset|preflight|clarify|all | -Route <text> | -Install <key> [-OutDir <path>]"
  Write-Host "note=unrecognized argument; nothing was executed"
  Write-Host "[/SKILL_RESULT]"
  exit 1
}

function Get-Python {
  # Reuse the content-fetch venv if present, else system python (bot logic is stdlib-only).
  $venvPy = Join-Path $env:USERPROFILE ".openvino\venv-contentfetch\Scripts\python.exe"
  if (Test-Path $venvPy) { return $venvPy }
  # 系统 python 也必须先确认存在 —— 否则 agent 拿到的是 PowerShell 的 CommandNotFoundException，
  # 而不是「该先去装 Python」这个可执行的结论。
  if (-not (Get-Command python -ErrorAction SilentlyContinue)) {
    Write-Host "[SKILL_RESULT]"
    Write-Host "status=error"
    Write-Host "skill=learning-bot"
    Write-Host "reason=python-not-found"
    Write-Host "next=openvino-environment-management"
    Write-Host "note=python is not on PATH; run the environment-management skill first"
    Write-Host "[/SKILL_RESULT]"
    exit 1
  }
  return "python"
}

$py = Get-Python

if ($Menu) {
  & $py $Bot --menu
  exit $LASTEXITCODE
}
if ($Questions) {
  & $py $Bot --questions $Questions
  exit $LASTEXITCODE
}
if ($Route) {
  & $py $Bot --route $Route
  exit $LASTEXITCODE
}
if ($Install) {
  if ($OutDir) { & $py $Bot --install $Install --out-dir $OutDir }
  else         { & $py $Bot --install $Install }
  exit $LASTEXITCODE
}

# Default: show the menu (i.e. "start the Learning Bot").
& $py $Bot --menu
exit $LASTEXITCODE
