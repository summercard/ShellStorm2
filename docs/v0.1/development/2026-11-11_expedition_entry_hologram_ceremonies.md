# 99F基地远征入场全息仪式：扫描成形与凝实成形

- FeatureID：`WORLD-ENTRY / NARRATIVE-TRIGGER / VFX-POOL / PLAYER-STATE / ASSET-PIPELINE`
- 工程版本：`0.1.0`
- 日期：`2026-11-11`
- 状态：**两模式Forward+真实fixture、四条正式host装配、“已准备99F出发请求→真实读取页→正式Level01”双seed端到端均通过；2026-11-12 另修掉「基地点出发恒报保存失败」的真实缺陷。基地菜单链读到装配阶段未跑完、移动端未验，整体partial不提升**
- 来源：用户要求「从99F基地进入关卡后，黑幕打开，近距离后方角色，全息组成角色，镜头拉回后可动」。

## 1. 设计与实现

从99F基地中央 `mission_operations` 出发，仍沿既有链路：

```text
ExpeditionDepartureService
→ ExpeditionLoadingScreen
→ IrisTransition 全黑
→ 目标场景装配/预热
→ release_loading_scene
→ 黑幕下 prepare_expedition_entry_ceremony
→ 隐藏读取页 Backdrop
→ IrisTransition.open_after_scene
→ ceremony_ready
→ NarrativeDirector 时间轴
→ 角色全息重建 + VFX
→ camera.restore
→ presentation.restore / 归还操作
```

唯一触发条件：

```text
reason == mission_operations_teleport
source == base_99f
current_room_id == start
非 runtime_restore
```

塔3天台来源、远征续档、返航和加载失败不播放。`run_seed % 2 == 0` 播放扫描成形，奇数播放凝实成形；两者不改存档，不写 `narrative_history`，按出发 request 幂等。

### 1.1 扫描成形 A

- AssetID：`VFX-HOLOGRAM-ENTRY-SCAN-3D`
- 剧本：`nar_expedition_entry_hologram_scan`
- 最终时长：**1.55s重建 + 0.25s实体化 + 0.25s停留 + 1.10s回镜 = 3.15s**；2.05s开始回镜，3.15s归还/flow.end。
- 只处理真实 `avatar.visual_root` 下可见有效几何，全体共用世界Y边界，从脚至耳扫描；不再使用逐部件 `local_height` 或写死1.5m角色高度。
- 低环、高环与扫描带按真实世界AABB边界定位；真实fixture覆盖20个角色/装备Mesh，隐藏祖先、状态环、准星与仅投影件不被覆盖。
- 初始近景在真实 `aim_yaw` 后方侧偏 `+12°`：距离 `3.8m`、俯角 `18°`；随后右摆 `+7°`至14°俯角，最后1.10s回接管前精确机位。

### 1.2 凝实成形 B

- AssetID：`VFX-HOLOGRAM-ENTRY-MATERIALIZE-3D`
- 剧本：`nar_expedition_entry_hologram_materialize`
- 最终时长：**1.75s重建 + 0.30s实体化 + 0.35s停留 + 1.20s回镜 = 3.60s**；2.40s开始回镜，3.60s归还/flow.end。
- 12片环场碎片从外侧向内收束，中心亮芯末拍凝实；真实角色与A共用世界Y扫描及原材质实体化流程。
- 初始近景在真实 `aim_yaw` 后方侧偏 `-14°`：距离 `4.6m`、俯角 `23°`；左摆 `-8°`至19°，1.75s再推近 `3.45m/12°`，最后1.20s回玩法机位。

最终数值以 `data/narrative/nar_expedition_entry_hologram_scan.json` 与 `nar_expedition_entry_hologram_materialize.json` 为准，替代过程稿3.2/4.15及2.4/3.3秒口径。距离、偏航和俯角复用NarrativeAdapter通道与host几何约束；镜头瞄准真实角色世界高度中心。回镜插值到接管前世界变换，最终精确归还原本地transform、FOV与原CameraAttributes/景深对象；近景暂停camera feedback、临时关闭Practical近/远景深，回镜恢复原景深强度，不新增第二套玩法相机。

