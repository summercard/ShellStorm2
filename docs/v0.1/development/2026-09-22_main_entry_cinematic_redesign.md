# 2026-09-22｜主界面基地霓虹摄影重制

## 功能
- feature_id：ENTRY-AVATAR
- 来源：用户提供参考图，要求基地内背光站位、补光、主页专用镜头参数、按钮重做与动态效果。
- 状态：实现完成；真实渲染专项通过；完整文档门禁和太阳旧回归仍有既有红项。

## 实现
- `MainEntryScreen3D`不再改写真实玩家位置、真实玩家朝向或玩法Camera；在99F基地全息平台南侧使用世界点 `facility.to_global(Vector3(5,0.05,1))` 建立展示站位。
- 从已装配的`PlayerAvatar3D`复制只读视觉树，递归清除脚本、碰撞、动画、相机和灯，只保留网格；真实Player3D继续作为玩法状态所有者，存档/库存/出生点不变。
- 新建主页专属Camera3D：FOV `34°`，near `0.05m`，far `90m`；`CameraAttributesPractical`关闭近景景深，保留远景轻柔模糊（amount `0.06`）。Environment使用深复制，不改玩法相机资源和全局画质资源。
- 新建4盏展示层OmniLight3D：冷白主光 `3.2`、暖面光 `1.3`、青蓝轮廓 `4.0`、品红轮廓 `4.5`；统一展示层 `1<<18`，不投影，不进入基地灯光控制。
- UI重制为 `EntryBrand.gd`（斜切青白标题+品红2）、`EntryNeonButton.gd`（切角描边、流光、呼吸、hover/焦点位移、按下反馈）、`EntryMenuLayout.gd`（1280×720响应式左栏）；开始/设置保留真实Button焦点与信号。
- 设置按钮复用`PauseMenu3D`，新增主页设置上下文：隐藏返回基地/复位存档，只保留画面设置、操作设置、返回主界面；Esc主页直接打开设置。
- 开始交接使用 `1.15s` 遮黑：过渡中点释放展示rig，结束恢复原Camera/HUD/输入并清理；重复present、skip、退出树路径有清理守卫。

## 验收证据
- `tests/verification/verify_main_entry_cinematic_flow.tscn`：隔离 user dir、真实窗口、21项检查，`MAIN_ENTRY_CINEMATIC_OK`；检查基地背景、43个展示网格、玩家位置不变、玩法FOV/Transform/Attributes/Environment不变、专属景深、右侧取景、设置开启/关闭、开始交接、重复present与异常退出清理。
- 实拍：`I:/工作项目/shellstrom2/outputs/main_entry_cinematic.png`、`main_entry_settings.png`。
- 回归：`verify_game_entry_flow` EXIT 0 / `GAME_ENTRY_FLOW_OK`；`verify_graphics_settings_ui_flow` EXIT 0 / `GRAPHICS_SETTINGS_UI_OK`（隔离工程）。
- `verify_main_entry_realtime_sun_flow` 的 `12:00太阳峰值不是1`在生产 HEAD 复现，确认是既有基线红，不归因本次主页改动。
- `verify_base_overhaul_flow` 当前仍有太阳峰值、旧存档revision、结构测试 `float(null)` 与既有基地断言红项；未把这些红项伪装成主页通过。

## 未执行/遗留
- `check_documentation_contracts.py`仍报2条既有坏链接（`docs/v0.1/README.md`与资产规范文档引用不存在的`../assets/registry/README.md`）。
- `_scratch`隔离窗口日志存在资源泄漏提示，生产主页专项无该日志门禁结论；需后续独立归因，不修改资产或存档处理。

## 2026-09-22 第二轮｜62°广角近景与背景隔离修正

