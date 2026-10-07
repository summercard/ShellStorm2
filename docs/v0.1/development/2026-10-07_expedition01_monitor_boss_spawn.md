# 远征01显示器Boss正式投放验收

- 日期：2026-10-07；游戏版本0.1.0；FeatureID：BOSS-STAGES / WORLD-ENTRY。
- 来源：用户要求将显示器Boss按正式Boss流程刷新在远征01 Boss房。
- 设计： [Boss002技能设计r2](../design/Boss002显示器技能设计.md)、[远征关卡01设计](../design/远征关卡01设计.md)。

## 接入与修正

现有设计源 `source/art/whitebox/tower_zones/expedition_01/v001/data/floors/floor_00.json` 已指派 `boss_content_id=boss_monitor002`。本次追踪并实跑：LevelPlanLoader/FloorPlanGenerator → TowerDescent3D房间元数据 → Dungeon3D进房 → box_boss_arena → MonsterInjector → Enemy3D与正式显示器Prefab。无需平行生成器或直接往场景树塞Boss。

保留三波encounter：第一波盒子有一个Boss，随从由盒子延迟及精英可投放规则决定；后续波次仍按原设计。Boss受击跨66%/33%阈值进入三阶段，死亡走正式killed信号、存活账与清房奖励。三波全清后，拾取正式钥匙并按原门策略开启撤离方向门；终点仍为STANDARD信标。

修复 TowerDescent3D._mark_room_cleared：远征此前错误累加塔楼下行权限并显示爬塔提示。现按模式分支，远征提示前往终点，塔楼保留原权限发放。

怪物表与技能数值沿用10月6日已登记内容，本次没有新增AssetID、改数值或重导模型。按用户后续要求，敌人账本补录投放位置与验收：资产主表第20行、3D-敌人第10行、域变更日志第52行，共12个值单元格。保留v031/active及正式资源SHA，新增显示器首波1只、三波清房、钥匙通行、STANDARD撤离、不重刷与不发下行权限说明。远征01设计的Boss房专节新增对应契约表及账本定位；独立验收结果仍记在本开发记录。专项加入core验收与功能登记。

## 验收

独立入口：`tests/verification/verify_expedition_monitor_boss_flow.tscn`。正式远征场景，固定种子77001199，真实房间碰撞；玩家实际移动到房内并走进房生命周期。禁用命运额外增兵以隔离房间编成，不预先开门、不跳过清房门策略。

- 基线：25项，只有“远征不授予塔楼下行权限”失败（退出1）；Boss刷新、身份、5200HP、模型绑定、三阶段、死亡、续波与门链均已通过。
- 修复后：25/25，退出0，非预期SCRIPT ERROR/ERROR为0；41.3秒。检查包括未进房不刷、首波一个显示器Boss、战斗锁门、自动三波、仅一次清房、存活归零、重进不重刷/发奖、正式钥匙开门、STANDARD撤离及无BOSS_KILL信标。
- 自动测试在Autoload前通过独立project.godot和APPDATA隔离数据。未操作玩家正式存档。
- 初版探针误写不存在的死亡回调，已更正为正式killed信号；该次超时运行不计验收通过。
- 场景载入存在既有房间GLB色盘UID警告（可按路径解析），不作为本次新增错误。

本专项未执行完整撤离倒计时/收益返航，也未重新验收动画视觉；这些与先前资产渲染验收分开。本次确认的是正式房间投放及清房通行。

相关回归：`verify_monitor_boss_flow` 507项、退出0、无非预期脚本错误；`verify_unique_boss_content_flow` 95/90/85模型、场地、阶段技能及掩体检查通过、退出0、无非预期脚本错误。未执行全量core/full套件。

全局门禁仍有工作区既有问题：`check_documentation_contracts.py`退出1，四个未登记场景为verify_base99_swivel_chairs、verify_expedition01_spawn_ramp、verify_expedition_resume_entry、verify_pushable_base_chairs；本次新增专项已登记。`check_asset_runtime_naming.py`退出1，涉及兔子v022–v024和基地椅子带版本运行资产、既有引用计数上升，本次未新增模型路径，未放宽门禁。定向git diff --check退出0。

运行日志：`assets/art/enemies/bosses/enm_boss_monitor002/previews/runtime/verify_expedition_monitor_boss_flow.log`、`verify_monitor_boss_flow.log`、`verify_unique_boss_content_flow.log`。

## 账本回填核验

通过ledger_index定位敌人分账本，Artifact Tool生成定向单元格后合入原表，保留原公式、数据验证及未涉及的值。主表与Prefab专表分两次事务更新目标基线，所有其他资产行指纹不变。核验目标区域的渲染，开启修改格换行并调整Prefab/日志行高。

结构门禁与无损基线均退出0：1008资产、9域、0丢失、0新增、0列摘要漂移。敌人full门禁退出1，仍为原四条SHA不一致（第6/7/13/17行），本次未改这些行与对应资源；未批量接受旧漂移。Boss行正式Prefab SHA保持不变。

远征房型状态与账本同步检查退出0。文档契约重跑仍仅四个既有未登记场景，未新增断链。逐格回读确认仅预定12个值变化，四条旧SHA问题对应资产git状态均无改动。全盘check_ledger_refs扫描长时间未完成，已停止本轮进程，未记为通过；本次登记引用的敌人分账本、Prefab及开发记录均已定向核对。
