# -*- coding: utf-8 -*-
"""Resolve a pipeline by DISCOVERING stages from openvino_notebooks (no baked catalog).

Input:
  --slug a[,b,c]   one or more notebook folder slugs (comma-separated = compose in order)
  --goal "text"    free-form goal; matched against the repo's notebooks/README.md index
Discovery: for each slug, scan notebooks/<slug>/*.ipynb + requirements.txt for model
references (from_pretrained("id") / snapshot_download("id") / OVModelForXxx) and infer
per-stage {role, model_id}. Roles drive device/precision policy. No hardcoded model IDs.

--repo <path> points at a cloned openvino_notebooks. Without it, emit an honest
{ok:false, reason:"repo-required"} rather than fabricating a plan. stdlib-only.
"""
import argparse, json, os, re, sys

DEVICE = {"llm": "GPU", "encoder": "GPU", "retriever": "CPU", "preprocess": "CPU", "postprocess": "CPU"}
PRECISION = {"llm": "INT4", "encoder": "INT8", "retriever": "INT8", "preprocess": "FP16", "postprocess": "FP16"}

# id-substring / class hints → stage role (order matters: first match wins)
ROLE_HINTS = [
    ("llm", ("causallm", "forcausal", "-instruct", "-chat", "qwen", "llama", "mistral", "gemma", "phi-")),
    ("encoder", ("whisper", "asr", "wav2vec", "clip", "vision", "vit", "sam", "grounding", "dino")),
    ("retriever", ("embedding", "bge", "reranker", "rerank", "e5-", "gte-")),
    ("postprocess", ("tts", "melo", "vocoder", "openvoice", "vae", "hifigan")),
]
# Tolerate escaped quotes: .ipynb stores cell source as JSON, so quotes appear as \"
MODEL_RE = re.compile(r'(?:from_pretrained|snapshot_download)\(\s*\\?["\']([\w\-.]+/[\w\-.]+)\\?["\']')
OVCLASS_RE = re.compile(r'OVModelFor(\w+)')


def _role_for(model_id, ov_classes):
    low = model_id.lower()
    # per-model id keywords are most specific -> check first
    for role, keys in ROLE_HINTS:
        if any(k in low for k in keys):
            return role
    # fall back to OVModel class hints seen in the notebook (blob-wide, less specific)
    for cls in ov_classes:
        c = cls.lower()
        if "causal" in c:
            return "llm"
        if "featureextraction" in c:
            return "retriever"
    return "encoder"


def _discover_slug(repo, slug):
    """Return list of {role, name, model_id} discovered from notebooks/<slug>/."""
    nb_dir = os.path.join(repo, "notebooks", slug)
    if not os.path.isdir(nb_dir):
        return None
    text = []
    for root, _dirs, files in os.walk(nb_dir):
        for fn in files:
            if fn.endswith((".ipynb", ".py", ".txt", ".md")):
                try:
                    text.append(open(os.path.join(root, fn), encoding="utf-8", errors="ignore").read())
                except Exception:
                    pass
    blob = "\n".join(text)
    ov_classes = OVCLASS_RE.findall(blob)
    seen, stages = set(), []
    for mid in MODEL_RE.findall(blob):
        if mid in seen:
            continue
        seen.add(mid)
        role = _role_for(mid, ov_classes)
        stages.append({"role": role, "name": mid.split("/")[-1], "model_id": mid})
    return stages  # possibly [] if the notebook fetches models dynamically


def _match_goal(repo, goal):
    """Pick the best slug(s) from notebooks/README.md by keyword overlap."""
    idx = os.path.join(repo, "notebooks", "README.md")
    if not os.path.isfile(idx):
        return []
    words = set(re.findall(r"[a-z0-9]+", goal.lower()))
    best, best_score = None, 0
    for line in open(idx, encoding="utf-8", errors="ignore"):
        m = re.search(r"notebooks/([\w\-.]+)/", line)
        if not m:
            continue
        slug = m.group(1)
        score = sum(1 for w in words if w in slug or w in line.lower())
        if score > best_score:
            best, best_score = slug, score
    return [best] if best else []


def apply_policy(stages, device=None, precision=None):
    out = []
    for st in stages:
        r = st["role"]
        out.append({"role": r, "name": st["name"], "model_id": st.get("model_id"),
                    "device": device or DEVICE.get(r, "CPU"),
                    "precision": precision or PRECISION.get(r, "FP16"),
                    "from_notebook": st.get("from_notebook")})
    return out


def resolve(args):
    if not args.repo or not os.path.isdir(os.path.join(args.repo, "notebooks")):
        return {"ok": False, "reason": "repo-required",
                "note": "clone openvino_notebooks and pass --repo (run.ps1 does this)"}

    slugs = []
    if args.slug:
        slugs = [s.strip() for s in args.slug.split(",") if s.strip()]
    elif args.goal:
        slugs = _match_goal(args.repo, args.goal)
        if not slugs:
            return {"ok": False, "reason": "goal-unresolved", "input": args.goal}
    else:
        return {"ok": False, "reason": "no-input"}

    stages, seen, missing = [], set(), []
    for slug in slugs:
        found = _discover_slug(args.repo, slug)
        if found is None:
            missing.append(slug)
            continue
        for st in found:
            if st["model_id"] in seen:
                continue
            seen.add(st["model_id"])
            st["from_notebook"] = slug
            stages.append(st)
    if missing:
        return {"ok": False, "reason": "slug-not-found", "missing": missing}

    return {"ok": True, "kind": ("multi" if len(slugs) > 1 else "slug"),
            "pipeline": "+".join(slugs), "slugs": slugs,
            "stages": apply_policy(stages, args.device, args.precision)}


def main():
    ap = argparse.ArgumentParser(description="Discover a pipeline from openvino_notebooks.")
    ap.add_argument("--slug")
    ap.add_argument("--goal")
    ap.add_argument("--device", choices=["NPU", "GPU", "CPU"])
    ap.add_argument("--precision", choices=["INT4", "INT8", "FP16"])
    ap.add_argument("--repo", help="path to a cloned openvino_notebooks repo")
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--out")
    args = ap.parse_args()

    result = resolve(args)
    print(json.dumps(result, ensure_ascii=False, indent=2))
    if not result.get("ok"):
        print("\n[resolve] not resolved: %s" % result.get("reason"))
        return 1

    print("\n[resolve] Pipeline: %s  (%d stage%s%s)" % (
        result["pipeline"], len(result["stages"]),
        "" if len(result["stages"]) == 1 else "s",
        "" if len(result["slugs"]) == 1 else ", multi"))
    for i, st in enumerate(result["stages"], 1):
        print("  %d. %-11s %-28s -> %s / %s  [nb: %s]" % (
            i, st["role"], st["model_id"] or st["name"], st["device"],
            st["precision"], st["from_notebook"]))
    if not result["stages"]:
        print("  (no static model ids found — this notebook fetches models dynamically;"
              " optimize.py will need explicit --model or notebook execution.)")
    if args.out:
        json.dump(result, open(args.out, "w", encoding="utf-8"), ensure_ascii=False, indent=2)
        print("[resolve] wrote %s" % args.out)
    return 0


if __name__ == "__main__":
    sys.exit(main())
