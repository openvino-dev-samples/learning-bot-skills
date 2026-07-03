Set-ExecutionPolicy Bypass -Scope Process -Force

Write-Host "=== Python Installation Test ===" -ForegroundColor Cyan

Write-Host ""
Write-Host "[1/3] Check if Python is installed..." -ForegroundColor White

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
    Write-Host "  Found Python: $pythonPath"
    
    try {
        $versionOutput = & $pythonPath --version 2>&1
        $pythonVersionStr = $versionOutput -replace "Python ", ""
        Write-Host "  Current version: $pythonVersionStr"
        
        $versionMatch = $pythonVersionStr -match "^(\d+)\.(\d+)"
        if ($versionMatch) {
            $major = [int]$matches[1]
            $minor = [int]$matches[2]
            
            if ($major -eq 3 -and $minor -ge 10) {
                Write-Host "  Python 3.10+ already installed, skipping" -ForegroundColor Green
                $pythonInstalled = $true
            } else {
                Write-Host "  Version below 3.10, need to install" -ForegroundColor Yellow
            }
        }
    } catch {
        Write-Host "  Cannot get Python version" -ForegroundColor Yellow
    }
} else {
    Write-Host "  Python not found, need to install" -ForegroundColor White
}

if (-not $pythonInstalled) {
    Write-Host ""
    Write-Host "[2/3] Download and install Python..." -ForegroundColor White
    
    $pythonVersion = "3.12.0"
    $pythonUrl = "https://www.python.org/ftp/python/$pythonVersion/python-$pythonVersion-amd64.exe"
    $pythonInstaller = "$env:TEMP\python-$pythonVersion-amd64.exe"
    $pythonTargetDir = "$env:LOCALAPPDATA\Programs\Python\Python312"

    Write-Host "  Version: $pythonVersion"
    Write-Host "  Download URL: $pythonUrl"
    Write-Host "  Install path: $pythonTargetDir"
    Write-Host "  Starting download..."
    
    try {
        $headers = @{
            "User-Agent" = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
        }
        Invoke-WebRequest -Uri $pythonUrl -OutFile $pythonInstaller -UseBasicParsing -Headers $headers -ErrorAction Stop
        Write-Host "  Download complete!"
        
        Write-Host "  Installing (no admin required)..."
        
        Start-Process -FilePath $pythonInstaller -ArgumentList "/quiet InstallAllUsers=0 PrependPath=1 Include_pip=1 TARGETDIR=`"$pythonTargetDir`"" -Wait -NoNewWindow
        Remove-Item $pythonInstaller -Force
        
        $env:PATH = "$pythonTargetDir;$pythonTargetDir\Scripts;" + $env:PATH
        
        Write-Host ""
        Write-Host "[3/3] Verify installation..." -ForegroundColor White
        
        $pythonPath = (Get-Command python -ErrorAction SilentlyContinue).Source
        if ($pythonPath) {
            Write-Host "  Python path: $pythonPath"
        }
        
        $pythonVersionOutput = python --version 2>&1
        Write-Host "  $pythonVersionOutput"
        
        $pipVersionOutput = pip --version 2>&1
        Write-Host "  $pipVersionOutput"
        
        Write-Host ""
        Write-Host "  Python installation successful!" -ForegroundColor Green
    } catch {
        Write-Host "  Installation failed: $_" -ForegroundColor Red
    }
}

Write-Host ""
Write-Host "=== Test Complete ===" -ForegroundColor Cyan
