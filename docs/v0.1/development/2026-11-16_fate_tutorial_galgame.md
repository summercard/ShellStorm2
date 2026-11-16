# 首次命运卡教程、双侧立绘与卡牌可读性

- 日期：2026-11-16开始，2026-11-17收尾；工程版本0.1.0。
- FeatureID：`NARRATIVE-TRIGGER / DIALOGUE-UI / BASE-NPC / FATE-RULES / UI-HUD / SAVE-PROFILE`。
- 来源：用户要求已装卡下至多五字作用、候选不显示枪名且放大功能字、星/月/日角标及暗背景；首次命运掉落与首次打开触发绿苔全息教程；全部现行角色对话使用底框旁双侧半身立绘，同段持续到一起退出。
- 设计主源：[主线剧本](../design/主线剧情剧本.md)、[节点表](../design/主线剧情节点表.md)、[对话呈现r9](../design/对话与战斗信息呈现设计.md)、[08剧情施工](../08_技术施工_剧情触发.md)、[18对话施工](../18_技术施工_UI与对话系统.md)、[04 §13.0](../04_技术施工_战斗与局内成长.md)、[本地化r2](../design/武器构建链路文本本地化设计.md)。
- 状态：正式代码与内容已接线，独立真实渲染专项通过；账本写入被占用/权限错误阻塞，尚未完成登记。完整救援回归已单场通过；人工完整主线及目标设备不以专项代签。相关模块继续partial，未提交、未推送。

## 1. 卡片表现增量

- `GameText.fate_effect_brief(id, reversed)`查询语言包新分区，22张武器卡×正逆共44条摘要，每条1—5字；未知回退“效果待查”，英文预留仍回退中文。不从description截字、不修改原牌效果或原说明。
- `WeaponBuildSocket.EffectBrief`是牌面下独立13号近白单行页脚；空巢和镶嵌在途不提前显示，逆位不倒置文字。来源枪名称不再写在卡下，仅保留暖色来源模块计数与完整tooltip，真实分支仍用保守shared_unmapped。
- 候选功能说明12→18号，列宽230、说明区70高；取消当前枪名、n/N及说明前重复scope符号，完整说明仍可悬停读取。
- `FateScopeGlyph`用数学几何画星/月/日，不依赖emoji字体；独立锚在实际contain牌面左上，逆位不倒转，未揭示和空巢不伪装生效图标。正式购卡、卡巢及占卜/训练兼容入口共用。
- 命运刻印标题后接独立星标再接计数；真实渲染发现HBox内裁切Label最小宽度为0，修复为标题/计数保留内容宽度。购卡遮罩alpha0.62→0.82，唯一金币读数仍在遮罩上层，空巢暗灰蓝材质保留。

## 2. 两段教程与唯一事实所有权

新增目录内容：

- `nar_tutorial_fate_drop_01`：当前房间命运凭据实体实际成功生成并落稳后，绿苔左侧全息出场，主角回答从右侧入场，解释靠近按E查看、不自动花钱。
- `nar_tutorial_fate_open_01`：真实凭据同步认领、原offer冻结后，等构建板到位和三牌flip-ready再解释本局金币、可多买/不买、退出放弃未购、星改当前枪/月改本局角色/日改世界，以及枪上永久刻印不可替换。

表演原文保存在两份`data/narrative/*.json`，主线剧本同步逐字副本。开场以“喂，脚边那张亮的——先别当废纸踢了。”带出主角误以为绿苔钻进远征，再澄清“全息通讯。我还在基地替你看灯呢。”；打开段以“先看钱包”的调侃进入实际界面规则，没有免费赠卡、强制三选一或可拆卸的错误承诺。

`FateTutorial3D`只拥有待播实体弱引用、offer/房间/玩家证据及代际，不拥有对白行号或历史。首次落地/读档恢复注册真实实体；pending、奖励解析、活拟态、空ID、创建失败不触发。正式默认启用，test_mode默认关闭，专项显式`enable_fate_tutorial_in_test=true`。没有按具体远征ID分支。

两JSON沿schema1、manual、once=run、priority20；duration0.4仅为虚游标基准，0.2的`ui.dialogue wait=true`要等对应run所有句completed，才进入后续收口；close/skip/被替换/丢失均中止、不写完成。完成仍由NarrativeDirector经BaseManager写原`narrative_history`，无新BaseData字段、无版本迁移。中断可据真实地面或原offer重试，正常完成每档每阶段一次。

