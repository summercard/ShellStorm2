# 炸弹果四足机甲两段动画与正式导入

## 1. 范围与依据

- FeatureID：ENEMY-AI / ASSET-PIPELINE；工程版本0.1.0；资产 `ENM-BOMBER-FRUIT01` / `exploder` / v002。
- 来源：2026-11-16用户要求，新四足机甲模型制作高频机械移动、原地抖动蓄爆两段，原尺寸保持，读设计/账本/技能并自检、导入游戏。
- 主设计：[怪物设计·炸弹果四足机甲表现](../design/怪物设计.md)；AI与爆炸Owner仍为Enemy3D。
- 已读目录/文档标准、角色双母版流程、普通怪制作与导入流程、敌人分账本主表r10/动画页r25、总目录分类与命名规则。场景设施技能仅复用目录/导入/源保护规则，不将设施公共色盘要求套到本角色原贴图。
- 桌面输入 `C:/Users/zhuangmenghong/Desktop/新怪物模型/炸弹果/自爆蜜蜂.zip` 只读；SHA256 `f230851b6772d9f3a0aac2fe7bd9b7e904e4ce9eddd0b020df9751cf21e29383`。FBX、JPEG提取至工程外会话，不改原件。输入许可仍待确认。
- 开工已有大量并行未提交改动；本轮没有回滚、清理或覆盖其它会话内容，不提交、不推送。

## 2. 制作和尺寸

原输入275顶点/546三角，自动骨架22骨但四腿链不完整。保留原网格、UV和贴图，重建14骨（Root、Body、四腿各Upper/Lower/Foot），13 deform、每顶点最多3权重，模型与动画双母版骨架签名一致。机甲腿采用短骨链求解和局部刚性主导权重；未新增造型或展示底座。

| 项目 | 结果 |
|---|---|
| move | 60fps，F0–30，0.50s循环，F30闭合，不把重复闭合帧算第二周期 |
| explode | 60fps，F0–54，0.90s单次；锁脚、轻沉、主体8→24Hz加速颤动 |
| 原可见包络 | Godot旧程序模型实测局部宽1.620000m/高1.150000m/深1.418732m；排除StateVFX/血条/bob和附肢旋转 |
| 新静止源尺寸 | 宽1.241947m/高1.150000m/深1.089577m；高度等比归一，不非等比拉宽 |
| 世界基准高度 | `1.15 × 0.70 × 0.78 = 0.6279m`，与旧可见高度一致 |
| 朝向/原点 | Blender +Y前/Z上；Godot -Z前/Y上；脚底0，包装根Scale=1 |
| 原玩法碰撞 | 局部radius0.88/height1.28，外层0.546，世界radius0.48048；保持不变 |
| 优化 | 独立优化Blend重开后导出；执行微距重复点/退化边/孤立点清理，无可安全减除几何，546→546，减面率0；不把三角化当减面 |

源级采样：move 61姿态、explode 109姿态（120Hz）。Root误差0；move首末顶点误差0；最大脚底接触误差分别0.453mm/0.908mm；四脚移动抬高约54.7mm。最低几何分别-0.439mm/-0.908mm，在3mm验收容差内。没有以此声称任意时间/任意动作全域绝对零穿透或零自交。原体型轮廓不同，新宽深比旧程序壳小；这是保持新形体而非拉宽凑尺寸的明确选择。

## 3. 文件与接入

制作源（相对工程根）：

- `art_source/enemies/normal_enemy_3d/exploder/source/model/enm_bomber_fruit01_model_v002.blend`
- `art_source/enemies/normal_enemy_3d/exploder/source/animation/enm_bomber_fruit01_animation_v002.blend`（几何外链前者）
- `art_source/enemies/normal_enemy_3d/exploder/export/v002/enm_bomber_fruit01_optimized_v002.blend`
- 同包 `asset_manifest.json`；当前源索引仅追加本包三源，完整SHA见清单。

稳定运行包：`assets/art/enemies/normal_enemy_3d/exploder/`。

- `components/enm_bomber_fruit01_visual_top3d.glb`：495900字节，SHA256 `55f410b3780b94916005b9152d5ae14741163223824a6cd963894df965159eaa`。
- 同目录原贴图导出的稳定JPEG为2048×2048，SHA256 `7f72f099a78e3c31e0ba130cb6bf441d7e124d6916c42a8cb26697aa4a4f44c0`，与GLB内嵌JPEG字节一致。
- `runtime/enm_bomber_fruit01_root_top3d.tscn`、`exploder_formal_visual.gd`、`exploder_post_import.gd`、`character_transfer_ledger.json`。
- 修改 `src/enemy3d/EnemyAvatar3D.gd` 的映射/挂载资格/死亡通知；`EnemyWarmup.gd` 加入预热；不修改Enemy3D玩法逻辑。
- 七只exploder代理怪仍使用旧程序壳；普通/精英互斥沿原契约，未修改刷怪表或远征房间。
- move按实际速度积分相位，零速停步；telegraph按实际前摇比例采explode，attack/recovery末帧。没有root motion或动画方法轨道触发伤害。被击杀保留原0.34s回收窗口，主动自爆当帧隐藏。
- `.gitignore`对白名单本包GLB及JPEG `.import`，保留60fps与post-import循环配置；导入配置使用 `gltf/embedded_image_handling=1`。

## 4. 验证结果与中间失败