### 变更
- `src/ui/main_entry/MainEntryScreen3D.gd`（相机保留 62° 广角、低机位、`-7°` 滚转，替代第一轮的 34° 口径）：
  - 撤掉 `PRESENTATION_AVATAR_SCALE=1.35` 擅自缩放，改为**真实位置前移**：`PRESENTATION_AVATAR_OFFSET=(-0.25,0,1.25)`，表观尺寸与原缩放相当且无比例畸变；展示快照 `scale` 恒为单位阵。
  - 背景虚化加强：`dof_blur_far_distance=2.6`、`dof_blur_far_transition=1.8`、`dof_blur_amount=0.30→0.42`，近景景深保持关闭。
  - 设施头顶 GUI 隔离改口径：不再只搜 `Blocks/Base/facility`（会漏兄弟设施），改为全树 `Label3D`（排除真实玩家与展示 rig 子树）；用**渲染层隔离**替代 visible 开关——暂存每个标签原 `layers` 后置 0，展示相机按 cull mask 不再渲染它们，动态提示即便把 `visible` 重新置真也不会穿透；退出时完整还原层与可见性。
  - 暗角 `EntryVignette` 移到 `Screen` 子节点**最底层**（`move_child(0)`），只衬在菜单/提示/过渡黑屏之下；不改 `menu.z_index=2`，不盖 UI、不盖过渡黑屏。
- `src/world3d/TowerDescent3D.gd`：本轮仅核验 `FACILITY_LOGOUT_SPAWN=(4.75,-11.95,6.65)`（基地返航/登出出生点，与主界面展示站位同处，y=−12+0.05 口径）；**新游戏开场仍走 98F `master_office` 分支不变**，存档恢复/远征出生规则不变。
- `tests/verification/verify_main_entry_cinematic_flow.gd`：21→36 项。新增：玩法相机 cull mask 展示前后不变、专属相机独立实例且带 `PRESENTATION_LAYER`、展示快照无缩放、近景距离（相机到快照 <2.6m）、DOF 三参数、暗角位于 `Screen` 子节点 index 0、全树标签展示期全被隔离且退出后层/可见性完整还原、`FACILITY_LOGOUT_SPAWN` 值断言、世界标签非空前置断言。

### 沙箱修复（`_scratch/run_entry_cinematic.py`，非项目内）
- 失败根因：真实工程 `.godot/global_script_class_cache.cfg` 里全局类 `Player3D` 被 `res://_scratch/gamepad_submenu/baseline_bak/Player3D.gd`（他人并发备份，同声明 `class_name Player3D`）抢注，真实 `src/player3d/Player3D.gd` 被挤出缓存；沙箱 junction 共享 `.godot` 后，该缓存项指向沙箱内不存在的文件 → 全局类解析失败（连带大量 "Could not find type" 连锁报错）。
- 修复：沙箱 `.godot` **私有化**——`imported/`（3.8GB）与 `shader_cache/` 仍 junction 共享以保留导入缓存；`uid_cache.bin`、`scene_groups_cache.cfg`、`.gdignore` 复制；`global_script_class_cache.cfg` 不共享，缺失或含 baseline_bak 抢注或缺真实 `src/player3d/Player3D.gd` 时，用编辑器 headless（`--headless --editor --quit`）按沙箱自身 res://（不含 `_scratch`）重新生成干净缓存后复用。全程未触碰他人备份与真实工程全局缓存。

### 运行结果
- `python _scratch/run_entry_cinematic.py`：`GODOT_EXIT=0`、`ENTRY_CHECKS=36`、`MAIN_ENTRY_CINEMATIC_OK`；日志无 SCRIPT ERROR、无意外 ERROR/泄漏告警（既有 GLB `invalid UID` 色盘噪音与本轮无关）。
- 截图（本轮实拍、已亲眼验证）：`I:/工作项目/shellstrom2/outputs/main_entry_cinematic.png`（角色近景清晰、背景强虚化、菜单/提示无暗角遮挡、背后无设施头顶 GUI）、`outputs/main_entry_settings.png`（设置面板清晰不被暗角覆盖）。

### 未完成/边界
- 基地返航出生只做了常量值断言与代码路径核对：`test_mode` 下玩家固定天台出生，`FACILITY_LOGOUT_SPAWN` 分支未被本测试真实执行；新游戏 98F 办公开场、存档恢复、远征出生本轮未重跑——**不宣称所有出生已完成**。
- 真实工程自身的全局类缓存仍被 `_scratch` 备份抢注（真实工程内 baseline_bak 文件存在所以能跑），属并发他人文件，未处置；沙箱已通过私有缓存绕开。
