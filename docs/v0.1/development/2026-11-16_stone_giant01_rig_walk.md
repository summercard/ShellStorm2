# 石甲巨人骨架修正与重型走路增量

日期：2026-11-16；记录ID：2026-11-16-stone-giant01-rig-walk；功能ID：ASSET-PIPELINE / ENEMY-AI；工程版本：0.1.0。
代码基线：`e81c3bc5f22339a9bb4da329bc947a35f3281c25`，多会话脏工作区；交付提交：未提交、未推送。
依据：[文档规范](../../DOCUMENTATION_STANDARD.md)、[工作区规范](../../WORKSPACE_LAYOUT.md)、[制作源规范](../../ART_SOURCE_LAYOUT.md)、[功能索引](../MODULE_INDEX.md)；本次用户明确确认新增普通怪、游戏绑定身高2m，只修当前Blender怪物并制作夸张厚重walking，不新增玩法规则。

## 1. 资产身份、范围与状态

| 项 | 本轮事实 |
|---|---|
| AssetID / 制作名 | `ENM-MELEE-STONE-GIANT01` / 石甲巨人（沿用原贴图名） |
| 逻辑ID / slug | `stone_giant01` / `enm_melee_stone_giant01` |
| 骨架ID / 版本 | `SKEL-STONEGIANT01-001` / `v001` |
| 台账定位 | `assets/registry/ledgers/ShellStorm2_敌人账本_v001.xlsx`，《资产主表》第56行；本事务不读写工作簿，不变更账本资产 |
| 制作交付范围 | 模型骨架/蒙皮修正 + 单独 `walking` 增量；双母版、GLB、纯视觉无脚本TSCN及manifest已由上游建立 |
| 未制作 | `idle`、`running`、`attack`、`hurt`、`dead`；不以占位或别的剪辑冒充 |
| 未接入 | AI、刷怪、玩法目录/状态机、伤害判定、碰撞；`Enemy3D / EnemyAvatar3D` 仅目标消费者，碰撞Owner不变 |
| 状态边界 | 最终保持 `exported_pending_godot_validation`；源与最小Godot raw导入通过，但完整动作集合、正式状态接线未执行，**不得active**；不自造额外状态枚举 |

这是新增增量资产，不替换任何旧怪物。全局Feature状态、游戏设计与 `feature_registry.json` 不变。`contract.json` 的 `design_only` 和第一阶段预登记是早期时点，不能当作最终制作状态；账本最终阶段由主agent补记。

## 2. 路径、双母版与指纹

工程根：`I:/工作项目/shellstrom2/ShellStorm2`。
工作目录（下文 `W/`）：`I:/工作项目/shellstrom2/ShellStorm2-work/sessions/2026-11-16_1626_giant_walker/`。原始报告与日志只读引用，不复制进运行资源，不在本事务重写。

| 用途 | 工程相对路径 |
|---|---|
| 模型母版，无动作 | `art_source/enemies/enemy_3d/enm_melee_stone_giant01/source/model/enm_melee_stone_giant01_model_v001.blend` |
| 动画母版，仅walking | `art_source/enemies/enemy_3d/enm_melee_stone_giant01/source/animation/enm_melee_stone_giant01_animation_v001.blend` |
| 稳定GLB | `assets/art/enemies/enemy_3d/enm_melee_stone_giant01/components/enm_melee_stone_giant01/enm_melee_stone_giant01_visual_top3d.glb` |
| 纯视觉Prefab | `assets/art/enemies/enemy_3d/enm_melee_stone_giant01/runtime/enm_melee_stone_giant01/enm_melee_stone_giant01_root_top3d.tscn` |
| 资产清单 | `assets/art/enemies/enemy_3d/enm_melee_stone_giant01/asset_manifest.json` |
| 角色交接清单 | `assets/art/enemies/enemy_3d/enm_melee_stone_giant01/runtime/character_transfer_ledger.json` |
| 当前源索引 | `assets/registry/current_source_index.json`（本事务仅追加下表两源） |

