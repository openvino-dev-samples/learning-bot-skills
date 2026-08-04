<#
  test_contracts.ps1 —— 跨 skill 的契约回归测试（离线、不联网、不安装任何东西）。

  它守的是「文档写的 == 脚本做的」这条线。本仓库真实出现过的三类事故各对应一组断言：

    A. param() 前面多了一行语句 -> PowerShell 把 param(...) 当普通命令调用，所有 -Xxx 参数
       静默失效，脚本仍返回 0。（intel_aipc_env_setup.ps1 曾如此）
    B. SKILL.md 写了脚本根本没有的参数（-China），或写了 PowerShell 绑不上的写法（--dry-run），
       调用方以为参数生效了，实际被静默丢弃。
    C. 脚本里有裸 Read-Host，在没有 stdin 的 agent/CI 终端里卡住或吞掉空答案。

  另有一组「脚本必须能解析」的基础断言 —— precheck_env.ps1 曾因为 "$key:" 被当成驱动器限定
  变量而整份无法解析，却从没被任何测试发现。

  用法:
    powershell -NoProfile -ExecutionPolicy Bypass -File test_contracts.ps1
  退出码 0 = 全部通过。
#>
param(
  [Parameter(ValueFromRemainingArguments = $true)][string[]]$Rest
)

$ErrorActionPreference = "Continue"
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path

if ($Rest -and $Rest.Count -gt 0) {
  Write-Host "unknown argument: $($Rest -join ' ')" -ForegroundColor Red
  exit 1
}

$script:Pass = 0
$script:Fail = 0

function Assert([string]$name, [bool]$cond, [string]$detail = "") {
  if ($cond) {
    Write-Host "  PASS: $name" -ForegroundColor Green
    $script:Pass++
  } else {
    Write-Host "  FAIL: $name" -ForegroundColor Red
    if ($detail) { Write-Host "        $detail" -ForegroundColor DarkRed }
    $script:Fail++
  }
}

# 4 个 skill 与它们的入口脚本。SKILL.md 里出现的参数必须能在对应脚本里绑上。
$Skills = @(
  @{ name = "learning-bot"
     doc  = "learning-bot\SKILL.md"
     entries = @("learning-bot\scripts\run.ps1") },
  @{ name = "openvino-content-fetch"
     doc  = "openvino-content-fetch\SKILL.md"
     entries = @("openvino-content-fetch\scripts\run.ps1") },
  @{ name = "openvino-pipeline-optimization"
     doc  = "openvino-pipeline-optimization\SKILL.md"
     entries = @("openvino-pipeline-optimization\scripts\run.ps1") },
  @{ name = "openvino-environment-management"
     doc  = "openvino-environment-management\SKILL.md"
     entries = @("openvino-environment-management\intel_aipc_env_setup.ps1",
                 "openvino-environment-management\precheck_env.ps1") }
)

# SKILL.md 代码块里会出现、但不是入口脚本参数的 token（外部命令自己的参数 / 占位符），逐一豁免。
$IgnoredFlags = @(
  "-NoProfile", "-ExecutionPolicy", "-File", "-Command", "-Type", "-c", "-m",
  "-Recurse", "-Force", "-Path", "-Value", "-Encoding", "-ItemType", "-Uri",
  "-OutFile", "-UseBasicParsing", "-Headers", "-ErrorAction", "-ArgumentList",
  "-Wait", "-NoNewWindow", "-FilePath", "-Directory", "-First", "-Tail",
  "-ForegroundColor", "-Method", "-TimeoutSec", "-PassThru", "-WindowStyle",
  "-Scope", "-Global", "-global", "-unset", "-get", "-depth", "-branch", "-EA",
  "-ItemProperty", "-Name", "-Descending", "-Property", "-Filter", "-Id",
  "--global", "--get", "--depth", "--branch", "--version", "--help", "--unset",
  "--index-url", "--trusted-host", "--upgrade", "--quiet", "--wait", "--norestart",
  "--nocache", "--installPath", "--add", "--ff-only", "--is-aipc", "--continue",
  "--health", "--run", "--input", "--chat", "--stub", "--model", "--ir-dir",
  "--plan", "--out", "--repo", "--source", "--download", "--out-dir",
  # PowerShell 的比较/逻辑运算符长得和参数一模一样，必须排除，否则 ST1-ST9 那些示例代码块
  # 里的 -not / -eq / -replace 会被误判成「文档写了脚本没有的参数」。
  "-not", "-and", "-or", "-xor", "-eq", "-ne", "-gt", "-ge", "-lt", "-le",
  "-like", "-notlike", "-match", "-notmatch", "-contains", "-notcontains",
  "-in", "-notin", "-replace", "-split", "-join", "-is", "-isnot", "-as", "-f",
  "-band", "-bor", "-bxor", "-bnot", "-shl", "-shr",
  # 外部工具（7-Zip / pip / Expand-Archive）自己的短参数
  "-o", "-i", "-y", "-DestinationPath", "-Destination"
)

