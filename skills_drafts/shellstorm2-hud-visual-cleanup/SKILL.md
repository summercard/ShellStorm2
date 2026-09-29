---
name: shellstorm2-hud-visual-cleanup
description: 在 ShellStorm2 战局 HUD 上做视觉清理——去掉面板背板/边框/霓虹角框、隐藏某个小面板、挪动面板位置，同时保证被探针 get_node 读取的节点不消失。当主人说"把 XX 的背板去掉 / 这个框也去掉 / 蓝色的背板去掉 / 时间去掉 / 头像去掉 / 挪到右上"且对象是战局 HUD（ReferenceCombatHUD 下）时使用。不用于启动页 MainEntryScreen3D。
agent_created: true
---

# ShellStorm2 战局 HUD 视觉清理

## 何时用

主人指着战局截图说「去掉背板 / 去掉框 / 去掉头像 / 这里的 XX 去掉 / 挪到右上」，对象是**战局 HUD**。

**先确认是哪个系统**：战局 HUD（`HUD/ReferenceCombatHUD`）与启动页 `MainEntryScreen3D` 是**两套东西**。
主人说「主界面」时要先看截图定系统，别改错地方。

## 铁律：只许隐藏 / 改样式，绝不许删节点

战局 HUD 是**纯代码运行时构建**的，根在 `HUD/ReferenceCombatHUD`（`_reference_hud_root`，`PRESET_FULL_RECT`、`z_index=100`）。
多枚**已注册的验收探针**直接 `get_node()`/`find_child()` 读这些节点，**删节点必红**。

必须先摸清依赖。已被探针读取、**不许删**的节点（写死引用位置）：

| 节点 | 引用探针（大致） | 允许的操作 |
|---|---|---|
| `minimap` / `DungeonMinimap3D` | 3d_parity_core / tactical_inventory_minimap_door_passability 等 | `visible=false` |
| `status_label` / `CurrentInfoPanel` | 多枚 | `visible=false`（`text` 仍可读写、零影响） |
| `PlayerStatusBlock` | reference_hud_fate_visual（size≤280） | 改样式；尺寸别超契约 |
| `CurrentWeaponPanel` / `QuickItemHUD_0` / `QuickItemHUD_1` | finite_ammo_flow（存在性 + 尺寸 + alpha 契约） | 改样式 |
| `SessionTimerPanel` | 无探针读它，但保留命名即可 | `visible=false` |
| `WorldDateTimeHUD` | base_overhaul_flow（`!= null`） | 改样式，**不许删** |
| `FlashlightBatteryPanel` / `BatteryCell_*` / `BatteryTimeLabel` | 3d_flashlight_charge_flow | 谨慎 |
| `FloorArrivalTitle` | tower_journey_polish | 谨慎 |
| `_full_map_control` | dual_weapon_quick_map_fate_flow | 谨慎 |

**判据：任何改动前先 grep `tests/verification/*.gd` 里有没有 `get_node`/`find_child` 指向要动的节点名。**
`visible=false` 时 `text`、`size`、`position` 仍可读，探针契约不受影响 —— 这是安全解。

## HUD「框」是两层叠出来的

一个面板的「框」通常由两层组成，去背板要**两层都处理**：

1. **StyleBox** —— `_make_hud_panel(accent, bg)` 产出的（深色底 + 彩色描边 + `shadow_size=7` 光晕）。
2. **霓虹角框** —— `_add_neon_frame(panel, cyan, 0.36, false)` 产出的 `NeonFrameControl`（青色角括号 + 扫描线）。

> 有的面板只有第 1 层（如 `WorldDateTimeHUD`），有的两层都有（如武器/快捷栏）。
> **改之前先确认这面板到底叠了几层**，漏掉一层就是「看着还在」。

## 两个 bare 助手（已内置，直接复用）

位于 `src/world3d/Dungeon3D.gd`（`TowerDescent3D` extends `Dungeon3D`，可继承使用），
`_make_hud_style` 之后：

```gdscript
func _make_bare_hud_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0)
	style.border_color = Color(0, 0, 0, 0)
	style.set_border_width_all(0)
	style.set_corner_radius_all(0)
	style.shadow_size = 0
	return style

func _make_bare_hud_panel() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override("panel", _make_bare_hud_style())
	return panel

func _outline_labels(labels: Array) -> void:
	for entry in labels:
		var label := entry as Label
		if label == null:
			continue
		label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.85))
		label.add_theme_constant_override("outline_size", 5)
```

