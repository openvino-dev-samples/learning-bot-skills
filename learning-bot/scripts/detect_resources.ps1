<#
  detect_resources.ps1 —— 探测本机可用于模型推理的内存/显存预算。

  为什么用 OpenVINO 而不是 WMI 取显存（本机 Intel Arc 140V 实测）：

    Win32_VideoController.AdapterRAM ........ 报 2.00 GB   ← UINT32 截断，设备名自己写着 16GB
    注册表 HardwareInformation.qwMemorySize .. 键不存在      ← 该 iGPU 上没有这个值
    OpenVINO GPU_DEVICE_TOTAL_MEM_SIZE ...... 25.36 GB    ← 唯一权威来源

  **不要改回 AdapterRAM。** 它在现代 GPU 上必然给出错误答案，用它做模型过滤会把能跑的模型
  全判成跑不动。

  另一个关键事实：iGPU 的显存是从系统内存里共享的（DEVICE_TYPE=INTEGRATED），
  所以 gpu_budget 和 free_ram 不是两份独立的内存，绝不能相加。

  用法:
    detect_resources.ps1              # 输出 [SKILL_RESULT] 并写缓存
    detect_resources.ps1 -Quiet       # 只写缓存，不打印
  退出码 0 = 探测成功（含 estimate 兜底）。
#>
param(
  [switch]$Quiet,
  [Parameter(ValueFromRemainingArguments = $true)][string[]]$Rest
)

$ErrorActionPreference = "Stop"

if ($Rest -and $Rest.Count -gt 0) {
  Write-Host "[SKILL_RESULT]"
  Write-Host "status=error"
  Write-Host "skill=learning-bot"
  Write-Host "action=capacity"
  Write-Host "reason=unknown-argument"
  Write-Host ("unknown=" + ($Rest -join " "))
  Write-Host "valid_params=-Quiet"
  Write-Host "note=unrecognized argument; nothing was executed"
  Write-Host "[/SKILL_RESULT]"
  exit 1
}

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$Base      = Join-Path $env:USERPROFILE ".openvino"
$CacheFile = Join-Path $Base "capacity.json"
New-Item -ItemType Directory -Force -Path $Base | Out-Null

# 安全余量：只把预算的这一比例算作可用，给运行时/碎片/其他进程留出空间。
$SafetyMargin = 0.85

# ---------------- 系统内存（永远可得，作为基线）----------------
$cs = Get-CimInstance Win32_ComputerSystem -ErrorAction SilentlyContinue
$os = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
$totalRamGb = if ($cs) { [math]::Round($cs.TotalPhysicalMemory / 1GB, 1) } else { 0 }
$freeRamGb  = if ($os) { [math]::Round($os.FreePhysicalMemory / 1MB, 1) } else { 0 }

# ---------------- 优先向 OpenVINO 问设备信息 ----------------
function Get-ProbePython {
  # 依次尝试两个 venv，最后退回系统 python。任何一个装了 openvino 就够。
  foreach ($p in @(
      (Join-Path $env:USERPROFILE ".openvino\venv-pipeopt\Scripts\python.exe"),
      (Join-Path $env:USERPROFILE ".openvino\venv-contentfetch\Scripts\python.exe"))) {
    if (Test-Path $p) { return $p }
  }
  if (Get-Command python -ErrorAction SilentlyContinue) { return "python" }
  return $null
}

# 探测脚本必须是**真实文件**，不能用 python -c 内联：PowerShell 传参给原生命令时会把
# Python 源码里的双引号吃掉（print("X" + y) 变成 print(X + y)），语法错误又被 catch 吞掉，
# 结果静默退化成估算模式。这个坑踩过一次了，不要改回内联。
$ProbeScript = Join-Path $ScriptDir "detect_resources.py"

$source      = "estimate"
$deviceNames = @()
$gpuBudgetGb = 0.0
$gpuType     = "none"
$note        = ""

