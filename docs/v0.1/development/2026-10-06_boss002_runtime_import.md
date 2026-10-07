# Boss002 v031 正式导入与战斗验收

FeatureID：BOSS-STAGES / ENEMY-AI / ASSET-PIPELINE。游戏0.1.0，动画设计r25、技能设计r1。日期2026-10-06，代码基线 `dd7d40a83313c87dc18b592c92577bd3da6d69a4`，在既有未提交工作区上局部迭代。

## 正式路径与范围

内容ID `boss_monitor002`，资产ID `ENM-BOSS-MONITOR002-3D`。远征01 `floor_00/f00_boss` 明确指定此ID，经BossContentCatalog→MonsterInjector→Enemy3D配置；旧95/90/85 Boss维持原内容与流程。

双母版另存v031，保留v030原件。静态视觉GLB在 `assets/art/enemies/bosses/enm_boss_monitor002/components/enm_boss_monitor002/`；正式无版本Prefab在同资产 `runtime/enm_boss_monitor002/enm_boss_monitor002_root_top3d.tscn`。64骨、18684三角、3材质，模型/动作重新计算完整rest-matrix签名一致。旧签名按head/tail/deform计算，与新签名算法不同，均存入中转记录。

Blender弹簧臂依赖驱动、约束、非均匀伸缩和剪切。常规GLB TRS曲线不能完整保留，采用纯视觉GLB加30Hz求值全局骨矩阵JSON，由AnimationPlayer索引16段正式剪辑；运行时仅采样，不计算新的手臂姿态。帧间旋转插值保留伸缩/剪切残差。键盘BoneAttachment在Skeleton更新后同帧同步，修正道具延迟；Godot重名骨的 `_2` 别名显式匹配。

Enemy3D独占生命、碰撞、AI状态、伤害、死亡和掉落。MonitorBossCombat是控制器持有的技能策略；MonitorBossPresentation和MonitorBossVfx仅显示。十二态、四技能、三阶段、受击/坐地/转向、死亡、读档取消危险技能已绑定。新增2秒死亡源动作由原失衡坐地动作延长并保持末姿态；死亡不用程序缩放压扁。

独立怪物登记位于内容数据库《怪物与Boss》及新页《Boss002技能设计》，记录HP5200、速度1.204m/s、四技能伤害/范围/时刻、三阶段序列和十二态。敌人账本同AssetID递增v031，记录exported_pending_godot_validation→validated→active；中转、SHA及独立生产账本同步。XLSX用Artifact Tool制作目标单元格并合并原始OOXML，逐格核验未编辑值/公式及原有样式定义；没有整本重导造成格式/验证损失。基线只接受本AssetID与两张稀疏修改的敌人专表，未批量接受其他资产漂移。

## 验收结果

所有Godot验收使用独立project/user目录 `_scratch/monitor_qa_project`、`_scratch/monitor_userdata`，没有写正式用户存档。

| 用例 | 结果 | 覆盖 |
|---|---|---|
| verify_monitor_boss_flow | 通过，507项；退出0；无非预期脚本错误 | 独立加载、根倍率1、64骨/16剪辑、十二态、源骨位置与变形网格边界、60fps分数帧插值、真实Enemy3D物理路径自动发动全部四技能、伤害时刻/范围/墙体拒绝/重复命中、通电打断、坐地重复受击、转向、三阶段、读档和死亡 |
| verify_monitor_boss_visual | 通过，Windows真实OpenGL渲染10关键帧；退出0；无非预期脚本错误 | 叉眼受击、双螺旋坐地与摊地双手、三圈旋转、黄色单帧形状、键盘/线鞭与接地电流；完整30fps序列另存预览 |
| verify_unique_boss_content_flow | 通过；退出0；无非预期脚本错误 | 原95/90/85 Boss内容、技能与权限流程回归 |
| verify_3d_enemy_behavior_flow | 通过；退出0；无非预期脚本错误 | 共用Enemy3D感知、伤害、重力和敌人行为回归 |
| verify_level_plan_design_source | 远征01通过115项；聚合退出1 | 本次接入所在远征计划可用；99层旧计划仍引用已退役shielded |
| 敌人资产结构门禁 | 通过，15资产 | 域归属、唯一ID、Prefab引用、制作状态 |
| 分账本无损门禁 | 通过，1008资产 / 9域；列指纹漂移0 | 仅更新Boss002行与受影响专表；所有其他行与原基线一致 |
| 功能追溯门禁 | 通过，37功能 | 主设计、开发记录及两项Boss002验收入口在功能注册表中登记 |

证据：资产 `previews/runtime/flow_report.json`、`visual_report.json`、各场景日志、10张关键帧、`monitor_runtime_preview.mp4`。源码网格对比容差0.008m，骨位置0.002m；真实渲染检查并非无头结果。正常与拒绝路径均覆盖；没有通过预期报错来掩盖新增脚本错误。

## 遗留与边界

仓库聚合门禁存在本次范围外问题，详见资产下 `previews/runtime/gates/`：四项旧敌人Prefab哈希不一致；旧玩家/椅子命名及引用计数债务；四个旧验收场景未登记；22个历史脚本仍会读写旧单体账本；旧level_99引用shielded。Boss002不在上述失败清单中。没有替其他资产回填哈希或更新命名债务白名单。全工程首次import也触发若干旧Blender源的“缺少旧材质角色”断言；Boss002独立GLB/Prefab加载与专项无此错误。文档门禁在临时指定已安装的openpyxl依赖并启用UTF-8后，只剩上述四个旧场景登记问题。

本次数值为初始平衡设计，已验证代码与独立怪物表一致；尚未进行长局难度平衡或多人实玩。所有状态与技能已可调用，后续平衡可在技能契约和内容表中独立迭代。
