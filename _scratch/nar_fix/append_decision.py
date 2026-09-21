# -*- coding: utf-8 -*-
TXN = r"I:\工作项目\shellstrom2\.workbuddy\memory\2026-09-21\1641_开场剧本真机缺陷修复与真机验收探针.md"
BLOCK = """
**主人决定（16:53）**：**不改**，留给 VFX 会话自己修 —— 避免两个会话同时写同一文件互相覆盖。
转达要点就这么一句：`src/vfx/VfxMuzzleFlash3D.gd:158` 与 `src/vfx/VfxImpact3D.gd:131` 的 `clamp(` 改 `clampf(`（各 1 行），
两处一改，12 条「Cannot infer the type」+ 2 条「inferred from a Variant value」全消。
⚠️ 在修好之前，这两个脚本**解析失败 ⇒ 枪口火光与命中特效在游戏里是哑的**。
"""
raw = open(TXN, "rb").read()
had = b"\r\n" in raw
sep = b"" if raw[-2:] == b"\r\n" else b"\r\n"
enc = (BLOCK.replace("\r\n", "\n").replace("\n", "\r\n") if had else BLOCK).encode("utf-8")
open(TXN, "ab").write(sep + enc)
b = open(TXN, "rb").read()
print("decision recorded; CR=%d LF=%d dbl=%d" % (b.count(b"\r"), b.count(b"\n"), b.count(b"\r\r\n")))