动画母版网格外链模型母版；上游 `finalize_sources.py` 已将库路径改为 `//../model/enm_melee_stone_giant01_model_v001.blend`，同时设置视口/播放区间，不改变骨架、网格、权重或动作数据。`W/finalize_stdout.log` 有 `SOURCES_FINALIZED` 和相对库路径；最终 `W/validation_blender.json` 仍 `passed=true`。

下列为本事务冻结时对**仅本次两源**的实测，不接受任何无关旧源漂移；family以 `_VERSION` 归族，version均为 `[1]`。

| 源 | 字节 | SHA-256 |
|---|---:|---|
| model_v001 | 718664 | `9512fd5234fbc98bbdfa304e037ef846698364ea4e50677aec312418797e0287` |
| animation_v001（相对外链收口后） | 1502360 | `3af9a9bdf92a5debfafb14a5a778e42351b667f366d476faa7ad10bd05477398` |

稳定GLB：180788字节，SHA-256 `9aeb72241870b1077791abf92fbecd88c9fad9181d9114a510a5b85081e802c5`；Prefab：805字节，SHA-256 `490421a9979f5d0634a4327096fbb4e944fa2e1baf9812b16432a97e49f89d42`（来自export/package与Godot复制输入证据）。

上述为文档子事务读取时点的差异，已由主事务最终同步：`package_result.json`、manifest/transfer现登记动画源1502360字节、SHA `3af9a9bdf92a5debfafb14a5a778e42351b667f366d476faa7ad10bd05477398`；`author_result.json` 外链元数据改为相对路径；contract/manifest名称恢复石甲巨人；最小Godot通过证据与当前正式.import哈希已回填。未修改双母版的最终骨架/网格/动作数据。

## 3. 尺寸、朝向、骨架和蒙皮

- 553顶点、1102三角、一个材质、一张512×512原贴图保留；保留原几何拓扑，仅统一变换与重分配蒙皮。`author_result.json` 登记522个顶点重分配权重。
- 源绑定总高 = `2.0 / 0.70 = 2.857142857m`；源数据已应用统一缩放，`author_result` 的应用倍率约3.4562488103。对象scale为 `(1,1,1)`；游戏外层显示倍率仅应用一次：`2.857143 × 0.70 ≈ 2.0m`。
- Blender正前 `+Y`、上 `+Z`（原朝向 `+X` 已转正）；Godot正前 `-Z`、上 `+Y`。不在纯视觉包装里再乘0.70，最小验收由独立父容器应用一次，未改玩法节点。
- 41根骨，22根deform；模型/动画骨架签名相同：`bb1858d59da8f3f0242ab967d9b5bc6eb251e59f8d7058100a7b91a922a0e4cc`，schema `bone-parent-restmatrix7-deform-v1`。
- 全顶点有权重、归一化、最多4影响；模型母版无动作，动画母版只含walking，外链几何一致，动画中权重保留。
- 头部测试从原3点扩大到111点，左右ToeBase各13点有效。锁骨压力最大边比约2.58→1.5268，上臂约2.764→2.0903；**新骨轴不同，只是压力参考，不能声称等价解剖动作对比**。
- 已制作walk的最大/最小边比为1.876200 / 0.264013；头部压力最大边1.531228，上臂60°压力仍达2.090323。极限姿态仍有局部拉伸/压缩风险，不签所有运动范围全绿。
- 2m是绑定站姿标定，不是每帧头顶高度。重型walk自然蹲伏，实测最高1.90311265m；不为满足每帧2m而反向拉伸或抬高整个怪物。

## 4. Walking制作与Blender证据

- 30fps，闭合关键帧 `0..72`，正常播放 `0..71`；周期 `(72 - 0) / 30 = 2.4s`，第72帧仅闭合，不重复播放端点。
- 交替重步、长支撑，左右Hip峰峰幅度0.299970746m；身体/肩胯反摆、沉身重落、重钳手滞后。设计契约支撑比例0.62、胸roll峰值10°、参考速度0.28m/s仅制作参考，不接AI移速。
- 左右抬脚峰值均0.139811069m；Hip垂直行程0.057712287m。Root原地固定，行走位移留给未来玩法Owner，不导出Root前移。
- Blender最终验证120Hz采样两圈、577样本；Root矩阵误差 `1.4210854715e-14`，闭合顶点残差0，有限值检查通过。
- 支撑脚/地面最大误差1.750624mm；超过3mm穿地帧为空；双脚同时离地最大值约0.000834mm（浮点误差），无双脚腾空。
- 闭合速度变化仍有0.233463622m/s，闭合顶点0不等于速度连续为0；重落风格与这一限制均保留，不提升为全动作/全范围验收。
- `W/frames/` 已有四视角共288张真实Blender渲染，`W/walking_four_views.mp4` 已存在（648393字节）；`W/preview_keys/` 是关键帧辅助图。视频/帧数存在性本事务已核对，但不冒充人工逐帧验收或Godot真实渲染。

