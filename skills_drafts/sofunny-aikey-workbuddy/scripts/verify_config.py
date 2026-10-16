#!/usr/bin/env python3
"""校验 ~/.workbuddy/models.json 与 sofunny-aikey-workbuddy 仓库清单的一致性。

用法:
    python3 verify_config.py [仓库路径]      # 默认从 ./models.json 读取仓库清单
退出码: 0 全部通过 / 1 存在不一致
"""
import json
import os
import sys

CONFIG = os.path.expanduser("~/.workbuddy/models.json")
EXPECTED_URL = "https://llm-api-proxy.hnfunny.com/v1"
ALLOWED_MISSING = {"apiKey"}

ok = True


def fail(msg):
    global ok
    ok = False
    print(f"  ✗ {msg}")


try:
    cur = json.load(open(CONFIG, encoding="utf-8"))
except Exception as e:
    print(f"✗ 无法解析 {CONFIG}: {e}")
    sys.exit(1)

print(f"配置文件: {CONFIG}")
print(f"✓ JSON 合法，条目数 {len(cur)}")

if not isinstance(cur, list) or not cur:
    fail("顶层应为非空数组")
    sys.exit(1)

# 基础字段检查
bad_url = [m["id"] for m in cur if m.get("url") != EXPECTED_URL]
bad_vendor = [m["id"] for m in cur if m.get("vendor") != "Custom"]
bad_proto = [m["id"] for m in cur if m.get("useCustomProtocol") is not False]
bad_tool = [m["id"] for m in cur if m.get("supportsToolCall") is not True]
for label, lst in (("url", bad_url), ("vendor", bad_vendor),
                   ("useCustomProtocol", bad_proto), ("supportsToolCall", bad_tool)):
    if lst:
        fail(f"{label} 异常: {lst}")
print("✓ url / vendor / useCustomProtocol / supportsToolCall 检查完成")

# apiKey
keys = {m.get("apiKey") or "" for m in cur}
if len(keys) != 1 or not next(iter(keys)).startswith("sk-"):
    fail(f"apiKey 不唯一或格式异常（共 {len(keys)} 种取值）")
else:
    k = next(iter(keys))
    print(f"✓ apiKey 唯一且已注入: {k[:8]}...{k[-4:]}")

# token 预算字段
missing_budget = [m["id"] for m in cur
                  if not isinstance(m.get("maxInputTokens"), int)
                  or not isinstance(m.get("maxOutputTokens"), int)]
if missing_budget:
    fail(f"maxInputTokens/maxOutputTokens 缺失或非整数: {missing_budget}")
else:
    print("✓ maxInputTokens / maxOutputTokens 均为整数")

# 与仓库清单比对
repo_path = sys.argv[1] if len(sys.argv) > 1 else "models.json"
if os.path.isfile(repo_path):
    repo = json.load(open(repo_path, encoding="utf-8"))
    r_ids = [m["id"] for m in repo]
    c_ids = [m["id"] for m in cur]
    if set(r_ids) - set(c_ids):
        fail(f"清单缺少模型: {sorted(set(r_ids) - set(c_ids))}")
    if set(c_ids) - set(r_ids):
        print(f"  · 本地多出（用户自建模型，正常）: {sorted(set(c_ids) - set(r_ids))}")
    rmap = {m["id"]: m for m in repo}
    diffs = []
    for m in cur:
        ref = rmap.get(m["id"])
        if not ref:
            continue
        for field, val in ref.items():
            if field in ALLOWED_MISSING:
                continue
            if m.get(field) != val:
                diffs.append(f"{m['id']}.{field}: 仓库={val} 本地={m.get(field)}")
    if diffs:
        fail("与仓库清单存在差异:\n      " + "\n      ".join(diffs))
    else:
        print(f"✓ 与仓库清单逐字段一致（{len(r_ids)} 个模型，除 apiKey）")
else:
    print(f"  · 未找到仓库清单 {repo_path}，跳过逐字段比对")

print()
print("结果: " + ("全部通过" if ok else "存在不一致，请检查上文 ✗ 项"))
sys.exit(0 if ok else 1)
