"""把弹壳 PBR 定档（metallic=0.8 / roughness=0.6）回写进 14.6 规范与 MODULE_INDEX。

二进制读写，保 CRLF 纯度（禁文本模式重写已含 CRLF 的文件）。
"""
from pathlib import Path

root = Path(r"I:\工作项目\shellstrom2\ShellStorm2")

# --- 1) 14.6 规范：版本历史新增 v002.3 ---
spec = root / "docs/v0.1/14.6_特效系统与制作规范.md"
raw = spec.read_bytes()
text = raw.decode("utf-8")
assert "\r\n" in text, "预期 CRLF"
assert "\r\r\n" not in text, "文件已有 CRCRLF，先修"

anchor = "| 2026-09-22 | v002.2 |"
idx = text.index(anchor)
line_end = text.index("\r\n", idx) + 2
new_row = (
    "| 2026-09-22 | v002.3 | 弹壳 `VFX-SHELL-CASING-3D` 材质定档（业主指定）：**金属度 metallic=0.8、"
    "反光度（roughness 通道）=0.6**，壳体/底缘/底火三件统一，原先三件各自分散的数值收敛为单一常量组 "
    "`VfxShellCasing3D.SHELL_METALLIC` / `SHELL_ROUGHNESS`，各件仅保留基色差异；"
    "`get_presentation_snapshot()` 增补 PBR 真值（读已挂载材质）；专项验收新增 PBR 断言"
    "（期望值硬编码在验收侧，防自印证）并附反向对照 |\r\n"
)
assert "v002.3" not in text, "v002.3 已存在，勿重复插入"
text = text[:line_end] + new_row + text[line_end:]
spec.write_bytes(text.encode("utf-8"))
print("SPEC_OK", "v002.3" in spec.read_text(encoding="utf-8"))

# --- 2) MODULE_INDEX：VFX-POOL 行补 PBR 口径 ---
mi = root / "docs/v0.1/MODULE_INDEX.md"
mraw = mi.read_bytes()
mtext = mraw.decode("utf-8")
assert "\r\r\n" not in mtext, "文件已有 CRCRLF，先修"
old = "（由 `WeaponModel3D` 开火链生成，经 `VfxPool3D` 回收，纯视觉无碰撞体）"
new = (
    "（由 `WeaponModel3D` 开火链生成，经 `VfxPool3D` 回收，纯视觉无碰撞体；"
    "PBR 定档 金属度 0.8 / 反光度 roughness 0.6，三件统一）"
)
assert mtext.count(old) == 1, f"锚点命中 {mtext.count(old)} 次，预期 1"
mtext = mtext.replace(old, new)
mi.write_bytes(mtext.encode("utf-8"))
print("MODULE_INDEX_OK", "PBR 定档 金属度 0.8" in mi.read_text(encoding="utf-8"))

# --- 3) 行尾复验 ---
for f in (spec, mi):
    b = f.read_bytes()
    cr = b.count(b"\r")
    lf = b.count(b"\n")
    print(f.name, "CR", cr, "LF", lf, "diff", cr - lf, "CRCRLF", b.count(b"\r\r\n"))
