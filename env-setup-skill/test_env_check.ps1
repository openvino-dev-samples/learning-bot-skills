Set-ExecutionPolicy Bypass -Scope Process -Force

Write-Host "=== Test Environment Check ==="

Write-Host ""
Write-Host "1. Check OS..."
if ($env:OS -eq "Windows_NT") {
    Write-Host "   OK: Windows OS"
} else {
    Write-Host "   FAIL: Not Windows"
}

Write-Host ""
Write-Host "2. Check CPU..."
$cpu = Get-WmiObject -Class Win32_Processor | Select-Object -First 1
$isIntel = $cpu.Name -like "*Intel*"
Write-Host "   CPU: $($cpu.Name)"
Write-Host "   Is Intel: $isIntel"

Write-Host ""
Write-Host "3. Check GPU..."
$gpuList = Get-WmiObject -Class Win32_VideoController
foreach ($gpu in $gpuList) {
    Write-Host "   GPU: $($gpu.Name)"
    Write-Host "        Driver: $($gpu.DriverVersion)"
}

Write-Host ""
Write-Host "=== Test Complete ==="
