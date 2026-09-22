"""把 2026-09-22 弹壳事务的可复用知识回写进 vfx-combat-effect-authoring skill 正本。

二进制读写，保 CRLF（本仓 skill 副本要求 CRLF 纯度）。
"""
from pathlib import Path

p = Path(r"C:\Users\zhuangmenghong\.workbuddy\skills\vfx-combat-effect-authoring\SKILL.md")
text = p.read_bytes().decode("utf-8")
assert "\r\r\n" not in text, "已有 CRCRLF，先修"
assert text.count("\n") == text.count("\r\n"), "行尾不是纯 CRLF"

steps = []


def rep(old: str, new: str, label: str) -> None:
    global text
    n = text.count(old)
    assert n == 1, f"[{label}] 锚点命中 {n} 次"
    text = text.replace(old, new, 1)
    steps.append(label)


# --- 0) frontmatter 描述补弹壳（可发现性）---
rep(
    "枪口花火、命中爆点、飞行子弹视觉、近战挥砍弧光、受击/治疗飘字、爆炸。",
    "枪口花火、命中爆点、飞行子弹视觉、近战挥砍弧光、弹壳抛出与落地、受击/治疗飘字、爆炸。",
    "frontmatter-desc",
)
rep(
    "VfxPool3D / VfxEffectBase3D / 特效验收 / 特效账本登记 / 14.6」这类问题。",
    "VfxPool3D / VfxEffectBase3D / 弹壳 / 抛壳 / 弹壳不落地 / 弹壳穿地 / 特效 PBR 材质 / 特效验收 / 特效账本登记 / 14.6」这类问题。",
    "frontmatter-triggers",
)

# --- 1) §2 真源表补弹壳行 ---
row_muzzle = (
    "| 枪口花火 | `VFX-MUZZLE-FLASH-3D` | `vfx_muzzle_flash_root_top3d.tscn` | "
    "`VfxMuzzleFlash3D.gd` | `WeaponModel3D._spawn_muzzle_effect()` | ✅ `FX01_MUZZLE_FLASH` |\r\n"
)
row_shell = (
    "| 弹壳抛出/落地 | `VFX-SHELL-CASING-3D` | `vfx_shell_casing_root_top3d.tscn` | "
    "`VfxShellCasing3D.gd` | `WeaponModel3D._fire_now()` → `_spawn_shell_casing()` | ✅ `FX01_SHELL_CASING` |\r\n"
)
rep(row_muzzle, row_muzzle + row_shell, "table-shell-row")

# --- 2) 子弹不进池段落后，补「弹壳为什么可以进池」---
rep(
    "旧 kind（如 `\"explosion\"`）必须抽成具名常量（`LEGACY_EFFECT_EXPLOSION`），别裸字符串。",
    "旧 kind（如 `\"explosion\"`）必须抽成具名常量（`LEGACY_EFFECT_EXPLOSION`），别裸字符串。\r\n"
    "**弹壳为什么可以进池**：它的生命周期由视觉自己了结（落地静止 → `lifetime` 到点回池），"
    "不像子弹那样另有一个 `ProjectilePool3D` 宿主 ⇒ 没有 double-free 风险。",
    "pool-note",
)

# --- 3) §3 步骤 2 补 PBR 定档两条 ---
rep(
    "- 几何优先复用 `src/vfx/ToonVfxGeometry.gd`（`core_mesh / flame_mesh / petal_mesh / ring_mesh / "
    "spark_mesh / spike_mesh / debris_mesh` + `toon_material()`，全部带缓存）。",
    "- 几何优先复用 `src/vfx/ToonVfxGeometry.gd`（`core_mesh / flame_mesh / petal_mesh / ring_mesh / "
    "spark_mesh / spike_mesh / debris_mesh` + `toon_material()`，全部带缓存）。\r\n"
    "- **PBR 参数走「单一常量组」**：一件资产的所有材质数值（`metallic` / `roughness` …）收敛成脚本顶部常量"
    "（如 `SHELL_METALLIC` / `SHELL_ROUGHNESS`），**件与件之间只允许基色差异**，一律经同一个 "
    "`_make_material(color)` 工厂出口。逐件散写数值 = 以后改一处漏两处（本事务初版就是三件各写各的）。\r\n"
    "- ⚠️ **术语口径**：「反光度」= `StandardMaterial3D.roughness` 通道（**不是** `metallic`、也不是 `specular`）。"
    "`WeaponModel3D._material(color, metallic, roughness)` 的第 3 参数就是它。代码与账本里两栏都要写全"
    "（`金属度 metallic=0.8 / 反光度 roughness=0.6`），只写「反光度 0.6」半年后没人知道映射到哪个通道。",
    "step2-pbr",
)

