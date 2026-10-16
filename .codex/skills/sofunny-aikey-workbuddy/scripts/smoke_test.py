#!/usr/bin/env python3
"""Sofunny AIKey 接入冒烟测试。

用 ~/.workbuddy/models.json 里的 apiKey 对 WorkBuddy 实际使用的端点
/v1/chat/completions 发一次最小推理请求，确认模型真的能出内容。

用法:
    python3 smoke_test.py [模型id ...]
    # 默认: deepseek-v4-flash glm-4.7 qwen3.7-max
退出码: 0 至少一个成功 / 1 全部失败
"""
import json
import os
import sys
import urllib.error
import urllib.request

CONFIG = os.path.expanduser("~/.workbuddy/models.json")
URL = "https://llm-api-proxy.hnfunny.com/v1/chat/completions"
DEFAULT_MODELS = ["deepseek-v4-flash", "glm-4.7", "qwen3.7-max"]

try:
    models = json.load(open(CONFIG, encoding="utf-8"))
    KEY = models[0]["apiKey"]
    known = {m["id"] for m in models}
except Exception as e:
    print(f"✗ 无法读取 {CONFIG}: {e}")
    sys.exit(1)

targets = sys.argv[1:] or DEFAULT_MODELS
unknown = [t for t in targets if t not in known]
if unknown:
    print(f"  · 注意：{unknown} 不在本地配置中，仍会尝试调用\n")

passed = 0
for mid in targets:
    payload = json.dumps({
        "model": mid,
        "messages": [{"role": "user", "content": "只回复两个字：可用"}],
        # 推理模型会先花掉思考 token，预算太小会导致 content 为空（假失败），故给足 256
        "max_tokens": 256,
        "stream": False,
    }).encode()
    req = urllib.request.Request(URL, data=payload, headers={
        "Authorization": f"Bearer {KEY}",
        "Content-Type": "application/json",
    })
    try:
        with urllib.request.urlopen(req, timeout=60) as resp:
            d = json.loads(resp.read().decode())
            content = (d["choices"][0]["message"].get("content") or "").strip()
            u = d.get("usage") or {}
            reason = (u.get("completion_tokens_details") or {}).get("reasoning_tokens")
            note = f"（其中思考 token {reason}）" if reason else ""
            print(f"[{mid}] HTTP 200 ✓ 内容={content[:20]!r} "
                  f"tokens={u.get('prompt_tokens')}→{u.get('completion_tokens')} {note}")
            passed += 1
    except urllib.error.HTTPError as e:
        print(f"[{mid}] HTTP {e.code} ✗ {e.read().decode(errors='replace')[:200]}")
    except Exception as e:
        print(f"[{mid}] 请求异常 ✗ {type(e).__name__}: {e}")

print(f"\n冒烟结果: {passed}/{len(targets)} 通过")
if passed == 0:
    print("全部失败 → 优先检查 Key 是否失效、内网/VPN 是否可达，而不是模型清单。")
sys.exit(0 if passed else 1)
