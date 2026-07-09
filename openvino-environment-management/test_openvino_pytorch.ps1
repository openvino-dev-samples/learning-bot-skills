Set-ExecutionPolicy Bypass -Scope Process -Force

Write-Host "=== OpenVINO 和 PyTorch 安装测试 ===" -ForegroundColor Cyan

Write-Host ""
Write-Host "[1/6] 正在安装 OpenVINO（最新稳定版）..." -ForegroundColor White

try {
    pip install --upgrade openvino --quiet
    $ovVersion = python -c "import openvino; print(openvino.__version__)"
    Write-Host "  OpenVINO 版本: $ovVersion" -ForegroundColor Green
} catch {
    Write-Host "  OpenVINO 安装失败: $_" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "[2/6] 正在安装 PyTorch CPU（经过测试的稳定配置）..." -ForegroundColor White

try {
    pip install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cpu --trusted-host download.pytorch.org --quiet
    $torchVersion = python -c "import torch; print(torch.__version__)"
    Write-Host "  PyTorch CPU 版本: $torchVersion" -ForegroundColor Green
} catch {
    Write-Host "  PyTorch CPU 失败，尝试清华大学镜像..." -ForegroundColor Yellow
    try {
        pip install torch torchvision torchaudio -i https://pypi.tuna.tsinghua.edu.cn/simple --trusted-host pypi.tuna.tsinghua.edu.cn --quiet
        $torchVersion = python -c "import torch; print(torch.__version__)"
        Write-Host "  PyTorch (清华镜像): $torchVersion" -ForegroundColor Green
    } catch {
        Write-Host "  PyTorch 安装失败: $_" -ForegroundColor Red
    }
}

Write-Host ""
Write-Host "[3/6] 测试 PyTorch CPU 可用性..." -ForegroundColor White

try {
    $torchCheck = python -c "import torch; print(f'PyTorch 版本: {torch.__version__}'); print(f'CPU 可用: {torch.cuda.is_available() == False}')"
    Write-Host "  $torchCheck" -ForegroundColor Green
} catch {
    Write-Host "  PyTorch 测试失败: $_" -ForegroundColor Red
}

Write-Host ""
Write-Host "[4/6] 使用 OpenVINO 测试设备可用性..." -ForegroundColor White

$testScriptPath = "$env:TEMP\test_openvino.py"
Set-Content -Path $testScriptPath -Value @"
from openvino.runtime import Core

print("=" * 60)
print("OpenVINO 设备查询")
print("=" * 60)

try:
    core = Core()
    available_devices = core.available_devices
    
    print(f"\n可用设备: {available_devices}")
    print(f"设备数量: {len(available_devices)}")
    
    has_gpu = False
    has_npu = False
    has_cpu = False
    
    for device in available_devices:
        print(f"\n--- 设备: {device} ---")
        try:
            props = core.get_property(device)
            for key, value in props.items():
                print(f"  {key}: {value}")
        except:
            print("  (属性不可用)")
        
        if "GPU" in device.upper():
            has_gpu = True
        elif "NPU" in device.upper():
            has_npu = True
        elif "CPU" in device.upper():
            has_cpu = True
    
    print("\n" + "=" * 60)
    print("设备摘要")
    print("=" * 60)
    
    if has_gpu:
        print("✓ Intel GPU (iGPU/Arc) 已检测并可用")
    else:
        print("✗ 未检测到 Intel GPU")
        
    if has_npu:
        print("✓ Intel NPU 已检测并可用")
    else:
        print("✗ 未检测到 Intel NPU")
        
    if has_cpu:
        print("✓ CPU 可用")
    else:
        print("✗ 未检测到 CPU")
        
except Exception as e:
    print(f"错误: {e}")
"@

python $testScriptPath
Remove-Item $testScriptPath -Force

Write-Host ""
Write-Host "[5/6] 下载并运行 hello_query_device..." -ForegroundColor White

$helloScriptPath = "$env:TEMP\hello_query_device.py"
$downloadUrls = @(
    "https://ghproxy.net/https://github.com/openvinotoolkit/openvino/raw/refs/heads/master/samples/python/hello_query_device/hello_query_device.py",
    "https://github.com/openvinotoolkit/openvino/raw/refs/heads/master/samples/python/hello_query_device/hello_query_device.py"
)

$downloadSuccess = $false
foreach ($url in $downloadUrls) {
    try {
        Write-Host "  尝试: $url"
        Invoke-WebRequest -Uri $url -OutFile $helloScriptPath -UseBasicParsing -ErrorAction Stop
        $downloadSuccess = $true
        break
    } catch {
        Write-Host "  失败" -ForegroundColor Yellow
    }
}

if ($downloadSuccess -and (Test-Path $helloScriptPath)) {
    Write-Host "  下载成功，正在运行..."
    python $helloScriptPath
    Remove-Item $helloScriptPath -Force
} else {
    Write-Host "  下载失败，跳过" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "[6/6] 最终验证..." -ForegroundColor White

$finalCheck = python -c "import torch; import openvino as ov; print(f'✓ PyTorch {torch.__version__} (CPU 模式)'); print(f'✓ OpenVINO {ov.__version__}'); print(f'✓ 所有组件已就绪')"
Write-Host "  $finalCheck" -ForegroundColor Green

Write-Host ""
Write-Host "=== 测试完成 ===" -ForegroundColor Cyan
