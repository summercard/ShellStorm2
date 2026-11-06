# 2026-11-06 近两日工作落档核对 + 设计/实现差异清单

- 核对时间：2026-11-06 09:04
- 核对范围：`e7407aec`（2026-11-05 04:03，6 项）与 `50628623`（2026-11-06 04:05，57 项）两次每日提交
- 口径：「落档」= 开发记录（`development/`）+ `CHANGELOG` + `MODULE_INDEX` + 九本分域账本（`assets/registry/ledgers/`）+ 验收注册表（`scripts/run_verification_suite.sh` 名单）+ 完成度清单（`12_全游戏完成度清单.md`）
- 方法：`git show` 逐文件比对 → 关键词回查文档 → 账本门禁复跑（`check_asset_registry` / `verify_ledger_split` / `check_ledger_refs` / `check_feature_traceability`）

---

## 1. 近两日六个工作项的落档情况

| # | 工作项 | 开发记录 | CHANGELOG | MODULE_INDEX | 账本 | 验收 | 判定 |
|---|---|:--:|:--:|:--:|:--:|:--:|---|
| 1 | 远征03 关灯底光 0.15（`Expedition03IndoorLightEnvelope`） | ✅ 11-04_dark_fill | ✅ | ✅ | — 无资产改动 | ✅ `verify_expedition03_indoor_lighting` | 完整 |
| 2 | Boss 房仪式封印门 `ENV-EXP03-BOSS-DOOR-RITUAL` | ✅ | ✅ | ❌ 缺摘要 | ✅ 场景账本 1019 行 / v0.1.71 | ⚠ 无正式渲染验收 | **MODULE_INDEX 缺** |
| 3 | 宝箱免钥匙直开 + 钥匙经济退役 | ✅ | ✅ | ✅ | ✅ 物品道具账本 + 场景账本 | ✅ 三只探针 | 完整（套件未跑见 §4） |
| 4 | 宝箱开箱前置/后置过渡（0.42/0.12/砰/余韵） | ✅ | ✅ | ✅ | — 纯程序表现 | ✅ `_egt_chest_probe` | 完整 |
| 5 | 子弹尾迹整体隐藏（`BULLET_TRAIL_VISIBLE=false`） | ✅ | ✅ | ❌ 缺摘要 | ❌ 特效账本无记录 | ✅ samples 69 / 16 | **账本 + 索引缺** |
| 6 | 僵尸死亡地面液体 → 黏液血泊贴图（`vfx_zombie_goo_puddle_floor.png`） | ✅ | ❌ 缺一条 | ❌ 缺摘要 | ❌ 特效账本未动（FX01-17/19 仍写「扁平方形地面液体」） | ✅ samples 17 | **三处缺** |

结论：**6 项里 3 项没落全档，全部集中在 VFX 域**。宝箱/钥匙那条主线（改动最大）反而是落得最齐的。

---

## 2. 本次已补录（写入完毕）

| 文件 | 补了什么 |
|---|---|
| `assets/registry/ledgers/ShellStorm2_特效账本_v001.xlsx` | ①《资产主表》A36/A38 规格列改写为「贴图面片地面液体」，关键词补 `血泊/黏液贴图/puddle`，更新时间 2026-11-05，备注追加完整改版说明 + 贴图路径 + SHA-256；②《3D-特效》FX01-17 / FX01-19 描述与尺寸列同步；③《域变更日志》`v0.1.36`（黏液贴图）+ `v0.1.37`（尾迹开关） |
| `assets/registry/ledger_split_baseline.json` | 白名单只刷新这两行指纹 + `3D-特效` 分页摘要（`scripts/refresh_ledger_baseline_goo_puddle_20261105.py`） |
| `docs/v0.1/development/CHANGELOG.md` | 补 `2026-11-05 · VFX-POOL · 地面液体换贴图面片` 一条 |
| `docs/v0.1/MODULE_INDEX.md` | 补 3 条摘要：Boss 仪式门 / 子弹尾迹隐藏 / 黏液贴图 |
| `docs/v0.1/development/2026-11-05_zombie_goo_puddle_texture.md` | 新增「账本」一节，记录原记录漏的账本动作与「贴图不单开 AssetID」的理由 |
| `docs/v0.1/05_技术施工_关卡生成与爬楼.md` | §5.4 钥匙与防卡死后补一条 **2026-11-05 例外**：远征03 整条钥匙经济退役，不要把「本关没有钥匙」当回归 |
| `src/world3d/TreasureChest3D.gd` | 头注释时间轴由 `0.54 砰 / 0.92 结束` 纠正为 `0.59 砰 / 0.97 结束`（常量 `OPEN_BURST_DELAY_SECONDS=0.59`、`BURST+SETTLE=0.38`；注释漏算了回正 0.05s，正是 11-05 那个「掉落比爆点早一帧」的坑） |

