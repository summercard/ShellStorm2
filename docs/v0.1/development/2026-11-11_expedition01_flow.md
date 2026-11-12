# 远征01十三房节奏、奖励与框架登记

日期：2026-11-11；记录ID：`2026-11-11_expedition01_flow`；工程版本：`0.1.0`；分支：`0.2`。
功能ID：`WORLD-PLAN`、`WORLD-ENTRY`、`ENCOUNTER-EVENT`、`REWARD-SERVICE`、`WORLD-LOOT`、`FATE-RULES`、`NARRATIVE-TRIGGER`、`SAVE-RUN`、`BOSS-STAGES`。全部挂既有ID，不增加平行模块或注册表schema。
设计依据：[远征01 §十一](../design/远征关卡01设计.md#十一首关13房小改实施冻结2026-11-11)、[触发器刷怪 §10](../design/触发器刷怪设计.md#10-运行时遭遇事件encounter-event2026-10-15)、[奖励设计 r5](../design/战斗奖励与物品流转设计.md)、[接入规范](../关卡接入规范.md)。三份协作设计只读，不由本登记事务覆盖。

## 1. 基线、授权与备份

- 修改前已推送基线：`46c1ca78`（建立心流修改前当前版本基线）；本地远端引用 `origin/0.2` 包含该提交。本会话开始HEAD为 `973f41b3`，另有协作方未提交改动，不能把当前工作树等同于纯净的 `46c1ca78`。
- `project.godot` 仍为 `0.1.0`；分支名 `0.2` 是开发线，不与工程版本、设计修订或存档schema冲突。本事务不提交、不推送。
- 备份：`ShellStorm2-backup/2026-11-11_expedition01_flow/before_edits/`，按工程相对路径保存。已有备份不覆盖；恢复须逐文件比对，不能整树覆盖协作进展。
- 本登记事务负责汇总游戏总设计、模块索引、机器注册表、开发记录入口/本记录、必要的接入规范，以及Runner专项登记；生产代码、关卡数据、资源与XLSX由对应Owner先行修改，本记录汇总最终交付事实。
- 用户所述 `development/README.md` 按工程规范落在 `docs/v0.1/development/README.md`；工程根无同名目录，不新建第二套开发记录入口。

## 2. 设计追加：固定时间窗口封门战与死路回退（2026-11-11）

本次用户调整已先更新设计主源，尚未改运行数据或生产代码：

- room03 本轮修正为“封门后先停顿60秒，再进入刷怪”：`preparation_sec=60`、`start_delay_sec=0`，准备期绝不刷怪；60秒结束第一波立即派发，随后按清波与间歇推进既有 `5→7→8`。本轮不启用重复末波或固定刷怪截止；其他房间的固定窗口设计仍待独立施工。
- room03 本轮不启用固定刷怪截止，也不改通用 `ENCOUNTER-EVENT` Director。room03只使用 `preparation_sec=60`、`start_delay_sec=0`：60秒准备期不刷怪，倒计时结束后进入现有有限波次链。其他房间固定时间窗口仍保留为后续独立施工项。
- `WORLD-SECRET` 允许隐藏子图出现死路；入口传送口在破板后长期保留，子图普通连接门免费双向，玩家可沿原路退回首间并返回主图。末端 `R0/R1` 返程门继续存在。该规则不改主路跳过房数、Boss 边界或撤离阈值。

## 2. 目标规则与当前状态

| 范围 | 批准规则/Owner交接 | 当前状态 |
|---|---|---|
| 十三房结构 | 安全屋→10内容房→Boss→撤离屋；沿用拓扑、模板、尺寸、门位及秘密点 | 本轮不改结构；数据只读专项待补结果 |
| 刷怪节奏 | 盒式房仍走原波次链；03/04/06/09/10使用固定总时间窗口、`clear/tick/duration_sec>0` 与 `stage_advance=clear`，时间到停止新波但保留已激活怪物，全部激活怪物清空后才完成；间歇从真实清空开始，末波不等待 | 设计已更新；通用 Director 能力、运行数据与专项验收待施工 |
| 空间与积压 | 默认离玩家6m，03首胖8m；`max_alive`按实体/休眠/预约/延迟统计，临时无合法点保留pending，下次重试不重掷，硬失败停止派发 | 已实现待验收；静态数量不等于实际安全落点 |
| 灯光与封门 | Director管事件；Host调用房间 `set_room_light_on()`；封门/房间清理归原Owner | 灯光正式接口已存在，纠正“light无正式接口”的旧事实；失败仍如实报告；整关待验收 |
| 固定奖励 | `ClearDropService`新局冻结清房计划；逐房小包2100弹/5药，教学箱另100弹及蓝枪；02/07命运机会替代原概率；07额外紫步枪绑定标准弹 | 服务及接线已实现待验收；箱、小包、追加枪分账，不自动装备、不迁卡、不补旧局 |
| 命运购买 | 凭据携带源房/源箱/普通报价标记；`price_index_for_room()`按来源定价，02保证现有普通正位候选；冻结offer沿旧快照恢复 | 已实现待验收；不新增卡ID、不改全局价格、不强弹窗 |
| 短提示 | `flow_barks`复用原bark与进入/遭遇/清房事实；`first_run_only`当前按对应主线钥匙尚未取得判断 | 首通前失败重试仍提示，不是“严格第一次尝试”；本局已触发ID随世界快照恢复 |
| Boss及主线 | 援军首轮12s、间隔9s、每轮3只、动态上限6；原主线钥匙事务与领取后8秒自动返航不改 | 援军待验收；不借本次登记重签原主线整链或视听品质 |

### 只读内容核对

`assets/registry/README.md`、`ledger_index.json` 已核对职责与域映射。内容数据库《掉落物品》A18/A20/A28/A34/A35现有 `item_ammo_pack`、`item_health_potion`、`mod_bullet_standard`、`weapon_rifle`、`weapon_shotgun`；《命运卡》A27/A34现有普通 `fate_scale_node`、`fate_bounce_bullet`。仅查相关行，未保存/改写工作簿，不将本轮关卡数值复制为另一套内容真源。

### 设计层补充：十三房心流曲线

同日补写[远征01 §十二](../design/远征关卡01设计.md#十二十三房心流曲线2026-11-11-设计)，为 §11 的机制数据提供节拍依据：五幕结构、逐房 `H`/`P`/`ρ` 读数、Boss 前三拍，以及 12.6 的 A1—D 待裁定项。该章不新增怪物、盒、字段或奖励，也不改变 §11 的冻结口径；12.6-A1（05 入场短句）与 12.6-B（10 房提示时机）**尚未实现**，不并入本轮已通过项。曲线数值由 `monster_rules.stats` + `floor_00.json` 的 `stages`/`spawn_placements` 按 12.1 公式复算，属只读推导，不构成对运行表现的验收。

## 3. 专项登记与验收边界

- `verify_expedition01_reward_flow`：服务规则/确定性、分账、凭据来源、报价、标准弹绑定、箱快照及溢出边界，归属manual，须Autoload前隔离；不代表实际地面拾取或整关通过。
- `verify_expedition01_flow_integration`：正式场景逻辑接线、准备期/间歇恢复、pending交付及事件收口，归属manual，须专用隔离外部Runner；`--partial-delivery-only`仅子集，不得代签完整模式。
- `python tests/verification/verify_expedition01_spawn_ramp.py`：只读数据/投影/结构与数量检查；与同名Godot波次专项分开。
- `probe_expedition_spawn_safety.tscn`：既有安全刷点检查；`probe_expedition01_encounter_spawn_capacity.tscn`：事件安全距离/容量检查；二者按既有 `kind=command/path/args` 登记，不伪装成新的 `verify_*.tscn`。
- 两个新专项使用 `python tests/verification/run_expedition01_flow_integration.py <专项ID>`。该外部Runner在Autoload前隔离APPDATA/LOCALAPPDATA；执行者仍须核对实际Godot路径、退出码及完整日志，隔离脚本存在不代表验收通过。

## 4. 验证结果

以下结果按本事务最终实际证据回填。每行记录实际命令与模式、隔离目录、退出码、断言数、预期故障、非预期错误和日志路径；headless 通过不代替视听或新人体验验收。

| 编号 | 命令/场景 | 隔离/范围 | 结果 | 退出码与证据 |
|---|---|---|---|---|
| D1 | `python scripts/check_documentation_contracts.py` | 当前协作工作树；只读 | 未通过：11条既有断链，未新增本轮断链 | exit 1；文档检查证据记录于工程外 documentation 目录 |
| D2 | `python scripts/check_feature_traceability.py` | 既有FeatureID/schema与文件引用 | 通过：46项、184 scene links、16 command links、0 issue | exit 0 |
| D3 | `python scripts/check_verification_registry.py` | 专项唯一归属 | 通过：303场景；smoke6/core244/visual42/manual11 | exit 0 |
| D4 | `python scripts/check_domain_boundaries.py` | 跨域私有访问静态检查 | 通过：0 violation | exit 0 |
| D5 | `python scripts/check_level_decoupling.py` | 7个通用机制容器 | 通过：0 violation | exit 0 |
| D6 | `bash -n scripts/run_verification_suite.sh`、`git diff --check` | Runner语法/补丁空白 | 通过 | exit 0 |
| P1 | `python -B tests/verification/run_expedition01_spawn_ramp.py` | 标准 `shellstorm-verification.*` 隔离目录 | 通过：`EXPEDITION01_SPAWN_RAMP_DONE checks=4028 compiled_boxes=23 endpoint_boxes=46 failures=0` | exit 0；`ShellStorm2-work/verification/shellstorm-verification.spawn_ramp/1794357389084350600_production/run.log` 与 `result.json` |
| G1 | `python tests/verification/run_expedition01_flow_integration.py verify_expedition01_reward_flow` | Autoload前隔离 | 通过：`EXPEDITION01_REWARD_FLOW checks=1291 failures=0` | exit 0；`ShellStorm2-work/sessions/2026-11-11_expedition01_flow/flow_integration/verify_expedition01_reward_flow/run.log` |
| G2 | `python tests/verification/run_expedition01_flow_integration.py` | 完整模式、Autoload前隔离 | 通过：`FLOW_INTEGRATION_OK checks=395 failures=0` | exit 0；`ShellStorm2-work/sessions/2026-11-11_expedition01_flow/flow_integration/verify_expedition01_flow_integration/run.log` |
| G3 | `python tests/verification/run_expedition01_flow_integration.py verify_encounter_event_flow`、`verify_encounter_trigger_room_flow` | 标准/专用隔离目录均可用 | 通过：`ENCOUNTER_EVENT_FLOW_OK samples=86`、`ENCOUNTER_TRIGGER_ROOM_OK samples=95` | exit 0；对应 flow_integration/verification 日志 |
| G4 | 安全刷点与Boss空投专项 | Autoload前隔离；正式Boss场景 | 通过：安全选点45项、Boss空投36项；生产Boss几何探针304项 | exit 0；`ShellStorm2-work/probes/2026-11-11_encounter_safe_selection/result.log`、`sessions/2026-11-11_expedition01_flow/flow_integration/verify_boss_reinforcement_airdrop/run.log`、`ShellStorm2-work/probes/2026-11-11_boss_walk_surface/production_1794355171628559100/result.log` |
| G5 | Godot `verify_expedition01_spawn_ramp.tscn` | 同P1；生产编译与负向映射 | 通过；负向移除bonus时按预期检出故障，运行器判定为预期故障 | 生产 exit 0；负向 Godot exit 1、runner exit 0 |
| M1 | 新局13房接线、旧局奖励迁移、失败重试与续局专项 | 隔离新局/旧档快照，不读真实用户存档 | 通过上述P1/G1/G2/G3及Boss空投覆盖的逻辑链；未完成真实完整玩家通关 | headless专项 exit 0；不等同实机通关 |
| V1 | 视听/新人体验/目标设备验收 | 本事务未执行 | 待验收 | 不以headless代签 |

本轮保留首次失败记录：早期 `room_type_invalid`、固定援军校验、准备期断言、P1终端卡房、旧档首领箱、Boss地面/空投接缝及旧漂移快照断言均已修复后复验；不将早期失败混入最终通过数。工程外证据统一位于 `ShellStorm2-work/`；11条文档旧断链仍未动。

## 5. 新旧issue与限制

改前文档门禁exit 1：11条既有断链，加两个新专项未登记汇总issue（12条顶层issue）。改后仍exit 1，但只剩同一组11条旧断链；比较时忽略日志顶部插入造成的行号偏移、保留重复条目，新增0，消除1个登记汇总issue（含2个新专项未登记）。Feature追溯改前/后均46项、schema_version=1、各条状态原样保留；文档总门禁旧正则只统计44行，不拿它冒充新增/删除Feature。跨域边界、关卡解耦均0违规。证据为 `documentation/before_checks.json`、`after_checks.json`、`issue_delta.json`。

11条既有断链保持不动：

| 位置 | 旧问题 | 条数 |
|---|---|---:|
| `docs/CREATION_PIPELINE_OUTLINE.md:14` | `创作链路_五层结构.png`缺失 | 1 |
| `docs/PRODUCTION_FRAMEWORK.md:14` | `制作框架_三层结构.png`缺失 | 1 |
| `docs/v0.1/06_技术施工_怪物精英与Boss.md:261` | `../04_技术施工_战斗与局内成长.md`相对层级错误 | 1 |
| `docs/v0.1/07.3_玩法系统_合成目录与兴趣曲线.md:7` | `../../data/ShellStorm2_游戏内容数据库_v010.xlsx`重复旧断链 | 2 |
| `docs/v0.1/development/2026-10-18_secret_site_slot_survey.md:28` | `../../design/支线秘密房间设计.md`相对层级错误 | 1 |
| `docs/v0.1/development/CHANGELOG.md`历史条目 | 三处`design/命运卡六关投放设计.md`、两处`../../04_技术施工_战斗与局内成长.md` | 5 |

没有执行运行用例或故障注入，本次静态命令均无非预期stderr错误；Git行尾提示单列。三份协作设计改前/后SHA-256一致，备份逐项校验一致；Python数据与Godot/整关/视听各行继续pending，不从其他线程日志摘绿。文档检查不验证Markdown锚点、玩法语义或运行正确性。

整关、真实拾取、溢出留物、旧局续档、提示重试语义、负向故障、视听与设备证据不能因登记完成自动判绿。涉及背包出口不能承接拆栈/留物时，由主线程报告/处理，不在本文件维护者权限内改生产实现。

## 7. 五间封门房统一限时循环（2026-11-12，16:07纠正与18:13扩围）

用户确认最终规则：room03/04/06/09/10全部触发即封门、启动60秒总窗口，第2秒首批，清批后0秒间歇推进，模板耗尽后重复末批；到点先停发并作废全部尚未出现的pending/预约/延迟，保留场上残怪，残怪清零才结算本房宝箱及解除封锁。不是空等60秒后刷怪，也不是固定三/四批。门解除封锁不自动推开门板。旧日志里的“60秒准备期”系本会话误解，已被用户最新要求纠正，不能作为当前设计。

- room03模板5/7/8，cap8；04模板6/6，cap6；06模板8/9/13，cap10；09模板12/16/20/24，cap16；10模板10/12，cap10。模板、容量、怪种、奖励与房型均保留；实际总量取决于60秒内击杀速度，不再是模板总和。
- `EncounterEventDirector3D` 新增显式 `deadline_behavior=close_dispatch_and_clear` 与 `repeat_last_stage=true`；缺省保留旧行为。窗口总时钟拥有者仍是Director；固定长度末阶段状态循环、唯一spawn_serial、截止先于派发、清场不判失败；schema1新增可选字段，旧活动快照按其原配置恢复，不强制把进行中的旧60秒准备局迁成新规则。
- Host按实例撤销未出现队列及休眠镜像，返还相应房间存活预约，保留实体/其他事件/精英预约边界；Validator严格检查能力组合；Dungeon仅透传能力，不按关卡ID分支。HUD消费 `battle` 总剩余与 `cleanup` 残怪清理，不自计时，字体和位置不改。
- 数据从权威floor_00源同步运行投影与manifest，52文件一致；备份分别在工程外 `ShellStorm2-backup/2026-11-12_room03_timed_loop/before_edits/` 与 `2026-11-12_all_timed_encounters/before_edits/`，不覆盖其他协作改动。
- 五房专项：`ALL_TIMED_PRODUCTION_OK rooms=5 checks=1720 failures=0`；含旧HUD/room03及真实Host撤队列总 `ENCOUNTER_ALERT_CONFIG_INTEGRATION_OK checks=2142 failures=0`，Godot exit0，无SCRIPT ERROR/ERROR。其中正式Loader/Generator/Dungeon配置接入真实，战斗推进使用FakeHost，不冒充五房实机通关；覆盖06/09/10超容量补发及到点pending丢弃、读档不重发、循环不提前完成。
- 证据：工程外 `ShellStorm2-work/probes/2026-11-12_all_timed_encounters/20261112_182504_883632/run.json` 与godot.log；原room03核心隔离纯测218项通过。最终正式遭遇回归 `ENCOUNTER_EVENT_FLOW_OK samples=261`，Godot exit0、无ERROR；真实远征01场景 `--room03-timed-only` 复验 `FLOW_INTEGRATION_OK checks=124 failures=0`，exit0、无ERROR，真实生成5批36只、peak8，最终cleared=true/sealed=false、chest_count=1/restored_chest_count=1。日志在同一证据根的 `formal_verify_encounter_event_flow/run.log` 与 `formal_verify_expedition01_flow_integration/run.log`。真实场景测试人工推进Director时间与击杀实体，是无头接线验收，不是玩家实机通关。
- 初次正式类型错误（Validator的bool推断）已修复；首轮五房测试在四房数据未切换时失败，数据投影后重跑全绿。真实room03初测已有实际5批36只、清房true/封锁false/唯一箱1，但exit1两条：按端口索引取不到方向制门、恢复后要求查询已被丢弃的terminal统计。已按真实门邻接接口与完成账恢复契约修正测试，未放宽玩法断言，后续复验单列。
- 文档门禁exit1为11条既有断链，本轮新增0；解耦0违规、数据投影与补丁空白通过。未做五房逐一真实渲染/人工游玩、冷进程活动实体恢复。旧spawn_ramp与其他全关专项仍有此前有限编排断言漂移，不把未跑的全套测试说成通过。

## 6. UI-HUD 独立事务：倒计时七段数码风格（2026-11-12）

### 字体替换修订（10:10 用户反馈后）

用户否定手绘七段效果：成熟字体优先，不用工程拼段替代字形设计。已删除 `_draw_digital_character` 与数字段表，引入作者官方 v0.46 发布包的 `DSEG7Classic-BoldItalic.ttf`（23604字节的普通斜体仅为比较候选，正式显示只引用粗斜体）；原始 `DSEG-LICENSE.txt` 随资源保存，SIL OFL 1.1。来源为作者站 `https://www.keshikan.net/fonts-e.html` 指向的官方发行包。字体原始字距、小数点、斜度与切角交给Godot字体排版，橙黄颜色和0.20高度不变。参考图原字体未确认，不宣称完全同款。正式导入/PCK走ResourceLoader，最小无缓存夹具直接读同一TTF；尚未执行PCK导出，不以代码路径等同打包验收。

本轮纯表现 `checks=71 failures=0`、真实控件渲染 `checks=69 failures=0`，均exit0、无SCRIPT ERROR/ERROR；覆盖十个数字/小数点字库、减少动效、旧态恢复与6状态截图。未重跑先前已失败/超时的背包和整体HUD专项，未做实际关卡游玩。文档门禁exit1仍11条旧断链，解耦0违规、补丁空白通过。证据：工程外 `ShellStorm2-work/probes/2026-11-12_countdown_font/`；特写位于 `ShellStorm2-work/outputs/2026-11-12_countdown_font/countdown_font_detail.png`。备份：`ShellStorm2-backup/2026-11-12_countdown_font/before_edits/`。以下原手绘交付记录仅保留过程历史，现行字体规则以本修订与设计r8为准。


- 来源：用户橙黄七段数码管截图及“稍微上去一点”；设计主源为[对话与战斗信息呈现 r8](../design/对话与战斗信息呈现设计.md)。仅改显示，不改本记录先前的计时/刷怪数据。
- 改动：`EncounterCountdownRing.gd` 使用切角、略右倾七段矢量数字，橙黄亮段和暗描边；等宽百分秒与减少动效整秒均读原快照。保留 `CountdownTimeLabel` 语义与节点，仅数码态隐藏Label渲染，战斗提示/旧圆环恢复原字样。
- `Dungeon3D.apply_encounter_hud_snapshot()` 的modern中心高度0.23→0.20，设计槽540×44→540×88（实际432×70.4 canvas）；`EncounterAlertOverlay`文字高度0.18→0.12，避免与数码小标题重叠。未更改其他协作方在Dungeon内的优化。
- 修改前备份：`ShellStorm2-backup/2026-11-12_countdown_digital/before_edits/`。
- 纯表现旧基线55项已通过；真实兼容渲染器生成6张截图，`COUNTDOWN_DIGITAL_RENDER_OK checks=70 failures=0`、exit0、无SCRIPT ERROR/ERROR。样本含60.00、45.56、间歇2.50、subtle、战斗提示、终态隐藏。证据位于工程外 `ShellStorm2-work/probes/2026-11-12_countdown_digital/`。这是**假快照注入真实控件**，不是实际关卡截图。第一次截图探针失败已保留在 `attempt_01_failed/`，修正探针后 `attempt_02_passed/` 通过，未为过测修改生产代码。
- 最终纯表现：`ENCOUNTER_ALERT_CONFIG_HUD_OK checks=60 failures=0`，exit0、无脚本/引擎错误；正式接线：`ENCOUNTER_ALERT_CONFIG_INTEGRATION_OK checks=23 failures=0`，exit0、无脚本/引擎错误。有限弹药 `FINITE_AMMO_FLOW_OK`，exit0、无脚本/引擎错误。
- 整体回归未全绿：标准batch两次均被既有远征03布局预检的GBK编码异常阻断（设置UTF-8环境也未解决）；改在Autoload前隔离APPDATA/LOCALAPPDATA直跑四场。`verify_reference_hud_fate_visual` 达360秒超时；`verify_tactical_inventory_minimap_flow` exit1、23条ERROR，涉及6列背包/血条颜色/保险与快捷栏拖放所有权等，未有本轮改前对照，不能认定为已证实的既有问题，也未擅自修复无关玩法。总回归Runner exit1，不将两项未通过混入成功总数。日志位于上述证据目录的 `shellstorm-verification.hud/<场景名>/run.log`。
- 文档门禁exit1仍11条既有断链，本轮新增0；解耦0违规，补丁空白通过。未做完整关卡人工体验与移动端验证。首次复验纯表现时复制目录尚未同步新增断言，旧55项通过但基线哈希护栏失败；prepare重新复制最新源后60项正式通过。
