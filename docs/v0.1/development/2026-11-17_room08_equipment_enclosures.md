# 远征01：08房封闭设备区与中央贩卖机

日期：2026-11-17；记录 ID：`2026-11-17_room08_equipment_enclosures`；FeatureID：`WORLD-PLAN`；工程版本：`0.1.0`。
设计依据：[远征关卡01设计 · room_08](../design/远征关卡01设计.md#room_08--拐角走廊0145--40)。状态：最终现行为**48个贴墙设施、216实例**；**最终216版standalone几何与真实渲染已验证，正式战斗几何专项已通过**；完整交易、人工整关及设备未验，整关partial不提升。本次最终回填仅修改本记录及设计页验收边界，不再写账本或索引。

## 1. 用户裁定与事实来源

- 用户图：`clipboard-2026-11-17T14-18-12-358Z-f88537a4.png`；用户明确选用**封闭设备区**，不是留入口的可进入机房。
- 主线程 manifest：`I:/工作项目/shellstrom2/ShellStorm2-work/sessions/2026-11-17_room08_equipment_enclosures/manifest.json`。本事务只读，不改原 manifest 或临时脚本。
- 正式场景：`assets/art/environments/tower_zones/expedition/runtime/room_instances/expedition_01/f00_room_08_static_layout.tscn`，不是旧房型默认布局路径。
- 此前矩形整面通透、贩卖机靠东墙的规则与旧测试读数已被本轮取代；[前轮记录](2026-11-17_room07_08_layout_fix.md)保留为历史，不代签本轮。

## 2. 主线程已落地的布局变更

坐标均为静态场景 **authored 帧**：西北设备区 `X[-20,0]、Z[-22.5,-7.5]`；东南设备区 `X[-5,20]、Z[7.5,22.5]`。两区完全封闭，不留入口；中央通路 `Z[-7.5,7.5]`，保留两条真实主路门与原端口关系，装甲面朝玩家走道。

| 项目 | 本轮口径 | 证据性质 |
|---|---|---|
| prefab 实例 | 原153＋15段 battle 5m装甲实墙＋48个贴墙设施＝216 | manifest＋正式TSCN只读计数，不是运行验收 |
| 围挡墙 | 复用 `battle/runtime/common_components/wall_standard_5m/wall_standard_5m_root_top3d.tscn` | 不制作或修改共享资产 |
| 设施 | 仅复用贴墙电柜、储物柜、工业水箱与备用发电机；32个独立服务器rack/spine已撤除 | 资源路径逐项见 manifest |
| 贩卖机 | `ServiceStation_Merchant_00` authored 锚点 `(0,0,0)` | 原服务配置、视觉与碰撞配置不变 |
| 既有盆栽 | manifest记录 `ENV-EXPEDITION-L-CORRIDOR-PLANTER_01` 从 `(-15.956414,0.27187443)` 移至 `(-15.956414,15.27187443)`（X/Z） | 主线程既有调整，本事务不再改动 |

最终视觉审查按用户“所有设施靠墙”撤掉32个独立rack/spine；仅保留48个贴墙设施。水箱/发电机相邻中心间距分别为**1.985/2.26m**，西东外墙水箱中心 **X=±18.76**。首轮80设施/248实例仅作历史，不作现行配置。

manifest 声明改前 SHA-256：`8ca3712b7e5e39006134e7b77664e4ad86daff9b50618890df1f6d4956110454`。
最终216版正式静态TSCN SHA-256 已只读核对，与 manifest 的 `after_sha256` 一致：`2cd31379ae363e83dafd80cd9f31962f2e3c3902fd78a6f0ca673d7ad312b722`。此前248版修正后SHA为`6c02651c2f905938e03881d2c01530993ef68b4c20bf0eb81d04c6e469c55cb8`，仅绑定248版历史专项。
此前登记快照中的 `5c5abc11ce2058e985bbeed9ec7234283411a9e2f515c86560a0602c72300cd4` 仅为首轮248版本，已被后续版本取代，不能绑定216版验收结论。
以上均为**本房实例哈希**，不覆盖场景账本目标行的房型源主哈希或版本。首轮误置源于 `Transform3D` 序列转置，导致6段墙朝反及18个大型设施越界；主线程在248版已修正，15墙朝向与80设施视觉bounds历史检查通过，详见§5；不能沿用为216版结果。

## 3. 本次登记范围与保护边界

- 设计正文仅替换 `room_08` 段的现行规则，移除过期通透/东墙落位的现行表述，不复制历史测试大日志；旧SVG明确标为旧房型参考。
- `MODULE_INDEX.md`、开发目录 `README.md`、`CHANGELOG.md` 仅插简短新链接；`feature_registry.json` 仅向 `WORLD-PLAN.development_records` 追加本记录，不更改功能状态或他人登记。
- 场景账本按 `AssetID=ENV-EXPEDITION-L01-L-CORRIDOR` 定位，仅允许《资产主表》备注/更新时间；使用 openpyxl，不通过编辑器保存，不强关用户程序。源版本、SHA-256、路径、规格、制作状态、R/S公式及域内专表均不改。占用失败即停止登记并报告待补，不绕过锁。
- 无损基线仅更新该ID的行指纹，并按 `ledger_index.json` 的9域汇总 `column_digests`、`category_counts`；保留其他资产指纹、专表摘要和他人已有改动，不运行 `--baseline-only`。
- 本事务不改主线程TSCN/GD、设计源JSON、测试、临时脚本、源资产或正式运行组件。

## 4. 首轮登记备份与静态门禁（历史记录）

登记前7份文件已备份并逐份SHA核对：
`I:/工作项目/shellstrom2/ShellStorm2-backup/2026-11-17_room08_equipment_enclosures_registration_224838/`。

检查输出经 `scripts/workspace_paths.py` 定位，全部留在工程外：
`I:/工作项目/shellstrom2/ShellStorm2-work/sessions/2026-11-17_room08_equipment_enclosures_registration_224838/`。

- `snapshot.json`：7份改前文件哈希与备份定位。
- `scene_readonly.json`：首轮历史248实例与当时场景哈希的只读核对，不是216版结果。
- `git_status_before.txt`、`protected_hashes.json`：接手时已有修改及45个主线程代码/场景文件哈希。
- `ledger_diff.json`：openpyxl保存后全工作簿逐格回读，实际差异严格为《资产主表》**Y242一格**；V242原已为`2026-11-17`，确认保持当天。源版本M242=`v012`、主SHA T242=`1ec561cf6c9668c580e662a41ad947df8e94e017ce451b8e2c70857ae6912b33`不变；全部单元格样式、公式、合并区、筛选、DV与zip层公式/DV/dimension均核对不变，域日志及域内专表未动。写入成功，无账本占用待补项；未关闭任何用户程序。
- 基线仅该ID的`assets[id].v`和`column_digests["25"]`实变；9域`category_counts`已重算、结果原值不变，其他资产指纹与`sheet_digests`逐项保留。9域行数：characters 26 / enemies 52 / scenes 1019 / props 45 / weapons 36 / vfx 68 / ui 26 / audio 184 / music 9，合计1465行；不将两只既有未入基线奖励箱补录为本轮资产。
- `docs_scoped.diff`、`scope_check.json`：设计页room_08之外逐字不变，三个导航文件旧正文不变，feature登记只增加WORLD-PLAN一条记录。正式08房TSCN哈希保持接手值。本事务期间另有12个武器/VFX相关受监控文件发生并行变化，明细留在范围报告，未回滚或归入本轮；因此不声称整个共享工作树未变。
- `before/`、`after/`保存同命令的完整输出及退出码，`gate_comparison.json`逐项反向对照；所有报红条目改前改后相同，文档断链按路径/目标比对（导航插入引起的行号偏移不作新问题）。

| 静态门禁 | 改前→改后退出码 | 实测结果与范围 |
|---|---|---|
| `check_asset_registry.py --scope structure` | 1→1 | 17→17条，issue集合逐项相同 |
| `check_asset_registry.py --scope full --ledger scenes` | 1→1 | 22→22条，含2条既有sha_mismatch，issue集合逐项相同；本轮全账本T列不变 |
| `verify_ledger_split.py` | 1→1 | 24→24条，failure集合逐项相同；missing为空，column_digest_drift为空；两只旧奖励箱extra仍保留 |
| `check_documentation_contracts.py` | 1→1 | 15→15项：14条既有断链＋`verify_fat_zombie21_gait`未登记；本轮新增问题0 |
| `check_expedition_room_asset_status.py` | 1→1 | 46→46条，问题行逐项相同 |
| `check_asset_runtime_naming.py` | 0→0 | `ASSET_RUNTIME_NAMING_OK`，输出相同，旧命名欠账保留 |
| `check_ledger_refs.py --project-root …` | 0→0 | `LEDGER_REFS_OK pending=0`，输出相同 |
| `check_feature_traceability.py` | 0→0 | `issues=[]`，输出相同 |

上述只是文档、账本与静态契约检查；全局红项未修复，不能标为全门禁通过，更不能作为运行验收。

## 5. 最终216版运行专项验收

### 5.1 执行范围与证据

最终 **direct standalone fixture** 直接加载正式08静态TSCN、正式 `ServiceStation3D` 与机器prefab，启动前将 `APPDATA` 等用户目录隔离到工程外WORK。此fixture不是整关Tower装配，不覆盖完整购买/存档、人工整关或设备体验。本次只读核对主线程最终报告，不重新运行fixture。

主线程执行命令（工程根）：

```text
python ../ShellStorm2-work/sessions/2026-11-17_room08_equipment_enclosures/run_verify.py --render
```

主线程已确认最终结果；当前`verification.json`为`passed=true`、`failures=[]`、`wall_count=15`、`facility_count=48`、`merchant_blocks=true`，15个armor、48个facility及6个path check逐项符合预期，绑定§2的216版SHA。

证据根目录：
`I:/工作项目/shellstrom2/ShellStorm2-work/sessions/2026-11-17_room08_equipment_enclosures/`。

- `verification.json`、`manifest.json`：最终216版验证与场景定位。
- `room08_top.png`、`room08_perspective.png`、`room08_center.png`：最终216版 `gl_compatibility` 真实渲染图。
- `render/run.log`：实际渲染日志；资源UID路径回退警告与脚本错误分开，不宣称零警告。
- `documentation_final.log`：主线程最终文档门禁退出1，保存既有问题，不记为全门禁通过。

### 5.2 最终216版验收表

路径点均为authored **X/Z**；起点为门A内侧 `(-12.5,20.5)`。

| 验收项目 | 最终216版状态 | 实际结果与未覆盖边界 |
|---|---|---|
| 封闭设备区不可进入 | fixture已验 | 西北内部 `(-10,-15)`、东南内部 `(8,15)` 从门A均不可达；不将目标点结果扩写为整关全周界零漏出 |
| 中央通路与两真实门连通 | fixture已验 | 门A → 门B内侧 `(18,-15)` 可达，不代签整关全部动态门状态 |
| 15段装甲墙朝向 | **15/15通过** | 全部normal对应步行区，`armor_checks.aligned=true` |
| 48个贴墙设施视觉bounds | **48/48通过** | 全部在所属设备区，`facilities.inside=true`；不等同所有路线或整关容量覆盖 |
| 中央贩卖机位置、实体阻挡及接近路径 | fixture已验 | authored `(0,0,0)`、`merchant_blocks=true`；门A → 正面 `(0,-2.0)`、左 `(-3,0)`、右 `(3,0)` 均可达，六项path check全部符合预期 |
| 正式战斗几何 | **216版专项通过** | runner退出0、`passed=true`、`engine_errors=[]`，精确报告见§5.4；旧224/224不沿用 |
| 真实渲染 | **最终216版已验证** | 三张最终图见§5.1，不代签人工整关与目标设备 |
| 完整交易/存档往返、人工整关及设备 | **未验** | 不以fixture或战斗几何专项替代完整流程验收 |
| path_coverage | **未执行** | 不宣称所有路线覆盖 |

### 5.3 首轮修正与保留边界

- 地面支撑使用中心＋四向各偏移 **0.12m** 足底采样，避免旧5m砖缝被零宽射线漏检；阻挡球半径 **0.32m保持不变**，不改正式地砖/碰撞。
- 首轮`Transform3D`序列转置造成6墙朝反、18个大型设施越界，已修；视觉审查又撤除32个独立rack/spine，最终仅48个贴墙设施、216实例。首轮Tower probe曾270s超时无结果，后续正式战斗几何已补跑通过，**不据首轮超时推导整关失败**。
- `l_turn`房型源与本房实例不一致、42格/72格足迹口径债及封门期交易策略仍保留；本轮不修改spawn。旧153实例面积、路径比及旧224/224不沿用。最终专项通过不等于完整交易、人工整关、设备或全部路线验收，整关partial不提升。

### 5.4 最终216版正式战斗几何报告

精确结果文件（已核对文件名为`result.json`）：
`I:/工作项目/shellstrom2/ShellStorm2-work/sessions/2026-11-16_exp01_combat/docs/shellstorm-verification/1794929600369413000_77001199_geometry/result.json`。

已只读核对`passed=true`、`exit_code=0`、`engine_errors=[]`、seed=77001199、`appdata_isolated_before_autoload=true`；同目录有`geometry.json`与`run.log`。`path_coverage`明确未执行，不能扩写为整关所有路线或完整清房流程验收。之前`1794928797336034700_77001199_geometry`属于248版历史证据，不再用其代签216版。

## 6. 216版最小同步事务

本次仅处理既有8个登记文件；feature_registry既有记录链接不含数量，不作无意义重写。账本仅改Y242本轮新增备注中的`80→48`、`248→216`，旧历史notes和其他格不动，目标ID基线指纹及9域汇总按skill重算。输出与diff位于：
`I:/工作项目/shellstrom2/ShellStorm2-work/sessions/2026-11-17_room08_wall_flush_216_232436/`。
备份位于工程外同名`ShellStorm2-backup/2026-11-17_room08_wall_flush_216_232436/`。该轮静态门禁及逐格差异以该目录报告为准，§4原门禁仅保留首轮历史；最终216版运行结论以§5的新证据为准。

已回读确认全工作簿仅Y242一格实变，本轮新增段仅数字`80→48`、`248→216`，原历史notes/日期/版本/主SHA/公式/DV/样式不变。基线按写入前最新快照对照，仅目标ID指纹与第25列摘要实变；9域1465行汇总完成，category_counts不变。写入前检测到并发8个VFX资产基线更新，已另备份至`before_ledger_apply/assets/registry/ledger_split_baseline.json`并全部保留，不覆盖其资产指纹或专表摘要。

本次静态门禁：structure 17→17、scenes full 22→22、split 24→24、文档19→19、资产状态46→46，均exit1且问题集合相同；命名/账本引用/Feature追溯exit0。该轮新增问题0；静态门禁本身不代表运行通过，最终216版运行结果另见§5。完整命令/退出码在`before/gates.json`、`after/gates.json`；对照在`gate_comparison.json`，账本差异在`ledger_diff.json`与`ledger_note_scoped.diff`，基线差异在`baseline_scoped.diff`，文档差异在`docs_scoped.diff`，范围核对在`scope_check.json`。既有8文件中7个实变，feature_registry链接无数量、保持原值。
