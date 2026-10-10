# 2026-10-10 命运来源选择面板改为图标卡片

- FeatureID：`FATE-RULES`（面板表现归属 `UI-HUD`）
- 工程版本：`0.1.0`
- 来源/状态：主人反馈「游戏过程中选择命运卡片的时候跳出这个是什么意思？我的卡片无效吗？」。判定为**表现缺陷**而非功能缺陷 —— 面板本身是正常流程（来源快照必须由玩家指认），但旧版只有一列纯文字按钮：单枪玩家的两个名字恰好相同（`GunBody_Sprinkler / GunBody_Sprinkler · #000493`），面板内又只有标题重复一遍，玩家读不出「为什么要选、取消会不会吞卡」。本轮把面板改为图标卡片。FATE 总体仍为 `partial`：真实窗口输入与整局视觉 QA 未签署。
- Owner：`FateCardGameBridge` 负责候选与展示数据（`get_source_candidates`）；`FateSourceSelectionPanel` 只做渲染；图标与模型复用 `ItemModelIcon3D` / `ItemModelFactory3D`，**不新建模型资产**。

## 改动

### 面板 `src/ui/FateSourceSelectionPanel.gd`

- `open_choices(heading, entries, hint := "")` 新增可选 `hint`：正文说明与窗口标题分离；不传 `hint` 时保持旧观感（「待领命运奖励」路径）。
- 条目带 `icon_item` 时渲染图标卡片：左 96×96 投影图标 + 右三行（名称／来源位置与实例号／命运槽占用或警示）；不带 `icon_item` 时回退纯文字行 —— 两条调用路径共用一个弹窗资产。
- 卡片最小高 108、弹窗 `560×360` → `620×470`；卡片描边在 `apply_tactical_tree` **之后**按稀有度重设（早于它会被通用青色样式覆盖）。
- 取消／Esc／关窗三路语义不变：`success = false`，卡片不消耗、不转移；焦点默认落在「取消 · 保留卡片」。

### 桥接 `src/game/FateCardGameBridge.gd`

- `get_source_candidates()` 为每个来源根记录它所属的 `WeaponInstance.to_item_dictionary()` 与来源位置（当前装备／副武器槽 N）。
- 新增 `_build_source_entry()`：保留旧字段 `source / supported / label`，新增 `icon_item / title / subtitle / badge / accent`。
- 新增 `_source_icon_item()`、`_content_item_for()`、`_content_display_name()`、`_gun_id_for_node()`、`_fate_slot_badge()`、`_rarity_accent()`、`_equipped_weapon_item()`、`_source_selection_hint()`。
- 显示名优先取 `ItemRegistry` 中文名（如「花洒机枪」），不再把 `GunBody_*` 内部节点名当玩家文案。
- 机型映射走内容注册表链（`BlueprintRegistry` → `ItemRegistry`），未在 UI 侧另抄映射表。

### 一个必须记住的启动期陷阱

首版在 `FateCardGameBridge`（启动期 autoload）里静态引用了 `WeaponModel3D.GUN_NAME_TO_ID`，面板又在 `const` 里 `preload` 图标场景并强类型 `as ItemModelIcon3D`。这让**编译期**把整条链（`ItemModelIcon3D` → `ItemModelFactory3D` → `WeaponModel3D` → autoload `BlueprintRegistry`）提前拉到注册表就绪之前，整条链加载失败，连带 `Dungeon3D` 的 HUD 武器图标一起变空。

启动日志证据（同一命令、同一隔离 `APPDATA`，改动后 / 回退后对照）：

| 状态 | 观测 |
|---|---|
| 含首版改动 | `ERROR: Failed to instantiate scene state of "", node count is 0.` + `SCRIPT ERROR: Invalid assignment of property or key 'name' ... on a base object of type 'Nil'.`（`Dungeon3D.gd:1509/1510`） |
| 回退两个文件 | 两条错误**均消失**，只剩 `[MapFateTriggers]` 与既有的 `ObjectDB instances leaked` 警告 |

⇒ 判定为首版改动引入，非既有问题。

修法：图标场景改运行时 `load()`（首次需要时解析并缓存），面板不再写 `as ItemModelIcon3D` 强类型、改鸭子类型调 `configure()`；桥接侧机型映射改走 `WeaponInstance.assembly_id_for_root()`。

## 验证

全部 Godot 进程在 Autoload 启动前把 `APPDATA` 指到独享的纯 ASCII 目录（`I:/_ss_tmp/appdata_*`），未触碰正式用户档。