**改样式**：把 `_make_hud_panel(...)` 换成 `_make_bare_hud_panel()`；若有 `_add_neon_frame(...)` 行**一并删掉**。
**改隐藏**：保留 `_make_bare_hud_panel()` + `_anchor_control(...)` + `add_child`，末尾 `panel.visible = false`，
并给一个**明确的 `panel.name`**（如 `"SessionTimerPanel"`）方便探针定位。

## 去背板必须补文字描边

背板去掉后文字直接压在浅色场景上会糊。**凡去掉背板且保留文字的，一律给文字补描边**：

```gdscript
label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.85))
label.add_theme_constant_override("outline_size", 5)
```

或用 `_outline_labels([label_a, label_b, ...])` 批量补。

## 挪动面板：先查尺寸契约，再定锚框

**动手前必须先查有没有探针断这个面板的尺寸。** 已知 `verify_finite_ammo_flow` 对
`CurrentWeaponPanel` 断言 `250 ≤ 宽 ≤ 312`、`44 ≤ 高 ≤ 59`。
原尺寸 281×47.2 是**被内容撑开**的；一旦挪位就会变成**由锚框决定** ⇒ 锚框算错直接红。

```
实际尺寸 = |offset_right - offset_left| × HUD_UI_SCALE(0.8)
```
想落在 250..312 → canvas 宽取 **313..390**。例：`350×70` → 实际 **280×56**，正好落带内。

两条易漏的配套动作：

1. **盒容器要显式右对齐**。`weapon_row.alignment = BoxContainer.ALIGNMENT_END`
   —— 内容（约 240）比面板（280）窄时，默认 `BEGIN` 会把内容**堆在左侧**、看着不像「贴右下角」。
2. **改完顺手量一次内容边界**（见「判据」里的 bbox 量法），确认右缘没有**溢出**面板。

## 「删文字但保留投影契约」

主人说「其它文字不要」时，**先分清是哪一层的文字**：

- **HUD 上的 Label** —— 归显示层，可以 `visible = false`。
- **`HUDPresenter3D` 产出的 `*_text` 字段** —— 是**投影契约**，
  `verify_hud_presenter_3d` 会**逐字断言**（`17 / 30`、`[2] 突击步枪 · 副武器`、`命运 2/5`）。
  **改了必红**，而且「去掉总弹药 / 只留 0/4」本质是**显示口径**，不该反向改投影。

**正确姿势 —— 加字段，不改文案**：

1. Presenter 命令字典**新增**原始数值字段（如 `ammo_current` / `ammo_capacity` /
   `fate_slot_used` / `fate_slot_capacity`），三个既有 `*_text` **逐字保留**。
2. 显示层改用**结构化字段**自行排版，**不解析字符串**
   （解析 `"100 / 100"` 定会随文案格式漂移而崩）。
3. 不再显示的 Label **只隐藏、不删**，且**保留写入路径** ——
   删了会让 `_apply_*_command` 里那处写入空引用，且 Presenter 契约仍需该字段。
   挂到父面板（而非行容器）下更明确表达「它不是这一行的内容」；容器布局**会跳过不可见子节点**，不占格。
4. **同步设计文档**的命令字段列表（`docs/v0.1/04_技术施工_战斗与局内成长.md` 第 20.1 节
   有 `[UI-HUD 当前工程边界]` 段），并说明「`*_text` 是投影侧就绪文案、与渲染解耦」。

> 这一条是**通用套路**：凡「显示层要改口径」而「投影层有逐字断言」，都走「投影加字段 + 显示层自排」。

## 🔴 坐标陷阱：HUD 坐标 ≠ 截图像素

`_anchor_control` 的 offsets 是 **canvas 坐标**，不是窗口像素。
`window/stretch/mode="canvas_items"` + 默认 aspect `expand` 下，1920×1000 窗口的 canvas 只有 **1382.4×720**，
缩放因子 `1920 / 1382.4 = 1.3889`。

**从截图裁剪比对区域时**：
```
像素坐标 = canvas 坐标 × (窗口像素宽 / canvas 宽)
```
例：把 canvas `x=-214`（`cx` 从右锚）换算到像素是 `W - 214*0.8*1.3889`，**不是** `W - 214*0.8`。
算错会裁到完全无关的区域，产出两张空白条，**极易误判成「这东西本来就不在」**。

⚠️ **canvas 尺寸本身随运行模式变**：无头 = `1280×1280`，窗口化 1920×1000 = `1382×720`。
同一个锚在底部中央的面板，无头探针打印 `y=1220`、窗口化打印 `y=660` —— **都正确**。
⇒ 探针的**绝对坐标只在同一次运行的 canvas 下可比**；跨模式要么换算、要么只比相对量
（如「右缘到 canvas 右边缘的距离」）。

## 🔴 无头模式出不了图

