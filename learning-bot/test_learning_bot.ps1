<#
  Smoke test for the learning-bot launcher skill.

  Offline & network-free: exercises menu + routing (stdlib-only) and validates the skills
  registry (14 preset skills + release URL) and the [SKILL_RESULT] contracts. It does NOT
  download any zip or require a live network (-Install is not exercised here).

  Usage:  powershell -ExecutionPolicy Bypass -File test_learning_bot.ps1
  Exit code 0 = all tests passed, 1 = one or more failed.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = "Continue"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$Scripts   = Join-Path $ScriptDir "scripts"
$Bot       = Join-Path $Scripts "learning_bot.py"
$Registry  = Join-Path $Scripts "skills_registry.json"

$VenvPy = Join-Path $env:USERPROFILE ".openvino\venv-contentfetch\Scripts\python.exe"
$Py = if (Test-Path $VenvPy) { $VenvPy } else { "python" }

$pass = 0; $fail = 0
function Check($name, [scriptblock]$cond) {
  $ok = $false
  try { $ok = (& $cond) } catch { $ok = $false }
  if ($ok) { Write-Host "  PASS: $name" -ForegroundColor Green; $script:pass++ }
  else     { Write-Host "  FAIL: $name" -ForegroundColor Red;   $script:fail++ }
}

Write-Host "=== learning-bot smoke test ===" -ForegroundColor Cyan
Write-Host "python: $Py"

Write-Host ""
Write-Host "1. Script compiles & --help works (stdlib-only)" -ForegroundColor White
Check "py_compile learning_bot.py" { & $Py -m py_compile $Bot; $LASTEXITCODE -eq 0 }
& $Py $Bot --menu | Out-Null
Check "--menu exit 0"             { $LASTEXITCODE -eq 0 }

Write-Host ""
Write-Host "2. Registry is well-formed (14 preset skills + release + 3 dev skills)" -ForegroundColor White
$reg = $null
try { $reg = Get-Content -Raw -Encoding UTF8 $Registry | ConvertFrom-Json } catch { $reg = $null }
Check "registry parses as JSON"        { $null -ne $reg }
Check "release base_url present"       { $reg.release.base_url -match "^https://github.com/makejiang/aipc-skills/releases/download/1\.0\.6/" }
Check "14 preset skills"               { $reg.preset_skills.Count -eq 14 }
Check "3 dev skills (ENV/FETCH/PIPE)"  { $reg.dev_skills.Count -eq 3 }
Check "every preset has key/zip/question/keywords" {
  $bad = $reg.preset_skills | Where-Object { -not $_.key -or -not $_.zip -or -not $_.question -or -not $_.keywords }
  ($bad | Measure-Object).Count -eq 0
}
$expectedKeys = @("asr","tts","realtime-translator","ocr-npu","ocr-gpu","mineru","txt2img","img2img","txt2video","sr","yolo26","screenshot-qa","computer-use","vram")
Check "all 14 expected keys present" {
  $have = $reg.preset_skills | ForEach-Object { $_.key }
  ($expectedKeys | Where-Object { $have -notcontains $_ } | Measure-Object).Count -eq 0
}

Write-Host ""
Write-Host "3. Menu emits a valid [SKILL_RESULT] (action=menu, count=14)" -ForegroundColor White
$menu = & $Py $Bot --menu 2>&1 | Out-String
Check "menu SKILL_RESULT block" { $menu -match "\[SKILL_RESULT\]" -and $menu -match "\[/SKILL_RESULT\]" }
Check "menu action=menu"        { $menu -match "action=menu" }
Check "menu count=14"           { $menu -match "count=14" }

Write-Host ""
Write-Host "4. Routing: preset inputs map to the expected preset skill" -ForegroundColor White
$presetCases = @{
  "帮我把这段录音转成文字"          = "asr"
  "把这段文字读出来生成语音"        = "tts"
  "帮我实时翻译这段对话"            = "realtime-translator"
  "识别这张图片里的文字"            = "ocr-npu"
  "用 GPU 识别这张图里的文字"       = "ocr-gpu"
  "帮我解析这个 PDF 转成 markdown"  = "mineru"
  "根据这段描述生成一张图片"        = "txt2img"
  "基于这张图重绘一张新图"          = "img2img"
  "根据描述生成一段视频"            = "txt2video"
  "把这张模糊的图片变清晰放大"      = "sr"
  "检测这张图片里有哪些物体"        = "yolo26"
  "帮我截个屏回答屏幕内容的问题"    = "screenshot-qa"
  "帮我自动操作电脑完成任务"        = "computer-use"
  "看看我现在的显存占用"            = "vram"
}
foreach ($k in $presetCases.Keys) {
  $want = $presetCases[$k]
  $out = & $Py $Bot --route $k 2>&1 | Out-String
  Check "route '$k' -> scope=preset"        { $out -match "scope=preset" }
  Check "route '$k' -> target=$want"        { $out -match ("target=" + [regex]::Escape($want) + "\b") }
}

Write-Host ""
Write-Host "5. Routing: non-preset (dev) inputs map to ENV/FETCH/PIPE" -ForegroundColor White
$devCases = @{
  "帮我在 Intel 笔记本上搭环境配置 OpenVINO" = "openvino-environment-management"
  "推荐一个做图像分割的 notebook"            = "openvino-content-fetch"
  "从 ModelScope 下载模型"                   = "openvino-content-fetch"
  "把这几个模型组装成流水线并部署服务"       = "openvino-pipeline-optimization"
  "给我的流水线跑个 benchmark 找瓶颈"        = "openvino-pipeline-optimization"
}
foreach ($k in $devCases.Keys) {
  $want = $devCases[$k]
  $out = & $Py $Bot --route $k 2>&1 | Out-String
  Check "route '$k' -> scope=dev"     { $out -match "scope=dev" }
  Check "route '$k' -> target=$want"  { $out -match ("target=" + [regex]::Escape($want)) }
}

Write-Host ""
Write-Host "6. Routing: ambiguous input asks to clarify" -ForegroundColor White
$amb = & $Py $Bot --route "给我用 AI 做点酷的东西" 2>&1 | Out-String
Check "ambiguous -> scope=clarify"   { $amb -match "scope=clarify" }
Check "ambiguous -> matched=false"   { $amb -match "matched=false" }

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
foreach ($t in @("preset","preflight","clarify","all")) {
  $qo = & $Py $Bot --questions $t 2>&1 | Out-String
  Check "questions --questions $t valid block" { Test-Questions "learning-bot" $qo }
}
# preset is single-sourced from the registry (14 preset skills)
$qp = & $Py $Bot --questions preset 2>&1 | Out-String
$qpCount = if ($qp -match "count=(\d+)") { [int]$Matches[1] } else { -1 }
Check "preset question offers all 14 skills (5th option = ... or block options)" {
  $dt = ($qp -split "`r?`n" | Where-Object { $_ -like "data=*" } | Select-Object -First 1)
  if (-not $dt) { return $false }
  try { $arr = @($dt.Substring(5) | ConvertFrom-Json) } catch { return $false }
  ($arr[0].options | Measure-Object).Count -eq 14
}

Write-Host ""
Write-Host "=== Result: $pass passed, $fail failed ===" -ForegroundColor Cyan
if ($fail -gt 0) { exit 1 } else { exit 0 }
