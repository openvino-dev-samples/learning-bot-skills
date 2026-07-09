<#
.SYNOPSIS
    Intel AIPC 开发环境预检查脚本
.DESCRIPTION
    此脚本在 Windows 上对 Intel AIPC 开发环境执行全面的预检查。
    在任何配置之前运行此脚本以评估当前环境状态。
#>

function Write-Success {
    param([string]$Message)
    Write-Host $Message -ForegroundColor Green
}

function Write-Warn {
    param([string]$Message)
    Write-Host $Message -ForegroundColor Yellow
}

function Write-Fail {
    param([string]$Message)
    Write-Host $Message -ForegroundColor Red
}

$results = @{}

Write-Host ("`n" + ("=" * 70))
Write-Host "Intel AIPC 环境预检查"
Write-Host ("=" * 70)

# 预检查 PC1: 检查 Windows 操作系统
Write-Host "`n[PC1] 正在检查 Windows 操作系统..."
$osInfo = Get-WmiObject -Class Win32_OperatingSystem
Write-Host "  操作系统名称: $($osInfo.Caption)"
Write-Host "  操作系统版本: $($osInfo.Version)"

if (-not ($osInfo.Caption -like "*Windows*")) {
    Write-Fail "  失败: 此脚本只能在 Windows 上运行！"
    $results["PC1"] = @{ status = "FAIL"; message = "检测到非 Windows 操作系统" }
} else {
    Write-Success "  通过: 检测到 Windows 操作系统"
    $results["PC1"] = @{ status = "PASS"; message = "检测到 Windows 操作系统" }
}

# 预检查 PC2: 检查 Intel 处理器
Write-Host "`n[PC2] 正在检查 Intel 处理器..."
$cpuInfo = Get-WmiObject -Class Win32_Processor
$cpuName = $cpuInfo.Name
Write-Host "  处理器: $cpuName"

$isIntel = $cpuName -like "*Intel*"
$isUltra = $cpuName -like "*Ultra*"
$hasArc = $cpuName -like "*Arc*"

if (-not $isIntel) {
    Write-Fail "  失败: 检测到非 Intel 处理器！此脚本仅支持 Intel 处理器。"
    $results["PC2"] = @{ status = "FAIL"; message = "非 Intel 处理器" }
} else {
    Write-Success "  通过: 检测到 Intel 处理器"
    $results["PC2"] = @{ status = "PASS"; message = "检测到 Intel 处理器" }
    
    if (-not ($isUltra -or $hasArc)) {
        Write-Warn "  警告: 非 Ultra 系列处理器。iGPU/NPU 加速可能受限。"
        $results["PC2"].warning = "非 Ultra 处理器"
    }
}

# 预检查 PC3: 检查 iGPU/NPU 和驱动
Write-Host "`n[PC3] 正在检查图形驱动..."

Write-Host "  GPU 设备:"
Get-WmiObject -Class Win32_VideoController | ForEach-Object {
    Write-Host "    名称: $($_.Name)"
    Write-Host "    驱动版本: $($_.DriverVersion)"
}

$intelDriver = Get-WmiObject -Class Win32_PnPSignedDriver | Where-Object {
    $_.DeviceName -like "*Intel*Graphics*" -or $_.DeviceName -like "*Intel*UHD*" -or $_.DeviceName -like "*Intel*Arc*"
}

if ($intelDriver) {
    Write-Success "  通过: 找到 Intel 图形驱动"
    $results["PC3"] = @{ status = "PASS"; message = "找到 Intel 图形驱动" }
    $intelDriver | ForEach-Object {
        Write-Host "    设备: $($_.DeviceName)"
        Write-Host "    驱动版本: $($_.DriverVersion)"
    }
} else {
    Write-Warn "  警告: 未找到 Intel 图形驱动"
    $results["PC3"] = @{ status = "WARN"; message = "未找到 Intel 图形驱动" }
}

# 预检查 PC4: 检查 Python 安装
Write-Host "`n[PC4] 正在检查 Python 安装..."

$pythonFound = $false
$pythonVersion = $null
$pipFound = $false

$pythonExePaths = @(
    (Get-Command python -ErrorAction SilentlyContinue).Source,
    (Get-Command python3 -ErrorAction SilentlyContinue).Source,
    "$env:LOCALAPPDATA\Programs\Python\Python312\python.exe",
    "$env:LOCALAPPDATA\Programs\Python\Python311\python.exe",
    "$env:SystemDrive\Python312\python.exe",
    "$env:SystemDrive\Python311\python.exe"
) | Where-Object { 
    $_ -and (Test-Path $_) -and (-not $_.Contains("WindowsApps")) 
} | Select-Object -First 1

