Set-ExecutionPolicy Bypass -Scope Process -Force

Write-Host "=== 环境检查 ===" -ForegroundColor Cyan

Write-Host ""
Write-Host "1. 检查操作系统..." -ForegroundColor White
if ($env:OS -eq "Windows_NT") {
    Write-Host "   正常: Windows 操作系统" -ForegroundColor Green
} else {
    Write-Host "   失败: 非 Windows 操作系统" -ForegroundColor Red
}

Write-Host ""
Write-Host "2. 检查 Intel 处理器..." -ForegroundColor White
$cpu = Get-WmiObject -Class Win32_Processor | Select-Object -First 1
$isIntel = $cpu.Name -like "*Intel*"
Write-Host "   CPU: $($cpu.Name)"
Write-Host "   是否为 Intel: $isIntel"

Write-Host ""
Write-Host "3. 检查 GPU (WMI)..." -ForegroundColor White
$gpuList = Get-WmiObject -Class Win32_VideoController
foreach ($gpu in $gpuList) {
    Write-Host "   GPU: $($gpu.Name)"
    Write-Host "        驱动: $($gpu.DriverVersion)"
}

Write-Host ""
Write-Host "4. 使用 OpenVINO hello_query_device.py 检查硬件（官方方法）..." -ForegroundColor Yellow
Write-Host "   这是硬件检测的主要方法。" -ForegroundColor Yellow
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
        Write-Host "   从以下地址下载: $url" -ForegroundColor Gray
        break
    } catch {
        Write-Host "   从以下地址下载失败: $url" -ForegroundColor Gray
    }
}

if ($downloadSuccess -and (Test-Path $helloScriptPath)) {
    Write-Host ""
    python $helloScriptPath
    Remove-Item $helloScriptPath -Force
} else {
    Write-Host "   失败: 无法下载 hello_query_device.py" -ForegroundColor Red
    Write-Host "   请确保 OpenVINO 已安装: pip install openvino" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "=== 环境检查完成 ===" -ForegroundColor Cyan
