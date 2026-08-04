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
    """纯开发意图短语：**产出物是开发资产**（环境 / notebook / 模型文件 / 量化 IR /
    性能报告）时才算。这类需求没法拿 14 个预设原子能力当基础，只能直接走 dev skill。

    注意：'部署 / 流水线 / pipeline / serve' 曾经在这个列表里，现在**故意移走**了 ——
    「把 asr→llm→tts 组成流水线并部署成服务」是可以拿预设原子能力搭出来的，应当走
    compose 并把 PIPE 当辅助（见 _assist_for），而不是整个交给 dev skill 从零开发。
    """
    return any(w in t for w in ("下载模型", "找模型", "download model",
                                "搭环境", "配置环境", "安装环境", "配好环境",
                                "基准测试", "benchmark", "找瓶颈", "量化",
                                "notebook", "教程"))


def _match_synthesis(reg, t):
    """内容合成类需求（PRD / 培训材料 / 学习路径）：产出物是散文文档，没有可安装的 skill，
    也没有 [SKILL_RESULT] 可产出 —— 真正干活的是 agent 自己的写作能力，skill 只能用
    content-fetch 抓真实 notebook/示例当素材。

    返回命中的 deliverable id；未命中返回 None。

    注意：'学习路径' 曾经在 _has_dev_phrase() 里，现已移到这里统一管，避免两处打架。
    """
    best, best_sc = None, 0
    for s in reg.get("synthesis_signals", []):
        sc = _score(t, s.get("keywords", []))
        if sc > best_sc:
            best, best_sc = s, sc
    return best["id"] if best else None


def _assist_for(t):
    """辅助（不是接管）：预设原子能力仍是主体，这些 dev skill 只负责补缺口。"""
    assist = []
    if any(w in t for w in ("部署", "服务", "常驻", "流水线", "pipeline", "serve",
                            "优化", "加速", "端到端")):
        assist.append("openvino-pipeline-optimization")
    if any(w in t for w in ("没装", "装不上", "环境", "第一次用", "还没配")):
        assist.append("openvino-environment-management")
    if any(w in t for w in ("缺模型", "没有模型", "换个模型", "换模型", "找个模型")):
        assist.append("openvino-content-fetch")
    return assist


def _match_combo(reg, t):
    """配方表命中：覆盖「会议纪要」「字幕助手」这类没有直白关键词、单靠多命中兜不住的说法。
    返回 (combo, 命中关键词数)；未命中返回 (None, 0)。"""
    best, best_sc = None, 0
    for c in reg.get("combos", []):
        sc = _score(t, c.get("keywords", []))
        if sc > best_sc:
            best, best_sc = c, sc
    return best, best_sc


def _match_gaps(reg, t):
    """缺口识别：这些能力 14 个预设原子覆盖不到，需要参考 dev skill 单独开发。
    命中缺口**不等于**放弃预设能力 —— 能被预设覆盖的阶段照常用预设原子，
    只有缺口阶段才单独开发。"""
    return [g["id"] for g in reg.get("gap_signals", [])
            if _score(t, g.get("keywords", [])) > 0]


