powershell -Command @"
function Write-Success {
    param([string]$text)
    Write-Host "OK $text" -ForegroundColor Green
}

function Write-Warn {
    param([string]$text)
    Write-Host "WARN $text" -ForegroundColor Yellow
}

Write-Host "=== Detecting GPU Devices ==="
$gpuList = Get-WmiObject -Class Win32_VideoController
$installedDriverVersion = $null

foreach ($gpu in $gpuList) {
    Write-Host "GPU: $($gpu.Name)"
    Write-Host "Driver: $($gpu.DriverVersion)"
    if ($gpu.Name -like "*Intel*") {
        $installedDriverVersion = $gpu.DriverVersion
        Write-Success "Found Intel GPU: $($gpu.Name)"
    }
}

Write-Host ""
Write-Host "=== Checking Driver Version ==="
Write-Host "Current: $installedDriverVersion"

$latestDriverVersion = $null

try {
    Write-Host "Try 1: winget..."
    $output = winget search Intel.DriverAndSupportAssistant 2>&1
    Write-Host "winget output: $output"
    if ($output -match "(\d+\.\d+\.\d+\.\d+)") {
        $latestDriverVersion = $matches[1]
        Write-Success "Found via winget: $latestDriverVersion"
    }
} catch {
    Write-Warn "winget failed: $_"
}

if (-not $latestDriverVersion) {
    try {
        Write-Host "Try 2: web page..."
        $page = Invoke-WebRequest -Uri "https://www.intel.com/content/www/us/en/support/detect.html" -UseBasicParsing -TimeoutSec 15
        if ($page.Content -match "(\d+\.\d+\.\d+\.\d+)") {
            $latestDriverVersion = $matches[1]
            Write-Success "Found via web: $latestDriverVersion"
        }
    } catch {
        Write-Warn "web failed: $_"
    }
}

if ($latestDriverVersion) {
    Write-Host "Latest: $latestDriverVersion"
    if ($installedDriverVersion) {
        $curr = $installedDriverVersion -split '\.' | ForEach-Object { [int]$_ }
        $latest = $latestDriverVersion -split '\.' | ForEach-Object { [int]$_ }
        $isLatest = $true
        for ($i = 0; $i -lt [Math]::Min($curr.Count, $latest.Count); $i++) {
            if ($curr[$i] -lt $latest[$i]) { $isLatest = $false; break }
            if ($curr[$i] -gt $latest[$i]) { $isLatest = $true; break }
        }
        if ($isLatest) {
            Write-Success "Current driver is latest!"
        } else {
            Write-Warn "Need update! Current: $installedDriverVersion, Latest: $latestDriverVersion"
        }
    } else {
        Write-Warn "No Intel driver installed"
    }
} else {
    Write-Warn "Cannot get latest version"
}

Write-Host "=== Done ==="
"@