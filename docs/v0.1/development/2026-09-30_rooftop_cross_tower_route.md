# 主塔100F跨塔天桥接入

功能：WORLD-PLAN / ASSET-PIPELINE。设计见[跨塔天桥](../design/rooftop_cross_tower_route.md)。适用0.1.0；基线c421b049及已有塔楼导入工作区。

## 本次改变

- 主场景 `Blocks/Rooftop/CrossTowerRoute` 挂独立稳定TSCN；塔2 (20,-90) 低16m、不可进入；塔3 (-12,-173.925626) 行走面与100F齐平。
- 主塔北侧x[17.5,22.5]同时删除一段可视女儿墙与碰撞。原68直段变67，默认独立楼层仍封闭，远征不接入。第一段含30m楼间净距及屋顶上方延伸，第二段西北转30度。
- 依用户后续要求，路线由初稿v001普通5m宽桥更新为v002塔吊起重臂桥。两段各用两节32m原吊臂，总长64m/段；原检修格栅净宽1.65m、桁架与护栏完整保留。移除普通桥板/纵梁，复用入口电柜封闭较宽桥口余隙；不拉伸模型。Godot实例旋转80°/110°抵消原10°烘焙方位，根y=-0.642502对齐原格栅行走面。
- 独立承重与按设备实心部位分段的代理碰撞归路线包装。塔3南侧栏杆的覆写仅属于路线，原塔楼源/Prefab与塔2三个塔吊身份不变。
- 零新增材质资源，复用原有材质，零新增MultiMesh批次。用户后续澄清 minimmap 指 MipMap：公共色盘必须无损、无 MipMap；不调整既有小地图和全球HUD规则。
- 场景分账本新增路线身份及真实Prefab行；定点更新已编辑主场景身份的哈希；其他资产哈希不接受或批量修复。备份在仓库外 `_scratch/cross_tower_ledger_backup`。

## 验收

APPDATA在Autoload启动前隔离到 `I:/_ss2_appdata_cross_tower_20260930`。`verify_cross_tower_route.gd` 使用真实OpenGL渲染器：308检查、0失败、退出0。包含67直段计数与桥口空槽、0.5m间隔连续承重射线、玩家同尺寸胶囊连续穿过整条路线、真实玩家到达后留在塔3及100F所有权、护栏侧向阻挡及转角胶囊扫掠、四节原吊臂实例、塔2无承重、根缩放1、普通实例无MultiMesh。

验收快照见 `open_world/runtime/cross_tower_route/acceptance.json` 与两张QA图片。取景临时关闭雾并补环境光，仅属于探针，不修改主场景灯光/材质；既有公共色盘UID回退和Compatibility不支持Forward+特性的警告不计为本次脚本错误。

最终专项：`check_cross_tower_route.py`退出0；`verify_rooftop_32x32_contract`与`verify_tower_level_blocks`均退出0；原塔楼309组件导出/哈希检查通过，确认源Blend和GLB未修改。登记结构退出0，9域732项无损基线退出0。场景账本full仍有152项既有SHA漂移，改前/改后逐项相同，新增0。命名全局门禁退出1（既有14文件/3目录/版本引用债）；文档门禁退出1，仅三个既有未登记验收入口：`verify_base99_swivel_chairs`、`verify_expedition01_spawn_ramp`、`verify_pushable_base_chairs`。本路线无新增命名或文档问题。未执行全游戏长测/移动端LOD与性能预算，不宣称全项目全绿。

## 回退

移除主场景的路线实例并重建楼层即可恢复原闭合北侧围护。可独立调整路线TSCN实例摆位；不可重跑旧塔楼布局生成器覆盖本路线。原Blender与组件均未改动。