## 2. 跨文件契约

| 落点 | 契约 |
|---|---|
| `TowerDescent3D` | 只在读取交接完成后由 `notify_expedition_entry_ceremony_ready()` 发事件；入口来源/原因/房间/续档负向判定集中在 `_is_valid_expedition_entry_ceremony()` |
| `ExpeditionLoadingScreen` | 释放 loading 场景后黑幕仍盖住时预热相机/输入/材质；先隐藏自己的 Backdrop，再开 Iris；开圈完整后才通知目标场景 |
| `NarrativeDirector3D` | 两个event剧本，pending预备不冒充active；匹配出发事件才转active。取消pending、目标/相机失效、host卸载/重绑、导演退出均归还；`once=departure`正常完整收口消费，中断清标可在同request重试，不写跨局history |
| `NarrativeAdapter3D` | 保存host、player与归还回调；输入/瞄准/host持锁、真实aim_yaw后方相机及精确位姿/景深归还；结束由host重裁模态输入锁 |
| `ExpeditionEntryPresentation3D` | 只取真实avatar.visual_root可见几何，共用世界Y边界；保存override/overlay/cast_shadow/transparency，暂停表情并恢复原presentation_held。实体化为原材质真实几何渐入与独立全息副层渐退，不近似重造原shader；正常/取消/中断/卸载均归还 |
| `VfxPool3D` | 两个 AssetID、两个独立 Prefab、两个池桶；不带碰撞、不带灯、不投影 |
| `runtime_player_state_v2` / `BaseData 2.0` | 未修改 |

## 3. 资产与账本

已登记特效域：

- 资产主表第 63 行：`VFX-HOLOGRAM-ENTRY-SCAN-3D`
- 资产主表第 64 行：`VFX-HOLOGRAM-ENTRY-MATERIALIZE-3D`
- `3D-特效` 第 258/259 行：对应两个正式 PackedScene
- 域变更日志：`v0.1.40`
- 初次登记使基线资产数 `1445 → 1447`；本次最终同步仍为1447，不再增资产/版本。仅定点修改主表 `Y63/Y64`、分页 `Q258/Q259` 与已有日志v0.1.40的 `E49/F49`（尚未交付的本批日志补全说明），原制作状态、Prefab/代码路径、v001及SHA不变。
- 基线只更新两资产的 `v`、`3D-特效`真实摘要与九域并集第25列备注摘要；`c/d`、category_counts原schema、其余资产v与分页digest不变，不接纳无关invalid_status/SHA。`PRP-3D-REWARD-CHEST-ADVANCED/NORMAL`仍保留extra，不顺便纳基线。

运行文件：

- `src/vfx/VfxHologramEntry3D.gd`
- `assets/art/vfx/combat_3d/vfx_hologram_entry_scan_root_top3d.tscn`
- `assets/art/vfx/combat_3d/vfx_hologram_entry_materialize_root_top3d.tscn`
- `src/narrative/ExpeditionEntryPresentation3D.gd`

## 4. 验证结果

### 4.1 初版证据不足与隔离修正

初版探针只核了简化Mesh/逻辑，不能证明真实多部件avatar、统一世界Y扫描、表情与材质归还、后方机位及正式host接线；早期“通过”不能代替最终验收。早先使用 `--user-data-dir .../.test-userdata-entry-final` 的命令未可靠证明Godot实际user://隔离，首次未在Autoload之前隔离的测试不计正式通过；保留该过程事实，不以旧exit0签收。

