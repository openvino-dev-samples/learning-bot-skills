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


def _has_download_intent(t):
    """强下载模型意图：'下载/拉/取' + '模型/权重/参数/IR'，中间允许插入 ≤4 个字符。
    解决 '下载一个 ASR 模型' 这类连字串匹配会漏掉的情况。"""
    triggers = ("下载", "拉取", "拉一个", "取一个", "get ", "fetch ", "download", "pull ")
    targets  = ("模型", "权重", "参数", " ir ", "(ir)", "openVINO ir")
    if not any(trig in t for trig in triggers):
        return False
    return any(tgt in t for tgt in targets)


def _has_out_of_scope_signal(t):
    """强越界信号：云端/不要本地/批量安装/造假 —— 这些都需要先让 agent 解释边界，
    路由层把它们引到 dev skill（由 agent 在 dev 阶段决定如何拒绝 / 收窄）。"""
    return any(w in t for w in (
        "云端", "云上", "调云", "api 做", "api进行", "用api", "用 api",
        "在线推理", "远程推理", "调用openai", "调 openai", "调chatgpt",
        "不用真跑", "直接告诉", "直接给", "伪造", "造假",
        "一次性全", "一次全", "批量安装", "全部安装", "全装", "把 14", "把14",
    ))


def _has_dev_phrase(t):
    """强开发意图短语：'下载模型'/'搭环境' 这类连字串必须出现。"""
    return any(w in t for w in ("下载模型", "找模型", "download model",
                                "搭环境", "配置环境", "安装环境", "配好环境",
                                "部署", "流水线", "pipeline", "基准测试", "benchmark",
                                "notebook", "教程", "学习路径"))


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
    # (e.g. "下载 ASR 模型" is a FETCH job, not the ASR skill). Layered check:
    #   1) 连字串开发短语（高置信度）
    #   2) '下载/拉' + '模型/IR' 模式（修复 "下载一个 ASR 模型" 漏召回）
    #   3) 越界信号（云端/批量安装/造假等）—— 也优先 dev，让 agent 在 dev 阶段解释边界
    dev_override = (
        _has_dev_phrase(t)
        or _has_download_intent(t)
        or _has_out_of_scope_signal(t)
    )

    if preset_hits and not dev_override:
        best = normalize_ocr(preset_hits[0][1])
        return {"scope": "preset", "target": best, "matched": "true",
                "reason": f"命中预设本地能力关键词（{preset_hits[0][0]} 个）"}

    if dev_hits:
        return {"scope": "dev", "target": dev_hits[0][1], "matched": "true",
                "reason": "超出预设本地能力，匹配到开发类 skill"}

    # dev_override 命中但 dev 关键词未命中：路由到最贴近的 dev skill（由 agent 解释边界）
    if dev_override:
        # 默认目标 = ENV（搭环境/装东西/解释硬件边界最常用），但下载模型类信号优先 FETCH
        if _has_download_intent(t):
            target = "openvino-content-fetch"
            reason = "检测到「下载/拉取 模型」强开发意图 → 路由到 FETCH"
        else:
            target = "openvino-environment-management"
            reason = "检测到越界/批处理/造假等强信号 → 路由到 ENV 由 agent 解释边界"
        return {"scope": "dev", "target": target, "matched": "true", "reason": reason}

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
