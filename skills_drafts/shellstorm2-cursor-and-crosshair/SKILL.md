---
name: shellstorm2-cursor-and-crosshair
description: 【⚠️ 当前工程已整体回退，无世界准星 / 鼠标可见性代码 —— 本 skill 是**恢复指南**】。当主人再次要求"把光标做成准星 / 准星不要贴着地板 / 准星要和角色一个高度 / 进游戏箭头不要显示 / 菜单里箭头要显示"，或要求**撤销 / 回退**这类改动时使用。内含两版设计的完整实现、四个场景接入点、55.87 px 错位证据与全部踩过的坑。不用于 2D HUD 面板的视觉清理（那走 shellstorm2-hud-visual-cleanup）。
agent_created: true
---

# ShellStorm2 世界准星与鼠标箭头可见性（恢复指南）

## 🔴 当前状态：已按主人指示**整体回退**（2026-09-29）

主人「返回最初版本，还有把鼠标的功能也恢复一下」+ 追问确认「**全部撤销**」⇒
工程内**不再有**世界准星改造与鼠标可见性管理：

- `scenes/Player3D.tscn` 的 `AimCursor` 回到**平躺的青色小环**
  （只有 `Ring` TorusMesh 内 0.16 / 外 0.21 + `Dot` CylinderMesh r 0.035，法线 +Y，
  无旋转、无四向十字、共 2 件，`cast_shadow = 0`）。
- `Player3D.gd` 的准星位置回到 `global_position + dir*3.2 + Vector3.UP * 0.035`
  （鼠标分支：`target + Vector3(0, 0.035, 0)`）—— 即**贴地 3.5 cm**。
- **全工程无任何 `mouse_mode` 代码**，系统鼠标箭头**一直显示**。
- `src/core/UiCursorMode.gd`、`tests/verification/verify_cursor_crosshair_flow.*`
  已删除；`project.godot` 的 autoload 注册行已移除；`run_verification_suite.sh`
  的 `core_scenes` 注册已移除（`VERIFICATION_REGISTRY_OK scenes=165`）。

**被删文件的完整备份**（恢复时直接从这儿拷）：
`_scratch/_reverted_20260929_cursor_mouse/`（`src_core/UiCursorMode.gd`、
`tests_verification/verify_cursor_crosshair_flow.{gd,tscn}`）。

> 下面记录**两版**设计。若主人再要求做这件事，优先按「第 2 版」实现（主人当时明确选了它）；
> ⛔ 别走「指针图案＝准星」（第 3 版，主人当场否掉，见文末）。

## 何时用

三类诉求：

1. **世界准星** —— 「把光标做成一个准星」「不要贴着地板」「跟角色一个高度」
   「准星是扁的」「光标和准星位置对不上」。
2. **箭头残留 / 恢复** —— 「进游戏后箭头不要显示」「菜单里箭头还在」
   「把鼠标的功能恢复一下（箭头要一直显示）」。
3. **撤销上面这些** —— 「返回最初版本」「改回原来的样子」。

对象：`src/player3d/Player3D.gd` 的 `AimCursor` 节点（世界准星）
+ `src/core/UiCursorMode.gd`（autoload，系统箭头可见性）。
**不用于 2D HUD 面板**（背板/边框/挪位）—— 那走 `shellstorm2-hud-visual-cleanup`。

## 第 2 版设计（主人选定的那版 · 恢复时按这个做）

**世界准星是玩法中唯一的瞄准指示器 + 系统箭头只在玩法里隐藏。**

### 一、世界准星 —— `Player3D` + `scenes/Player3D.tscn`

```gdscript
## Player3D.gd
const AIM_CURSOR_HEIGHT_M := 1.10          # 相对角色原点 = 脚底
const AIM_CURSOR_RAY_FALLBACK_M := 20.0    # 射线不朝下（抬头越过地平线）时的兜底距离

func _resolve_aim_cursor_position(
	ray_origin: Vector3, ray_direction: Vector3, aim_target: Vector3
) -> Vector3:
	if ray_direction.y < -0.0001:
		var plane_y := global_position.y + AIM_CURSOR_HEIGHT_M
		var hit = Plane(Vector3.UP, plane_y).intersects_ray(ray_origin, ray_direction)
		if hit is Vector3 and (hit as Vector3).is_finite():
			return hit as Vector3
	# 射线不朝下 ⇒ 退回射线上固定距离处，屏幕位置依然对齐。
	var fallback := ray_origin + ray_direction * AIM_CURSOR_RAY_FALLBACK_M
	return fallback if fallback.is_finite() else aim_target


func _place_aim_cursor(world_position: Vector3) -> void:
	if aim_cursor == null:
		return
	if camera == null or not camera.is_inside_tree():
		aim_cursor.global_position = world_position
		return
	aim_cursor.global_transform = Transform3D(
		camera.global_transform.basis, world_position
	)
```

