Set-ExecutionPolicy Bypass -Scope Process -Force

Write-Host "=== 驱动检查 ===" -ForegroundColor Cyan

Write-Host ""
Write-Host "1. 检查 GPU 驱动 (WMI)..." -ForegroundColor White
$gpuList = Get-WmiObject -Class Win32_VideoController
foreach ($gpu in $gpuList) {
    Write-Host "   GPU: $($gpu.Name)"
    Write-Host "        驱动版本: $($gpu.DriverVersion)"
    Write-Host "        驱动日期: $($gpu.DriverDate)"
    Write-Host ""
}

Write-Host ""
Write-Host "2. 检查 Intel 图形驱动..." -ForegroundColor White
$intelDriver = Get-WmiObject -Class Win32_PnPSignedDriver | Where-Object {
    $_.DeviceName -like "*Intel*Graphics*" -or 
    $_.DeviceName -like "*Intel*UHD*" -or 
    $_.DeviceName -like "*Intel*Arc*" -or
    $_.DeviceName -like "*Intel*AI*Boost*"
}

if ($intelDriver) {
    Write-Host "   找到 Intel 图形/NPU 驱动:" -ForegroundColor Green
    $intelDriver | ForEach-Object {
        Write-Host "   设备: $($_.DeviceName)"
        Write-Host "   驱动版本: $($_.DriverVersion)"
        Write-Host "   驱动日期: $($_.DriverDate)"
        Write-Host ""
    }
} else {
    Write-Host "   警告: 未找到 Intel 图形驱动" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "3. 检查驱动更新..." -ForegroundColor White
try {
    $updateSession = New-Object -ComObject Microsoft.Update.Session
    $updateSearcher = $updateSession.CreateUpdateSearcher()
    $searchResult = $updateSearcher.Search("IsInstalled=0 AND Type='Driver' AND Title='*Intel*'")
    
    if ($searchResult.Updates.Count -eq 0) {
        Write-Host "   正常: 当前驱动是最新的" -ForegroundColor Green
    } else {
        Write-Host "   警告: 有可用的 Intel 驱动更新" -ForegroundColor Yellow
        Write-Host "   请运行 Intel 驱动支持助手进行更新" -ForegroundColor Yellow
    }
} catch {
    Write-Host "   警告: 无法自动检查驱动更新" -ForegroundColor Yellow
    Write-Host "   请手动访问: https://www.intel.com/content/www/us/en/support/detect.html" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "4. 使用 OpenVINO hello_query_device.py 检查硬件..." -ForegroundColor Yellow
Write-Host "   这提供了完整的硬件信息，包括 CPU、GPU 和 NPU。" -ForegroundColor Yellow
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
Write-Host "=== 驱动检查完成 ===" -ForegroundColor Cyan
