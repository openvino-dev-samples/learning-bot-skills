<#
  grade.ps1 —— 给 L2/L3 的 agent 评测判分。

  输入：
    -Cases      agent-eval/cases.jsonl（默认取本脚本同目录下的 cases.jsonl）
    -Transcript 一个文本文件，内含从被测 agent 回复里收集来的 [EVAL_VERDICT] 行
                （格式见 harness-prompt.md；一行一条，顺序无所谓，其余文字会被忽略）

  输出：逐条 pass/fail + 通过率。退出码 0 = 全部通过。

  为什么需要它：现有的 test_*.ps1 只测脚本层（learning_bot.py --route 的返回值），
  完全没有验证「一个真实 agent 读了 SKILL.md 之后会不会做对」—— 而本轮修复针对的恰恰是后者。

  用法:
    powershell -NoProfile -ExecutionPolicy Bypass -File grade.ps1 -Transcript .\transcript.txt
#>
param(
  [string]$Cases,
  [Parameter(Mandatory = $true)][string]$Transcript,
  [Parameter(ValueFromRemainingArguments = $true)][string[]]$Rest
)

$ErrorActionPreference = "Continue"
$Here = Split-Path -Parent $MyInvocation.MyCommand.Path

if ($Rest -and $Rest.Count -gt 0) {
  Write-Host "unknown argument: $($Rest -join ' ')" -ForegroundColor Red
  Write-Host "valid_params=-Cases <path> -Transcript <path>"
  exit 1
}

if (-not $Cases) { $Cases = Join-Path $Here "cases.jsonl" }
if (-not (Test-Path $Cases))      { Write-Host "cases file not found: $Cases" -ForegroundColor Red; exit 1 }
if (-not (Test-Path $Transcript)) { Write-Host "transcript not found: $Transcript" -ForegroundColor Red; exit 1 }

# ---- 读用例 ----
# 注意变量名不能叫 $cases —— PowerShell 变量名大小写不敏感，$cases 和参数 $Cases 是同一个变量，
# 赋值成哈希表会把传进来的路径直接冲掉，后面 Get-Content 就读了个空。
$caseMap = @{}
$order = @()
foreach ($line in (Get-Content $Cases -Encoding UTF8)) {
  if (-not $line.Trim()) { continue }
  $c = $line | ConvertFrom-Json
  $caseMap[$c.id] = $c
  $order += $c.id
}

# ---- 读 [EVAL_VERDICT] 行 ----
# 形如: [EVAL_VERDICT] case=PR1 scope=preset target=asr invoked=none
$verdicts = @{}
foreach ($line in (Get-Content $Transcript -Encoding UTF8)) {
  if ($line -notmatch '\[EVAL_VERDICT\]') { continue }
  $v = @{ case = ""; scope = ""; target = ""; targets = ""; gaps = ""; deliverable = ""; invoked = "" }
  # 注意：targets= 里含有子串 target=，所以 target= 必须用 (?<!s) 把 targets 的尾巴排除掉，
  # 否则两个字段会互相串味。
  if ($line -match 'case=(\S+)')            { $v.case    = $Matches[1] }
  if ($line -match 'scope=(\S*)')           { $v.scope   = $Matches[1] }
  if ($line -match 'targets=([^\s]*)')      { $v.targets = $Matches[1] }
  if ($line -match '(?<!s)\btarget=(\S*)')  { $v.target  = $Matches[1] }
  if ($line -match 'gaps=([^\s]*)')         { $v.gaps    = $Matches[1] }
  if ($line -match 'deliverable=([^\s]*)')  { $v.deliverable = $Matches[1] }
  # invoked 在最后且可能含空格，所以单独匹配到行尾。
  if ($line -match 'invoked=(.*)$')         { $v.invoked = $Matches[1].Trim() }
  if ($v.case) { $verdicts[$v.case] = $v }
}

$script:pass = 0; $script:fail = 0; $script:missing = 0