def route(reg, text):
    t = (text or "").lower()

    # Hardware boundary: only Intel AIPC (Windows) is supported locally. If the user
    # explicitly names an unsupported host (Apple Silicon / macOS / discrete NVIDIA /
    # Linux desktop), return clarify BEFORE any preset/dev routing so the agent is
    # forced to confirm hardware rather than silently mapping it to a preset skill.
    non_intel_markers = (
        "m3 macbook", "m3 mac", "m2 macbook", "m2 mac", "m1 macbook", "m1 mac",
        "m4 macbook", "m4 mac", "macbook", "macos", "mac os", "apple silicon",
        "apple m1", "apple m2", "apple m3", "apple m4",
    )
    if any(m in t for m in non_intel_markers):
        return {"scope": "clarify", "target": "", "matched": "false",
                "reason": "仅支持 Intel AIPC (Windows)；当前输入提到非 Intel 硬件，请确认硬件平台"}

    # 内容合成类（PRD / 培训材料 / 学习路径）必须在 combo / preset / dev 之前判定。
    # 否则「给一个端侧会议纪要总结功能写个 PRD」里的"会议纪要"会先被 combo 抢走，
    # 路由成 preset/asr —— 用户要的是一份文档，弱 agent 却跑去装 ASR skill 做推理。
    deliverable = _match_synthesis(reg, t)
    if deliverable:
        return {
            "scope": "synthesize", "target": "openvino-content-fetch", "targets": [],
            "assist": [], "gaps": [], "deliverable": deliverable, "matched": "true",
            "reason": ("内容合成类需求：用 content-fetch 抓真实 notebook/示例做素材，"
                       "正文由 agent 自己写并标注来源；不要安装任何 preset skill，"
                       "也不要搭环境 / 下载模型 / 部署服务"),
        }

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

    # ------------------------------------------------------------------
    # 核心原则：14 个预设 skill 是**原子能力**，优先拿它们当基础拼装；三个开发类 skill
    # 只在预设能力搭不出来、或链条上有缺口时作为**辅助**出现。判断顺序：
    #   1) 产出物是开发资产（环境/notebook/模型文件/量化IR/性能报告）→ dev
    #   2) 命中配方表 → compose
    #   3) 命中 ≥2 个不同预设原子 → compose（按 flow_order 排序）
    #   4) 命中 1 个预设原子 → preset
    #   5) 都没有 → dev / clarify
    # 缺口（gap_signals）不会否决前面的结论：能被预设覆盖的阶段照常用预设原子，
    # 缺口阶段单独走 dev 开发，由 gaps= 字段告诉 agent 哪几段要自己做。
    # ------------------------------------------------------------------
    assist = _assist_for(t)
    gaps = _match_gaps(reg, t)
    order = {s["key"]: s.get("flow_order", 5) for s in reg["preset_skills"]}

    def _finish(res):
        """统一补上 targets / assist / gaps / deliverable 四个字段。"""
        res.setdefault("targets", [])
        res.setdefault("deliverable", "")   # 只有 scope=synthesize 才非空
        merged = list(assist)
        # 有缺口就必须把 FETCH/PIPE 带上：缺口阶段要找模型 + 自己接进流水线。
        if gaps:
            for k in ("openvino-content-fetch", "openvino-pipeline-optimization"):
                if k not in merged:
                    merged.append(k)
        res["assist"] = merged
        res["gaps"] = gaps
        return res

    if preset_hits and not dev_override:
        # 2) 配方表优先 —— 它把 stages 顺序写死，比 flow_order 自动排序更可靠。
        combo, combo_sc = _match_combo(reg, t)
        if combo and combo_sc > 0:
            stages = list(combo["stages"])
            return _finish({
                "scope": "compose" if len(stages) > 1 else "preset",
                "target": stages[0], "targets": stages, "matched": "true",
                "reason": f"命中组合配方「{combo['name_cn']}」，以预设原子能力为基础拼装",
            })

        # 3) 多原子命中 → 组合。先按 key 去重（OCR 的 npu/gpu 变体归一成一个）。
        seen, keys = set(), []
        for _sc, k in preset_hits:
            nk = normalize_ocr(k)
            if nk not in seen:
                seen.add(nk)
                keys.append(nk)
        if len(keys) > 1:
            stages = sorted(keys, key=lambda k: (order.get(k, 5), keys.index(k)))
            return _finish({
                "scope": "compose", "target": stages[0], "targets": stages,
                "matched": "true",
                "reason": f"命中 {len(stages)} 个预设原子能力，按数据流顺序组合",
            })

        # 4) 单原子
        return _finish({
            "scope": "preset", "target": keys[0], "targets": [keys[0]],
            "matched": "true",
            "reason": f"命中预设本地能力关键词（{preset_hits[0][0]} 个）",
        })

    # 配方表也能救回「一个预设关键词都没命中」的说法（如「帮我做个会议助手」）。
    if not dev_override:
        combo, combo_sc = _match_combo(reg, t)
        if combo and combo_sc > 0:
            stages = list(combo["stages"])
            return _finish({
                "scope": "compose" if len(stages) > 1 else "preset",
                "target": stages[0], "targets": stages, "matched": "true",
                "reason": f"命中组合配方「{combo['name_cn']}」，以预设原子能力为基础拼装",
            })

    if dev_hits:
        return _finish({"scope": "dev", "target": dev_hits[0][1], "matched": "true",
                        "reason": "产出物是开发资产，预设原子能力无法作为基础"})

    # dev_override 命中但 dev 关键词未命中：路由到最贴近的 dev skill（由 agent 解释边界）
    if dev_override:
        # 默认目标 = ENV（搭环境/装东西/解释硬件边界最常用），但下载模型类信号优先 FETCH
        if _has_download_intent(t):
            target = "openvino-content-fetch"
            reason = "检测到「下载/拉取 模型」强开发意图 → 路由到 FETCH"
        else:
            target = "openvino-environment-management"
            reason = "检测到越界/批处理/造假等强信号 → 路由到 ENV 由 agent 解释边界"
        return _finish({"scope": "dev", "target": target, "matched": "true",
                        "reason": reason})

    if preset_hits:
        best = normalize_ocr(preset_hits[0][1])
        return _finish({"scope": "preset", "target": best, "targets": [best],
                        "matched": "true", "reason": "命中预设本地能力关键词"})

    return _finish({"scope": "clarify", "target": "", "matched": "false",
                    "reason": "无法可靠归类，建议先向用户追问具体任务 / 模态 / 目标"})