## 5. 验证结果、退出码与过程失败

本事务只读上游证据，不重新运行Blender/Godot；不得把本事务命令exit0当作上游制作进程exit0。上游Blender stdout以UTF-16解码读取，避免误判二进制/乱码。

| 阶段/命令 | 结果/退出码 | 隔离与证据 |
|---|---|---|
| `author_stone_giant.py` | 生成双源及author_result；原进程退出码未见独立保存，待主agent补 | `W/author_result.json` / `author_stdout.log` |
| `finalize_sources.py` | 已见相对库路径与 `Blender quit`；原进程退出码待主agent补 | `W/finalize_stdout.log`；只读，不再保存blend |
| 最终Blender验证 | `passed=true`，failed_checks/ issues为空，全部显式checks通过；原进程退出码待主agent补 | `W/validation_blender.json` / `verify_stdout.log` |
| 导出/打包 | 一个mesh/一图、41骨、仅walking、123导出轨、2.4秒、闭合帧已导出、pure_visual；原进程退出码待主agent补 | `W/export_result.json` / `export_stdout.log` / `package_result.json` |
| Blender四视角渲染 | 288帧与MP4存在；渲染/编码原进程退出码待主agent补 | `W/render_stdout.log` / `walking_four_views.mp4` |
| Godot工具自检 `174003_81e9057e`、`174219_b748b41d` | tool_selftest各passed；两脚本check-only各exit0；bool=false传播与越界拒绝通过，不算资产验收 | `W/godot_minimal/runs/<完整时间ID>/tool_selftest.json` |
| 首次Godot `174740_4c152d04` | raw_import exit0，raw_check exit1；runner exit2 / blocked_or_error，未通过 | 同run的summary：loop actual0/expected1，并因非loop问题拒绝补验；保留RuntimeError traceback，不隐藏 |
| 修正倍率后 `175032_fcf52b9b` | raw_import exit0、raw_check exit1（loop=0）；副本规则配置/重导入/检查各exit0 | 仅副本补循环规则后pass，状态 `configured_copy_passed_pending_formal_import_decision`，不能代签正式raw |
| 最新正式规则raw `175340_893c9e22` | godot_help/raw_import/raw_check各exit0，runner exit0、passed=true、status=raw_passed | `W/godot_minimal/runs/20261116_175340_893c9e22/summary.json` 与 `reports/raw_check.json` |
| 最新负向：期望时长2.5s | exit1且准确拒绝duration / wrapper_animation_duration，observed_expected_failure=true | 仅改独立期望配置，不改GLB/Animation |
| 最新负向：外层倍率1.0 | exit1且准确拒绝game_bind_height / outer_multiplier_applied_once，observed_expected_failure=true | 仅独立测试容器漏乘0.70，源和2m期望保持 |
| 文档门禁改前 | exit1：15条断链 + 注册/追溯/媒体三个聚合issue，共18个顶层issue | `W/docs_phase/before_gate.json`、`before_stdout.log` / `before_stderr.log` |

最新Godot为4.7.2 stable：41骨、walking实测2.400000095秒；源绑定高2.857142687m，外层一次0.70后高1.999999881m。120Hz两圈577姿态样本，Root及父链固定、端点闭合、动画目标解析与纯视觉GLB/包装检查通过。22deform只引用Blender证据及骨名存在性，不冒充Godot复验deform标记，也不把姿态采样冒充动态CPU蒙皮。