# --- 4) 新增 §5.5 抛出物类特效 ---
sec55 = (
    "## 5.5 抛出物类特效（弹壳）—— 脱离挂点进入世界空间（2026-09-22 落地）\r\n"
    "\r\n"
    "**与枪口花火正好相反**：枪口花火要**绑** `context.follow`（钉死在挂点上），弹壳必须**不绑任何跟随**，"
    "一次性取得初速度后完全由自己积分位置。别顺手给抛壳物也加 `follow` —— 加了它就永远钉在枪上不落地。\r\n"
    "\r\n"
    "契约（`VfxShellCasing3D` 已实现，可直接抄）：\r\n"
    "\r\n"
    "| 项 | 口径 |\r\n"
    "|---|---|\r\n"
    "| 出生点 | 调用方枪械的 `EjectionSocket`；缺失回落 `TacticalSocket`；程序生成枪用 "
    "`Vector3(width*0.62, height*0.20, -length*0.42)`；**近战武器直接 return 不抛壳** |\r\n"
    "| 初速度 | `v = 2.1·right + 1.55·up + 0.22·forward`（枪械 `global_basis` 基向量；"
    "forward 只给一点点前送，主要是右抛 + 上抛） |\r\n"
    "| 重力 | `GRAVITY := 9.8`，自积分 `v.y -= g*dt`；**不用 `RigidBody3D`**（Prefab 内禁碰撞体，纯视觉） |\r\n"
    "| 落地 | `PhysicsRayQueryParameters3D.create(from, to, FLOOR_MASK)`，`FLOOR_MASK = 1`；"
    "射线从当前位置打到「下一帧位置」 |\r\n"
    "| 无碰撞兜底 | `context.floor_y`（调用方传地板高度）。**仅在射线没命中且 `next.y <= floor_y + SHELL_RADIUS` 时**启用 |\r\n"
    "| 弹跳 | `MAX_BOUNCES := 2`；法向速度 `absf(normal_speed) <= REST_SPEED (0.12)` ⇒ 直接 `_settle()` 不再计次 |\r\n"
    "| 寿命 | `DEFAULT_LIFETIME := 3.2`，到点走基类回池 |\r\n"
    "\r\n"
    "三条实测坑：\r\n"
    "\r\n"
    "1. **弹跳计数别把「首次落地结算」也当成一次弹跳**：若在 `_land_or_bounce()` 里无条件 `_bounces += 1`，"
    "静止结算会被数成第 3 次 ⇒ 验收报「超过最大弹跳次数」的**假红**。只有真的反弹了才加：\r\n"
    "\r\n"
    "```gdscript\r\n"
    "if _bounces < MAX_BOUNCES and absf(normal_speed) > REST_SPEED:\r\n"
    "    _bounces += 1\r\n"
    "    # …反弹…\r\n"
    "else:\r\n"
    "    _settle()\r\n"
    "```\r\n"
    "\r\n"
    "2. **贴地判据半径必须等于几何真实半径**（本件 `CylinderMesh` r≈0.045 ⇒ `SHELL_RADIUS := 0.025`）。"
    "取大了会浮在地面上方，肉眼可见「悬空」。\r\n"
    "3. **`_on_tick(_elapsed, lifetime)` 给的是累计时间不是 dt**：要位移得自己转增量，并夹住卡帧尖峰，"
    "否则一次 0.5 s 卡顿会让弹壳瞬移穿过地板：\r\n"
    "\r\n"
    "```gdscript\r\n"
    "var dt: float = clampf(delta_elapsed - _last_tick_elapsed, 0.0, 1.0 / 15.0)\r\n"
    "_last_tick_elapsed = delta_elapsed\r\n"
    "```\r\n"
    "\r\n"
)
rep("## 6. 验收配方", sec55 + "## 6. 验收配方", "sec55")

# --- 5) §6 样本数与新增第 9 条断言 ---
rep("samples=9", "samples=12", "samples-count")
item9 = (
    "9. **PBR / 材质真值**（业主指定了具体数值时）：断言必须**读已挂载材质**"
    "（`mesh_instance.material_override.metallic`），且期望值**硬编码在验收侧**"
    "（`EXPECTED_SHELL_METALLIC := 0.8`），**另加一条** `脚本常量 == EXPECTED_*` 把常量本身也钉住；"
    "每件（壳体/底缘/底火）各查一遍。\r\n"
    "   ⛔ 反例（本事务初版写法）：`_expect(absf(snap.metallic - VfxShellCasing3D.SHELL_METALLIC) < 0.0001, …)` "
    "—— 期望引用被测常量 ⇒ 常量改成 0.5 时期望跟着变 0.5，**断言永远绿**。这个「自印证」模式对任何"
    "「期望值由被测代码自己给出」的断言都成立，不止 PBR。\r\n"
    "   辅助函数 `_material_float(node, \"metallic\")` **无材质时返 `-1.0` 哨兵**（返 0.0 会被当成合法值混过断言）。\r\n"
)
rep(
    "⚠️ `BlueprintRegistry.create_assembly_node()` 返回 `AssemblyNode`，**不能**直接喂 `configure_from_tree()`"
    "（它要 `WeaponAssemblyTree`）⇒ 测试一律用 `build_weapon_tree(gun_id, bullet_id)`。\r\n",
    "⚠️ `BlueprintRegistry.create_assembly_node()` 返回 `AssemblyNode`，**不能**直接喂 `configure_from_tree()`"
    "（它要 `WeaponAssemblyTree`）⇒ 测试一律用 `build_weapon_tree(gun_id, bullet_id)`。\r\n" + item9,
    "item9-pbr",
)

