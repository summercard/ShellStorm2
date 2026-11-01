# 远征03：分裂/召唤怪出生在房外

日期：2026-11-02；FeatureID：`WORLD-PLAN`、`ENEMY-AI`；工程版本：0.1.0；交付：当前工作区，未提交。
代码基线：本次改动前逐文件备份`ShellStorm2-backup/2026-11-02_enemy_spawn_boundary/before_edits/`；与同日[受光/AI修正](2026-11-02_enemy_ai_light_motion.md)连续施工。

## 用户要求与复现

用户报告远征03部分房间的怪物会刷在房外。先区分初始盒内出怪与死亡分裂/召唤预约：

- 实际加载远征03，种子42、77003244、12345、9，共207个初始盒内点，房内归属与脚下承重检查均未发现越界（非“没有出怪也算通过”）。
- 实际关卡hub_01大堂45×40m，房心世界Z=5、南墙Z=25：母体在局部(0,0.05,19)、世界(102.5,0.05,24)，仍在房内。调用正式`_on_split_requested`→预约→`_flush_reserved_room_spawns`后，子代出现在局部Z=20.4、世界Z=25.4，**越过墙0.4m**，出生即在房外，尚未推进AI位移。
- 根因是分裂给母体两侧加1.4m、召唤在周围加1.8m，生成的显式世界坐标在统一实例化出口只检查“有限”，跳过房内轮廓/离墙净距。不能用已注入的瞬移房间矩形去证明出生安全；旧运动探针也只覆盖两种子/部分路径，未覆盖贴墙死亡分裂。

这是一条已复现原因，不声称207点排查覆盖所有种子、所有房间和所有运行时位移。

## 修正与所有权

主契约见[触发器刷怪设计§0.5](../design/触发器刷怪设计.md#05-唯一出口的-6-个调用点)。

- `DungeonRoom3D.resolve_enemy_spawn_position`持有几何判据：合法原位返回原值；越界/缺角/缺少墙边净距时，从既有安全候选池选最近点，避开实体障碍，保留请求高度。没有合法点返回INF。
- `Dungeon3D._resolve_spawn_position`仍按显式数组→配置内嵌→房间索引的原优先级解析，但房间战斗的前两条都经过同一几何Owner；预约、延迟等所有正式出怪仍从原唯一出口实例化。INF继续触发原整批失败、波次保留，不在房外落地。楼梯/天台等世界锚点剧情的授权空间由剧情适配器拥有，依原有`narrative_spawned / narrative_placement`能力集中判定，保留其原位；不通过关卡ID放行。
- 旧敌人快照恢复的现存实体/重新实例化两条分支，均在导入状态后修复越界位置；生命、持久ID、冷却等不重置，成功修复后由原快照Owner重新捕获。若旧位置无可替代候选，仅报告无法修复警告；该极端恢复失败路径未覆盖。
- 怪种/数量/延迟/奖励/预约存活账不变；无关卡ID分支、无存档schema变化、无美术与内容ID/数值表修改。合法多标高Boss原位不压回Y=0。

## 本次验收

所有Godot进程启动前独立隔离APPDATA、LOCALAPPDATA、XDG_DATA_HOME、XDG_CONFIG_HOME。日志、临时控制脚本均经workspace_paths放在工程外`ShellStorm2-work/sessions/2026-11-02_enemy_ai/`。

| 验收 | 退出码与结果 | 预期故障 / 非预期错误 |
|---|---|---|
| 初始点审计spawn_audit_audit | exit0；4种子207点，无越界/无承重缺失 | 无预期故障，0条ERROR/SCRIPT ERROR |
| split_negative_split原实现 | exit1；母体房内、实际子怪房外0.4m | 越界失败为反向对照预期，0条引擎错误 |
| boundary_fixed_split | exit0；同正式预约链子怪全在房内 | 无预期故障，0条引擎错误 |
| verify_enemy_spawn_boundary | exit0；84检查，4朝向×凹口/四墙、原高度、合法点不改、无容量拒绝、世界锚点保留、真实分裂/召唤数量、预约清账、旧位置修复保留HP/ID/冷却 | 无预期故障，日志门禁exit0 |
| probe_expedition03_save_roundtrip | exit0；03存档往返 | 日志门禁exit0 |
| probe_expedition03_save_doors | exit0；门状态存档恢复 | 日志门禁exit0 |
| verify_encounter_trigger_room_flow | exit0；91检查 | 日志门禁exit0 |
| verify_enemy_light_motion_regression | exit0；同轮AI/照射专项保持 | 无ERROR/SCRIPT ERROR |
| verify_3d_enemy_behavior_flow | exit0；原基础行为链保持 | 无ERROR/SCRIPT ERROR |
| verify_narrative_opening_02_05（最终） | exit0；164项，楼梯承重与原剧情接入保持 | 日志门禁exit0 |

旧关卡对照：工程外控制脚本只覆盖本次新增的落点解析/恢复修复行为，使用原方法并保留场景导出属性，不覆盖工作区文件。`verify_expedition_level01_flow`当前/控制组均exit1、同12条ERROR；`verify_expedition01_spawn_ramp`当前/控制组均exit1、同3条ERROR，逐行集合相同，无新脚本错误。证据`spawn_baseline_comparison.json`。无新增白名单、未修改旧断言。

扩大剧情回归时初版通用夹取使楼梯锚点失去承重（2条失败，原行为对照164项全过）；据此按现有放置能力区分世界锚点与房间战斗，而不是改旧断言。最终164项全部通过，边界专项84项与03存档再次通过。早期新增测试曾因Variant推断导致解析失败，已修正显式类型后重新执行；失败尝试不纳入通过数。

最终工程门禁：`check_level_decoupling.py`、`check_feature_traceability.py`和本次文件的`git diff --check`均exit0；文档门禁仍为同45条现有问题，新记录/测试无缺失引用。新增边界场景已登记core与两个受影响FeatureID。所有标记通过的最终日志均另外执行`check_verification_log.py`，无非预期脚本或引擎错误。

## 范围与未执行项

未运行全量core/full、Android、全部种子及长周期瞬移/抓取压力；本次只确认出生与恢复边界，不能代替怪物后续行动穿墙专项。模块总体保持partial。原项目文档、资产命名和工作区卫生门禁既有问题沿用同日AI记录，不新增白名单。
