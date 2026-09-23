# P0 运行入口、奖励桥、基地交互与玩家手枪验收修复

日期：2026-09-23；记录ID：P0-RUNTIME-ENTRY-PLAYER-20260923；功能ID：`ENTRY-AVATAR`、`WORLD-LOOT`、`BASE-FACILITY`、`PLAYER-STATE`、`WEAPON-COMBAT`；工程版本：0.1.0。设计依据与修订：`03_技术施工_玩家与操作.md`、`04_技术施工_战斗与局内成长.md`、`07_技术施工_基地设施.md`、`16_技术施工_主页面与角色换装.md`；代码基线：`a419bc6a`；交付提交：工作区。

## 变更与原因

| 范围 | 根因 | 修复结果 |
|---|---|---|
| 入口验收可执行性 | `verify_main_entry_cinematic_flow`仍引用旧展示代理字段并依赖旧专用用户目录名；headless 下等待`frame_post_draw`会挂死 | 改为安全查询旧契约字段、使用 runner 动态隔离目录、headless 跳过截图等待；入口现在能完整运行并报告设计差异，不再以退出码2或超时中断 |
| 主页设置与异常退出 | `SettingsButton`未接线；重复`present()`会覆盖玩法镜头快照；异常卸载不恢复输入、镜头、HUD与相机属性 | 接入既有`PauseMenu3D.open_entry_settings()`，隐藏返城/存档复位；重复调用幂等；正常交接和异常卸载统一归还玩法状态 |
| 奖励落地桥 | `call_deferred("_spawn_loot_items", ..., drops, ...)`跨延迟边界时，非类型化`Array`不能传给`Array[Dictionary]` | 接收边界改为`Array`并逐项校验/复制`Dictionary`；`verify_3d_parity_core`不再出现延迟数组类型错误 |
| 基地设施碰撞 | 新全息终端使用`StaticCollision/OptimizedOutputBounds`，通用代码绑死旧`StaticBody3D/CollisionShape3D`；作者锁定交互盒仍被旧正面 profile 接管 | `BaseFacility3D`按`StaticBody3D + BoxShape3D`契约寻找主体碰撞；全息终端声明`interaction_shape_locked=true`；锁定交互盒保持作者范围 |
| 玩家手枪动作簇 | 出厂枪已改为`bp_sprinkler`，但换弹、DIY、待机、gallery 与基地综合验收仍把默认枪当手枪，形成长枪状态与手枪阈值混测 | 所有手枪专项显式装备`bp_pistol`；未修改 Blender v021 关键帧、状态绑定器或握持阈值。待机头部判据同时读取新版剪辑实际存在的位移/旋转变化 |
| 玩家真实渲染 | 武器握持视觉用例同样依赖旧默认手枪 | 视觉场景显式装备手枪；Apple M1 / Forward+ 真渲染通过并人工查看握点与枪口对齐证据 |
| 基地综合入口 | `float(module.get("target_walkable_height_m"))`在属性缺失时触发`Nonexistent 'float' constructor`，随后用例中断 | 缺失属性改为显式失败项；空楼梯节点和类型数组安全处理。未实现设计仍保持红项，不把当前代码事实写成设计完成 |

## 验证结果

| 命令/场景 | 环境及存档隔离 | 结果 | 日志/截图证据 |
|---|---|---|---|
| `verify_base_facility_interaction_zones` | runner 独立项目缓存与动态 user dir | 通过，exit 0 | 正式全息终端、枪械工坊、售货机均有可用交互/实体碰撞 |
| `verify_3d_reload_state_flow` | 同上 | 通过，exit 0 | 手枪换弹覆盖层、真实计时、右手握持通过 |
| `verify_player3d_diy_flow` | 同上 | 通过，exit 0 | 手枪静止、移动、开火握姿通过 |
| `verify_player3d_idle_animation_flow` | 同上 | 通过，exit 0 | Blender-only待机、头部/耳朵变化与握持通过 |
| `verify_player3d_state_gallery_flow` | 同上 | 通过，exit 0 | gallery开火覆盖层与右手握持通过 |
| `verify_player3d_weapon_pose_collision_flow` | 同上 | 通过，exit 0 | 手枪/长枪状态、枪口方向与碰撞隔离通过 |
| `verify_player3d_weapon_grip_visual` | runner 独立 user dir；Apple M1 Metal 4.0 / Forward+ | 通过，exit 0 | `outputs/verification/player3d_weapon_grip.png`、`player3d_right_hand_grip_rig.png`、`player3d_sidearm_muzzle_aim_alignment.png`；人工查看握点0.00mm、枪口/弹道0.000° |
| `verify_base_world_flow` | runner 独立项目缓存与动态 user dir | 失败，exit 1；手枪目标已关闭 | 手枪跑步握姿断言不再失败；只剩首片596/500节点预算，属于独立性能债务 |
| `verify_3d_parity_core` | runner 独立项目缓存与动态 user dir | 失败，exit 1；本批目标错误已消失 | 不再出现`Cannot convert argument 2 from Array to Array`；仍有相邻房未流送、2558/2200节点预算两项 |
| `verify_main_entry_cinematic_flow` | runner 独立项目缓存与动态 user dir | 可完整执行，exit 1 | 退出码2编译失败与headless挂死已关闭；仍报告17项独立展示代理/相机/灯光/出生点等设计差异 |
| `verify_base_overhaul_flow` | runner 独立项目缓存与动态 user dir | 可完整执行，exit 1 | `float`构造与数组类型脚本错误已关闭；仍报告太阳、L梯连续碰撞、设施尺寸/位置权威及入口展示设计差异 |
| `aggregate core` | runner 独立项目缓存与逐场景动态 user dir | 129项中114项非失败、15项失败，exit 1 | 失败入口由复评基线20项降至15项；本批关闭的5个整体验收失败入口为换弹、DIY、待机、状态画廊、设施交互，另关闭多个残留子错误；剩余失败见复评报告§6.3 |

本轮没有预期故障注入。绿色用例没有非预期脚本错误。红色用例中的`push_error`均来自保留的合同断言；基地尘埃VFX失效UID回退警告仍存在，未在本批顺带接受或隐藏。

## 遗留与状态更新

- P0-1“验收入口编译/执行阻断”已关闭；不代表入口独立展示相机设计完成。`verify_main_entry_cinematic_flow`与`verify_base_overhaul_flow`继续以exit 1保留真实差距。
- P0-2“延迟掉落数组类型错误”和“全息终端碰撞识别”已关闭；`verify_3d_parity_core`的流送与节点预算另列后续主链修复。
- P0-3“玩家手枪动作簇”已关闭，相关5个专项逻辑入口和1个真实渲染入口通过；基地综合入口中的手枪握姿失败也已消失，仅保留节点预算失败。修复属于验收前置条件纠正，没有程序姿势回流，也没有覆盖Blender手部关键帧。
- 未执行完整26项视觉套件、目标GPU矩阵、移动端或长时稳定性；本轮只执行与手枪握持直接相关的真实渲染用例。
- 回滚可按文件撤销：奖励桥在`Dungeon3D.gd`；设施识别在`BaseFacility3D.gd`与全息终端Prefab；主页设置/清理在`MainEntryScreen3D.gd`；验收前置条件在对应测试文件。