最终入口为 `python scripts/run_expedition_entry_qa.py`（真实渲染；`--logic`仅逻辑）。Runner在启动Godot前设置工程外 `APPDATA/LOCALAPPDATA/XDG_DATA_HOME/XDG_CONFIG_HOME` 与 `SHELLSTORM_VERIFICATION_OUTPUT`，创建外部运行工程并复制独立 `.godot`缓存；不执行editor导入。专项开头断言实际user://位于隔离APPDATA下，不能等Autoload完成才改路径。本次仅核对既有最终产物，未重跑或修改运行代码/Runner。

### 4.2 最终真实证据（20261111_212813）

证据根：`I:/工作项目/shellstrom2/ShellStorm2-work/verification/expedition_entry/20261111_212813/`。日志实际是根下 `console.log` 与 `timeline_final.log`，不存在 `console/timeline_final.log`。

| 项目 | 真实结果与边界 |
|---|---|
| `result.json` + `console.log` | 正常Godot CLI，Vulkan Forward+ / RTX 4060 Ti / 1280×720，进程exit0；`script_errors=0`；复核console为0 `SCRIPT ERROR` / 0 `ERROR`，`EXPEDITION_ENTRY_RESULT ... failures=0` |
| 两模式真实Player fixture | `CEREMONY_MODE_OK`分别 `meshes=20 duration=3.15/3.60`；真实兔子与武器/背包，不是Box替身 |
| 六张截图 | `output/0_half.png`、`0_solid_close.png`、`0_gameplay.png`与`1_half.png`、`1_solid_close.png`、`1_gameplay.png`：半成形、原材质实体近景、精确归还玩法机位；最小舞台fixture，不冒充正式地图全景 |
| 正式host接入 | `OFFICIAL_HOST_OK base_scan/base_materialize`：真实 `ExpeditionLevel01_3D.tscn` / `TowerDescent3D`，`test_mode=false`，经公开prepare/notify入口及正式导演；取消同request重试和正常归还通过 |
| 来源/续档负向 | `OFFICIAL_HOST_OK tower03/resume`：拒绝塔3，实际落盘checkpoint再加载的host存在恢复快照且不播，不是只改字符串假装续档 |
| 归还与故障 | 无效相机准备失败回滚、pending取消、播放中断、相机失效、pending/active卸载与同request重试，精确transform/FOV/attributes及override/overlay/shadow/transparency断言；归还后真实输入移动通过 |
| `timeline_final.log` | `verify_narrative_timeline_OK checks=113`；其中故意缺参 `player.teleport` 的负测打印1条预期 `ERROR`，0 `SCRIPT ERROR`，不能写“113项零ERROR” |

真实六图已逐张核看：A/B半成形与实体近景不同，均回到同一顶视玩法机位；状态环/准星保留。截图只证明fixture画面，读取链交接由下面 §4.3 的真实读取页E2E单独证明。

### 4.3 真实读取页交接E2E（20261111_222806）

命令：`python scripts/run_expedition_entry_qa.py --loading-e2e`（真实Forward+，产物在工程外；Runner继续在Autoload前隔离 `APPDATA/LOCALAPPDATA/XDG_*`）。范围是**已准备的99F出发请求 + carry 快照**（`reason=mission_operations_teleport`、`BASE`来源、正确pending level），由真实 `ExpeditionLoadingScreen` 自行切到正式 `ExpeditionLevel01_3D`；不包含人工在99F基地菜单点击出发，也不覆盖选关UI本身。