def cmd_route(reg, text):
    r = route(reg, text)
    # target= 保留为「单个 key / 链首」，老的只读 target 的解析方不会炸；
    # targets= 是有序的完整链条，assist= 是辅助的 dev skill，gaps= 是预设覆盖不到、
    # 需要参考 dev skill 单独开发的阶段。
    emit([
        ("status", "ok"),
        ("action", "route"),
        ("matched", r["matched"]),
        ("scope", r["scope"]),
        ("target", r["target"]),
        ("targets", ",".join(r.get("targets") or [])),
        ("deliverable", r.get("deliverable") or ""),
        ("assist", ",".join(r.get("assist") or [])),
        ("gaps", ",".join(r.get("gaps") or [])),
        ("reason", r["reason"]),
    ])


QUESTIONS_FILE = HERE / "questions.json"


def _emit_questions(skill, qtype, blocks):
    """Emit a [SKILL_QUESTIONS] block (same contract as the shared questions.ps1)."""
    print("[SKILL_QUESTIONS]")
    print(f"skill={skill}")
    print(f"type={qtype}")
    print(f"count={len(blocks)}")
    print("data=" + json.dumps(blocks, ensure_ascii=False))
    print("[/SKILL_QUESTIONS]")


def _preset_block(reg):
    """Build the preset (recommend) block from the registry — single source of truth."""
    opts = [
        {"key": s["key"], "label": s["name_cn"], "example": s["question"]}
        for s in reg["preset_skills"]
    ]
    return {
        "type": "preset",
        "id": "menu",
        "prompt": "你可以直接问我这些本地能力（每条对应一个在 Intel AIPC 上离线运行的 skill）：",
        "multiselect": False,
        "options": opts,
    }


def cmd_questions(reg, qtype):
    """Emit prepared questions. preset comes from the registry; preflight/clarify from
    scripts/questions.json. Offline / network-free."""
    extra = {}
    if QUESTIONS_FILE.exists():
        with open(QUESTIONS_FILE, "r", encoding="utf-8") as f:
            extra = json.load(f)
    preset = [_preset_block(reg)]
    preflight = extra.get("preflight", [])
    clarify = extra.get("clarify", [])
    if qtype == "preset":
        blocks = preset
    elif qtype == "preflight":
        blocks = preflight
    elif qtype == "clarify":
        blocks = clarify
    else:  # all
        blocks = preset + preflight + clarify
    _emit_questions("learning-bot", qtype, blocks)
    return 0


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
    g.add_argument("--questions", metavar="TYPE",
                   choices=["preset", "preflight", "clarify", "all"],
                   help="输出准备好的问题（preset/preflight/clarify/all），[SKILL_QUESTIONS] 契约")
    ap.add_argument("--out-dir", default=None, help="--install 的目标目录（默认 ~/.aipc-skills）")
    args = ap.parse_args()

    reg = load_registry()
    if args.menu:
        cmd_menu(reg)
        return 0
    if args.route is not None:
        cmd_route(reg, args.route)
        return 0
    if args.questions is not None:
        return cmd_questions(reg, args.questions)
    if args.install is not None:
        return cmd_install(reg, args.install, args.out_dir)
    return 0


if __name__ == "__main__":
    sys.exit(main())
