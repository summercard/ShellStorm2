"""在 CHANGELOG 顶部插入「弹壳抛出落地 + PBR 定档」条目（二进制读写，保 CRLF）。"""
from pathlib import Path

root = Path(r"I:\工作项目\shellstrom2\ShellStorm2")
p = root / "docs/v0.1/development/CHANGELOG.md"
text = p.read_bytes().decode("utf-8")
assert "\r\r\n" not in text, "文件已有 CRCRLF，先修"
assert "VFX-SHELL-CASING-3D" not in text, "弹壳条目已存在，勿重复插入"

head = "# 游戏设计文档 v0.1 变更记录\r\n"
assert text.startswith(head), "文件头不符预期"

entry = (
    "\r\n"
    "## 2026-09-22｜新开枪反馈：弹壳抛出并落地（VFX-SHELL-CASING-3D），材质定档 金属度 0.8 / 反光度 0.6\r\n"
    "\r\n"
    "`WeaponModel3D._fire_now()` 每次成功开火新增生成 **1 枚弹壳**（命运复制波次与霰弹多弹丸不额外重复抛壳）。"
    "弹壳脱离武器挂点进入世界空间：初速度 `v = 2.1·right + 1.55·up + 0.22·forward`（从枪械右侧抛出），"
    "受 `g = 9.8 m/s²` 下落，命中地板后**最多 2 次小弹跳**再静止，`lifetime 3.2 s` 回池；"
    "落地判定优先走物理射线（collision layer 1），无场景碰撞时用 `context.floor_y` 兜底以避免穿地。"
    "出生点取枪械 `EjectionSocket`，缺失时回落 `TacticalSocket`；近战武器不抛壳。\r\n"
    "\r\n"
    "新增独立 Prefab `assets/art/vfx/combat_3d/vfx_shell_casing_root_top3d.tscn`"
    "（AssetID `VFX-SHELL-CASING-3D`，v001，黄铜圆柱 + 底缘环 + 底火，**纯视觉无碰撞体**）"
    "与脚本 `src/vfx/VfxShellCasing3D.gd`，注册为 `VfxPool3D.FX01_SHELL_CASING`（按 AssetID 路由，调用方禁裸字符串）。\r\n"
    "\r\n"
    "**材质定档（业主指定）**：金属度 `metallic = 0.8`、反光度（roughness 通道）`= 0.6`，"
    "壳体 / 底缘 / 底火**三件统一**，各件仅保留基色差异；原先三件各自的分散数值收敛为单一常量组 "
    "`VfxShellCasing3D.SHELL_METALLIC` / `SHELL_ROUGHNESS`。\r\n"
    "\r\n"
    "验收 `verify_combat_vfx_toon_v002`（`samples=12`）新增弹壳用例（AssetID/版本、主体 mesh、重力、右侧飞出、"
    "不穿地、最大弹跳、无碰撞体、真实开火接线）与 **PBR 真值断言**（读已挂载材质，期望值硬编码在验收侧以防止"
    "「期望引用被测常量」的自印证）；两轮反向对照均精准命中后还原：右向初速度归零 → 红（实测 0.000 m/s），"
    "PBR 改 0.5/0.2 → 红（实测 0.500/0.200）；`verify_vfx_pool_lifecycle` 同步复绿，两者 headless 退出码 0。\r\n"
    "\r\n"
    "文档与台账：`docs/v0.1/14.6_特效系统与制作规范.md` §6.1 迁移表 + §10 版本历史 v002.2 / v002.3；"
    "`docs/v0.1/MODULE_INDEX.md` 的 `VFX-POOL` 行补弹壳与 PBR 口径；账本 `ShellStorm2_特效账本_v001.xlsx` "
    "登记 `资产主表` row 22、`3D-特效` FX01-07、`域变更日志` v0.1.3 / v0.1.4，门禁 `check_asset_registry.py --ledger vfx` 无新增红项。\r\n"
    "\r\n"
    "<br>\r\n"
)
text = head + entry + text[len(head):]
p.write_bytes(text.encode("utf-8"))
b = p.read_bytes()
print("CHANGELOG_OK", "VFX-SHELL-CASING-3D" in b.decode("utf-8"))
print("CR", b.count(b"\r"), "LF", b.count(b"\n"), "diff", b.count(b"\r") - b.count(b"\n"), "CRCRLF", b.count(b"\r\r\n"))