function Report([string]$id, [bool]$ok, [string]$detail) {
  if ($ok) { Write-Host ("  PASS  {0}" -f $id) -ForegroundColor Green; $script:pass++ }
  else     { Write-Host ("  FAIL  {0}  {1}" -f $id, $detail) -ForegroundColor Red; $script:fail++ }
}

Write-Host ""
Write-Host "=== Agent eval: $($order.Count) cases ===" -ForegroundColor Cyan

foreach ($id in $order) {
  $c = $caseMap[$id]
  if (-not $verdicts.ContainsKey($id)) {
    Write-Host ("  MISS  {0}  no [EVAL_VERDICT] line in transcript" -f $id) -ForegroundColor Yellow
    $script:missing++
    continue
  }
  $v = $verdicts[$id]
  $problems = @()

  # scope 断言。not-preset 是一类特殊期望：只要不是 preset 就算过（拒绝/追问/转 dev 都可以）。
  if ($c.expect_scope -eq "not-preset") {
    if ($v.scope -eq "preset") { $problems += "scope=preset but this request is out of scope" }
  } elseif ($v.scope -ne $c.expect_scope) {
    $problems += "scope=$($v.scope), expected $($c.expect_scope)"
  }

  # target 断言（期望为空时不检查）。
  if ($c.expect_target -and ($v.target -ne $c.expect_target)) {
    $problems += "target=$($v.target), expected $($c.expect_target)"
  }

  # expect_targets：组合链必须**有序**且完全一致 —— 顺序错了（如 tts 排在 mineru 前面）
  # 就是错的，这正是「预设能力当积木」要守住的东西。
  if ($c.PSObject.Properties.Name -contains 'expect_targets' -and $c.expect_targets) {
    if ($v.targets -ne $c.expect_targets) {
      $problems += "targets=$($v.targets), expected $($c.expect_targets)"
    }
  }

  # expect_deliverable：内容合成类必须认出交付物是哪一种文档（PRD / 培训材料 / 学习路径），
  # 这决定了 agent 接下来是去写文档还是去装 skill 跑推理。
  if ($c.PSObject.Properties.Name -contains 'expect_deliverable' -and $c.expect_deliverable) {
    if ($v.deliverable -ne $c.expect_deliverable) {
      $problems += "deliverable=$($v.deliverable), expected $($c.expect_deliverable)"
    }
  }

  # expect_gaps：链条上预设原子覆盖不到的阶段必须被如实标出来，
  # 而不是假装能做，也不是因此放弃整条链。
  if ($c.PSObject.Properties.Name -contains 'expect_gaps' -and $c.expect_gaps) {
    foreach ($g in ($c.expect_gaps -split ',')) {
      if ($v.gaps -notmatch [regex]::Escape($g.Trim())) {
        $problems += "gaps=$($v.gaps), expected to contain $($g.Trim())"
      }
    }
  }

  # must_not：这些 key 不允许出现在 target 里。
  foreach ($bad in $c.must_not) {
    if ($v.target -eq $bad) { $problems += "target must not be '$bad'" }
  }

  Report $id ($problems.Count -eq 0) ($problems -join "; ")
}

$total = $order.Count
$rate  = if ($total -gt 0) { [math]::Round(100.0 * $script:pass / $total, 1) } else { 0 }

Write-Host ""
Write-Host "=== Result: $($script:pass) passed, $($script:fail) failed, $($script:missing) missing / $total total ($rate%) ===" -ForegroundColor Cyan
if ($script:missing -gt 0) {
  Write-Host "提示：MISS 表示 transcript 里没有该用例的 [EVAL_VERDICT] 行 —— 要么这条没跑，" -ForegroundColor Yellow
  Write-Host "      要么被测 agent 没遵守 harness-prompt.md 规定的输出格式。" -ForegroundColor Yellow
}
if (($script:fail -gt 0) -or ($script:missing -gt 0)) { exit 1 } else { exit 0 }
