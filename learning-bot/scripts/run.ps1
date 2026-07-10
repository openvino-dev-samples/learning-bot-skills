<#
  Learning Bot launcher - orchestrator entry point.

  Starts the Learning Bot: recommends the preset questions, routes a user utterance to a
  preset local skill (14 aipc-skills) or a dev skill (ENV/FETCH/PIPE), and can install a
  preset skill locally. All logic lives in scripts/learning_bot.py (stdlib only; menu and
  routing are offline, only -Install touches the network).

  Usage:
    run.ps1 -Menu                         # 打印推荐给用户的预设问题
    run.ps1 -Route "帮我把录音转成文字"    # 对一句用户输入给出路由建议
    run.ps1 -Install asr [-OutDir C:\path] # 下载并解压对应的 aipc-skill
#>
[CmdletBinding()]
param(
  [switch]$Menu,
  [string]$Route,
  [string]$Install,
  [string]$OutDir
)

$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$Bot = Join-Path $ScriptDir "learning_bot.py"

function Get-Python {
  # Reuse the content-fetch venv if present, else system python (bot logic is stdlib-only).
  $venvPy = Join-Path $env:USERPROFILE ".openvino\venv-contentfetch\Scripts\python.exe"
  if (Test-Path $venvPy) { return $venvPy }
  return "python"
}

$py = Get-Python

if ($Menu) {
  & $py $Bot --menu
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
