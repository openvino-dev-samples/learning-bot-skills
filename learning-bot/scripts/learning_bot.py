#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
learning_bot.py - entry / router driver for the Learning Bot launcher skill.

It does three things, all emitting a machine-parsable [SKILL_RESULT] block:

  --menu                Print the recommended preset questions (map to the 14 local aipc-skills).
  --route "<text>"      Classify a user utterance -> a preset skill, a dev skill (ENV/FETCH/PIPE),
                        or "clarify". This is a SUGGESTION for the agent, not a hard decision.
  --install <key>       Download + unzip the matching aipc-skill release zip locally.

The 14 preset skills, the 3 dev skills and the release URLs live in scripts/skills_registry.json.
Menu and routing are offline / network-free (stdlib only). Only --install touches the network.
"""
import argparse
import io
import json
import os
import sys
import zipfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
REGISTRY = HERE / "skills_registry.json"


def load_registry():
    with open(REGISTRY, "r", encoding="utf-8") as f:
        return json.load(f)


def emit(fields):
    """Print a [SKILL_RESULT] block from an ordered list of (key, value) pairs."""
    print("[SKILL_RESULT]")
    for k, v in fields:
        if isinstance(v, (dict, list)):
            v = json.dumps(v, ensure_ascii=False)
        print(f"{k}={v}")
    print("[/SKILL_RESULT]")


def cmd_menu(reg):
    presets = reg["preset_skills"]
    data = [
        {"key": s["key"], "name": s["name_cn"], "question": s["question"]}
        for s in presets
    ]
    print("Learning Bot 已启动。你可以直接问我下面这些本地能力（每一条都会调用一个本地 skill，")
    print("全部在你的 Intel AIPC 上离线运行）：\n")
    for i, s in enumerate(presets, 1):
        print(f"  {i:>2}. [{s['key']}] {s['name_cn']} —— 例如：{s['question']}")
    print()
    print("如果你的需求超出上面这些，我会根据实际情况改用开发类 skill：")
    for d in reg["dev_skills"]:
        print(f"     - {d['alias']} ({d['key']})：{d['when']}")
    print()
    emit([
        ("status", "ok"),
        ("action", "menu"),
        ("count", len(presets)),
        ("data", data),
    ])


def _score(text, keywords):
    return sum(1 for kw in keywords if kw.strip() and kw.strip().lower() in text)


def route(reg, text):
    t = (text or "").lower()

    # Score every preset skill by keyword hits.
    preset_hits = []
    for s in reg["preset_skills"]:
        sc = _score(t, s["keywords"])
        if sc > 0:
            preset_hits.append((sc, s["key"]))
    preset_hits.sort(reverse=True)

    # OCR is offered on both NPU and GPU; pick by explicit device, default to NPU.
    def normalize_ocr(key):
        if key in ("ocr-npu", "ocr-gpu"):
            if "gpu" in t:
                return "ocr-gpu"
            return "ocr-npu"
        return key

    # Score dev skills.
    dev_hits = []
    for d in reg["dev_skills"]:
        sc = _score(t, d["keywords"])
        if sc > 0:
            dev_hits.append((sc, d["key"]))
    dev_hits.sort(reverse=True)

    # Strong development-intent words steer to dev skills even if a modality word appears
    # (e.g. "下载 ASR 模型" is a FETCH job, not the ASR skill).
    dev_override = any(w in t for w in ("下载模型", "找模型", "download model", "部署", "流水线",
                                        "pipeline", "基准测试", "benchmark", "搭环境", "配置环境",
                                        "安装环境", "notebook", "教程", "学习路径"))

    if preset_hits and not dev_override:
        best = normalize_ocr(preset_hits[0][1])
        return {"scope": "preset", "target": best, "matched": "true",
                "reason": f"命中预设本地能力关键词（{preset_hits[0][0]} 个）"}

    if dev_hits:
        return {"scope": "dev", "target": dev_hits[0][1], "matched": "true",
                "reason": "超出预设本地能力，匹配到开发类 skill"}

    if preset_hits:
        best = normalize_ocr(preset_hits[0][1])
        return {"scope": "preset", "target": best, "matched": "true",
                "reason": "命中预设本地能力关键词"}

    return {"scope": "clarify", "target": "", "matched": "false",
            "reason": "无法可靠归类，建议先向用户追问具体任务 / 模态 / 目标"}


def cmd_route(reg, text):
    r = route(reg, text)
    emit([
        ("status", "ok"),
        ("action", "route"),
        ("matched", r["matched"]),
        ("scope", r["scope"]),
        ("target", r["target"]),
        ("reason", r["reason"]),
    ])


def cmd_install(reg, key, out_dir):
    presets = {s["key"]: s for s in reg["preset_skills"]}
    if key not in presets:
        emit([
            ("status", "error"),
            ("action", "install"),
            ("skill", key),
            ("reason", f"未知的 preset skill key：{key}；可选：{', '.join(presets)}"),
        ])
        return 1

    s = presets[key]
    url = reg["release"]["base_url"] + s["zip"]
    base = Path(out_dir) if out_dir else Path(os.path.expanduser("~")) / ".aipc-skills"
    install_dir = base / key
    install_dir.mkdir(parents=True, exist_ok=True)

    try:
        import urllib.request
        req = urllib.request.Request(url, headers={"User-Agent": "learning-bot/1.0"})
        with urllib.request.urlopen(req, timeout=60) as resp:
            payload = resp.read()
        with zipfile.ZipFile(io.BytesIO(payload)) as zf:
            zf.extractall(install_dir)
        emit([
            ("status", "ok"),
            ("action", "install"),
            ("skill", key),
            ("url", url),
            ("install_dir", str(install_dir)),
        ])
        return 0
    except Exception as e:  # network/unzip failure - stay honest, hand back the URL
        emit([
            ("status", "error"),
            ("action", "install"),
            ("skill", key),
            ("url", url),
            ("install_dir", str(install_dir)),
            ("reason", f"{type(e).__name__}: {e}（可手动下载该 zip 到 install_dir 后解压）"),
        ])
        return 1


def main():
    ap = argparse.ArgumentParser(description="Learning Bot launcher / router")
    g = ap.add_mutually_exclusive_group(required=True)
    g.add_argument("--menu", action="store_true", help="打印推荐给用户的预设问题")
    g.add_argument("--route", metavar="TEXT", help="对一句用户输入做路由建议")
    g.add_argument("--install", metavar="KEY", help="下载并解压对应的 aipc-skill")
    ap.add_argument("--out-dir", default=None, help="--install 的目标目录（默认 ~/.aipc-skills）")
    args = ap.parse_args()

    reg = load_registry()
    if args.menu:
        cmd_menu(reg)
        return 0
    if args.route is not None:
        cmd_route(reg, args.route)
        return 0
    if args.install is not None:
        return cmd_install(reg, args.install, args.out_dir)
    return 0


if __name__ == "__main__":
    sys.exit(main())