| 项目 | 真实结果与边界 |
|---|---|
| 双seed运行 | seed `20261110` exit0 / 101.97 s / `engine_errors=0`；seed `20261111` exit0 / 69.24 s / `engine_errors=0`；`passed=true`，两seed `failures=[]` |
| 预热 | `warmup.completed=true`、`kinds 3/3`、`vfx 12/12=0 pending`；`room_warmup 13/13`、`truncated=""`，非headless跳过 |
| 黑幕与输入 | `prepared_under_black` 时 `IrisTransition.is_covered()`、`presentation` 尚未 active、`input_locked`；开圈期间仍锁，且相机水平偏移与 `aim_yaw` 后方点积 >0.90、距离 <5 m |
| 时序 | `presentation.start` 与 `camera.pan` 同帧在开圈完成后（`_radius==HOLE_MAX`、mask不可见）；A 2.05 s 回镜、3.15 s `presentation.restore/flow.end`；B 1.75 s 再推近、2.40 s 回镜、3.60 s 收口 |
| 归还 | `restored_mesh_count=20`，override/overlay/cast_shadow/transparency 逐件同引用；相机局部transform精确、世界位移只等于玩家自身位移，FOV与 CameraAttributes 对象同引用；读取页/黑幕/`disable_3d`/pending 无残留 |
| 可玩 | `flow.end` 后 20 物理帧内按 `move_right` 12 帧位移 `0.7965186 m`（两seed相同），证明输入真正归还 |
| 截图 | 每seed三张：`loading_<seed>_screen.png`（读取页）、`_solid_close.png`（近景成形）、`_gameplay.png`（玩法恢复）；主线程已核看近景构图与恢复画面，无黑幕/全息残留 |

**同批次未完成项**：旧双host专项最新一次 `20261111_223135` 在240 s全进程上限超时（runner/Godot exit1、`engine_errors=0`），console停在 `_check_official_hosts` 装配正式host，`base_scan`/`tower03` 已过、`base_materialize` 未完成、resume未执行。该超时不能用作通过证据，也不能否定早先 `20261111_212813` 的正式host记录和本次双seed E2E；默认时限已调至300 s，未再复跑。

### 4.4 旧警告与未执行项

- 工程既有GLB invalid UID路径回退警告、中断用例现场强制归还warning保留，不通过删日志掩盖；历史ObjectDB退出泄漏警告未在本事务处理，也不把其修复算作本次成果。
- **人工在99F基地菜单实际点击出发仍未验**：§4.3 的E2E从已准备请求开始；后补的 `--base-menu-e2e`（见 §6）已把基地→设施交互→菜单点击→读取页跑通到开圈前，但**读取页装配阶段没跑完**，所以整条链仍不签通过。
- 未做纯新档人工全链路游玩、移动端、全关卡构图/手感与全工程回归；本次不补签。
- `WORLD-ENTRY / NARRATIVE-TRIGGER`及关联整体状态仍为partial，仅记录本专项真实fixture和正式host接入已验。

## 5. 本次文档/账本同步审计

外部备份、哈希护栏与新门禁证据：`ShellStorm2-work/99f_hologram_entry_sync_20261111/`；旧门禁/反向对照：`99f_hologram_entry_gates_20261111/`与`99f_hologram_entry_evidence_20261111/`。只改文档与账本；保留其他会话并行修改，不整文覆盖。账本使用openpyxl定点写，逐格白名单为6格；基线逐项检查仅两资产v、备注列25与3D-特效摘要变化。旧invalid_status、SHA与公式红项不接纳，双宝箱extra保留。

### 5.1 运行证据与日志检查分列

| 证据 | 既有run结果 | 本次check退出码 | 说明 |
|---|---|---:|---|
| 最终新入场专项 `20261111_212813` | `result.json exit_code=0`、failures0、6图 | 0 | `check_verification_log.py console.log`；0 SCRIPT ERROR/ERROR |
| 旧叙事回归 `timeline_final.log` | `verify_narrative_timeline_OK checks=113`；此日志无单独run退出码记录，不从OK字样补造 | 严格3；带既有expected清单0 | 1条刻意缺参player.teleport ERROR；0 SCRIPT ERROR。expected清单为 `tests/verification/expected_errors/verify_narrative_timeline.txt` |

本次没有重跑Godot；上表run为实读既有证据，check为本次实际执行。检查输出保存在 `runtime_evidence_checks.json`，不能把进程exit0、断言通过、日志零ERROR三者混写。

### 5.2 账本/文档门禁新旧退出码