Write-Host ""
Write-Host "=== Section 1: 每个 .ps1 都必须能被 PowerShell 解析 ===" -ForegroundColor Cyan
# precheck_env.ps1 曾因为 "$key:" 整份无法解析，而所有既有测试都没发现 —— 这一节堵住它。
$allPs1 = Get-ChildItem -Path $Root -Recurse -File -Filter *.ps1 |
          Where-Object { $_.FullName -notmatch '\\\.git\\' }
foreach ($f in $allPs1) {
  $errs = $null
  $null = [System.Management.Automation.Language.Parser]::ParseFile($f.FullName, [ref]$null, [ref]$errs)
  $rel = $f.FullName.Substring($Root.Length + 1)
  $detail = ""
  if ($errs -and $errs.Count -gt 0) {
    $detail = "line $($errs[0].Extent.StartLineNumber): $($errs[0].Message)"
  }
  Assert "$rel parses" (-not $errs -or $errs.Count -eq 0) $detail
}

Write-Host ""
Write-Host "=== Section 2: param() 必须是脚本的第一个语句 ===" -ForegroundColor Cyan
# 事故 A：param() 之前只要有一行可执行语句，它就退化成普通命令调用，所有参数静默失效。
foreach ($sk in $Skills) {
  foreach ($e in $sk.entries) {
    if ($e -match 'precheck_env\.ps1$') { continue }   # 该脚本无参数，天然没有 param()
    $path = Join-Path $Root $e
    if (-not (Test-Path $path)) { Assert "$e exists" $false "file not found"; continue }
    $errs = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$null, [ref]$errs)
    if ($errs -and $errs.Count -gt 0) { continue }     # Section 1 已经报过了
    Assert "$e declares a real param() block" ($null -ne $ast.ParamBlock) `
      "param() missing or shadowed by a preceding statement -> every -Xxx would be silently ignored"
  }
}

Write-Host ""
Write-Host "=== Section 3: SKILL.md 里出现的参数必须真的能绑上 ===" -ForegroundColor Cyan
# 事故 B：-China 在文档里存在、脚本里不存在；--dry-run 在文档里存在、PowerShell 绑不上。
foreach ($sk in $Skills) {
  $docPath = Join-Path $Root $sk.doc
  if (-not (Test-Path $docPath)) { Assert "$($sk.doc) exists" $false; continue }

  $declared = New-Object System.Collections.Generic.HashSet[string] ([StringComparer]::OrdinalIgnoreCase)
  foreach ($e in $sk.entries) {
    $path = Join-Path $Root $e
    if (-not (Test-Path $path)) { continue }
    # 脚本真正声明的参数
    try { foreach ($p in (Get-Command $path).Parameters.Keys) { [void]$declared.Add($p) } } catch { }
    # 入口脚本里显式归一化过的写法（如 '^--?dry-run$' -> $dryrun）也算声明过
    $src = Get-Content $path -Raw
    foreach ($m in [regex]::Matches($src, "'\^-{1,2}\??([A-Za-z][A-Za-z0-9-]*)\`$'")) {
      [void]$declared.Add($m.Groups[1].Value)
    }
  }

  $doc = Get-Content $docPath -Raw
  $seen = New-Object System.Collections.Generic.HashSet[string] ([StringComparer]::OrdinalIgnoreCase)
  foreach ($b in [regex]::Matches($doc, '(?s)```powershell(.*?)```')) {
    foreach ($m in [regex]::Matches($b.Groups[1].Value, '(?<![\w"''=/\\-])(--?[A-Za-z][A-Za-z0-9-]*)')) {
      $flag = $m.Groups[1].Value
      if ($IgnoredFlags -contains $flag) { continue }
      [void]$seen.Add($flag)
    }
  }

  $missing = @()
  foreach ($flag in $seen) {
    if (-not $declared.Contains($flag.TrimStart('-'))) { $missing += $flag }
  }
  Assert "$($sk.name): SKILL.md flags all bind to a real parameter" ($missing.Count -eq 0) `
    ("undeclared in the entry script(s): " + ($missing -join ", "))
}