**贴图为什么不单开 AssetID 行**：按 FX01-16 吼叫图标 `vfx_monster_roar_icon_atlas_v001.png` 的既有先例，贴图视为所属特效的**内嵌资产**，路径与 SHA 记在 FX 行备注里 ⇒ 资产总数仍 1437、查重范围不变、`LEDGER_SPLIT_VERIFY_OK`。

---

## 3. 设计文档 vs 实际内容：差异清单

按「文档过期 / 文档自相矛盾 / 做完没验收 / 登记欠账」四类，共 **12 条**。除标注「已修」外均未改动，等裁决。

### A. 文档写过时（代码已经变了，正文还在说旧的）

| 编号 | 位置 | 文档怎么说 | 实际怎么做 | 建议 |
|---|---|---|---|---|
| A1 | `design/远征关卡03设计.md` §6e | 房间美术（地砖/墙板/**陈设**/**灯**/门扇本体）一栏写 **未做** | `data/layouts/expedition/v012/component_instances.json` 已有 123 条陈设实例，作者灯/补光已在 11-02 落地（`2026-11-02_expedition03_indoor_lighting.md`） | 把「陈设/灯」从 6e 拆出并标已做；地砖/墙板/门扇本体另立状态 |
| A2 | `04_技术施工_战斗与局内成长.md:249` | 太阳钥印「立即获得 1 把普通房间钥匙」，无关卡限定 | 远征03 已把该卡从报价池移除（`_gate_expedition_fate_offer`），只剩塔楼/远征01/02 可出 | 表格加一句「EGT 不出价」 |
| A3 | `12_全游戏完成度清单.md:3` | 「最近结构核对：2026-09-12，代码基线 `31ed360`」 | 距今近两个月，期间经历远征03 整套（宝箱/钥匙/精英/Boss 门/室内光）；该清单**根本没有远征03 章节** | 要么补一章，要么在页首明确「本页只覆盖塔楼主线，远征03 见 MODULE_INDEX」 |
| A4 | `14.6_特效系统与制作规范.md` v003.7 段 | 尾迹锥面数是「账本与 `EXPECTED_TRAIL_PARTS` 的契约」 | 尾迹当前整体隐藏（`BULLET_TRAIL_VISIBLE=false`），面数契约仍在，但预算不再影响画面 | 补一句「开关关闭期间面数预算不生效，窗口重开时按原契约复核」 |

### B. 文档自相矛盾