if ($pythonExePaths) {
    $pythonFound = $true
    Write-Host "  找到: $pythonExePaths"
    
    try {
        $versionOutput = & $pythonExePaths --version 2>&1
        $pythonVersion = $versionOutput -replace "Python ", ""
        Write-Host "  版本: $pythonVersion"
        
        $versionMatch = $pythonVersion -match "^(\d+)\.(\d+)"
        if ($versionMatch) {
            $major = [int]$matches[1]
            $minor = [int]$matches[2]
            
            if ($major -eq 3 -and $minor -ge 10) {
                Write-Success "  通过: Python 3.10+ 已安装"
                $results["PC4"] = @{ status = "PASS"; message = "Python $pythonVersion 已安装" }
            } else {
                Write-Warn "  警告: Python 版本 $pythonVersion 低于 3.10"
                $results["PC4"] = @{ status = "WARN"; message = "Python 版本低于 3.10" }
            }
        }
    } catch {
        Write-Warn "  警告: 无法获取 Python 版本"
        $results["PC4"] = @{ status = "WARN"; message = "无法获取 Python 版本" }
    }
    
    try {
        & $pythonExePaths -m pip --version 2>&1 | Out-Null
        $pipFound = $true
        Write-Success "  通过: pip 已安装"
    } catch {
        Write-Warn "  警告: pip 未安装或无法访问"
    }
} else {
    Write-Fail "  失败: Python 未安装"
    $results["PC4"] = @{ status = "FAIL"; message = "Python 未安装" }
}

# 预检查 PC5: 检查 pip 镜像配置
Write-Host "`n[PC5] 正在检查 pip 镜像配置..."

$pipConfigPath = "$env:APPDATA\pip\pip.ini"
$pipMirrorConfigured = $false

if (Test-Path $pipConfigPath) {
    $pipConfigContent = Get-Content $pipConfigPath -Raw
    if ($pipConfigContent -match "index-url\s*=\s*https://pypi\.tuna\.tsinghua\.edu\.cn/simple") {
        $pipMirrorConfigured = $true
        Write-Success "  通过: pip 镜像已配置为清华大学镜像"
        $results["PC5"] = @{ status = "PASS"; message = "已配置清华镜像" }
    } else {
        Write-Warn "  警告: pip.ini 存在但未配置镜像"
        $results["PC5"] = @{ status = "WARN"; message = "pip.ini 存在但未配置镜像" }
    }
} else {
    Write-Warn "  警告: pip.ini 未找到，未配置镜像"
    $results["PC5"] = @{ status = "WARN"; message = "pip.ini 未找到" }
}

# 预检查 PC6: 检查 Git 安装
Write-Host "`n[PC6] 正在检查 Git 安装..."

$gitFound = $false

try {
    $gitVersion = git --version 2>&1
    if ($gitVersion -match "git version") {
        $gitFound = $true
        Write-Success "  通过: Git 已安装: $gitVersion"
        $results["PC6"] = @{ status = "PASS"; message = "Git 已安装" }
    }
} catch {
    Write-Fail "  失败: Git 未安装或不在 PATH 中"
    $results["PC6"] = @{ status = "FAIL"; message = "Git 未安装" }
}

if ($gitFound) {
    try {
        $gitLfsVersion = git lfs version 2>&1
        if ($gitLfsVersion -match "git-lfs") {
            Write-Success "  通过: Git-LFS 已安装"
        } else {
            Write-Warn "  警告: Git-LFS 未安装"
        }
    } catch {
        Write-Warn "  警告: Git-LFS 未安装"
    }
}

# 预检查 PC7: 检查 Git 镜像配置
Write-Host "`n[PC7] 正在检查 Git 镜像配置..."

$gitMirrorConfigured = $false

try {
    $ghProxyConfig = git config --global --get url."https://ghproxy.net/https://github.com/".insteadOf 2>&1
    if ($ghProxyConfig -eq "https://github.com/") {
        $gitMirrorConfigured = $true
        Write-Success "  通过: Git 镜像已配置为 ghproxy.net"
        $results["PC7"] = @{ status = "PASS"; message = "ghproxy 镜像已配置" }
    } else {
        Write-Warn "  警告: Git 镜像未配置用于 github.com"
        $results["PC7"] = @{ status = "WARN"; message = "Git 镜像未配置" }
    }
} catch {
    Write-Warn "  警告: 无法检查 git 镜像配置"
    $results["PC7"] = @{ status = "WARN"; message = "无法检查 git 镜像" }
}

# 预检查 PC8: 检查 HF_ENDPOINT 和 ModelScope API 配置
Write-Host "`n[PC8] 正在检查 Hugging Face 和 ModelScope 配置..."

$hfEndpoint = [Environment]::GetEnvironmentVariable("HF_ENDPOINT", "User")
if ($hfEndpoint) {
    Write-Host "  HF_ENDPOINT: $hfEndpoint"
    if ($hfEndpoint -eq "https://hf-mirror.com") {
        Write-Success "  通过: HF_ENDPOINT 已设置为 hf-mirror.com"
    } else {
        Write-Warn "  警告: HF_ENDPOINT 设置为非标准值"
    }
} else {
    Write-Warn "  警告: HF_ENDPOINT 未设置"
    $results["PC8"] = @{ status = "WARN"; message = "HF_ENDPOINT 未设置" }
}

