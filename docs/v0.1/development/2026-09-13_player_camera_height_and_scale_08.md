# 玩家默认镜头与80%体型调整

日期：2026-09-13  
功能：PLAYER-STATE / WORLD镜头表现

## 变更范围

- 塔楼无遮挡默认相机由玩家局部`(0, 8.0, 2.77)`调整为`(0, 10.719009, 4.037671)`。该位置按原相机到焦点的视线轴计算，严格等价于调试快捷键`'`连续按15次、每次拉远0.20m；焦点、俯视角与FOV不变。
- 玩家默认展示倍率由旧资产0.70改为0.80。完整含耳视觉与胶囊高度改为1.20m，胶囊半径0.272m、中心Y=0.600m；角色根、相机、准星、手电、移动和战斗数值不缩放。
- 墙后相机探针随新镜头通道与玩家体型调整：高度1.09m、起点-0.46m、长度7.47m、横向采样±0.32m、抬升混合距离1.37m，收镜触发距离4.037671m。墙体仍不透明，触发后仍只抬升并沿固定后方轴收回。
- 楼梯斜楼板竖向探针起点由1.15m提高至1.31m，避免新1.20m角色顶部进入探针起始区；楼板语义、净空和恢复规则不变。
- 怪物、设施、世界掉落物、楼层、墙体、门、楼梯、移动速度、伤害、交互距离与存档结构均未修改。

## 数据与所有权

- 玩家基础体型唯一事实源：`Player3D.DEFAULT_BASE_SIZE_MULTIPLIER=0.80`。
- 塔楼默认镜头与墙边触发唯一事实源：`TowerDescent3D`的`CAMERA_*`常量；运行快照公开默认高度、后移和墙探针参数供专项验收。
- 美术GLB保持作者尺寸1.0；运行时外层缩放视觉、武器/背包挂点与独立玩法胶囊。

## 验收入口

- `verify_debug_camera_hotkeys`
- `verify_player3d_debug_scale_flow`
- `verify_player3d_avatar_bounds`
- `verify_player3d_weapon_pose_collision_flow`
- `verify_tower_descent_flow`
- `verify_tower_camera_occlusion_flow`
- `verify_tower_lighting_wall_combat_regressions`

## 本次验收结果

- 退出码0：`verify_debug_camera_hotkeys`、`verify_player3d_debug_scale_flow`、`verify_player3d_avatar_bounds`、`verify_player3d_weapon_pose_collision_flow`、`verify_player3d_diy_flow`、`verify_3d_fate_weapon_flow`、`verify_player3d_vertical_physics_flow`。
- 功能断言通过：`verify_tower_lighting_wall_combat_regressions`输出`TOWER_LIGHTING_WALL_COMBAT_REGRESSIONS_OK`；`verify_tower_camera_occlusion_flow`输出`v0.1_REAL_CAMERA_FLOW_PASS`；`verify_tower_descent_flow`输出迁移提示，相关动态门流程由独立专项承接。
- 塔楼三个场景在退出清理阶段仍报告既有`ObjectDB instances leaked`，其中遮挡与完整塔楼专项另有`2 resources still in use at exit`并被runner记为退出码4；本次未发现新的功能断言失败或GDScript解析错误。
- 资产预加载继续报告共享色盘UID无效并回退到同一路径文本引用；纹理可加载，但该UID登记问题不属于本次玩家/相机数值变更。
