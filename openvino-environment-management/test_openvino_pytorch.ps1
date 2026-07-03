Set-ExecutionPolicy Bypass -Scope Process -Force

Write-Host "=== OpenVINO and PyTorch Installation Test ===" -ForegroundColor Cyan

Write-Host ""
Write-Host "[1/5] Installing OpenVINO..." -ForegroundColor White

try {
    pip install openvino openvino-dev --quiet
    $ovVersion = python -c "import openvino; print(openvino.__version__)"
    Write-Host "  OpenVINO version: $ovVersion" -ForegroundColor Green
} catch {
    Write-Host "  OpenVINO installation failed: $_" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "[2/5] Installing PyTorch (Intel XPU)..." -ForegroundColor White

try {
    pip install torch torchvision torchaudio --index-url https://pytorch-extension.intel.com/release-whl/stable/xpu/cn/ --trusted-host pytorch-extension.intel.com --quiet
    $torchVersion = python -c "import torch; print(torch.__version__)"
    Write-Host "  PyTorch version: $torchVersion" -ForegroundColor Green
} catch {
    Write-Host "  XPU version failed, trying CPU version..." -ForegroundColor Yellow
    try {
        pip install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cpu --trusted-host download.pytorch.org --quiet
        $torchVersion = python -c "import torch; print(torch.__version__)"
        Write-Host "  PyTorch CPU version: $torchVersion" -ForegroundColor Green
    } catch {
        Write-Host "  PyTorch CPU failed, trying Tsinghua mirror..." -ForegroundColor Yellow
        try {
            pip install torch torchvision torchaudio -i https://pypi.tuna.tsinghua.edu.cn/simple --trusted-host pypi.tuna.tsinghua.edu.cn --quiet
            $torchVersion = python -c "import torch; print(torch.__version__)"
            Write-Host "  PyTorch (Tsinghua): $torchVersion" -ForegroundColor Green
        } catch {
            Write-Host "  PyTorch installation failed: $_" -ForegroundColor Red
        }
    }
}

Write-Host ""
Write-Host "[3/5] Installing Intel PyTorch Extension (IPEX)..." -ForegroundColor White

try {
    pip install intel-extension-for-pytorch --index-url https://pytorch-extension.intel.com/release-whl/stable/xpu/cn/ --trusted-host pytorch-extension.intel.com --quiet
    $ipexVersion = python -c "import intel_extension_for_pytorch as ipex; print(ipex.__version__)"
    Write-Host "  IPEX version: $ipexVersion" -ForegroundColor Green
} catch {
    Write-Host "  IPEX installation failed: $_" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "[4/5] Testing device availability with OpenVINO..." -ForegroundColor White

$testScriptPath = "$env:TEMP\test_openvino.py"
Set-Content -Path $testScriptPath -Value @"
from openvino.runtime import Core

print("=" * 60)
print("OpenVINO Device Query")
print("=" * 60)

try:
    core = Core()
    available_devices = core.available_devices
    
    print(f"\nAvailable devices: {available_devices}")
    print(f"Number of devices: {len(available_devices)}")
    
    has_gpu = False
    has_npu = False
    has_cpu = False
    
    for device in available_devices:
        print(f"\n--- Device: {device} ---")
        try:
            props = core.get_property(device)
            for key, value in props.items():
                print(f"  {key}: {value}")
        except:
            print("  (Properties unavailable)")
        
        if "GPU" in device.upper():
            has_gpu = True
        elif "NPU" in device.upper():
            has_npu = True
        elif "CPU" in device.upper():
            has_cpu = True
    
    print("\n" + "=" * 60)
    print("Device Summary")
    print("=" * 60)
    
    if has_gpu:
        print("✓ Intel GPU (iGPU/Arc) detected and available")
    else:
        print("✗ No Intel GPU detected")
        
    if has_npu:
        print("✓ Intel NPU detected and available")
    else:
        print("✗ No Intel NPU detected")
        
    if has_cpu:
        print("✓ CPU available")
    else:
        print("✗ No CPU detected")
        
except Exception as e:
    print(f"Error: {e}")
"@

python $testScriptPath
Remove-Item $testScriptPath -Force

Write-Host ""
Write-Host "[5/5] Downloading and running hello_query_device..." -ForegroundColor White

$helloScriptPath = "$env:TEMP\hello_query_device.py"
$downloadUrls = @(
    "https://ghproxy.net/https://github.com/openvinotoolkit/openvino/raw/refs/heads/master/samples/python/hello_query_device/hello_query_device.py",
    "https://github.com/openvinotoolkit/openvino/raw/refs/heads/master/samples/python/hello_query_device/hello_query_device.py"
)

$downloadSuccess = $false
foreach ($url in $downloadUrls) {
    try {
        Write-Host "  Trying: $url"
        Invoke-WebRequest -Uri $url -OutFile $helloScriptPath -UseBasicParsing -ErrorAction Stop
        $downloadSuccess = $true
        break
    } catch {
        Write-Host "  Failed" -ForegroundColor Yellow
    }
}

if ($downloadSuccess -and (Test-Path $helloScriptPath)) {
    Write-Host "  Download successful, running..."
    python $helloScriptPath
    Remove-Item $helloScriptPath -Force
} else {
    Write-Host "  Download failed, skipping" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "=== Test Complete ===" -ForegroundColor Cyan