所有Godot子进程在Autoload前隔离APPDATA/LOCALAPPDATA/HOME/USERPROFILE/TEMP及XDG目录；没有启动正式存档游戏。所有过程出口为工程外 `ShellStorm2-work/sessions/2026-11-16_1904_exploder_mech/`。

| 验证 | 退出码/结果 | 证据（相对会话） |
|---|---|---|
| 双源重开、权重、骨架签名、落脚、循环 | 通过，全部源级断言true | `validation_blender.json` |
| 旧模型实际AABB | Godot exit0 | `baseline/baseline.json` |
| 独立冷导入与正式Avatar映射 | exit0，errors空 | `live_integration/runs/20261116_201614_negative_291232/test.run.json` |
| 两项错误时长负测 | 两子进程exit0，但确实触发预期Assertion；passed与assertion_seen均true，不伪报exit1 | 同目录 `negative_result.json`及负测日志 |
| 官方batch五项 | 总exit0，count=5，无非预期ERROR | `game_regression/official_batch.log` |
| 最终正式导入、贴图读回 | exit0，材质三路非空、2048²图可读 | `game_regression/final_texture/final_texture_result.json` |
| 最终仓库表现专项 | exit0，`EXPLODER_PRESENTATION_OK checks=152` | 同目录 `presentation.log` |
| 最终真实Enemy3D补测 | exit0，主动爆炸100→70单次且0碎片；被击杀恰8碎片，每片8；碰撞、重力、自动telegraph采样通过 | 同目录 `real_exploder.log`及`exploder_real_evidence.json` |
| 最终Forward+真实Avatar录帧 | 冷导入/正测/录帧均exit0，errors空，86PNG | `live_integration/runs/20261116_212335_render_290220/` |
| 动态预览 | 正常速度MP4及0.5倍检查版，工程外HTML | `../../outputs/2026-11-16_exploder_mech/`（工作根下outputs） |

官方五项为行为、收招、攻击站姿、受光状态、受光运动专项。五项batch在材质修复前通过；最终修订后只重跑贴图/仓库表现152项与真实炸弹果补测，不冒称又跑完整五项。收招专项8条NOTE保留，其中抓握大师单人夹具自灭、链枪手未出现排队分支不算该分支已验。

中间失败及处理：

1. 初次源级Root使用单位全局矩阵而非静止矩阵，独立检查根与脚底失败；修正为静止骨矩阵后重新生成双源，全部专项通过。Blender错误时可能仍返回0，验收以JSON passed和无Traceback共同判断。
2. 初次冷导入runner漏传env参数，脚本TypeError；修正后重跑，不将初次计通过。
3. 初次引擎录帧发现白模：误用设施 `embedded_image_handling=0` 丢弃贴图。修正为1并正式重导，生产材质与仓库专项均增加非空贴图/尺寸断言；最终渲染两张关键帧人工查看已恢复红橙球体和深色四足，未见明显拉丝或严重穿插。历史白模图不作为交付预览。
4. 入树后设置autoplay的警告移到post-import处理；最终修订0 autoplay警告。仍保留公共资源UID警告，未静音。
5. 账本中间路径键/列名/日期序列化失败及最终受控列摘要阻断，均按事务修正，未批量接纳历史漂移；详见ledger报告。

## 5. 登记与门禁

敌人账本既有主表r10升级，不新增重复AssetID；动画页r25及新增两剪辑r67/68、3D-敌人r13同步。最终active，runtime_integrated=true，validation=passed；最终转正日志v0.1.52/r94。主表、动画和Prefab分事务，只改本包指纹/允许的专表增量，其它资产和既有漂移保留。保存前备份位于上层 `ShellStorm2-backup/2026-11-16_1904_exploder_mech/before_edits/`。

| 门禁 | 最终退出码 | 结论 |
|---|---:|---|
| registry structure | 1 | 17项既有问题，前后相同，本包0新增 |
| registry full enemies | 1 | 仅收租人r55非法状态，前后相同 |
| verify_ledger_split | 1 | 24项既有问题，前后相同，未接纳历史专表漂移 |
| runtime naming | 0 | 通过 |
| 文档契约 | 1 | 最终复核仍11条旧断链，去行号对照新增0；详见会话final_checks.json |
| 专项登记/Feature追溯/关卡解耦 | 0/0/0 | 最终复核通过，未放宽规则 |

最终交付HTML本地资源引用全部存在，两个正常速度视频及两个慢速检查视频可读取；桌面原始ZIP哈希不变，diff空白检查通过。

机器登记和最终摘要：`final_promotion/final_promotion_report.json`。manifest与transfer除各自promotion_history路径/时间外内容一致，10项源/运行文件SHA均匹配。

仓库固化专项：`tests/verification/verify_exploder_presentation.gd/.tscn`，归core；`feature_registry.json`登记到ENEMY-AI/ASSET-PIPELINE，不提升这两个整体partial状态。

## 6. 未执行与交付边界

- 未执行完整远征01人工实玩、目标设备/Android/APK、core/full/aggregate总套件、完整存档迁移测试。
- 引擎预览使用真实正式Avatar/材质和确定性AI输入，不冒充完整关卡或完整Enemy3D物理录像；真实Enemy3D另有独立玩法专项。
- 只交付move/explode，不宣称已制作idle/hurt/roar/dead。无需把原玩法改成动画结束驱动。
- 用户桌面原件不改；制作源、优化源和正式输出均保留。动作母版默认打开move，在Action库选择explode即可检查第二段。
- 未提交、未推送。所有未提交的其它会话内容保持原状。
