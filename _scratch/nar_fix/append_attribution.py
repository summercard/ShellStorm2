# -*- coding: utf-8 -*-
import os
TXN = r"I:\工作项目\shellstrom2\.workbuddy\memory\2026-09-21\1641_开场剧本真机缺陷修复与真机验收探针.md"

BLOCK = """
## 8. 更正 / 追加：那批 VFX 解析错误的**归因定论**（16:51 主人追问）

主人拿报错行号追问「这些报错是这次修出来的吗」。**不是。** 已用 git 取证定死：

- 报错行号 **158/164/165/169/170/175/182** 与 `src/vfx/VfxMuzzleFlash3D.gd` **逐行吻合**（另有 `VfxImpact3D.gd:131/137/143/150`）。
- **本轮改动集里零个 `src/vfx/`**；`git show HEAD:` 该文件里**根本没有 `var fg/fl/pg/pl/rs/dist :=` 这些行**（count=0）。
- 差异带 `+const _ASSET_VERSION := "v002"` + `_on_activate` 形参改名（`size: float` → `_size: float`）⇒ 是**并发的 VFX v002 升级**在改。

**根因（1 行引爆 12 行）**：
```gdscript
var t := clamp(elapsed / total, 0.0, 1.0)   # ← clamp() 是全局函数、返回 Variant
```
`clamp()`（非 `clampf()`）返回 **Variant**，而项目开了 `treat_warnings_as_errors` ⇒ 第 158 行报「inferred from a Variant value」，
随后所有 `* t` 的表达式 `fg/fl/pg/pl/rs/dist` 全部退化成 Variant ⇒ 「Cannot infer the type」。`VfxImpact3D.gd:131` 同源。

**项目自身约定是 `clampf()`**（返回 float）：`CombatEffect3D.gd:70`、`Projectile3D.gd:233`、`WeaponModel3D.gd:353` 等都用 `clampf`。
⇒ 修法就是把那两处 `clamp(` 换成 `clampf(`（或写 `var t: float := clamp(...)`）。**两行**。

⚠️ 该文件属**并发会话在改的在途件**，本会话**未动**；已向主人报告并等指示（不擅自改他人在途文件）。
"""

raw = open(TXN, "rb").read()
had = b"\r\n" in raw
sep = b"" if raw[-2:] == b"\r\n" else b"\r\n"
enc = (BLOCK.replace("\r\n", "\n").replace("\n", "\r\n") if had else BLOCK).encode("utf-8")
with open(TXN, "ab") as fh:
    fh.write(sep + enc)
b = open(TXN, "rb").read()
print("appended 1641; CR=%d LF=%d dbl=%d" % (b.count(b"\r"), b.count(b"\n"), b.count(b"\r\r\n")))