$py = Get-ProbePython
if ($py -and (Test-Path $ProbeScript)) {
  try {
    # 不要加 2>$null：Windows PowerShell 下重定向原生命令的 stderr 会把每一行包成
    # NativeCommandError，配合 $ErrorActionPreference="Stop" 会直接抛异常，
    # 于是即便探测成功也会被误判成失败。这里临时放宽，读完再恢复。
    $prevEap = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    $raw = (& $py $ProbeScript) | Out-String
    $ErrorActionPreference = $prevEap
    $line = ($raw -split "`n" | Where-Object { $_ -match '^OV_JSON:' } | Select-Object -First 1)
    if ($line) {
      $ov = ($line -replace '^OV_JSON:', '').Trim() | ConvertFrom-Json
      $source      = "openvino"
      $deviceNames = @($ov.devices | ForEach-Object { $_.name })
      $gpuType     = $ov.gpu_type
      if ($ov.gpu_total_bytes -gt 0) {
        $gpuBudgetGb = [math]::Round($ov.gpu_total_bytes / 1GB, 1)
      }
    }
  } catch {
    # 探测失败不是致命错误 —— 落回估算路径，并在 note 里说明。
    $note = "openvino probe failed; fell back to a system-RAM estimate"
  }
}

if ($source -ne "openvino") {
  # 兜底：没有 OpenVINO 就只能按系统内存估。iGPU 通常最多能共享到约一半物理内存。
  # 这是估值，必须如实标注 source=estimate，不要伪装成精确值。
  $deviceNames = @("CPU")
  $gpuType     = "unknown"
  $gpuBudgetGb = [math]::Round($totalRamGb * 0.5, 1)
  if (-not $note) {
    $note = "openvino not available; GPU budget is a rough estimate from system RAM"
  }
}

# ---------------- 换算成「实际能拿来装模型」的预算 ----------------
# 关键：iGPU 的显存与系统内存同源，报得出 25GB 可寻址不代表此刻真有 25GB 空闲。
# 所以 integrated 时取 min(显存预算, 当前空闲内存)；discrete 才用独立显存。
$sharedWithRam = ($gpuType -ne "discrete")
if ($gpuBudgetGb -gt 0) {
  $effective = if ($sharedWithRam) { [math]::Min($gpuBudgetGb, $freeRamGb) } else { $gpuBudgetGb }
} else {
  $effective = $freeRamGb
}
$usableBudgetGb = [math]::Round($effective * $SafetyMargin, 1)

# ---------------- 写缓存供其他 skill 复用 ----------------
$cache = [ordered]@{
  source           = $source
  total_ram_gb     = $totalRamGb
  free_ram_gb      = $freeRamGb
  devices          = $deviceNames
  gpu_type         = $gpuType
  gpu_budget_gb    = $gpuBudgetGb
  shared_with_ram  = $sharedWithRam
  safety_margin    = $SafetyMargin
  usable_budget_gb = $usableBudgetGb
}
# 无 BOM 写出：Python 侧用 encoding="utf-8" 读，带 BOM 会让 json.load 失败。
[System.IO.File]::WriteAllText($CacheFile,
  ($cache | ConvertTo-Json -Depth 5),
  (New-Object System.Text.UTF8Encoding($false)))

if ($Quiet) { exit 0 }

Write-Host "[SKILL_RESULT]"
Write-Host "status=ok"
Write-Host "skill=learning-bot"
Write-Host "action=capacity"
Write-Host "source=$source"
Write-Host "total_ram_gb=$totalRamGb"
Write-Host "free_ram_gb=$freeRamGb"
Write-Host ("devices=" + ($deviceNames -join ","))
Write-Host "gpu_type=$gpuType"
Write-Host "gpu_budget_gb=$gpuBudgetGb"
Write-Host ("shared_with_ram=" + $sharedWithRam.ToString().ToLower())
Write-Host "usable_budget_gb=$usableBudgetGb"
Write-Host "cache=$CacheFile"
if ($note) { Write-Host "note=$note" }
Write-Host "[/SKILL_RESULT]"
exit 0