| 项 | 命令 | 结果 |
|---|---|---|
| 脚本链可编译 + autoload 可初始化 | `godot --headless --path . --quit-after 5` | **EXIT=0**；日志与回退对照逐行一致，无 `SCRIPT ERROR`、无 `instantiate` 失败 |
| 资产账本结构 | `check_asset_registry.py --scope structure` | **EXIT=0** `ASSET_REGISTRY_CHECK_OK scope=structure assets=1062 ledgers=9` |
| 无损基线 | `verify_ledger_split.py` | **EXIT=0** `LEDGER_SPLIT_VERIFY_OK assets=1062 ledgers=9`；`failure_count=0`、`column_digest_drift=[]`、`extra_assets=[]` |
| UI 域 full | `check_asset_registry.py --scope full --ledger ui` | EXIT=1，**5 条 `sha_mismatch`（r6／r18／r19／r20／r21）** —— 均为**既有红项**：这 5 个文件（`Dungeon3D.tscn`、`InventoryUI.gd`、`ui_pause_overlay_screen.tscn`、`ui_item_model_icon_root.tscn`、`BaseVendingMenu.tscn`）`git status` 全为空，本次未修改；**新增行 r23 无任何失败项**（路径存在、SHA 与磁盘一致、派生化公式与唯一性判定全部通过） |
| 运行资产命名 | `check_asset_runtime_naming.py` | EXIT=1，6 处**既有**版本化资产债务（`Player3D`／`Player3DStateGallery`／`TrainingRack3D`／`WardrobeMenu3D`／`Dungeon3D`／`ItemModelFactory3D`）；名单内文件 `git status` 全为空，本次未修改任何资产 |
| 媒体域计数 | `check_media_asset_domains.py` | EXIT=1，`ui row count: expected 16, got 18` —— **既有红项**：改动前已为 `expected 16, got 17`（2026-10-08 增 `UI-ATLAS-FATE-CARD` 时未同步该常量），本次新增一行使其增至 18；**未改门禁常量**，见「当前遗留」 |
| 文档契约 | `check_documentation_contracts.py` | EXIT=1，全部为既有项（CHANGELOG 断链 1 条、未注册用例 6 项、媒体域计数 1 条）；本次新增/修改的文档未引入新断链 |

**未执行**：真实窗口输入、鼠标与手柄点击路径、整局视觉 QA。headless 启动只能证明脚本链可编译、autoload 可初始化，不替代上述验收。

### 图标卡片运行期探针

headless 下 `SubViewport` 不产出像素，但 `ItemModelIcon3D` 的取景量是**几何计算**，可无头读回。临时探针 `_scratch/probe_fate_source_panel.{gd,tscn}` 直接实例化面板、喂两种条目并读 `get_snapshot()`：

```text
PROBE_OK   ItemRegistry 可用
PROBE_OK   图标卡片生成了 SourceModelIcon3D 节点
PROBE_SNAPSHOT {"model_kind":"weapon","mesh_count":1,"fit_ratio":0.880,"fit_fill_ratio":0.88,
                "center_error_pixels":"(-0.000009, -0.000013)","viewport_size":"(96, 96)",
                "camera_size":1.5755,"item_id":"weapon_sprinkler",
                "model_bounds_size":"(0.987662, 1.550834, 1.952163)", ...}
PROBE_OK   model_kind == weapon | weapon
PROBE_OK   模型有网格 | mesh_count=1
PROBE_OK   取景不出框（fit_ratio<=1） | fit_ratio=0.880
PROBE_OK   居中偏差 < 8px | offset=(-0.000009, -0.000013)
PROBE_OK   卡片有 ChoiceTitle 文本
PROBE_OK   带图标时不出现纯文字行
PROBE_OK   无 icon_item 时回退 TextChoice
PROBE_OK   回退路径不生成图标占位
PROBE_FATE_SOURCE_PANEL_OK failed=0
```

⇒ `icon_item` 确实驱动出正确机型（`weapon`）与真实网格（包围盒 ≈ 0.99×1.55×1.95，与洒水机造型相符），取景自适应到 `FIT_FILL_RATIO` 上限且居中偏差 < 0.001px；无 `icon_item` 时回退纯文字行且不生成图标占位。

**未覆盖**：SubViewport 的实际出像素（headless 无渲染器）。该项依赖既有组件能力 —— 背包／商人／HUD 共用同一 `ItemModelIcon3D`，本轮未新增渲染层断言。

## 当前遗留与边界

- **真实窗口输入与整局视觉 QA 未签署**：headless 启动只能证明脚本链可编译、autoload 可初始化，不能证明 620×470 弹窗内图标取景正确、鼠标点击与手柄焦点符合预期。
- **「面板不得在编译期拉入图标链」这条契约目前只有注释盯着，尚未固化为门禁用例**。上面那个探针留在 `_scratch/` 是临时的：它没有注册进 `run_verification_suite.sh`，所以不会在后续提交里自动跑。要长期钉住这条契约，应把它升为 `tests/verification/verify_fate_source_panel_icon.gd` 并注册进套件 —— 本轮未做，因为改动套件组成后需要跑通整套并处理既有未注册用例债务，超出本次范围。
- 图标为 96×96 投影，与背包格同口径；来源为**配件**（权杖·三）时 `ItemModelFactory3D` 只按 tint 生成通用配件外形，不区分配件种类 —— 属既有能力边界，本轮未扩展。
- `check_media_asset_domains.py` 的 `EXPECTED["ui"]["count"] = 16` 是**既有红项**（改动前账本已 17 行，2026-10-08 新增 `UI-ATLAS-FATE-CARD` 时未同步），本轮新增一行后为 18。未改门禁常量（不为全绿放宽旧阈值），建议单独处理该计数漂移。