购卡教学使用独立`_fate_tutorial_locked`，不冒用交易busy；价格刷新、翻牌、按钮、退出与ESC接线统一裁决。教程完毕只重算原模态/剧情输入，不能把仍开着的购卡页直接解锁到战斗。教程期间构建板临时居中缩至0.68，为两侧人物及底框让区，结束精确恢复比例和位置。此缩排为纯表现，不改域快照。

## 3. 共用Galgame表现

`DialogueUI`继续唯一持有打字、左键/空格/回车、防漏射及临时run；新增`begin_presentation/end_presentation/get_presentation_snapshot`作为整段表现会话，与逐句run分离。

- 主角右、NPC左；首次发言从画外滑入0.3秒，另一侧说过后双方留场，焦点/表情切换不重复入场；整段结束共同滑出0.25秒，减少动效短淡入/出。
- 同源正式Bunny视觉树和电子面具作透明SubViewport半身取景，不生成第二个可行动玩家/NPC；进树前清理脚本/物理/交互/相机/声音控制。绿苔读取对应皮肤、全息扫描/断带；主角保持normal。最多两viewport，隐藏停渲染。
- Director/Adapter按剧本整段建/还会话；NPC自由交谈、首遇节拍、脚本演出和Base99Rescue分别包整段，借用既有session时不取得结束权。原主线钥匙动作、Boss实体屏障、救援奖励/起身业务不转移到UI。
- 数据库显示器对白原署名“系统”不改，但cue显式带`boss_monitor002`，左侧借真实Boss PackedScene的Model纯几何；普通系统/旁白不虚构人物。其台词、时刻、激活与战斗逻辑不变。
- `narrative_finished`延后一帧通知，先归还/清active防同步重入覆盖新session；对应测试保留真实完成语义。旧UI抢占run不发aborted的原缺口仍在，教程等待侧通过对应run/session失效拒绝假完成，不声称修复了所有抢占请求。

## 4. 实际文件

- 表现：`src/ui/dialogue/DialogueUI.gd`、`DialoguePortraitCatalog.gd`、`DialoguePortrait3D.gd`、`DialoguePortraitStage.gd`；`assets/art/ui/dialogue/dialogue_portrait_{player,green,stage}.tscn`。
- 编排：`src/narrative/FateTutorial3D.gd`、`NarrativeCatalog.gd`、`NarrativeDirector3D.gd`、`NarrativeAdapter3D.gd`与两教程JSON；显示器原JSON仅加纯表现身份。
- 正式接线：`src/world3d/Dungeon3D.gd`、`src/npc/NpcCharacter3D.gd`、`src/base3d/Base99Rescue3D.gd`。
- 卡片：`src/ui/weapon_build/`、`src/weapons/FateCardView.gd`、`src/i18n/GameText*.gd`与占卜/训练卡视图。
- 专项：`verify_fate_tutorial_dialogue.gd/.tscn`、扩充`verify_weapon_hologram_ui.gd`；外部隔离runner `scripts/run_fate_tutorial_qa.py`。新场景manual且renderer排full裸扫，四个既有FeatureID登记命令，不新增FeatureID。

## 5. 验收事实与证据

以下路径相对工程外`ShellStorm2-work/`。全部自动运行在Autoload前隔离APPDATA/LOCALAPPDATA、custom_user_dir及证据目录，只复用已有完整import证据的独立工程/缓存；不在主工程跑自动存档，不停止用户编辑器或游戏。

| 场次 | 结果 | 证据 |
|---|---|---|
| 首轮副本类扫描 | exit0但含新geometry_changed类型推断错误，未签通过；已显式bool修复 | `verification/fate_tutorial/20261116_232007_02a6d6/result.json` |
| 初轮逻辑 | 教程185项四红、0引擎错误；武器386通过。候选方位meta中文与测试枚举比较及JSON序列化误报随后修正 | `verification/fate_tutorial/20261116_232949_6e8b4d/result.json` |
| 初轮双分辨率 | 教程因orientation_roll序列化比较三红保留；卡片各401通过，0引擎错误 | `verification/fate_tutorial/20261116_235253_97a51e/result.json` |
| 安全区完整专项 | 教程720p309/1080p310、卡片各401；四场exit0/0 SCRIPT ERROR或ERROR，runner passed=true | `verification/fate_tutorial/20261117_000617_48c3e4/result.json` |
| 含显示器与载体兼容最终专项 | 教程720p315/1080p317、卡片各401；四场exit0，0脚本/引擎错误，Forward+/Vulkan真实截图与录帧 | `verification/fate_tutorial/20261117_004223_c79e00/result.json` |
| 旧对白/NPC回归 | 普通底栏、空格44项、鼠标恢复79项、NPC自由交谈与节拍均exit0；空格/鼠标各一个精确story.fail预期负测，非预期错误0 | `sessions/fate_dialogue_regression/runs/20261117_000917_afae28fb/result.json` |
| 旧时间轴最终回归 | 113项，exit0，恰好一条player.teleport预期错误，非预期错误0；前轮FakeBark缺可选current_sentence_id错误已改适配器has_method守卫 | `sessions/fate_dialogue_regression/runs/20261117_002413_49629250/result.json` |
| 关卡解耦 | exit0，7个共享机制文件，violations=0 | 本轮直接执行`check_level_decoupling.py`，原始输出为0条details |