- 鼠标分支末行改成 `_place_aim_cursor(_resolve_aim_cursor_position(ray_origin, ray_direction, aim_target))`；
  摇杆分支改成 `_place_aim_cursor(Vector3(aim_point.x, global_position.y + AIM_CURSOR_HEIGHT_M, aim_point.z))`。
- 🔴 **求交是硬要求**。改成「取地面瞄准点 XZ、再把 Y 抬到角色高度」会让准星**离开射线**，
  投影回屏幕实测偏 **55.87 px**（本作相机 17.5 m 高 / 俯角 52°，四点 53.4~55.9 px）
  —— 那正是主人报的「和准星位置对不上」。求交后误差 **0.0001 px**。
- 🔴 **朝向每帧取相机 basis** ⇒ 局部 XY 平面 = 屏幕平面 ⇒ 俯视斜角下也是**正圆**。
  最初那版是平躺环（法线 +Y），斜俯视下被压成椭圆 —— 主人说的「贴着地板 / 是扁的」。
- 🔴 **不写死世界 Y**：塔楼分层，高度取玩家当前 `global_position.y`，否则下楼后准星留在楼顶。

### 造型（`AimCursor` 下 6 件）

`Ring` + `Dot`（都 `rotation = Vector3(1.5707964, 0, 0)` 立起来）
+ `CursorBarUp/Down/Left/Right`（位置 ±0.255；左右两条再绕 Z 转 90°），
共用新增的 `BoxMesh` 子资源 `MeshCursorBar`（`size = Vector3(0.014, 0.1, 0.014)`）。
`load_steps` 11 → 12。

- 🔴 `top_level = true`（准星独立定位）。
- 🔴 **每个部件都要 `cast_shadow = 0`**：`verify_tower_lighting_wall_combat_regressions.gd`
  会遍历玩家下所有 `GeometryInstance3D`，断言它们**不进前向光束阴影贴图**。

### 二、系统箭头可见性 —— autoload `src/core/UiCursorMode.gd`

```gdscript
## 玩法期间：隐藏箭头，同时把指针限制在窗口内 ——
## 只用 MOUSE_MODE_HIDDEN 时指针会被推出窗口，瞄准随即失去输入。
const GAMEPLAY_MOUSE_MODE := Input.MOUSE_MODE_CONFINED_HIDDEN
## 菜单 / 非玩法场景：箭头自由移动。
const NON_GAMEPLAY_MOUSE_MODE := Input.MOUSE_MODE_VISIBLE

func wants_visible() -> bool:
	return not is_gameplay_active() or _paused_or_modal()

func _apply() -> void:
	# headless（验收套件）没有鼠标设备：设置会刷无关警告并污染验收日志。
	if not DisplayServer.has_feature(DisplayServer.FEATURE_MOUSE):
		return
	var desired := NON_GAMEPLAY_MOUSE_MODE if wants_visible() else GAMEPLAY_MOUSE_MODE
	if Input.mouse_mode == desired:
		return
	Input.mouse_mode = desired
```

- 🔴 玩法用 **`CONFINED_HIDDEN`** 而不是 `HIDDEN`（`HIDDEN` 会让指针被推出窗口、瞄准丢输入）。
- 🔴 `wants_visible()` 是**纯函数**，专门留给无头探针断言 ——
  无头没有鼠标设备，`_apply()` 会整体早退，探不到真实结果。
- 三入口：`hold(owner)` / `release(owner)`（**比对引用**再清，防场景切换时序顶掉）/
  `set_modal(owner, open)`；`_prune_stale_owners()` 清 `is_instance_valid == false` 的 owner。
- 🔴 必须 autoload 且 `PROCESS_MODE_ALWAYS`：暂停菜单走 `Global.acquire_pause` 把
  `tree.paused` 置 true，挂在玩法场景上的 `_process` 会停摆 ⇒ 箭头再也回不来
  （表现为「看得见菜单、点不到按钮」）。
- `project.godot` 的 `[autoload]` 段加：
  `UiCursorMode="*res://src/core/UiCursorMode.gd"`（在 `NarrativeDirector` 之后）。

### 三、接入点（四个场景 + 一个时序坑）

