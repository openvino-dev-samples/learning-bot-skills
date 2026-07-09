<#
.SYNOPSIS
    Environment Pre-Check Script for Intel AIPC Development Environment
.DESCRIPTION
    This script performs comprehensive pre-checks for Intel AIPC development environment on Windows.
    Run this before any setup to assess current environment state.
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
Write-Host "Intel AIPC Environment Pre-Check"
Write-Host ("=" * 70)

# PreCheck PC1: Check Windows Operating System
Write-Host "`n[PC1] Checking Windows Operating System..."
$osInfo = Get-WmiObject -Class Win32_OperatingSystem
Write-Host "  OS Name: $($osInfo.Caption)"
Write-Host "  OS Version: $($osInfo.Version)"

if (-not ($osInfo.Caption -like "*Windows*")) {
    Write-Fail "  FAIL: This script can only run on Windows!"
    $results["PC1"] = @{ status = "FAIL"; message = "Non-Windows OS detected" }
} else {
    Write-Success "  PASS: Windows OS detected"
    $results["PC1"] = @{ status = "PASS"; message = "Windows OS detected" }
}

# PreCheck PC2: Check Intel Processor
Write-Host "`n[PC2] Checking Intel Processor..."
$cpuInfo = Get-WmiObject -Class Win32_Processor
$cpuName = $cpuInfo.Name
Write-Host "  Processor: $cpuName"

$isIntel = $cpuName -like "*Intel*"
$isUltra = $cpuName -like "*Ultra*"
$hasArc = $cpuName -like "*Arc*"

if (-not $isIntel) {
    Write-Fail "  FAIL: Non-Intel processor detected! This script only supports Intel processors."
    $results["PC2"] = @{ status = "FAIL"; message = "Non-Intel processor" }
} else {
    Write-Success "  PASS: Intel processor detected"
    $results["PC2"] = @{ status = "PASS"; message = "Intel processor detected" }
    
    if (-not ($isUltra -or $hasArc)) {
        Write-Warn "  WARN: Non-Ultra series processor. iGPU/NPU acceleration may be limited."
        $results["PC2"].warning = "Non-Ultra processor"
    }
}

# PreCheck PC3: Check iGPU/NPU and Drivers
Write-Host "`n[PC3] Checking Graphics Drivers..."

Write-Host "  GPU Devices:"
Get-WmiObject -Class Win32_VideoController | ForEach-Object {
    Write-Host "    Name: $($_.Name)"
    Write-Host "    Driver Version: $($_.DriverVersion)"
}

$intelDriver = Get-WmiObject -Class Win32_PnPSignedDriver | Where-Object {
    $_.DeviceName -like "*Intel*Graphics*" -or $_.DeviceName -like "*Intel*UHD*" -or $_.DeviceName -like "*Intel*Arc*"
}

if ($intelDriver) {
    Write-Success "  PASS: Intel graphics driver found"
    $results["PC3"] = @{ status = "PASS"; message = "Intel graphics driver found" }
    $intelDriver | ForEach-Object {
        Write-Host "    Device: $($_.DeviceName)"
        Write-Host "    Driver Version: $($_.DriverVersion)"
    }
} else {
    Write-Warn "  WARN: No Intel graphics driver found"
    $results["PC3"] = @{ status = "WARN"; message = "No Intel graphics driver found" }
}

# PreCheck PC4: Check Python Installation
Write-Host "`n[PC4] Checking Python Installation..."

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
    Write-Host "  Found: $pythonExePaths"
    
    try {
        $versionOutput = & $pythonExePaths --version 2>&1
        $pythonVersion = $versionOutput -replace "Python ", ""
        Write-Host "  Version: $pythonVersion"
        
        $versionMatch = $pythonVersion -match "^(\d+)\.(\d+)"
        if ($versionMatch) {
            $major = [int]$matches[1]
            $minor = [int]$matches[2]
            
            if ($major -eq 3 -and $minor -ge 10) {
                Write-Success "  PASS: Python 3.10+ installed"
                $results["PC4"] = @{ status = "PASS"; message = "Python $pythonVersion installed" }
            } else {
                Write-Warn "  WARN: Python version $pythonVersion below 3.10"
                $results["PC4"] = @{ status = "WARN"; message = "Python version below 3.10" }
            }
        }
    } catch {
        Write-Warn "  WARN: Unable to get Python version"
        $results["PC4"] = @{ status = "WARN"; message = "Unable to get Python version" }
    }
    
    try {
        & $pythonExePaths -m pip --version 2>&1 | Out-Null
        $pipFound = $true
        Write-Success "  PASS: pip is installed"
    } catch {
        Write-Warn "  WARN: pip not installed or not accessible"
    }
} else {
    Write-Fail "  FAIL: Python is not installed"
    $results["PC4"] = @{ status = "FAIL"; message = "Python not installed" }
}