| 门禁 | 早期99f gates | 本次改前 | 本次改后 | 问题增量 |
|---|---:|---:|---:|---|
| `check_asset_registry --scope structure` | 1 | 1 | 1 | 102→102：50键公式、50结果公式、2 invalid_status；新增0 |
| `check_asset_registry --scope full --ledger vfx` | 1 | 1 | 1 | 8→8：1 invalid_status、7 sha_mismatch；新增0 |
| `verify_ledger_split` | 1 | 1 | 1 | 109→109；missing=[]，双宝箱extra原样保留，column_digest_drift=[]；新增0 |
| `check_asset_runtime_naming` | 0 | 0 | 0 | 通过 |
| `check_ledger_refs` | 0 | 0 | 0 | 通过 |
| `check_documentation_contracts` | 未存该项 | 1 | 1 | 11条既有断链→11，忽略插入文本导致行号位移后逐项相同；新增0，不修无关docs |
| `check_feature_traceability` | 未存该项 | 0 | 0 | WORLD-ENTRY/NARRATIVE-TRIGGER仅补开发记录与隔离Runner映射，status仍partial |

本次证据为 `before_* / after_*` 日志及各自 `*_exit_codes.json`，归一化比较报告 `final_audit.json`（数组公式对象内存地址与文档行号位移不当成新问题）。旧invalid_status/SHA/公式红项仍报红，没有改状态、重算SHA或用全量资产指纹覆盖来接纳它们。

### 5.3 无损与并行修改护栏

- 外部 `before/`保留改前文档/账本；`before_hashes.json`冻结4107个相关文件，写入前再次断言九域账本及baseline哈希未发生并发变化。
- `ledger_cell_diff.json`逐格差异恰为 `资产主表!Y63/Y64`、`3D-特效!Q258/Q259`、`域变更日志!E49/F49`；其余单元格/样式、公式、DataValidation及合并区不变，XML层另验。
- baseline语义差异恰为两资产 `/v`、`column_digests/25`及 `sheet_digests/3D-特效`；列摘要用九域真实并集和权威 `col_digest`重算备注列，其他列摘要不变。`category_counts`保持原扁平分类→整数schema及原值，资产数1447、其余资产v/分页摘要、历史targeted_updates保留。
- 哈希复核本事务仅12个文件变化（10份既有docs及2份账本/基线），`runtime_files_changed=[]`；未改src/scenes/scripts/tests、最终JSON或Prefab，未提交/推送。原道具账本及其他会话修改保持不动。

### 5.4 读取页E2E证据回填（2026-11-11 22:45 后）

- 只回填文档：`design/关卡进入与冷启动预热设计.md` §8.5、本记录状态/§4.3/§4.4、`05_技术施工_关卡生成与爬楼.md`、`08_技术施工_剧情触发.md`、`14.6_特效系统与制作规范.md`、`MODULE_INDEX.md`、`README.md`、`development/CHANGELOG.md`、`development/README.md`。
- **不再改账本**：主表63/64、分页258/259与日志v0.1.40的登记、路径、状态和备注在登记时已定稿且仍然成立（“人工菜单点击端到端未跑”依旧为真）；E2E属于验证证据而非资产登记信息，写在本记录并在账本备注已带的链接下查阅，避免为同一条资产再做一次基线与六格改写。
- 未改 `src/`、`scenes/`、`tests/`、`scripts/`、剧本JSON、Prefab或Runner；未提交/推送。

## 6. 2026-11-12 基地出发事务缺陷与验收拆分

### 6.1 找到的实际缺陷：99F 基地里点任何远征入口都失败

补 `--base-menu-e2e` 时暴露：从真实 `BaseWorld3D` 点远征01，控制台只有一条

```text
ERROR: [HologramCity] 保存失败，请重试
```

`RogueMapSelectMenu._commit_departure()` → `ExpeditionDepartureService.prepare()` →
`BaseManager.flush_runtime_checkpoint()` 返回 false。根因不是磁盘：