glTF extras中的loop不自动变成Godot循环；正式新 `.glb.import` 已由主agent写入walking的 `settings/loop_mode=1`。最新raw只复制正式GLB、包装与.import，在全新隔离缓存导入，无需运行时篡改Animation；GLB与包装loop均实测1。正式.import复制前后SHA均为 `6d5faf763a949f025305eaf8bc02222d2614fafb822ad544d1647565000f6f3b`，源输入变化列表为空。

用户数据隔离：该Godot二进制help无可靠 `--user-data-dir` 支持，Runner使用run内独立APPDATA、LOCALAPPDATA、USERPROFILE/HOME、TEMP/TMP和XDG目录；`user_directory_isolated=true`，无正式游戏档参与。

**脚本错误单列**：最新raw摘要及每条命令 `unexpected_script_errors / unexpected_errors` 均为空；早期runner的RuntimeError traceback保留于174740摘要，不计成功。已解码检查author/diagnose/export/finalize/keys/render/verify七份顶层log，未发现Traceback、SCRIPT ERROR、Error:或Exception匹配；此文本扫描不等于获得未记录的退出码，也不覆盖未保存的交互控制台历史。

**本次改前旧红项**：历史11条断链之外，当前另有4处 `2026-11-16_expedition01_combat_feel.md` 缺失导航（共15条断链）；注册门禁另报未登记 `verify_projectile_enchant_visuals` / `verify_weapon_hologram_ui`，追溯门禁6项引用同一缺失记录，媒体门禁UI行数expected21/got23。均在本事务写入前已存在，不补登记、不修旧链接、不接受其他会话资产或哈希漂移。改后结果在下节追加实测。

## 6. 备份、CAS与本事务变更

改前四文件以完整工程相对路径冻结到：`I:/工作项目/shellstrom2/ShellStorm2-backup/2026-11-16_stone_giant01/before_edits/docs_phase/`。

| 冻结文件 | 冻结SHA-256 |
|---|---|
| development/README.md | `16a6d7240910268b6691f472766c9c3652d601917df012255d8bb92d2022f6cf` |
| development/CHANGELOG.md | `db9b7b37d7d00dee12d431dc57b04343766ac805a8bce61417f2ebb287f638a5` |
| MODULE_INDEX.md | `b69bb0c9d5368f9dc4c3d340810d0e79fc6f7d10048fb211c9ccd02bad4eea96` |
| current_source_index.json | `65a85466f2acfbe8e51ebe987a2eceb0cf519ff3ae34ecc0e8c843d69c8faaa6` |

过程脚本：`W/docs_phase_transaction.py`；冻结清单：`W/docs_phase/state.json`。三个导航各前置一条最小记录，原字节作为完整后缀保留；源索引只在sources尾部追加两项path/bytes/family/version/sha256，不改date及其他顶层元数据，不重排或重序列化旧条目，不计算任何旧源文件哈希。

写入前对四文件取得Windows拒写锁，逐字节对比冻结副本并校验SHA，四项全通过才写入；两源再次对比冻结指纹，新记录exclusive-create，冲突直接停止，禁止以旧快照覆盖其他会话改动。落盘后读取核对，保留 `W/docs_phase/applied.json`。回滚需逐文件审阅与后续会话比对，禁止整树恢复或覆盖后续修改。

原Blender未保存源已由主agent备份在 `I:/工作项目/shellstrom2/ShellStorm2-backup/2026-11-16_stone_giant01/original_tree/unsaved_blender_before_rig_fix.blend`，749462字节、SHA-256 `b0bcf02655ef845d1bfe6822c017b011514cbab84cd1822d067d0fbe77bb58c1`；来源 `W/snapshot_metadata.json`。账本第一阶段备份与退出码在 `W/ledger/phase1_result.json`，仅引用，不在本事务重做或签最终账本。

本事务仅改本独立记录、development两个导航、MODULE_INDEX一条导航、当前源索引两项；不修改blend、GLB、TSCN、.import、manifest/transfer/package/validation等产物JSON、资产账本、baseline、src/tests/scripts工程代码、设计或feature_registry。

## 7. 遗留、未执行与主agent最终补记