# PreCheck PC5: Check pip Mirror Configuration
Write-Host "`n[PC5] Checking pip Mirror Configuration..."

$pipConfigPath = "$env:APPDATA\pip\pip.ini"
$pipMirrorConfigured = $false

if (Test-Path $pipConfigPath) {
    $pipConfigContent = Get-Content $pipConfigPath -Raw
    if ($pipConfigContent -match "index-url\s*=\s*https://pypi\.tuna\.tsinghua\.edu\.cn/simple") {
        $pipMirrorConfigured = $true
        Write-Success "  PASS: pip mirror configured to Tsinghua University mirror"
        $results["PC5"] = @{ status = "PASS"; message = "Tsinghua mirror configured" }
    } else {
        Write-Warn "  WARN: pip.ini exists but mirror not configured"
        $results["PC5"] = @{ status = "WARN"; message = "pip.ini exists but mirror not configured" }
    }
} else {
    Write-Warn "  WARN: pip.ini not found, no mirror configured"
    $results["PC5"] = @{ status = "WARN"; message = "pip.ini not found" }
}

# PreCheck PC6: Check Git Installation
Write-Host "`n[PC6] Checking Git Installation..."

$gitFound = $false

try {
    $gitVersion = git --version 2>&1
    if ($gitVersion -match "git version") {
        $gitFound = $true
        Write-Success "  PASS: Git is installed: $gitVersion"
        $results["PC6"] = @{ status = "PASS"; message = "Git installed" }
    }
} catch {
    Write-Fail "  FAIL: Git is not installed or not in PATH"
    $results["PC6"] = @{ status = "FAIL"; message = "Git not installed" }
}

if ($gitFound) {
    try {
        $gitLfsVersion = git lfs version 2>&1
        if ($gitLfsVersion -match "git-lfs") {
            Write-Success "  PASS: Git-LFS is installed"
        } else {
            Write-Warn "  WARN: Git-LFS is not installed"
        }
    } catch {
        Write-Warn "  WARN: Git-LFS is not installed"
    }
}

# PreCheck PC7: Check Git Mirror Configuration
Write-Host "`n[PC7] Checking Git Mirror Configuration..."

$gitMirrorConfigured = $false

try {
    $ghProxyConfig = git config --global --get url."https://ghproxy.net/https://github.com/".insteadOf 2>&1
    if ($ghProxyConfig -eq "https://github.com/") {
        $gitMirrorConfigured = $true
        Write-Success "  PASS: Git mirror configured to ghproxy.net"
        $results["PC7"] = @{ status = "PASS"; message = "ghproxy mirror configured" }
    } else {
        Write-Warn "  WARN: Git mirror not configured for github.com"
        $results["PC7"] = @{ status = "WARN"; message = "Git mirror not configured" }
    }
} catch {
    Write-Warn "  WARN: Unable to check git mirror configuration"
    $results["PC7"] = @{ status = "WARN"; message = "Unable to check git mirror" }
}

# PreCheck PC8: Check HF_ENDPOINT and ModelScope API Configuration
Write-Host "`n[PC8] Checking Hugging Face and ModelScope Configuration..."

$hfEndpoint = [Environment]::GetEnvironmentVariable("HF_ENDPOINT", "User")
if ($hfEndpoint) {
    Write-Host "  HF_ENDPOINT: $hfEndpoint"
    if ($hfEndpoint -eq "https://hf-mirror.com") {
        Write-Success "  PASS: HF_ENDPOINT set to hf-mirror.com"
    } else {
        Write-Warn "  WARN: HF_ENDPOINT set to non-standard value"
    }
} else {
    Write-Warn "  WARN: HF_ENDPOINT is not set"
    $results["PC8"] = @{ status = "WARN"; message = "HF_ENDPOINT not set" }
}

