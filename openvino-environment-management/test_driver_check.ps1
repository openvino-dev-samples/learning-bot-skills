Set-ExecutionPolicy Bypass -Scope Process -Force

Write-Host "=== Driver Check ===" -ForegroundColor Cyan

Write-Host ""
Write-Host "1. Check GPU Drivers (WMI)..." -ForegroundColor White
$gpuList = Get-WmiObject -Class Win32_VideoController
foreach ($gpu in $gpuList) {
    Write-Host "   GPU: $($gpu.Name)"
    Write-Host "        Driver Version: $($gpu.DriverVersion)"
    Write-Host "        Driver Date: $($gpu.DriverDate)"
    Write-Host ""
}

Write-Host ""
Write-Host "2. Check Intel Graphics Driver..." -ForegroundColor White
$intelDriver = Get-WmiObject -Class Win32_PnPSignedDriver | Where-Object {
    $_.DeviceName -like "*Intel*Graphics*" -or 
    $_.DeviceName -like "*Intel*UHD*" -or 
    $_.DeviceName -like "*Intel*Arc*" -or
    $_.DeviceName -like "*Intel*AI*Boost*"
}

if ($intelDriver) {
    Write-Host "   Found Intel Graphics/NPU Driver:" -ForegroundColor Green
    $intelDriver | ForEach-Object {
        Write-Host "   Device: $($_.DeviceName)"
        Write-Host "   Driver Version: $($_.DriverVersion)"
        Write-Host "   Driver Date: $($_.DriverDate)"
        Write-Host ""
    }
} else {
    Write-Host "   WARN: No Intel graphics driver found" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "3. Check Driver Updates..." -ForegroundColor White
try {
    $updateSession = New-Object -ComObject Microsoft.Update.Session
    $updateSearcher = $updateSession.CreateUpdateSearcher()
    $searchResult = $updateSearcher.Search("IsInstalled=0 AND Type='Driver' AND Title='*Intel*'")
    
    if ($searchResult.Updates.Count -eq 0) {
        Write-Host "   OK: Current driver is up to date" -ForegroundColor Green
    } else {
        Write-Host "   WARN: Intel driver updates available" -ForegroundColor Yellow
        Write-Host "   Please run Intel Driver Support Assistant to update" -ForegroundColor Yellow
    }
} catch {
    Write-Host "   WARN: Unable to check driver updates automatically" -ForegroundColor Yellow
    Write-Host "   Please manually visit: https://www.intel.com/content/www/us/en/support/detect.html" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "4. Check Hardware with OpenVINO hello_query_device.py..." -ForegroundColor Yellow
Write-Host "   This provides complete hardware info including CPU, GPU, and NPU." -ForegroundColor Yellow
Write-Host ""

$helloScriptPath = "$env:TEMP\hello_query_device.py"
$downloadUrls = @(
    "https://ghproxy.net/https://github.com/openvinotoolkit/openvino/raw/refs/heads/master/samples/python/hello_query_device/hello_query_device.py",
    "https://github.com/openvinotoolkit/openvino/raw/refs/heads/master/samples/python/hello_query_device/hello_query_device.py"
)

$downloadSuccess = $false
foreach ($url in $downloadUrls) {
    try {
        Invoke-WebRequest -Uri $url -OutFile $helloScriptPath -UseBasicParsing -ErrorAction Stop | Out-Null
        $downloadSuccess = $true
        Write-Host "   Downloaded from: $url" -ForegroundColor Gray
        break
    } catch {
        Write-Host "   Download failed from: $url" -ForegroundColor Gray
    }
}

if ($downloadSuccess -and (Test-Path $helloScriptPath)) {
    Write-Host ""
    python $helloScriptPath
    Remove-Item $helloScriptPath -Force
} else {
    Write-Host "   FAIL: Could not download hello_query_device.py" -ForegroundColor Red
    Write-Host "   Please ensure OpenVINO is installed: pip install openvino" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "=== Driver Check Complete ===" -ForegroundColor Cyan