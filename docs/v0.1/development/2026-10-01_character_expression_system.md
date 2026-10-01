# 独立角色表情系统与8种网格表达

FeatureID：ENTRY-AVATAR、ASSET-PIPELINE；ModuleID：CHARACTER-EXPRESSION；工程0.1.0；日期2026-10-01。[目标契约](../design/character_expression_system.md)。来源：用户要求方块网格情绪、红色生气、其它符号，先做8种、单独入账并由状态机调用独立系统。

## 实现

父电子面具 `CHR-PLY-BUNNY01-FACE-ELECTRONIC-MASK` 升级v003，原v001/v002母版与原角色11网格/骨架/姿态不变。新增模型/动作双母版，共享 `SKEL-BUNNY01-004` 的原静止签名。8个实际方块网格各有独立GLB、PackedScene、AssetID、manifest及中转记录：

| expression_id | 表情 | AssetID | 颗粒数 | 类型 |
| --- | --- | --- | --- | --- |
| neutral | 平静 | CHR-PLY-BUNNY01-EXPR-NEUTRAL | 140 | 情绪 |
| happy | 开心 | CHR-PLY-BUNNY01-EXPR-HAPPY | 52 | 情绪 |
| sad | 难过 | CHR-PLY-BUNNY01-EXPR-SAD | 68 | 情绪 |
| angry | 生气，红色 | CHR-PLY-BUNNY01-EXPR-ANGRY | 80 | 情绪 |
| surprised | 惊讶 | CHR-PLY-BUNNY01-EXPR-SURPRISED | 78 | 情绪 |
| love | 爱心 | CHR-PLY-BUNNY01-EXPR-LOVE | 79 | 情绪 |
| question | 疑问，? | CHR-PLY-BUNNY01-EXPR-QUESTION | 60 | 符号 |
| alert | 警示，! | CHR-PLY-BUNNY01-EXPR-ALERT | 56 | 符号 |

每颗10.8mm，网格间距14mm。集合 `01_部件/眼镜/眼镜__electronic_mask/表情__<id>`；共享双母版按source_object定位，子组件不复制整套角色源。运行路径稳定无版本，子组件首版v001，父面具v003；显式分类child_variant/version_increment。

独立系统代码放在 `src/presentation/expressions/`，无需Player3D、角色动作库、衣柜或Autoload。唯一所有者为CharacterExpressionSystem；Catalog只提供数据；PlayerExpressionStateAdapter单向把真实玩法表现事件转换为命令；ElectronicMaskExpression3D只换网格/独立材质。状态机在初始化完成后接入事件，初始平静；变化状态随机调用，重复同状态/进度事件不重复抽取。背景首次4秒后随机，此后3–6秒；明确命令可指定表情和保持时间，保持期间背景随机暂停。用户可直接调用 `player.expression_system.request_expression("angry", 2.0)`。

保留Blender局部眨眼/亮度曲线。嘴形不随眼睛闭合，?和!不压缩；表情事件不装备面饰、写存档、改HP/碰撞/武器或改变玩法状态。换装隐藏期间可更新表情，重新显示沿用最新表情。

## 验证与账本

- 源独立重开：8网格数量与计划逐项一致，原11网格/UV/材质/变换/权重不变；原骨架签名、1448壳体顶点与双母版局部曲线通过。
- `verify_character_expression_flow`独立与正式玩家调用：无头690项，Forward+700项；300次抽取无连续重复，8种全部可达；未知ID/负数/非有限保持值原子拒绝；保持结束恢复随机；独立实例；实际StateMachine转换触发表情，重复进度事件不触发；角色状态/HP/碰撞/武器不变；卸下面饰不会被表情命令重新装备；符号不闭合。
- Forward+逐种捕捉实际网格，8张不同图像；红色生气颜色专项通过。[实际总览](../../../assets/art/characters/player/chr_player_capsule01_3d/variants/bunny01/components/face/electronic_mask/previews/expressions_overview.png)。
- 既有电子面具专项无头73项、Forward+76项；眨眼/闪烁、保存/读档/换装通过。5项角色回归均退出0：边界、动画、衣柜、返回持久化、母版契约。
- 8个子资产先行登记《资产主表》23–30行；父行22升级v003。随后主行与组件/3D/动画/中转专表分事务推进，其他资产指纹保留；每种表达各有独立资产、组件、3D分页和表达记录，不伪造玩家状态。
- 最终退出码、预期失败、非预期错误、未执行项及当前门禁限制见[机器报告](../../../assets/art/characters/player/chr_player_capsule01_3d/variants/bunny01/components/face/electronic_mask/verification_report.json)。最终专项无预期失败或非预期脚本错误；原色盘UID回退警告保留。未运行整游戏full及移动设备性能。未提交或推送。

初次导入在扫描前预加载新GLB时有缺失缓存错误，正式导入完成后再次执行并校验；总览合成的格式错误及测试哈希API错误均已修复后重跑，不计入最终通过。全局既有女仆头哈希、版本命名与三项场景注册门禁问题与本功能隔离记录。

验收期间共享工作区的DungeonRoom3D端口同步代码发生并行改动并一度阻断Autoload编译。实例方法问题由该处后续修改恢复；本次只将`marker_position_meta`补为显式`Variant`，消除“Variant推断警告按错误处理”的编译阻塞，未改变运行值或端口规则。随后再次执行独立逻辑690项与真实渲染700项，日志没有非预期脚本/引擎错误。