| 场景 | 接入 |
|---|---|
| `Dungeon3D`（父类） | `_ready` 末 → `_begin_gameplay_cursor()`（**虚方法**，内部 `hold(self)`）；`_exit_tree` **首行** → `release(self)`；`_process` **首行** → `set_modal(self, _cursor_modal_open())`；新增 `_cursor_modal_open()` |
| `TowerDescent3D` | **覆写 `_begin_gameplay_cursor()` 为 `pass`**，改在 `_emit_gameplay_started()` 里 `hold(self)` |
| `BaseWorld3D` | `_ready` → `hold`；**新增** `_exit_tree` → `release`；**新增** `_process` → `set_modal(self, _active_menu != null and is_instance_valid(_active_menu))` |
| `TrainingRange3D` | `_ready` 末 → `hold`；**新增** `_exit_tree` → `release`（靶场无菜单） |
| 暂停菜单 | **无需单独接入** —— 走 `Global.is_paused` 自动兜底 |

⚠️ **消费者场景可自愿挂钩（非必需）**：`scenes/RogueMapSelectMenu.gd`（3D 全息城选关菜单）
曾自行挂 `get_node_or_null("/root/UiCursorMode")` → `set_modal(self, true)` / `release(self)`。
**不挂也能跑** —— 它自己存/还原 `Input.mouse_mode`（开 → `VISIBLE`、关 → 还原）。
2026-09-29 回退时这两处钩子已按主人裁定删除（删除前后**均为 no-op**，因 autoload 已不存在）。
恢复该功能时**可选**顺手挂回，⛔ 别当成必需的「第五接入点」。

```gdscript
## Dungeon3D
func _cursor_modal_open() -> bool:
	return _has_exclusive_modal() or (
		_inventory_ui != null and _inventory_ui.is_inventory_open()
	)
```

（`_has_exclusive_modal()` 原本就有，已覆盖 大地图 / 工作台 / 商人 / 命运卡 / `_completed`。）

🔴 **塔楼冷启动的开场页时序**：`MainEntryScreen3D` 交回相机与输入**之前**指针必须可点，
否则玩家点不到「开始 / 跳过」。所以 `TowerDescent3D` 不能走父类的 `_ready` 接管，
必须推迟到 `_emit_gameplay_started()`。

⚠️ **回退时注意**：`BaseWorld3D` / `TrainingRange3D` 的 `_exit_tree`、`_process` 在
`HEAD` 里**根本不存在**，是整套新增的（要删整个函数）；而 `Dungeon3D` 的
`_exit_tree` / `_process` 本来就有，只能删**首行**。`Dungeon3D.gd` 还混着 HUD 改动
⇒ 回退必须**外科式**，⛔ 不能 `git checkout HEAD -- Dungeon3D.gd`。

### 四、验收（恢复该功能时重建）

正门禁 = `tests/verification/verify_cursor_crosshair_flow.{gd,tscn}`（登记进 `core_scenes`，
紧跟 `verify_tower_descent_flow`）。成功标记 `CURSOR_CROSSHAIR_FLOW_OK`，失败
`CURSOR_CROSSHAIR_FLOW_FAIL: ...`（退出码 1）。四组判据：

- **几何**：`child_count == 6`、`visible == true`、四向十字都有 mesh。
- **位置 / 朝向**：`|cursor.global_position.y - (player.y + 1.10)| < 0.02`、
  `cursor.basis.z.dot(cam.basis.z) > 0.999`。
- **屏幕对齐（硬判据）**：4 条合成射线 `unproject_position` 与采样点偏差 `≤ 1.0 px`
  （实测 0.0001）；世界高度 `== player.y + HEIGHT`（容差 0.001）。
  脚本同时打印**旧写法对照** `worst_old_screen_err ≈ 55.87 px`，是防止改回去的活证据。
- **指针可见性 7 态**：`idle true / gameplay false / modal true / modal closed false /
  paused true / unpaused false / released true`；`GAMEPLAY_MOUSE_MODE == CONFINED_HIDDEN`。

🔴 **别把断言只写在 `verify_tower_descent_flow` 里**：该场景在当前工程状态下**会提前早退**
（`floor_generation_mode == "arrival_gate_atomic_floor_bundle"` 时第 29~36 行直接 `quit(0)`，
直跑 15 s 只打一行 MIGRATED），写在它后面的断言**根本不会执行**。它里面那条准星断言
（`y - (player.y + 0.035) < 0.02`）方向正确但**不可达** —— 真正的门禁必须是独立场景。

**整套回归**（动过准星几何时；灯影那条必须在内）：

```bash
export TMPDIR=/d/ssverif/tmp
export GODOT_BIN="<godot-console 绝对路径>"
bash scripts/run_verification_suite.sh batch verify_cursor_crosshair_flow verify_tower_lighting_wall_combat_regressions
```