1. 本记录只签双源/单walking与限定最小Godot证据；不签全运动范围、完整Enemy状态机或正式游戏已接入。绑定极限压力仍在，需未来对应动作单独制作和验收。
2. Godot真实渲染/截图、动态CPU蒙皮、deform标记原生重验未执行；Blender四视角真实渲染不替代这些项目。主工程全量导入/完整场景游玩、移动端、正式PCK导出与性能未执行。
3. AI、刷怪、碰撞、战斗接线及idle/running/attack/hurt/dead明确不在本轮范围，不为补齐验收而擅自制作。
4. 主agent最终补记：核对收口后双源指纹并按授权同步manifest/transfer/package及敌人账本56行，修正相关名称乱码/旧外链元数据，补制作与渲染/编码退出码；本事务不越权代改。不能因raw_passed把资产升级active。
5. 文档门禁改后结果及范围核对由本事务下方追加；全局旧红项不在本轮修复范围。其后新的产物或账本事务由主agent另行备份、CAS和记录，不能覆盖这份多会话冻结内容。

## 8. 本事务门禁与范围复核

改后门禁待下方实测追加；在结果写入前不宣称总门禁通过。


- 实际执行 `python scripts/check_documentation_contracts.py`：改前/改后均exit1，18个顶层issue（15条断链及注册/追溯/媒体3项聚合问题）；按文件+目标归一化行号并保留重复计数后，问题多重集完全相同，新增0、消失0。CHANGELOG旧行号与MODULE_INDEX旧行号因前置导航各顺延2行，不是新增断链。
- 门禁stdout/stderr与退出码已分别捕获：`W/docs_phase/before_gate.json`、`after_gate.json`及对应stdout/stderr.log；stderr均为空，无本次门禁脚本崩溃。文档594份、链接3137条、索引功能44项/测试引用136条；该静态门禁不校验Markdown锚点、设计语义或运行表现。
- `W/docs_phase/comparison.json`：三份导航的原字节完整保留；1346条旧源条目值与原始文本逐字保持，顶层元数据不变，只追加本次2条；旧源文件重新计算哈希0个。四文件CAS/落盘校验及新记录exclusive-create均通过，应用事务进程exit0；门禁子进程exit1单独登记，不能被外层捕获命令exit0洗绿。
- 本记录收口补记使用新记录初始草稿字节作CAS基准，并以文件锁排他追加本段；不覆盖后来会话内容。最终门禁复跑证据入口为 `W/docs_phase/final_gate.json`；后续最终资产/账本同步见下节，不改本轮非active边界。

## 9. 主事务最终交付补记

- 制作、源便携外链收口、Blender重开验证、GLB导出、288帧真实渲染与FFmpeg编码均退出0。最终MP4为1280×1280、30fps、2.4秒，四格顺序为正面/侧面/三分之四/剪影；降低机位并扩大构图，完整保留巨大钳手与脚部，不以相机裁切制造剪影。
- 当前Godot编辑器自动展开了正式.import的默认切片参数，文件哈希由早期规则变化，但walking `settings/loop_mode=1`未变。对**当前实际.import**重新全新隔离验收：`W/godot_minimal/runs/20261116_181643_bb7bace4/summary.json`，raw_import/raw_check及runner均退出0，`passed=true`；两项预期负向仍精确退出1，未出现非预期脚本错误。最新输入哈希由该summary冻结，manifest/transfer同步当前.import哈希，不复制隔离导入缓存。
- 账本最终登记：敌人域《资产主表》56行、《敌人动画与状态》66行、《3D-敌人》12行；版本v001，状态`exported_pending_godot_validation`。主路径指向805字节纯视觉Prefab，SHA `490421a9979f5d0634a4327096fbb4e944fa2e1baf9812b16432a97e49f89d42`。只签本次双母版/walking/独立导入，不称正式在役。
- 账本采用主表与专表两次独立备份/CAS事务；`W/ledger/final_result.json`记载主表16格和专表/日志32格差异，无关内容变化0。已有1459个其他资产指纹保留；专表原先已经漂移，保留旧基线摘要及旧漂移证据，不全表接受当前内容。去除本次新增行后，专表旧内容摘要与改前一致；全局结构/敌人full/split门禁旧红项保持，新增问题0。本行路径、哈希、查重与状态单独通过。
- `asset_guard --classify child_variant`最终退出0；新增运行命名门禁退出0。首次以Python `-I`直接运行asset_guard因导入路径缺失失败，最终通过明确加入项目scripts路径重跑，未改门禁源码。文档门禁最终退出1，仍是15条断链及注册/追溯/媒体聚合旧问题，与文档子事务基线归一行号后相同，新增0。
- 已在打开最终动画前再存一份当前用户会话快照 `W/before_open_final_user_session.blend`，随后当前Blender加载正式动画母版，F18、30fps、播放0–71，Action为walking；未覆盖原始未保存模型备份。
- 最终仍未执行：正式AI/刷怪/碰撞/战斗状态接线、其余五类动作、Godot真实渲染与动态CPU蒙皮、主工程全量运行及目标设备人工观感验收。极限压力风险仍按§3保留；不提交、不推送。

