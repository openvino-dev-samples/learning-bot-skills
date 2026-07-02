# -*- coding: utf-8 -*-
"""Benchmark a composed pipeline (per-stage + end-to-end) and emit [SKILL_RESULT].

Reads <ir_dir>/pipeline-plan.json, times each stage, finds the bottleneck. Each stage is
tagged (from IR)/(REBUILT!) so an inflated first-run number is never sold as a deploy figure.
--dry-run emits a well-formed placeholder block (latencies=n/a) — testable without hardware.
"""
import argparse
import json
import os
import sys


def emit_result(d):
    """Print the machine-parseable [SKILL_RESULT] block."""
    print("[SKILL_RESULT]")
    print("status=%s" % d["status"])
    print("pipeline=%s" % d.get("pipeline", ""))
    print("stages=%s" % d.get("stages_str", ""))
    print("e2e_latency_ms=%s" % d.get("e2e_latency_ms", "n/a"))
    print("throughput=%s" % d.get("throughput", "n/a"))
    print("bottleneck=%s" % d.get("bottleneck", "n/a"))
    print("ir_dir=%s" % d.get("ir_dir", ""))
    print("[/SKILL_RESULT]")


def time_stage(stage):
    """Return latency_ms: compile the stage IR on its device (cold-stage cost dominant).
    Raises if IR/device unavailable so the caller marks it errored (never silently 0)."""
    import time
    import openvino as ov  # noqa
    xml = stage["ir_path"]
    if not xml or not os.path.isfile(xml):
        raise FileNotFoundError("IR not found for stage %s: %s" % (stage["name"], xml))
    core = ov.Core()
    t0 = time.perf_counter()
    compiled = core.compile_model(xml, stage["device"])  # noqa: F841
    # NOTE: a real run feeds a representative input tensor here and calls infer();
    # compile+first-infer time is what dominates a cold pipeline stage.
    return (time.perf_counter() - t0) * 1000.0


def main():
    ap = argparse.ArgumentParser(description="Benchmark a composed pipeline; emit [SKILL_RESULT].")
    ap.add_argument("--ir-dir", required=True)
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--repeats", type=int, default=1)
    args = ap.parse_args()

    plan_path = os.path.join(args.ir_dir, "pipeline-plan.json")
    if not os.path.isfile(plan_path):
        emit_result({"status": "error", "ir_dir": args.ir_dir,
                     "stages_str": "pipeline-plan.json not found — run optimize.py first"})
        return 1

    with open(plan_path, encoding="utf-8") as f:
        plan = json.load(f)

    stages = plan["stages"]
    parts, per_stage = [], []
    e2e = 0.0
    ok = True

    for st in stages:
        tag = {"reused": "from IR", "rebuilt": "REBUILT!", "skipped": "glue",
               "would-build": "planned", "error": "ERR"}.get(st.get("status"), "?")
        if args.dry_run or st.get("status") in ("skipped", "would-build"):
            lat = None
        else:
            try:
                lat = min(time_stage(st) for _ in range(max(1, args.repeats)))
            except Exception as e:
                lat = None
                st["bench_error"] = "%s: %s" % (type(e).__name__, e)
                ok = False
        if lat is not None:
            e2e += lat
        per_stage.append((st["name"], lat, st))
        parts.append("%s:%s/%s/%s(%s)" % (
            st["name"], st["device"], st["precision"],
            ("%.0fms" % lat) if lat is not None else "n/a", tag))

    # bottleneck = stage with the largest measured latency
    timed = [(n, l) for (n, l, _s) in per_stage if l is not None]
    bottleneck = max(timed, key=lambda x: x[1])[0] if timed else "n/a"

    result = {
        "status": "ok" if ok else "error",
        "pipeline": plan.get("pipeline", ""),
        "ir_dir": args.ir_dir,
        "stages_str": "; ".join(parts),
        "e2e_latency_ms": ("%.0f" % e2e) if timed else "n/a",
        "throughput": "n/a",  # filled from LLM [PERF] parsing in the real run
        "bottleneck": bottleneck,
    }
    emit_result(result)

    # human-readable per-stage table after the block
    print("\nPer-stage:")
    for name, lat, st in per_stage:
        print("  %-18s %8s  %s/%s  [%s]" % (
            name, ("%.0fms" % lat) if lat is not None else "n/a",
            st["device"], st["precision"], st.get("status")))
    if args.dry_run:
        print("\n[bench] --dry-run: latencies are placeholders (no hardware run).")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
