import json, pathlib, sys

D = pathlib.Path(r"I:\工作项目\shellstrom2\ShellStorm2\_scratch\tex512")


def cmp(name):
    b = json.loads((D / f"fp_{name}_before.json").read_text(encoding="utf-8"))
    a = json.loads((D / f"fp_{name}_after.json").read_text(encoding="utf-8"))
    print(f"=== {name} ===")
    keys = sorted(set(b) | set(a))
    bad = []
    for k in keys:
        if k in ("images", "counts"):
            continue
        if b.get(k) != a.get(k):
            bad.append(k)
            print("  CHANGED", k)
            print("    before:", json.dumps(b.get(k), ensure_ascii=False)[:200])
            print("    after :", json.dumps(a.get(k), ensure_ascii=False)[:200])
        else:
            print("  same   ", k, json.dumps(b.get(k), ensure_ascii=False)[:110])
    print("  counts before:", b.get("counts"))
    print("  counts after :", a.get("counts"))
    print("  images before:", json.dumps({k: v["size"] for k, v in b["images"].items()}, ensure_ascii=False))
    print("  images after :", json.dumps({k: v["size"] for k, v in a["images"].items()}, ensure_ascii=False))
    print("  RESULT:", "FAIL " + str(bad) if bad else "PASS 骨架/几何/权重/动作逐项一致")
    return not bad


ok = True
for n in ("model", "anim"):
    ok &= cmp(n)
sys.exit(0 if ok else 1)