- `flush_runtime_checkpoint()` 先 `_capture_runtime_checkpoint()`，后者必须有
  `_runtime_checkpoint_provider` 且该节点实现 `build_runtime_save_snapshot()`；
- 全仓库只有 `Dungeon3D` 注册这个提供者（`_activate_runtime_persistence()`）；
- 99F 基地是 `BaseWorld3D extends Node3D`，**没有**这个方法、也从不注册；
- 于是 `_capture_runtime_checkpoint()` 恒为空 → `flush_runtime_checkpoint()` 恒 false →
  `prepare()` 恒返回「保存失败，请重试」。

结论：**玩家在 99F 基地永远无法通过情报室进入任何远征关卡**，本功能的入口在真机上根本不可达。
既有 `verify_expedition_departure_carry` 之所以一直绿，是因为它用真实 `TowerDescent3D` 当提供者，
从未从 `BaseWorld3D` 出发。

### 6.2 修法（两个文件，行为最小化）

| 文件 | 改动 |
|---|---|
| `src/base/BaseManager.gd` | 新增只读查询 `has_runtime_checkpoint_provider()`，让调用方区分「没有提供者」与「写盘失败」 |
| `src/world3d/ExpeditionDepartureService.gd` | 只有**有提供者**时才要求 flush 成功；无提供者时沿用已落盘快照；`previous` 为空（新档直接站在基地）时不伪造 schema 不完整快照，直接成功返回 `carried=false`；回滚在 `previous` 为空时清空检查点 |

塔3天台路径（`RooftopExpeditionEntrance3D` → `prepare(tower, TOWER03)`）行为不变：那里有提供者，flush 仍必须成功。
目的地来源不依赖空快照：`TowerDescent3D._expedition_entry_source` 的默认值就是 `ExpeditionEntryContext.BASE`。

### 6.3 修复后实测（同一隔离 Runner）

| 证据 | 结果 |
|---|---|
| `.../20261112_003833/basemenu_20261110_console.log` | 点击前 `_pick(screen)=0`、`state=active`；`push_input(click, true)` 后 `state=entering`、`departing=true`；日志出现 `base_menu_click_departure frame=288` 与 `loading_screen frame=316` → **出发事务已通过，读取页已接上** |
| 同次读取页 | 预热与装配停在 `正在装配地图 · 11/13`，180 s 预算到期（引擎 exit 由 Runner 按超时计 1，`engine_errors=0`） |
| `.../20261112_004317`（预算 420 s） | 261 s 才到「远征资源与规划已完成」，300 s 停在 `11/13`，随后被外部进程终止 |
| `.../20261112_005448`（带临时装载诊断、600 s） | 连基地场景都没装完，控制台无任何 `LOADING_E2E` 事件 |

**判定**：出发缺陷已修且有直接证据；基地菜单链**整体未通过**。三次尝试期间本机另有 3 个与本任务无关的
Godot 4.7.2 进程各占约 1 GB，其中一次站点载入 600 s 未完，所以 `11/13` 既不能算通过，也不足以定性为产品死锁，
须在机器空闲时复跑同一条命令。诊断用的临时 `SHELLSTORM_DEBUG_LOAD` 打印已从 `Dungeon3D` 完全移除。

### 6.4 Runner 拆分（同进程预算被吃穿）

`--official-hosts` 独立成一条命令：四次完整 host 装配各约 40 s，和两套 fixture 同进程时
`20261111_223135`（240 s）与 `20261112_001044`（300 s）都在第 3 个 host 中途被杀，看起来像产品失败，
实际是预算。拆开后 `20261112_002015` 四条全绿：

| 命令 | 2026-11-12 实测 |
|---|---|
| `python scripts/run_expedition_entry_qa.py` | exit 0，`CEREMONY_MODE_OK ... meshes=20 duration=3.15/3.60`，6 图 |
| `... --official-hosts --timeout 600` | exit 0，`OFFICIAL_HOST_OK base_scan/tower03/base_materialize/resume` 各一条 |
| `... --loading-e2e` | 见 §4.3（20261111_222806，双 seed exit 0） |
| `... --base-menu-e2e` | 期望失败：读取页装配未完成，见 §6.3；模式保留，待空闲复跑 |

