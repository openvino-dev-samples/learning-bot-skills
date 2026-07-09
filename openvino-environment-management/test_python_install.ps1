Set-ExecutionPolicy Bypass -Scope Process -Force

Write-Host "=== Python 安装测试 ===" -ForegroundColor Cyan

Write-Host ""
Write-Host "[1/3] 检查 Python 是否已安装..." -ForegroundColor White

$pythonInstalled = $false
$pythonPath = $null
$pythonVersionStr = $null

$pythonExePaths = @(
    (Get-Command python -ErrorAction SilentlyContinue).Source,
    (Get-Command python3 -ErrorAction SilentlyContinue).Source,
    "$env:LOCALAPPDATA\Programs\Python\Python312\python.exe",
    "$env:LOCALAPPDATA\Programs\Python\Python311\python.exe"
) | Where-Object { 
    $_ -and (Test-Path $_) -and (-not $_.Contains("WindowsApps")) 
} | Select-Object -First 1

if ($pythonExePaths) {
    $pythonPath = $pythonExePaths
    Write-Host "  找到 Python: $pythonPath"
    
    try {
        $versionOutput = & $pythonPath --version 2>&1
        $pythonVersionStr = $versionOutput -replace "Python ", ""
        Write-Host "  当前版本: $pythonVersionStr"
        
        $versionMatch = $pythonVersionStr -match "^(\d+)\.(\d+)"
        if ($versionMatch) {
            $major = [int]$matches[1]
            $minor = [int]$matches[2]
            
            if ($major -eq 3 -and $minor -ge 10) {
                Write-Host "  Python 3.10+ 已安装，跳过" -ForegroundColor Green
                $pythonInstalled = $true
            } else {
                Write-Host "  版本低于 3.10，需要安装" -ForegroundColor Yellow
            }
        }
    } catch {
        Write-Host "  无法获取 Python 版本" -ForegroundColor Yellow
    }
} else {
    Write-Host "  未找到 Python，需要安装" -ForegroundColor White
}

if (-not $pythonInstalled) {
    Write-Host ""
    Write-Host "[2/3] 下载并安装 Python..." -ForegroundColor White
    
    $pythonVersion = "3.12.0"
    $pythonUrl = "https://www.python.org/ftp/python/$pythonVersion/python-$pythonVersion-amd64.exe"
    $pythonInstaller = "$env:TEMP\python-$pythonVersion-amd64.exe"
    $pythonTargetDir = "$env:LOCALAPPDATA\Programs\Python\Python312"

    Write-Host "  版本: $pythonVersion"
    Write-Host "  下载 URL: $pythonUrl"
    Write-Host "  安装路径: $pythonTargetDir"
    Write-Host "  开始下载..."
    
    try {
        $headers = @{
            "User-Agent" = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
        }
        Invoke-WebRequest -Uri $pythonUrl -OutFile $pythonInstaller -UseBasicParsing -Headers $headers -ErrorAction Stop
        Write-Host "  下载完成！"
        
        Write-Host "  正在安装（无需管理员权限）..."
        
        Start-Process -FilePath $pythonInstaller -ArgumentList "/quiet InstallAllUsers=0 PrependPath=1 Include_pip=1 TARGETDIR=`"$pythonTargetDir`"" -Wait -NoNewWindow
        Remove-Item $pythonInstaller -Force
        
        $env:PATH = "$pythonTargetDir;$pythonTargetDir\Scripts;" + $env:PATH
        
        Write-Host ""
        Write-Host "[3/3] 验证安装..." -ForegroundColor White
        
        $pythonPath = (Get-Command python -ErrorAction SilentlyContinue).Source
        if ($pythonPath) {
            Write-Host "  Python 路径: $pythonPath"
        }
        
        $pythonVersionOutput = python --version 2>&1
        Write-Host "  $pythonVersionOutput"
        
        $pipVersionOutput = pip --version 2>&1
        Write-Host "  $pipVersionOutput"
        
        Write-Host ""
        Write-Host "  Python 安装成功！" -ForegroundColor Green
    } catch {
        Write-Host "  安装失败: $_" -ForegroundColor Red
    }
}

Write-Host ""
Write-Host "=== 测试完成 ===" -ForegroundColor Cyan