`await RenderingServer.frame_post_draw` 在 `--headless` 下**不会触发**，
截图代码段被**静默跳过**（日志里没有 `PROBE_HUD_SHOT_OK`、也没有 PNG，但退出码正常）。
⇒ **要真渲染截图必须窗口化**：
```bash
"<godot-console>" --path "<project>" --resolution 1920x1000 --scene res://<probe>.tscn > log.txt 2>&1
```
无头只用来取**结构 / 尺寸 / 字号 / 可见性**。两者配合：无头判结构，窗口化出实拍。

## 🔴 GDScript 不热重载

改完 `.gd` 后，**正在运行的旧实例不会生效**——主人截图里仍看到背板，多半是没重启。
必须**全新进程**：先确认无 Godot 在跑，改文件，再重开。
（设置类改动更严：`project.godot` 只在进程启动时读入内存。）

## 验证：先探针、再回归

**第一步 —— 运行时探针**（几十秒，不必跑 17 min 全套）：
写一个 headless 探针遍历 `ReferenceCombatHUD` 下所有 `PanelContainer`，打印
`visible / pos / size / bg_alpha / border_w / shadow`。判据：

```
PROBE_PANEL_<Name> visible=... bg_alpha=0.0 border_w=0 shadow=0
```

- 去背板成功 ⇒ `bg_alpha=0.0 border_w=0 shadow=0`
- 隐藏成功 ⇒ `visible=false`
- 文字仍在 ⇒ 另打印 label 的 `text` 非空
- 改字号 ⇒ 打印 `label.get_theme_font_size("font_size")`（**硬判据**，别靠看图）
- 挪位置 ⇒ 打印 `panel.get_global_rect()` 与**到 canvas 边缘的距离**
  （如 `right_gap` / `bottom_gap`），比绝对坐标更抗 canvas 尺寸变化
- 量内容是否溢出 ⇒ 在截图里对面板区域求**非背景像素 bbox**（见第三步）

跑法（用 ASCII APPDATA，避免污染）：
```bash
export APPDATA='C:\tmp\ss2_appdata_probe'
"<godot-console>" --headless --path "<project>" --scene res://tests/verification/<probe>.tscn > log.txt 2>&1
```

**第二步 —— batch 回归**（改动后必跑，确认没把探针弄红）：
```bash
export TMPDIR=/d/ssverif/tmp          # 默认落 C 盘会 No space left
export GODOT_BIN="<godot-console 绝对路径>"
bash scripts/run_verification_suite.sh batch verify_reference_hud_fate_visual verify_finite_ammo_flow verify_tactical_inventory_minimap_flow
```
期望末行 `VERIFICATION_SUITE_OK suite=batch count=3`，三枚各自 `*_OK`。
动过 `HUDPresenter3D` 就**必须加跑 `verify_hud_presenter_3d`**；
动过武器/快捷栏交互加跑 `verify_dual_weapon_quick_map_fate_flow`。
四枚都要是 `*_OK` 才算过（本机冷缓存约 15 min，日志会长时间 0 字节，属正常块缓冲）。

**第三步 —— 渲染截图 + 前后对比**（视觉改动必须有渲染证据）：
窗口模式跑同一场景截图，按上面的 canvas→像素公式裁出面板区域，
量 `dark%`（暗像素占比）作为去背板的客观指标。
**别用 `cyan%` 当指标** —— 场景里的蓝色光带/光柱会污染它。

**量内容 bbox（判断有没有溢出/是否有大片空白）**：取面板区域众数色当背景，
统计偏离背景 > 阈值的像素的 x/y 范围：

```python
cnt = Counter(px[x, y] for x in range(W) for y in range(H))
bg = cnt.most_common(1)[0][0]
def is_content(c): return sum(abs(a-b) for a, b in zip(c, bg)) > 70
```
得到 `content bbox` 与面板尺寸一比 ⇒ 右缘到面板边的间隙、内容占宽比例。
⭐ 顺带提醒：**`ItemModelIcon3D` 的模型会视觉溢出它的 layout box**
（相机取景所致，非缺陷）。看图觉得「图标和文字贴一起」时，
先按上面量一次真实 bbox 再下结论 —— 实测两者间仍有约 45 px 间隙。

## 收尾

- 跑完套件**清残留进程**：`taskkill //F //IM Godot_v4.6.3-stable_win64.exe`
  （console 包装器常出现「日志已打完但进程不退出」，`tasklist` 里 2 GB+ 的常是真在跑/卡住的）。
- 用「事务」写记忆：`I:/工作项目/shellstrom2/.workbuddy/memory/YYYY-MM-DD/HHMM_<slug>.md`，同步 `_INDEX.md`。