账本与基线本轮未改（mtime 仍为 2026-11-11 21:53）：修的是出发事务，不改任何资产登记、路径或 SHA。

### 6.5 今日复证状态（同一台机器、同一隔离 Runner）

| 命令 | 2026-11-12 结果 | 说明 |
|---|---|---|
| 默认（两套 fixture） | **exit 0**，`20261112_001831` | A 3.15 s / B 3.60 s，20 Mesh，6 图 |
| `--official-hosts --timeout 600` | **exit 0**，`20261112_002015` | `base_scan` / `tower03` / `base_materialize` / `resume` 四条全 `OFFICIAL_HOST_OK` |
| `--loading-e2e --seeds 20261110` | **未复证**，`20261112_011355` | Godot 425.6 s 超时，`engine_errors=0`、0 张截图、`report` 为空——连读取页首帧都没到。当次运行期间本机另有 3 个与本任务无关的 Godot 4.7.2 进程各约 1 GB。最后一次有效证据仍是 `20261111_222806`（双 seed） |
| `--base-menu-e2e --seeds 20261110` | **未通过**，见 §6.3 | 出发与读取页已接上，装配停在 11/13 |

关于 `--loading-e2e` 未复证的风险边界：本次对测试文件的改动只涉及该路径的**截图标签前缀**（非基地模式仍是 `loading_`，文件名不变）、`departed` 守卫（读取页路径恒为 true）、`request_id`/carry 断言移入 `if not via_base_menu` 分支（条件与断言内容不变）、总预算 180→420 s。
脚本能被 fixture 与 official-hosts 两种模式完整解析并跑完，说明没有编译错误；但没有新的运行时证据，就不写成"已复证"。

## 7. 2026-11-12 入场朝向改为「面向第一间房的门」

### 7.1 用户反馈与实测现象

用户要求：角色入场时要**面对通往第一个房间的门**，而不是面对出口位置。

真渲染证据（`verification/expedition_entry/20261112_022533/output/loading_20261110_solid_close.png`）显示两个问题：

1. 角色出生时 `aim_yaw = 0`，即面向世界 −Z。远征01 起始房 `entry_side = east`、主路向西（`exit_side = west`），
   世界 −Z 恰好是"回去的方向" —— 近景拍到的是身后的虚空/入口侧。
2. 更糟的是**角色被杀掉的办公椅挡住八成**：椅子正好卡在近景机位与角色之间。

### 7.2 修法

**朝向**（`TowerDescent3D.prepare_expedition_entry_ceremony()` → `_face_player_toward_forward_door()`）：

- 几何真源放在通用层 `Dungeon3D.forward_door_point_from(room_id)`，不认关卡 ID（符合《关卡接入规范》）：
  1. 主路下一间 = 记录里 `parent == 本房` 的第一个房间（远征01 的 `room_01` 挂在 `entry` 下）；
  2. 环状图（EGT 骨架）没有 `parent` 时退回开放邻边第一个；
  3. 门节点优先于房间中心 —— 门在墙上，朝门才有"朝着出口走"的观感。
- 只写 `player.aim_yaw = atan2(-delta.x, -delta.z)`（与 Player3D 同口径）。**不手动转 avatar**：
  `PlayerAvatar3D` 每帧朝 `aim_yaw` 插值，手动再转一次会与插值打架。
- 新增 `DungeonRoom3D.get_door_links_snapshot()` 暴露 `方向 → RoomDoor3D`，避免外部直接读私有 `_door_nodes`
  （改结构时会静默拿到空字典，表现只是"朝向又不对了"）。

**遮挡**（`ExpeditionEntryPresentation3D.suppress_occluders()`）：