序列化修正不是任意epsilon放宽：只对`/orientation_roll`接受**恰好等于Godot默认JSON.stringify→parse一次的值**；ID、方位、报价、claim、数组顺序与其它效果参数仍逐键严格比较，完整记录表示差异。截图与立绘不是手画替代UI，主角/绿苔/显示器均用实际正式模型。

真实图像已检查双侧留场、全息身份、标题和卡面字。教程安全区修复后人物与构建板分离；纯系统无角色，显示器明确身份可见。过程回放使用实采时间戳，不冒充60fps实时录屏。截图中的fixture地板/灯光不等于人工整关。

完整`verify_base99_rescue`首轮180秒超时，未到成功marker（期间只有旧UID回退warning）；首次600秒请求因副本锁冲突未启动，未抢占或删除锁。副本释放后再次独立运行359.989秒完成：exit0、`BASE99_RESCUE_OK`、0脚本/引擎错误，`sessions/fate_dialogue_regression/runs/20261117_004610_463f68f1/result.json`明确passed=true。该场加载真实远征和基地并覆盖原救援R01—R17，逻辑通过不代签人工完整主线或救援真人观感。

## 6. 账本写入阻塞

计划更新UI账本既有r26 `UI-SCREEN-DIALOGUE-BAR`、r27 `UI-WEAPON-BUILD-BOARD`、r28 `UI-FATE-HOLOGRAM-PRESENTATION`，新增三项 `UI-DIALOGUE-PORTRAIT-PLAYER / GREEN / STAGE`。它们是UI同源模型投影，不是新角色模型或VFX3D；场景中已有稳定asset_id，但**账本尚未登记**。

事务` sessions/2026-11-16_fate_tutorial_ledger/txn_20261116_232340_679754/blocked_result.json`明确`blocked_before_first_write`：openpyxl保存UI workbook得到PermissionError Errno13，检测非只读且有WPS进程但未认定锁归属。不强关进程、不更权限、不另壳覆盖；已通知用户关闭UI账本后再继续。UI workbook、来源索引、基线、媒体门禁四文件改前改后SHA相同，未发生半事务。备份与计划在同事务目录，恢复写入前必须重读并核对最新代码hash，不能盲用旧断言。

改前门禁structure/UI full/split各exit1，分别有17项、5项sha mismatch、24项旧问题；本次未写入故未跑改后门禁，不声明新增问题归零或全库全绿。此前被安全检查拒绝的文档/命名/注册/追溯四项全局命令本次不重试、不换壳绕过；只能保留未执行边界。

## 7. 交付与未完成

成品位于`outputs/fate_tutorial_galgame_20261116/`，含真实双分辨率截图、过程帧回放、来源摘要、原始专项报告及账本阻塞清单。它是工程外预览，不是游戏运行依赖。

- 尚未完成：UI账本解除占用后的正式登记与基线同步；人工基地→远征→首卡→后续主线全流程、所有嵌套组合、Android和性能压力。救援旧逻辑全链已独立通过，未人工取代完整主线。
- `focus_target`只透传元数据，目前没有自动聚光/圈选；不宣传已做逐控件高亮。教程靠台词、图标、左右人物焦点与临时安全布局引导。
- 不改掉落概率、候选池、报价、月/日不占枪槽、确认与退款、BaseData2.0/武器身份、四钥匙业务及剧情动作时序；不以教程发钱/发牌/扩大容量。
- 备份为`ShellStorm2-backup/2026-11-16_fate_tutorial_galgame/before_edits/`及卡片`2026-11-16_weapon_card_readability/before_edits/`；不覆盖并行工作区修改，不提交推送。
