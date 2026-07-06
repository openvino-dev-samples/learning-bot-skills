Set-ExecutionPolicy Bypass -Scope Process -Force

Write-Host "=== Environment Check ===" -ForegroundColor Cyan

Write-Host ""
Write-Host "1. Check OS..." -ForegroundColor White
if ($env:OS -eq "Windows_NT") {
    Write-Host "   OK: Windows OS" -ForegroundColor Green
} else {
    Write-Host "   FAIL: Not Windows" -ForegroundColor Red
}

Write-Host ""
Write-Host "2. Check Intel Processor..." -ForegroundColor White
$cpu = Get-WmiObject -Class Win32_Processor | Select-Object -First 1
$isIntel = $cpu.Name -like "*Intel*"
Write-Host "   CPU: $($cpu.Name)"
Write-Host "   Is Intel: $isIntel"

Write-Host ""
Write-Host "3. Check GPU (WMI)..." -ForegroundColor White
$gpuList = Get-WmiObject -Class Win32_VideoController
foreach ($gpu in $gpuList) {
    Write-Host "   GPU: $($gpu.Name)"
    Write-Host "        Driver: $($gpu.DriverVersion)"
}

Write-Host ""
Write-Host "4. Check Hardware with OpenVINO hello_query_device.py (Official Method)..." -ForegroundColor Yellow
Write-Host "   This is the PRIMARY method for hardware detection." -ForegroundColor Yellow
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
Write-Host "=== Environment Check Complete ===" -ForegroundColor Cyan