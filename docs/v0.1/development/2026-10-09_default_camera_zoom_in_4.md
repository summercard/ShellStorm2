# 塔楼默认镜头按 `;` 拉近4次

日期：2026-10-09  
功能：WORLD镜头表现

## 变更范围

- 塔楼无遮挡默认相机由玩家局部`(0, 10.719009, 4.037671)`调整为`(0, 9.993940, 3.699625)`。
- 调整口径：在上一版默认位置上，按调试快捷键`;`（拉近）连续按4次、每次沿「相机→焦点」视线轴缩短0.20m，共0.80m。
- 相机到焦点的视线轴**方向不变**，因此默认俯视角与 FOV 65° 不变；焦点`(0, 0.45, -0.75)`不变。
- 收镜触发距离`CAMERA_LOWER_WALL_RETRACT_TRIGGER_M`直接引用默认后移常量，随本次改动自动由`4.037671m`变为`3.699625m`。
- 墙后相机探针的参数（高度1.09m、起点-0.46m、长度7.47m、横向采样±0.32m、抬升混合距离1.37m）**未改**：它们由角色体型与墙体几何决定，与镜头距离无关；镜头拉近后探针相对相机通道的覆盖裕度反而增大。
- 玩家朝向、移动、战斗、怪物、设施、掉落、楼层、墙体、门、楼梯、移动速度、伤害、交互距离与**存档结构**均未修改；`.tres` / `.tscn` 资产与场景文件未动。

## 默认镜头的历史链条

| 时间 | 玩家局部位置 | 相对上一版的变化 | 相机到焦点距离 |
| --- | --- | --- | --- |
| v0.1 初始 | `(0, 8.0, 2.77)` | — | 8.330240m |
| 2026-09-13 | `(0, 10.719009, 4.037671)` | `'` 拉远15次 ×0.20m | 11.330240m |
| 2026-10-09（本次） | `(0, 9.993940, 3.699625)` | `;` 拉近4次 ×0.20m | 10.530240m |

自 v0.1 初始算起，净变化为沿视线轴拉远11次 ×0.20m = 2.20m。三步都只改变「相机→焦点」向量的**长度**、不碰方向，这是俯视角始终不变的原因，也是本次溯源断言的判据。

## 数据与所有权

- 塔楼默认镜头唯一事实源：`src/world3d/TowerDescent3D.gd:155-162` 的`CAMERA_HEIGHT_M` / `CAMERA_DEFAULT_TRAILING_M`。
- 收镜触发`CAMERA_LOWER_WALL_RETRACT_TRIGGER_M`无独立取值，直接引用上述常量。
- 运行诊断字段`camera_base_height_m` / `camera_desired_trailing_offset_m`等自动跟随，供专项验收读取，**不写入存档**。
- 该组常量被塔楼与两个远征关卡共用（`TowerDescent3D.tscn` / `ExpeditionLevel01_3D.tscn` / `ExpeditionLevel99_3D.tscn` 均挂载`TowerDescent3D.gd`），本次一并生效。

## 同步改动

- `tests/verification/verify_debug_camera_hotkeys.gd`：默认值溯源断言改为**双链条**——既验证「自 v0.1 初始沿视线轴净拉远11次 ×0.20m」，也独立验证「上一版默认沿同一轴拉近4次 ×0.20m」。
- `tests/verification/verify_tower_camera_occlusion_flow.gd`、`verify_tower_descent_flow.gd`、`verify_tower_lighting_wall_combat_regressions.gd`：固定机位与收镜触发距离断言由旧值改为新值；楼梯楼板测试夹具由相机后方`4.037671m`移到`3.699625m`，保持「夹具正落在相机通道上」的原有语义。
- 视觉预览/探针脚本`preview_reload_ring.gd`、`probe_interaction_dot_visual.gd`：机位常量同步，保证预览仍然是实机机位。

## 验收入口

- `verify_debug_camera_hotkeys`
- `verify_tower_camera_occlusion_flow`
- `verify_tower_descent_flow`
- `verify_tower_lighting_wall_combat_regressions`

## 本次验收结果

- `verify_debug_camera_hotkeys`：退出码0，输出`DEBUG_CAMERA_HOTKEYS_OK`。新增的双链条溯源断言（自 v0.1 初始沿轴净拉远11次、上一版默认沿轴拉近4次，容差均 1e-5）通过；按键分类、偏移边界、yaw 旋转合成、默认机位合成等原有断言不受影响。
- `verify_tower_descent_flow`：退出码0，输出`TOWER_DESCENT_FLOW_MIGRATED`（动态到达门流程已迁移到独立专项）。
- `verify_tower_camera_occlusion_flow`：相机抬升区间断言通过。首轮运行暴露的「99层基地南墙镜头抬升高度异常：10.294m」是脚本里写死的抬升区间 `10.89 / 11.020`（由旧默认高度 10.719 推出）造成的，已改为跟随常量的 `CAMERA_HEIGHT_M + 0.17 / + 0.301`，改后该条消失。
- 该专项剩余 9 条 `v0.1_REAL_CAMERA_FLOW_FAIL` 为**既存失败**：在 2026-09-24 全局审计的 `audits/evidence/2026-09-24_global/runtime_results.json` 中逐条记录在案（当时 9 条全中）。本次以 `APPDATA` 指向空目录隔离 `user://` 复跑，得到与当时**同名同序的同一批 9 条**，数值仅随新默认高度同步平移（抬升高度 10.727→10.003、10.719→9.994；后移 3.931→3.587、4.038→3.700），证明与本次改动无关，也与本机存档无关。根因是 98 层随机布局未生成可用于验收的南侧门墙等场景生成问题，属既有技术债。
- `verify_tower_lighting_wall_combat_regressions`：楼梯楼板下压断言通过。原判据 `drop > 6.0` 是旧默认高度 10.719 时代 drop≈6.19 的写死值，已改为 `drop ≈ CAMERA_HEIGHT_M − clearance`（±0.05）。剩余 3 条为**既存失败**，2026-09-24 全局审计逐条记录在案：`Enemy below a streamed-out upper-floor slab is falsely classified as sunlight`、`99F floor support does not stay physically active under disabled stage streaming`、`Opening the 98F hub door does not create its first enemy wave` —— 均与相机默认值无关。
- 运行快照复核：`camera_base_height_m=9.99394`、`camera_desired_trailing_offset_m=3.699625`、`camera_lower_wall_retract_trigger_m=3.699625`，新常量已在塔楼运行时生效。
- 全部运行无 `SCRIPT ERROR`（GDScript 解析错误计数 0）。
