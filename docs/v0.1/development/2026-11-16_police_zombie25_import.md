# 警察僵尸2.5正式替换与256贴图

- FeatureID：ASSET-PIPELINE / ENEMY-AI。
- 工程版本：0.1.0，不提升游戏版本。
- 来源：2026-11-16用户要求先读游戏框架、规范、账本，再导入替换并更新账本；追加运行贴图压到256。
- 资产身份：既有`ENM-RANGED-SPORESHOOTER01`，显示名保留“保安僵尸”，逻辑ID保留`ranged_caster`；增加“警察僵尸2.5”别名，不新增怪种。
- 当前状态：运行资产v004已接入，完成源与正式表现L1、Forward+/Vulkan真实渲染L2；完整关卡人工游玩、Android设备未验。不提升全局功能partial状态。

## 1. 前置与范围

已读`CREATION_PIPELINE_OUTLINE.md`、`PRODUCTION_FRAMEWORK.md`、`DOCUMENTATION_STANDARD.md`、`ART_SOURCE_LAYOUT.md`、`WORKSPACE_LAYOUT.md`、`MODULE_INDEX.md`的ENEMY-AI/ASSET-PIPELINE入口、怪物设计、角色动作接入流程、运行贴图预算与账本分类/命名规则。

账本经`ledger_index.json`路由到敌人域；目标原记录为《资产主表》7行、《3D-敌人》8行、《敌人动画与状态》22行。既有目标为36骨/10剪辑/L_Hand外挂枪；新模型不能直接沿用该挂载与红眼配置。

替换只处理视觉资源及表现适配。`Enemy3D`继续拥有AI、状态、HP、伤害、三弹散布、弹丸出生位置、攻击时序、速度、碰撞、导航、掉落与死亡结算。本事务未编辑Enemy3D、刷怪或关卡数值。新资源同时影响10种借用ranged_caster视觉的egt代理，保持它们的逻辑ID、体型与染色规则。

## 2. 源、导出与稳定入口

- 模型源：`art_source/enemies/normal_enemy_3d/police_zombie25/source/model/police_zombie_25_model_v002.blend`。
- 动画源：`art_source/enemies/normal_enemy_3d/police_zombie25/source/animation/police_zombie_25_animation_v002.blend`。
- 稳定GLB：`assets/art/enemies/normal_enemy_3d/ranged_caster/components/enm_ranged_sporeshooter01_visual_top3d.glb`。
- 稳定Prefab：`assets/art/enemies/normal_enemy_3d/ranged_caster/runtime/enm_ranged_sporeshooter01_root_top3d.tscn`。
- 运行贴图：`assets/art/shared/textures/enemies/tex_color_ec827f2a2c65836f15cc.png`。
- 规格：65骨、474制作顶点、918三角、单蒙皮网格/单材质、一体枪刚性跟随`mixamorig_RightHand`。
- 制作源30fps：`armed_idle`3.2秒循环、`walking_armed`1.6秒循环、`running_armed`0.8秒循环、`shoot`0.8秒单次。射击视觉关键点0.384秒/48%，不接管玩法发弹。
- 源保持Blender -Y；仅VisualGLB子节点yaw180°、统一缩放1.85804992，归一静止视觉高1.857143m，再由既有实体0.7倍率展示约1.30m。Prefab根scale=1，碰撞表radius0.88/height1.62保持。
- 贴图从2048²等比Lanczos缩到256²。运行GLB外链共享PNG，并重排二进制buffer物理移除原2048内嵌字节；源高清图和双Blend哈希不变。PNG约77KB；S3TC、ETC2实际导入尺寸均256²，`process/size_limit=256`。
- `.gitignore`定点放行该GLB及新PNG的`.import`，保存动画采样、外链图片与256导入契约，避免干净克隆回归默认配置。

双母版独立重开骨架签名相同：`b3feb75b3488678b7611e93b72eb56be711db629f0ba8c8f84098968d7cf2345`。签名包含骨名、父级、rest矩阵、尾点及deform，不把联合网格签名冒充骨架签名。

## 3. 表现适配

`ranged_caster_formal_visual.gd`取消旧外挂枪创建，使用真实RightHand蒙皮几何判定，不生成第二把枪。保留速度迟滞0.62/0.50、满速平滑0.30秒、循环交叉淡化0.16秒及攻击抢占。

四剪辑不包含hurt/dead。请求缺失动作明确回退到`armed_idle@0`，停止相位和残留混合；受击仍闪白，`flash_hit(false)`不插受击姿态。正式死亡继续无尸体绿色特效与回收，不恢复旧倒地动画；保留2.4秒兼容接口不代表产生尸体。