## 10. 18:44 用户参考图修订：双钳上下摆动 v002

用户纠正姿态为图示身前屈肘，钳子应上下而非前后摆。本次仅重写16根上肢骨的walking曲线，模型母版仍v001；动画改为`enm_melee_stone_giant01_animation_v002.blend`，包版本v002。模型几何、权重、骨架签名与Hip/躯干/下肢/Root关键帧保持不变，非上肢曲线逐点对比通过。

- 两钳维持身体前下方、腕与钳方向朝下，左右相反相位上下起伏。按各侧86个Hand主权重点的蒙皮后重心测量：左Z峰峰0.209493m、Y前后0.001044m；右Z峰峰0.209463m、Y前后0.000989m。方向断言要求Z>0.15m、Y<0.04m且Z/Y>5，两侧均通过；不是只按屏幕位移猜方向。
- 新动作仍30fps、2.4秒、0–71播放/F72闭合。577样本重验：地面误差1.750598mm、首尾顶点残差0、Root固定、无双脚腾空；最大/最小边比1.876200/0.264013，原压力风险不变。真实渲染288帧与新版四视角MP4均退出0；源、导出、方向检查退出0。
- 工作证据根为`I:/工作项目/shellstrom2/ShellStorm2-work/sessions/2026-11-16_1844_stone_giant_vertical_claws/`；方向证据`claw_direction_validation.json`，总源验收`validation_blender.json`，预览`walking_vertical_claws.mp4`。
- 账本原资产行56、动画行66、3D页12更新，不新增资产；20个定点单元格变化，无关单元格0，其他1459资产指纹保留，专表旧债不重刷。源索引只将旧动画条目换成v002，其他1347项原样保留。详见本轮`ledger/ledger_revision_result.json`。
- 当前模型SHA仍`9512fd5234fbc98bbdfa304e037ef846698364ea4e50677aec312418797e0287`；动画v002为1502995字节、SHA`f8a33cec296655281d2142d206865e5648cec1724874059537f232a77427cf1c`。GLB稳定路径覆盖为178628字节、SHA`7dbd4829775c7e56fba54b661b2cb202faafc815f1b684317a85366c4b7282ed`；Prefab只更新metadata版本为v002，805字节、SHA`58c55bf1d628de64496d2db23bf1864f774990e0e0da5a4b8df175adfbc23d5f`。manifest/transfer已同步新哈希及本轮验证结果。
- 旧动画v001经副本SHA核对后移至上层`ShellStorm2-backup/2026-11-16_1844_stone_giant_vertical_claws/original_tree/`对应原相对路径；本轮改前稳定输出、源索引和当前Blender会话均有独立备份。
- **本轮Godot尚未通过**：`185007_e14690a2`隔离raw_import启动后超时exit124，runner exit2；详细诊断关闭音频并指定兼容渲染后`191556_e858655d`仍超时，未进入raw_check。未运行本轮引擎负向控制，不拿v001通过代签。状态保持`exported_pending_godot_validation`；无游戏正式接线变化。
- 本轮最终文件哈希、账本v002、ZIP CRC及预览内嵌视频一致性全部通过；当前Blender已在保存会话副本后打开v002，F18、walking、播放0–71。后续文档总门禁启动后长时间无输出，停止本轮检查进程及其任务，结果记为未完成，不套用v001的旧通过/旧问题统计；账本专项保留本轮前后问题对照与命名exit0。文档及引擎总验收均不宣称通过。