- 在 `NarrativeAdapter3D.prepare_expedition_entry()` 里、相机 `tick(0)` 就位之后调用 —— 此刻黑幕仍全覆盖，
  移走的陈设观众看不到消失的那一帧；`restore()` 在演出收尾时恢复。
- 判据两条（任一命中）：线段穿过局部 AABB；或「中心到线段距离 < 0.45 m + 该件半对角」且单件最长边 ≤ 3 m。
- 两条都必须留：实测椅子中心离中心线 0.61 m，单看线段判定完全不算遮挡，但它 0.75×1.29 的体量把角色挡了大半。
  → **只判线段会得到 `faded=0`、画面里却看不见人的假绿**。
- 3 m 上限用来排除地板、承重底板（15×15）、墙体与散落碎屑群：它们必然覆盖任何线段，移掉等于把地面擦掉。
- **不能用 `transparency` 淡出**：GLB 家具是不透明材质，实例透明度对它无效 —— 实测设 0.12 后画面零变化
  （诊断打印 `faded=2`，截图里椅子照样实心）。这就是第一版失败的根因。

### 7.3 实测

| 证据 | 结果 |
|---|---|
| `20261112_024819/result.json`（正式 Runner，双 seed） | `passed=true`；两 seed `exit 0`、`engine_errors=0`、`door_facing_dot=1.000`、`completed=true` |
| 同目录 6 张截图 | 两套演出的近景都显示角色**完整可见、背对镜头、正对门洞**；椅/花瓶不再挡人 |
| `20261112_024819/output/loading_20261110_gameplay.png` | 玩法恢复后椅子、花瓶等陈设照常可见 → 隐藏已精确归还 |
| `20261112_025300`（`--official-hosts`） | 四条 `OFFICIAL_HOST_OK` 全过，`base_scan`/`base_materialize` 同时断言 `door_facing_dot > 0.95` |
| `20261112_024705`（默认 fixture） | exit 0，A 3.15 s / B 3.60 s，20 Mesh |

### 7.4 期间撞到的并行改动（如实记录）

这两小时内另一会话正在改 `EncounterEventDirector3D.gd` 与 `LevelPlanValidator.gd`，我先后撞到两次中间状态：

1. `02:41` 编译失败：`Function "_close_dispatch_and_clear()" not found`（调用已写、定义还没写）；
2. `02:51` 正式 host 装配报 `encounter_duration_invalid:room_03..10:0.0`（校验器正被改）。

两次都不是本次改动引起的；`02:46` 与 `02:52` 对方补齐后，用**同一份正式 Runner** 复跑即全绿。
中间为了不被对方半成品阻塞，曾在工程外用实拷贝 `src` 的临时 runner 验证过一轮
（`ShellStorm2-work/tmp_entry_qa_runner/`，只在副本注入 stub，未改仓库文件）；正式结论以上表为准。

### 7.5 本段改动清单

- `src/world3d/Dungeon3D.gd`：新增 `forward_door_point_from()` / `_main_path_next_room_id()`
- `src/world3d/DungeonRoom3D.gd`：新增 `get_door_links_snapshot()`
- `src/world3d/TowerDescent3D.gd`：`prepare_expedition_entry_ceremony()` 先转向；新增 `_face_player_toward_forward_door()`
- `src/narrative/ExpeditionEntryPresentation3D.gd`：新增 `suppress_occluders()` / `restore_occluders()`，`get_snapshot()` 加 `suppressed_occluders`
- `src/narrative/NarrativeAdapter3D.gd`：相机就位后调用 `suppress_occluders()`
- `tests/verification/verify_expedition_entry_hologram_ceremonies.gd`：读取页 E2E 与正式 host 均断言 `door_facing_dot`
- 诊断打印 `DBG_OCC*` 由 `SHELLSTORM_DEBUG_OCCLUDER` 环境变量开关，默认静默

未改账本与基线（不涉及资产登记）。