$modelscopeApi = [Environment]::GetEnvironmentVariable("MODELSCOPE_API_URL", "User")
if ($modelscopeApi) {
    Write-Host "  MODELSCOPE_API_URL: $modelscopeApi"
    if ($modelscopeApi -eq "https://api.modelscope.cn") {
        Write-Success "  PASS: MODELSCOPE_API_URL set to api.modelscope.cn"
        $results["PC8"] = @{ status = "PASS"; message = "HF/ModelScope configured" }
    }
} else {
    Write-Warn "  WARN: MODELSCOPE_API_URL is not set"
    $results["PC8"] = @{ status = "WARN"; message = "MODELSCOPE_API_URL not set" }
}

# PreCheck PC9: Check OpenVINO Installation
Write-Host "`n[PC9] Checking OpenVINO Installation..."

try {
    $ovVersion = python -c "import openvino; print(openvino.__version__)" 2>&1
    if (-not ($ovVersion -match "ImportError")) {
        Write-Success "  PASS: OpenVINO installed: $ovVersion"
        $results["PC9"] = @{ status = "PASS"; message = "OpenVINO $ovVersion installed" }
    } else {
        Write-Warn "  WARN: OpenVINO not installed"
        $results["PC9"] = @{ status = "WARN"; message = "OpenVINO not installed" }
    }
} catch {
    Write-Warn "  WARN: Unable to check OpenVINO installation"
    $results["PC9"] = @{ status = "WARN"; message = "Unable to check OpenVINO" }
}

# PreCheck PC10: Check PyTorch Installation
Write-Host "`n[PC10] Checking PyTorch Installation..."

try {
    $torchVersion = python -c "import torch; print(torch.__version__)" 2>&1
    if (-not ($torchVersion -match "ImportError")) {
        Write-Success "  PASS: PyTorch installed: $torchVersion"
        $results["PC10"] = @{ status = "PASS"; message = "PyTorch $torchVersion installed" }
        
        try {
            $cudaAvailable = python -c "import torch; print(torch.cuda.is_available())" 2>&1
            Write-Host "  CUDA available: $cudaAvailable"
        } catch {
            Write-Host "  Unable to check CUDA status"
        }
    } else {
        Write-Warn "  WARN: PyTorch not installed"
        $results["PC10"] = @{ status = "WARN"; message = "PyTorch not installed" }
    }
} catch {
    Write-Warn "  WARN: Unable to check PyTorch installation"
    $results["PC10"] = @{ status = "WARN"; message = "Unable to check PyTorch" }
}

# Summary
Write-Host ("`n" + ("=" * 70))
Write-Host "Pre-Check Summary"
Write-Host ("=" * 70)

$failCount = ($results.Values | Where-Object { $_.status -eq "FAIL" }).Count
$warnCount = ($results.Values | Where-Object { $_.status -eq "WARN" }).Count
$passCount = ($results.Values | Where-Object { $_.status -eq "PASS" }).Count

Write-Host "`nResults:"
Write-Host "  PASS: $passCount" -ForegroundColor Green
Write-Host "  WARN: $warnCount" -ForegroundColor Yellow
Write-Host "  FAIL: $failCount" -ForegroundColor Red

Write-Host "`nAction Required:"
foreach ($key in $results.Keys) {
    $result = $results[$key]
    if ($result.status -eq "FAIL") {
        Write-Fail "  $key: $($result.message) → Run corresponding setup step"
    } elseif ($result.status -eq "WARN") {
        Write-Warn "  $key: $($result.message) → Consider running setup"
    }
}

Write-Host ("`n" + ("=" * 70))

# JSON Output for Agent Consumption
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
                "PC4" { "Run ST1: Install Python" }
                "PC5" { "Run ST2: Configure pip mirror (with -China)" }
                "PC6" { "Run ST3: Install Git" }
                "PC7" { "Run ST4: Configure Git mirror (with -China)" }
                "PC8" { "Run ST5: Install ModelScope and configure mirrors" }
                "PC9" { "Run ST6: Install OpenVINO" }
                "PC10" { "Run ST7: Install PyTorch" }
                default { "Manual action required" }
            }
        }
    }
}

$summary | ConvertTo-Json
Write-Host "[/AGENT_OUTPUT]"