$modelscopeApi = [Environment]::GetEnvironmentVariable("MODELSCOPE_API_URL", "User")
if ($modelscopeApi) {
    Write-Host "  MODELSCOPE_API_URL: $modelscopeApi"
    if ($modelscopeApi -eq "https://api.modelscope.cn") {
        Write-Success "  通过: MODELSCOPE_API_URL 已设置为 api.modelscope.cn"
        $results["PC8"] = @{ status = "PASS"; message = "HF/ModelScope 已配置" }
    }
} else {
    Write-Warn "  警告: MODELSCOPE_API_URL 未设置"
    $results["PC8"] = @{ status = "WARN"; message = "MODELSCOPE_API_URL 未设置" }
}

# 预检查 PC9: 检查 OpenVINO 安装
Write-Host "`n[PC9] 正在检查 OpenVINO 安装..."

try {
    $ovVersion = python -c "import openvino; print(openvino.__version__)" 2>&1
    if (-not ($ovVersion -match "ImportError")) {
        Write-Success "  通过: OpenVINO 已安装: $ovVersion"
        $results["PC9"] = @{ status = "PASS"; message = "OpenVINO $ovVersion 已安装" }
    } else {
        Write-Warn "  警告: OpenVINO 未安装"
        $results["PC9"] = @{ status = "WARN"; message = "OpenVINO 未安装" }
    }
} catch {
    Write-Warn "  警告: 无法检查 OpenVINO 安装"
    $results["PC9"] = @{ status = "WARN"; message = "无法检查 OpenVINO" }
}

# 预检查 PC10: 检查 PyTorch 安装
Write-Host "`n[PC10] 正在检查 PyTorch 安装..."

try {
    $torchVersion = python -c "import torch; print(torch.__version__)" 2>&1
    if (-not ($torchVersion -match "ImportError")) {
        Write-Success "  通过: PyTorch 已安装: $torchVersion"
        $results["PC10"] = @{ status = "PASS"; message = "PyTorch $torchVersion 已安装" }
        
        try {
            $cudaAvailable = python -c "import torch; print(torch.cuda.is_available())" 2>&1
            Write-Host "  CUDA 可用: $cudaAvailable"
        } catch {
            Write-Host "  无法检查 CUDA 状态"
        }
    } else {
        Write-Warn "  警告: PyTorch 未安装"
        $results["PC10"] = @{ status = "WARN"; message = "PyTorch 未安装" }
    }
} catch {
    Write-Warn "  警告: 无法检查 PyTorch 安装"
    $results["PC10"] = @{ status = "WARN"; message = "无法检查 PyTorch" }
}

# 摘要
Write-Host ("`n" + ("=" * 70))
Write-Host "预检查摘要"
Write-Host ("=" * 70)

$failCount = ($results.Values | Where-Object { $_.status -eq "FAIL" }).Count
$warnCount = ($results.Values | Where-Object { $_.status -eq "WARN" }).Count
$passCount = ($results.Values | Where-Object { $_.status -eq "PASS" }).Count

Write-Host "`n结果:"
Write-Host "  通过: $passCount" -ForegroundColor Green
Write-Host "  警告: $warnCount" -ForegroundColor Yellow
Write-Host "  失败: $failCount" -ForegroundColor Red

Write-Host "`n需要执行的操作:"
foreach ($key in $results.Keys) {
    $result = $results[$key]
    if ($result.status -eq "FAIL") {
        Write-Fail "  $key: $($result.message) → 运行相应的配置步骤"
    } elseif ($result.status -eq "WARN") {
        Write-Warn "  $key: $($result.message) → 考虑运行配置"
    }
}

Write-Host ("`n" + ("=" * 70))

# 供智能体使用的 JSON 输出
Write-Host "`n[AGENT_OUTPUT]"
$summary = @{
    total = $results.Count
    pass = $passCount
    warn = $warnCount
    fail = $failCount
    results = $results
    actions = @()
}

foreach ($key in $results.Keys) {
    $result = $results[$key]
    if ($result.status -ne "PASS") {
        $summary.actions += @{
            check = $key
            status = $result.status
            message = $result.message
            recommended_action = switch($key) {
                "PC4" { "运行 ST1: 安装 Python" }
                "PC5" { "运行 ST2: 配置 pip 镜像 (使用 -China)" }
                "PC6" { "运行 ST3: 安装 Git" }
                "PC7" { "运行 ST4: 配置 Git 镜像 (使用 -China)" }
                "PC8" { "运行 ST5: 安装 ModelScope 并配置镜像" }
                "PC9" { "运行 ST6: 安装 OpenVINO" }
                "PC10" { "运行 ST7: 安装 PyTorch" }
                default { "需要手动操作" }
            }
        }
    }
}

$summary | ConvertTo-Json
Write-Host "[/AGENT_OUTPUT]"
