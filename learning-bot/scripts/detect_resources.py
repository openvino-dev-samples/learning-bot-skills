"""OpenVINO 设备探测 —— 供 detect_resources.ps1 调用。

为什么单独一个文件而不是内联进 PowerShell 的 `python -c`：
PowerShell 把参数传给原生命令时会做一轮引号处理，会把 Python 源码里的双引号**吃掉**，
于是 `print("OV_JSON:" + ...)` 变成 `print(OV_JSON: + ...)` 直接语法错误 —— 而且这个错误被
catch 吞掉后只会静默退化成「估算」模式，很难发现。放成真实文件就没有这层引号地狱。

输出（stdout 单行）：
    OV_JSON:{"devices":[{"name":"GPU","full_name":"..."}],"gpu_total_bytes":0,"gpu_type":"none"}
或
    NO_OPENVINO

本文件只读设备属性，不加载任何模型，不联网。
"""
import json
import sys


def main():
    try:
        import openvino as ov
    except Exception:
        print("NO_OPENVINO")
        return 0

    try:
        core = ov.Core()
    except Exception:
        print("NO_OPENVINO")
        return 0

    out = {"devices": [], "gpu_total_bytes": 0, "gpu_type": "none"}
    for dev in core.available_devices:
        entry = {"name": dev}
        try:
            entry["full_name"] = str(core.get_property(dev, "FULL_DEVICE_NAME"))
        except Exception:
            entry["full_name"] = dev
        out["devices"].append(entry)

        if not dev.startswith("GPU"):
            continue

        # GPU_DEVICE_TOTAL_MEM_SIZE 是唯一可信的显存来源。
        # WMI 的 AdapterRAM 是 UINT32，在 >4GB 的卡上必然截断（实测 16GB 的 Arc 140V 报 2GB）。
        try:
            out["gpu_total_bytes"] = int(core.get_property(dev, "GPU_DEVICE_TOTAL_MEM_SIZE"))
        except Exception:
            pass

        # INTEGRATED 意味着显存与系统内存同源 —— 调用方据此决定不要把两者相加。
        try:
            dtype = str(core.get_property(dev, "DEVICE_TYPE")).upper()
            out["gpu_type"] = "integrated" if "INTEGRATED" in dtype else "discrete"
        except Exception:
            out["gpu_type"] = "discrete"

    print("OV_JSON:" + json.dumps(out))
    return 0


if __name__ == "__main__":
    sys.exit(main())