# --- 6) §7 账本 openpyxl 三条硬要求 ---
rep(
    "⚠️ 用 openpyxl 往返（`load_workbook` → 改 → `save`）会保留 DV 下拉与合并格；**改前 `shutil.copy2` 备份到 `_scratch/`**，改后回读校验。",
    "⚠️ 用 openpyxl 往返（`load_workbook` → 改 → `save`）会保留 DV 下拉与合并格；**改前 `shutil.copy2` 备份到 `_scratch/`**，改后回读校验。\r\n"
    "\r\n"
    "⚠️ **回写脚本三条硬要求**（2026-09-22 踩坑）：\r\n"
    "1. **样式复制必须用 `copy()`**：`cell._style` 是 openpyxl 的 `StyleArray`，**没有 `.copy()` 方法**"
    "（写 `x._style.copy()` 直接 `AttributeError` 中断，且中断点在 `save()` 之前 ⇒ 文件没坏但白干）。"
    "正确写法 `from copy import copy` → `dst._style = copy(src._style)`，并另拷 `dst.number_format = src.number_format`。\r\n"
    "2. **脚本必须幂等**：备注按「是否已含标记串」判重、日志行按「台账版本号列是否已存在」判重；"
    "否则重跑一次就多一段文字 / 多一行 `v0.1.4`。\r\n"
    "3. **新增行后要一起扩公式范围**：派生查重列（R/S）与总览公式的统计范围从 `$R$6:$R$<旧末行>` 扩到新末行，"
    "否则门禁报 `dedupe_result_formula_wrong` / `stale_overview_formula`。",
    "sec7-openpyxl",
)

# --- 7) §8 射线 API 坑 ---
rep(
    "- 脚本快照 / `.before.gd` **禁落 `res://` 内**（`class_name` 抢注 + class cache 被旧副本覆盖，本仓已发生两次事故）。",
    "- `PhysicsRayQueryParameters3D.create(from, to, mask)` **只有 3 个参数**；想「排除自身」也不能传第 4 个 "
    "`[get_rid()]`（本仓 Godot 4.6.3 报 `Function \"get_rid()\" not found in base self`）。"
    "弹壳是纯视觉 `Node3D`，本来就不需要排除。\r\n"
    "- 脚本快照 / `.before.gd` **禁落 `res://` 内**（`class_name` 抢注 + class cache 被旧副本覆盖，本仓已发生两次事故）。",
    "sec8-rayquery",
)

# --- 8) §9 速查表补 5 行 ---
rep(
    "| 验收绿但游戏里是坏的 | 只测了机制层，没测调用方接线 | 加端到端接线探针（§6.8） |",
    "| 验收绿但游戏里是坏的 | 只测了机制层，没测调用方接线 | 加端到端接线探针（§6.8） |\r\n"
    "| 弹壳浮在地面上方不落地 | 贴地判据 `SHELL_RADIUS` 大于几何真实半径 | 按 `CylinderMesh` 实际半径取值 |\r\n"
    "| 验收报「弹跳超过最大次数」 | 首次落地结算被误计成一次弹跳 | 只在真的反弹时 `_bounces += 1`（§5.5） |\r\n"
    "| 弹壳穿地掉到无限深 | 探针场景没有物理地板，且没传 `floor_y` | 调用方传 `context.floor_y` 兜底 |\r\n"
    "| 弹壳钉在枪上不飞出去 | 顺手给抛壳物也绑了 `context.follow` | 抛出物**不绑跟随**，一次性初速度 |\r\n"
    "| 改了 PBR 常量但验收仍绿 | 期望值引用了被测脚本常量（自印证） | 期望硬编码在验收侧 + 额外钉常量（§6.9） |",
    "sec9-table",
)

p.write_bytes(text.encode("utf-8"))
b = p.read_bytes()
print("STEPS", steps)
print("CR", b.count(b"\r"), "LF", b.count(b"\n"), "CRCRLF", b.count(b"\r\r\n"))
print("LINES", b.decode("utf-8").count("\r\n"))