| 编号 | 位置 | 矛盾点 |
|---|---|---|
| B1 | `04_技术施工_战斗与局内成长.md:718` vs `:728` | 718 行写左上角色状态块含「局内货币/**钥匙**」；728 行（2026-10-15 修订）写金币迁到右下角、「**不再显示**背包数量与钥匙数量」。同一节两句话直接打架 |
| B2 | `src/world3d/TreasureChest3D.gd` 头注释 vs 常量 | **已修**。注释 0.54/0.92，常量 0.59/0.97 |

### C. 做完但没验收 / 验收口径不足

| 编号 | 事项 | 现状 |
|---|---|---|
| C1 | Boss 仪式封印门 | `asset_manifest.json` 保留 `godot_rendered=false`、`formal_scene_assembled=false`；端口运行时探针被**既有** `MonsterInjector.gd` 全局类解析错误（`EliteRosterService` 未找到）阻断，只做了静态链路确认。等于「三段字段链正确」已证，「门实际长在 Boss 前厅」未证 |
| C2 | 全量验收套件 | 11-05 两条记录都写明：套件场景被**既有 27 项房间门位指纹漂移**预检阻断，相关用例**未执行**。当前宝箱/钥匙的绿来自 3 只专项探针，不是全套 |

### D. 登记欠账（门禁读数）

| 编号 | 欠账 | 读数 |
|---|---|---|
| D1 | 账本 SHA 漂移 | **16 条**，`check_asset_registry` 报 `sha_mismatch`：场景 2（`ENV-BASE99-REMAINING-FACILITIES-V021`、`ENV-OPENWORLD-UNDERGROUND-STREET`）、道具 3（`GroundLootPickup3D.gd`、武器工作台/阁楼工位 tscn）、特效 7（视野场 `PlayerVision3D.gd` + 6 件 combat_3d tscn）、UI 4（`Dungeon3D.tscn`、`VaultMenu.gd`、暂停层、命运来源面板）。**未批量重算** —— 按 AGENTS.md 得先逐条溯源 |
| D2 | 验收未登记 | ~~4 个~~ **已解决（2026-11-06）**：`verify_base_lamp_dynamics` / `verify_base_lamp_visual` / `verify_stairwell_turn_rail` / `verify_enemy_action_recovery` 全部登记（core×3 + visual×1），`VERIFICATION_REGISTRY_OK scenes=277`。过程中修掉两处收招缺陷、修正护栏判据坐标系，详见 [登记记录](../development/2026-11-06_verification_registry_backfill.md) |
| D3 | 文档破链 | 15 条（既有）：`07.3` 与 `CHANGELOG` 指的 `../../data/ShellStorm2_游戏内容数据库_v010.xlsx` 路径不存在（真身在 `docs/v0.1/data/`）、`支线秘密房间设计.md` 三处指向不存在的 development 记录等 |
| D4 | 内容数据库 | `docs/v0.1/data/ShellStorm2_游戏内容数据库_v010.xlsx` 最后更新 11-03，**未随 11-05 的钥匙/宝箱口径更新**。表是全局口径（钥匙小子那行本来就只写「铸币 1~2 枚」），所以不算错，但关卡级例外只活在 `level_plan.json` 与设计正文里 |
| D5 | 工作区卫生 | `check_workspace_hygiene` 报 3 项：`outputs/`、`_scratch/`、`Godot/` 在工程内（均已 gitignore，属口径问题非泄漏） |
| D6 | 资产命名欠账 | `ASSET_RUNTIME_NAMING_OK`，但存量欠账：文件 289 / 目录 13；带版本引用 `gd=23`、`tscn=93` |

---

## 4. 门禁现状（本次复跑）

| 门禁 | 结果 |
|---|---|
| `verify_ledger_split.py` | **PASS** `assets=1437 ledgers=9`（补齐后） |
| `check_ledger_refs.py` | **PASS** `pending=0 allowed=2 dangling=0` |
| `check_feature_traceability.py` | **PASS** `features=45`，`issues=[]` |
| `check_level_decoupling.py` | **PASS** `violations=0`（7 个通用容器无 `expedition_0N` 字面量） |
| `check_expedition03_flow_quotas.py` | **PASS** `issues=[]` |
| `check_asset_runtime_naming.py` | PASS（只拦新增；欠账见 D6） |
| `check_asset_registry.py` | **FAIL 16**（全为 SHA 漂移，见 D1） |
| `check_documentation_contracts.py` | **FAIL**：15 破链 + 验收注册缺 4 + `check_media_asset_domains` 因缺 `openpyxl` 未跑 |
| `check_workspace_hygiene.py` | **FAIL 3**（见 D5） |

> 注：本机 bash 的 `python` 没有 `openpyxl`，带账本的检查需用 `C:\Users\zhuangmenghong\AppData\Local\Python\pythoncore-3.14-64\python.exe`。

---

## 5. 建议处理顺序

1. ~~**D2（4 个验收登记）**~~ **已完成** —— 见 [2026-11-06 登记记录](../development/2026-11-06_verification_registry_backfill.md)。
   过程中发现两个新的代码缺陷（已修）与两个待裁决问题：
   - 已修：收招段外部推力逐帧叠加（击退 5.0 → 9.7 → 14+）；死亡/硬直后仍打排期连发。
   - **待裁决 ①**：近战结算不看视线（只有胖子僵尸查 LOS，其余只判距离），贴墙会被打到。
   - **待裁决 ②（P1）**：体型缩放放大 `move_and_slide` 位移 —— `scale=0.7` 时 7.2 m/s 走 0.120 m/帧，
     `scale=1.05` 实走 1.080 m/帧（约 7 倍）。影响 `_strong` 变体、精英（2.5×）与 Boss，
     会让「speed 数值」与实际移动速度脱钩。
2. **B1（HUD 钥匙读数）** —— 需要业主一句口径：钥匙读数到底还在不在；定了才能改 718 行。
   （实测：HUD 常驻区**不显示**钥匙，只有开门时状态栏写「剩余钥匙 N」；所以 718 行是错的。）
3. **D1（16 条 SHA 漂移）** —— 逐条 `git log -1 -- <path>` 溯源到提交，再决定「重算」还是「回退资产」；**别用一次性全量刷新掩盖差异**。
4. **C1 / C2** —— Boss 门补一次真实渲染取证；套件那 27 项门位指纹漂移要么修、要么显式降级，否则「全绿」始终是局部绿。
5. **A3（完成度清单）** —— 补远征03 章节，或明确它的覆盖边界。