红眼按原贴图双瞳射线命中脸部，再转正式导入头骨空间；Godot实际骨名为`mixamorig_Head`。模型通过`get_eye_socket_spec()`声明骨名、双锚点和半径；EnemyAvatar共用适配优先读模型声明，其它模型仍走原配方。普通/强化目标实测跟骨误差约1.24e-7m。共享文件中的并行exploder代码保留；遇到该并行代码的`exploded := Variant比较`编译错误，仅显式标注bool，不改变含义。

## 4. 本次验收事实

过程与日志总目录：`../ShellStorm2-work/sessions/2026-11-16_police_zombie_import/`。

| 验证 | 退出码/结果 | 范围与限制 |
|---|---|---|
| 双母版骨架签名 | 0/pass | Blender4.5独立重开，两源签名一致，源哈希不变 |
| 正式保安表现专项 | 0/pass，0脚本错误 | 65骨/4段/256/12态、缺片回退、闪白、48%边界、实际速度迟滞 |
| 正式Forward+/Vulkan | 0/pass，0脚本错误 | RTX4060Ti，258图，普通/强化与10代理共12类；动作俯视及侧面连续采样 |
| 明暗移动连续与攻击抢占 | 0/pass | 原单帧跳变<12°及切段约束保留，不放宽阈值 |
| 攻击站定 | 0/pass | 原行为回归 |
| 攻击恢复 | 0/pass | 3278检查、8条说明；延迟弹队列与恢复保持 |
| 普通/强化警察目标契约 | 0/pass | 16检查、四段各21点；双瞳实际跟骨、碰撞、游戏根及枪向前(-Z) |
| 目标CPU蒙皮脚底 | pass | 全动作采样最低约-0.000722m，低于3mm阈值；不宣称连续时间零穿透 |
| 256运行文件 | pass | PNG与S3TC/ETC2均256²、无内嵌图像、原高清图不变 |
| 全库红眼专项 | 超时，未通过 | 120秒启动预算耗尽，没有完成标记；不得以目标专项代签全库 |
| 运行资产命名 | 0/pass | 无新增带版本运行路径，原有债务仍保留 |
| 敌人账本structure/full | 1 | 仅旧row55收租人`开发中（partial）`状态不被门禁接纳，目标row7无哈希问题 |
| 全库split | 1，24项 | 与更新前历史债集合对照保留；目标AssetID指纹正确，未吸收其它资产/专表漂移 |
| 文档契约 | 1，11断链 | 旧框架图片、旧战斗/合成链接等，不修无关文档 |
| 全库贴图策略 | 1 | 其它VFX/胖子候选/石甲巨人/玩家外部图等旧或并行问题；本警察路径无错误 |

最初专项旧的高速巡逻“只能走路”断言与现行按速度切档冲突，已按真实满速夹具验证迟滞，不回退生产规则。部分早期引擎启动原生异常、错误探针入口及测试夹具不包含在最终通过；最终以`*_qa_result.json`实际退出码、完成标记与空errors为准。正常UID回退警告与脚本错误分开记录。验收在Autoload启动前隔离APPDATA/LOCALAPPDATA等；隔离工程使用目录junction和共享只读导入资源，不能声称源目录完全物理隔离。曾有一次诊断直启未显式隔离，不作为正式通过证据。

## 5. 账本及追溯同步

敌人账本仍52条，不新增重复AssetID。两次独立原子事务共34格：主表9格、Prefab页6格、动画页5格、域日志14格；日志为v0.1.49/v0.1.50。R/S公式、DV、其它资产行与并行小僵尸/石甲巨人/炸弹果改动保留；无损基线只更新目标行指纹、目标专表批准差异及受影响列摘要，不洗平其它债务。逐格回读和ZIP公式形态比对通过。

同步当前源索引（只新增两源）、runtime_texture_policy、源manifest、中转记录、Prefab元数据和包README。去重门禁计算报告为replacement/pass、同ID和同哈希0；原脚本最后truncate-open在本机报OSError22，已按同一报告通过r+b方式同步元数据，不修改门禁算法、不改ACL。

运行GLB SHA：`fa2b7fd396d2d2244ecb9ca90b058790b5925e5f5e4b78b5e1600d7433813604`。
Prefab SHA：`a569572389c6821a873907548b698942db5706f11810efa171908e52437db40f`。

## 6. 回滚与未执行项

替换前19个目标/共享文件备份并哈希验证：`../ShellStorm2-backup/2026-11-16_police_zombie_import/before_edits/`；账本提交前另有`ledger_prewrite_20261116_203359_844727/`两阶段快照。共享文件须逐差异回滚，禁止整树覆盖后续并行改动。

未执行：完整关卡人工跑图、Android设备、PCK发行实测、全局红眼完整通过、全游戏性能长期测试。未制作独立hurt/dead/reload或融合手指开合。未提交或推送Git，不宣称整工程全绿。

查看交付：`../ShellStorm2-work/outputs/2026-11-16_police_zombie_import/警察僵尸_正式游戏256贴图动作预览.mp4`及`final_acceptance.json`。