新增验收场景后 **必须**跑 `python3 scripts/check_verification_registry.py`
（每个 `verify_*.tscn` 必须恰好属于 smoke / core / visual / manual / retired 之一）。

⚠️ **`verify_verification_runner_contract` 不能直跑**：它读的
`SHELLSTORM_VERIFICATION_USER_DIR_NAME` / `SHELLSTORM_VERIFICATION_CACHE_ISOLATED`
两个环境变量**只有真套件会设**，且要求 `OS.get_user_data_dir()` **不以 `/弹壳风暴2` 结尾**
（直跑时 `APPDATA` 隔离只是换了盘，目录名仍是项目名）⇒ 直跑必报三条 `push_error`。
只能通过 `run_verification_suite.sh` 用 `batch` 真跑一次它。

**跑前先数 `AimCursor` 的引用方**：`grep -rn "AimCursor" --include=*.gd src tests`。
（已知 3 处：`verify_3d_melee_combat_visual.gd` / `verify_player3d_weapon_grip_visual.gd`
各设 `visible=false` 做干净截图 —— 与新设计方向一致不用改；`verify_tower_descent_flow.gd` 已不可达。）

## 🔴 坑（都实测踩过）

- **新增 autoload 只在 Godot 进程启动时读入**。加完 `project.godot` 必须**重启编辑器**，
  否则引用它的脚本一律 `Identifier not found: UiCursorMode`；正在跑的旧实例同样不认。
  **删除 autoload 同理**，也要重启才彻底生效。
- **`--script` 与 `--check-only` 两种 headless 模式不把 autoload 名注册进 GDScript 全局标识符表**
  （`Global` / `BaseManager` / `UiCursorMode` / `InputDevice` 全部解析不到）。探针**必须跑场景**：
  `godot --headless --path . res://<probe>.tscn`。用 `--script` 会把「模式局限」误读成「标识符未声明」。
  ⚠️ 一次性探针别放 `_scratch/`（会与正式场景两份漂移）—— 写进 `tests/verification/` 并登记注册表。
- **GDScript 不支持链式比较**：`not (0.3 <= a <= 0.8)` 是**解析错误**
  （`Invalid operands "bool" and "float" for "<=" operator`）。
  ⚠️ 解析失败时场景根节点没有脚本 ⇒ 没人调 `quit()` ⇒ Godot **挂住不退出**，
  前台跑会一路跑到超时才被杀，容易误判成「卡死」。
- 改 `scenes/*.tscn` / `project.godot` 前先查 `tasklist | grep -i godot`：编辑器文件监视会短暂
  锁住打开中的场景（`EBUSY`），**直接重试同一 Edit 常可过**。
- GDScript 不热重载：改完 `.gd` 要让主人**重启场景/编辑器**再截图，否则看的是旧实例。

## 第 3 版：指针图案＝准星（⛔ 主人当场否掉，别再用）

曾把**系统指针图案本身**换成准星：`Input.set_custom_mouse_cursor(48×48 程序化贴图,
Input.CURSOR_ARROW, Vector2(24,24))`，`mouse_mode` 改为只管约束
（`VISIBLE` 菜单 / `CONFINED` 键鼠玩法 / `HIDDEN` 无指针设备），
并新增 `has_crosshair_cursor()` / `sample_cursor_pixel()` / `resolve_mouse_mode()`
三个探针接口（贴图**按像素生成、不落盘 PNG**；中心点用**方盒**判定
`max(|dx|,|dy|) <= 1.5`，圆盘在 48 px 下只覆盖 12 像素、会与四臂重复十字母题）。

它逻辑上能根除「两个指示器」的问题，但主人要的是「上一版 · 世界准星」，
指令「别改了 改回原来的样子把」⇒ **整体删除**。相关代码 / 常量 / 预览脚本均已移除。
⛔ 不要再用指针图案替代世界准星。

## 收尾

- 视觉证据必须补：准星与鼠标箭头的样子**只能靠主人实拍确认**，探针只能证明几何 / 模式正确。
- 🔴 **提醒主人重启 Godot 编辑器 / 场景**（autoload 与 GDScript 都不热重载），这是唯一的阻塞项。
- 改了正本 `~/.workbuddy/skills/` 里 **W 已有的 skill**，收尾必跑
  `sync_skill_mirrors.py --check` 与 `sync_workspace_skills.py --check`，保持 0 欠账。
  本机（Safe-Delete 守卫）**不要跑 `--sync`**，用 `cp -rf` + sha256 校验的替代流程。
- 用「事务」写记忆：`I:/工作项目/shellstrom2/.workbuddy/memory/YYYY-MM-DD/HHMM_<slug>.md`，同步 `_INDEX.md`。
- **未得主人明确指示前不 `git commit`**。
