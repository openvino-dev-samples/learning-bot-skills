# -*- coding: utf-8 -*-
"""Optimize each stage of a resolved pipeline -> <ir_dir>/pipeline-plan.json.

Per stage: export to OpenVINO IR (task-agnostic optimum-cli), NNCF weight compression
at the stage precision, device assignment (with fallback), reused/rebuilt/skipped status.
--dry-run plans + writes the plan file without heavy deps/downloads (testable anywhere).
"""
import argparse
import json
import os
import sys


def log(msg):
    print("[optimize] " + msg, flush=True)


def available_devices():
    """Return OpenVINO device list; empty on failure (dry-run friendly)."""
    try:
        import openvino as ov  # noqa
        return list(ov.Core().available_devices)
    except Exception:
        return []


def pick_device(requested, devices):
    """Fallback chain: requested -> GPU -> CPU, honoring what's actually present."""
    if not devices:  # unknown (dry-run) — trust the request
        return requested, False
    def has(d):
        return any(dev == d or dev.startswith(d + ".") for dev in devices)
    if has(requested):
        return requested, False
    for fb in ("GPU", "CPU"):
        if has(fb):
            return fb, True
    return "CPU", True


def ir_paths(ir_dir, stage_name):
    d = os.path.join(ir_dir, stage_name)
    return d, os.path.join(d, "openvino_model.xml")


def optimize_stage(stage, ir_dir, dry_run, devices):
    role = stage["role"]
    name = stage["name"]
    model_id = stage.get("model_id")
    precision = stage.get("precision", "FP16")
    device, fell_back = pick_device(stage.get("device", "CPU"), devices)

    stage_dir, xml = ir_paths(ir_dir, name)
    reused = os.path.isfile(xml)

    record = {
        "role": role, "name": name, "model_id": model_id,
        "device": device, "precision": precision,
        "ir_path": xml, "device_fell_back": fell_back,
    }

    if model_id is None:
        # pre/post-process or a stage whose weights come bundled with the notebook demo
        record["status"] = "skipped"
        record["note"] = "no standalone model_id (glue / bundled stage)"
        log("%-18s : skipped (%s)" % (name, record["note"]))
        return record

    if reused:
        record["status"] = "reused"
        log("%-18s : reused IR (from IR)  device=%s precision=%s" % (name, device, precision))
        return record

    if dry_run:
        record["status"] = "would-build"
        log("%-18s : WOULD build IR  %s -> %s @ %s  device=%s"
            % (name, model_id, precision, stage_dir, device))
        return record

    # --- real optimization path (inside venv) ---
    try:
        os.makedirs(stage_dir, exist_ok=True)
        _export_stage(model_id, stage_dir, precision)
        record["status"] = "rebuilt"
        log("%-18s : REBUILT IR  %s -> %s @ %s  device=%s"
            % (name, model_id, precision, stage_dir, device))
    except Exception as e:
        record["status"] = "error"
        record["error"] = "%s: %s" % (type(e).__name__, e)
        log("%-18s : ERROR %s" % (name, record["error"]))
    return record


def _export_stage(model_id, out_dir, precision):
    """Export any model to OpenVINO IR via `optimum-cli export openvino` (task auto-detected,
    so LLM/ASR/vision/embedding/diffusion all work without a family switch)."""
    weight_format = {"INT4": "int4", "INT8": "int8", "FP16": "fp16"}.get(precision, "fp16")
    cmd = [
        sys.executable, "-m", "optimum.commands.optimum_cli",
        "export", "openvino",
        "--model", model_id,
        "--weight-format", weight_format,
        out_dir,
    ]
    import subprocess
    proc = subprocess.run(cmd, capture_output=True, text=True)
    if proc.returncode != 0:
        # Surface the CLI's own error; never silently produce a partial/empty IR dir.
        tail = (proc.stderr or proc.stdout or "").strip().splitlines()[-8:]
        raise RuntimeError("optimum-cli export failed:\n" + "\n".join(tail))


def main():
    ap = argparse.ArgumentParser(description="Optimize pipeline stages -> pipeline-plan.json")
    ap.add_argument("--plan", required=True, help="resolved plan JSON from resolve_pipeline.py --out")
    ap.add_argument("--ir-dir", required=True, help="output IR dir (per pipeline slug)")
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    with open(args.plan, encoding="utf-8") as f:
        plan = json.load(f)
    if not plan.get("ok"):
        log("resolved plan is not ok: %s" % plan.get("reason"))
        return 1

    os.makedirs(args.ir_dir, exist_ok=True)
    # In dry-run we deliberately DO NOT import openvino / probe devices — keeps the
    # orchestration testable on any machine and instant. Trust the requested devices.
    devices = [] if args.dry_run else available_devices()
    log("available devices: %s" % (devices or "(unknown / dry-run)"))

    out_stages = [optimize_stage(st, args.ir_dir, args.dry_run, devices) for st in plan["stages"]]
    errors = [s for s in out_stages if s.get("status") == "error"]

    result = {
        "pipeline": plan["pipeline"],
        "title": plan.get("title"),
        "ir_dir": args.ir_dir,
        "devices_seen": devices,
        "stages": out_stages,
        "ok": not errors,
    }
    out_path = os.path.join(args.ir_dir, "pipeline-plan.json")
    with open(out_path, "w", encoding="utf-8") as f:
        json.dump(result, f, ensure_ascii=False, indent=2)
    log("wrote %s" % out_path)

    if errors:
        log("%d stage(s) failed to optimize" % len(errors))
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