Write-Host ""
Write-Host "=== Section 4: 不允许裸 Read-Host（agent/CI 里会卡住） ===" -ForegroundColor Cyan
# 事故 C：无 stdin 的终端里 Read-Host 会卡住或吞掉空答案。允许存在，但必须有非交互兜底。
foreach ($f in $allPs1) {
  $rel = $f.FullName.Substring($Root.Length + 1)
  if ($rel -eq "test_contracts.ps1") { continue }   # 本文件只是在注释/正则里提到这些名字
  $src = Get-Content $f.FullName -Raw
  if ($src -notmatch 'Read-Host') { continue }
  $guarded = ($src -match 'Test-Interactive') -or ($src -match 'Confirm-Step') -or
             ($src -match 'IsInputRedirected')
  Assert "$rel guards its Read-Host with a non-interactive fallback" $guarded `
    "a bare Read-Host blocks forever when stdin is empty (agent / CI terminals)"
}

Write-Host ""
Write-Host "=== Section 5: 未知参数必须显式报错并退出 1 ===" -ForegroundColor Cyan
# 静默吞掉未知参数 = 对 agent 谎报「参数生效了」。每个入口脚本都必须拒绝它。
$guardTargets = @(
  "learning-bot\scripts\run.ps1",
  "openvino-content-fetch\scripts\run.ps1",
  "openvino-pipeline-optimization\scripts\run.ps1",
  "openvino-environment-management\intel_aipc_env_setup.ps1"
)
foreach ($t in $guardTargets) {
  $path = Join-Path $Root $t
  if (-not (Test-Path $path)) { Assert "$t exists" $false; continue }
  $out = & powershell -NoProfile -ExecutionPolicy Bypass -File $path --definitely-not-a-real-flag 2>&1 | Out-String
  $code = $LASTEXITCODE
  Assert "$t rejects an unknown argument" `
    (($code -eq 1) -and ($out -match 'status=error') -and ($out -match 'reason=unknown-argument')) `
    "exit=$code; output lacked status=error + reason=unknown-argument"
}

Write-Host ""
Write-Host "=== Section 6: --dry-run 真的置位且不下载 ===" -ForegroundColor Cyan
# 事故 B 的行为侧断言：--dry-run 曾被 PowerShell 静默丢弃，导致「只解析」的命令跑成完整构建。
$pipe = Join-Path $Root "openvino-pipeline-optimization\scripts\run.ps1"
if (Test-Path $pipe) {
  $out = & powershell -NoProfile -ExecutionPolicy Bypass -File $pipe --dry-run --slug vlm-chatbot 2>&1 | Out-String
  Assert "--dry-run does not clone"     ($out -notmatch 'Cloning')    "output mentioned Cloning"
  Assert "--dry-run does not pip install" ($out -notmatch 'Installing') "output mentioned Installing"
  Assert "--dry-run took the dry-run path" ($out -match 'dry-run')    "no dry-run marker in output"
} else {
  Assert "pipeline run.ps1 exists" $false
}

Write-Host ""
Write-Host "=== Result: $script:Pass passed, $script:Fail failed ===" -ForegroundColor Cyan
if ($script:Fail -gt 0) { exit 1 } else { exit 0 }
