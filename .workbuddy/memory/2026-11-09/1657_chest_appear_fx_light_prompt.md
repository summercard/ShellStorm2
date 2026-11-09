# 宝箱出现特效 · 自带地面光 · 提示牌让位（2026-11-09 16:57）

FeatureID：`WORLD-LOOT`。开发记录 `docs/v0.1/development/2026-11-09_chest_appear_fx_light_prompt.md`。

## 业主三条

1. 救援箱的消失特效改个颜色、放关卡宝箱出现时、适当放大 —— 「宝箱出来的时候不会很突兀」
2. 宝箱头顶的「E 开启宝箱」和靠近后的白字重复
3. 宝箱上方加灯、绑模型 —— 「不然宝箱在里头根本看不见」

## 做了什么

| 项 | 实现 |
|---|---|
| 出现特效 | `TreasureChest3D.play_appear_effect()`：**FX01-35 IN**（不是 OUT）+ 暖金 `(1.00,0.78,0.32)` + 尺寸 `2.0`（=1.6×1.25）+ 贴地 0.05 |
| 触发 | `Dungeon3D._on_room_entered()` → `DungeonRoom3D.play_chest_appear_effects()`；清房掉落 `spawn_runtime_chest()` 当场播 |
| 提示牌 | `set_interaction_focus(candidate, focused)` → 聚焦收起 / 失焦淡回；`_opened` 后永不再亮 |
| 灯 | `OmniLight3D` 挂 `_visual_root`，暖白、energy 1.1、range 3.0、**shadow off**；平涂箱灯色 = `body_tint.lightened(0.5)` |

## 三个被判掉的做法（别再走一遍）

- **用 OUT 播出现**：环向内收拢，读作"被吸走"。OUT/IN 是同一脚本的配对，只复用几何不复用曲线。
- **在 `_build_treasure_chests()` 里播**：房间 detail 会在加载页预热开局房/邻房（`_prebuild_entry_room_details`），玩家还在读条就播完了，而且旗标一置再补不上。
- **删掉头顶提示牌**：没靠近时圆点没聚焦、功能词不显示，远处还得靠它。让位比删除正确。
- **按距离阈值判断让位**：聚焦与圆点功能词本来同一个条件（`provider == _focused_provider`），另算一条距离必然漂开，会出现"牌没了白字也没出来"。

## 验收

`tests/verification/verify_chest_appear_fx_prompt.tscn`（core）exit 0。
**8 组反向对照**：OUT 冒充 IN / 聚焦不让位 / 房间不过滤已开 / 断开进房接线 / 箱子去掉 `_opened` 守卫 / 灯开阴影 / 灯不绑模型 / 浅灰箱打暖黄 —— 除"房间不过滤已开"（由箱子守卫兜住，故另加了箱子侧用例）外全部精准变红。

## 账本

《3D-特效》FX01-35 只改 `J/V/Y` 三格，`v001`、行数、总览区间、DataValidation 全不动；域变更日志 `v0.1.39`。
脚本 `tools/asset_pipeline/update_chest_appear_fx_ledger.py`（幂等）。

**基线只更新该行指纹，不重算 `column_digests`/`category_counts`** —— 工作区有并行会话未提交的账本改动，重算等于用当前文件掩盖差异。

## 环境坑（这次踩到的）

- `openpyxl` **read_only 模式**下逐格 `ws.cell(r,c)` 是 O(n²)：1017 行的场景账本要吃几分钟，脚本被强杀两次。改普通模式后 9 本 0.3 s。
- `--check-only --script` 不加载 autoload，任何用 `VfxPool`/`BaseManager` 的脚本都会报 `Identifier not found` —— 是工具限制，不是语法错。
- headless 直跑测试若不关 `GameTimeManager.set_process(false)`，会满屏 `Refusing stale save` 并写正式存档。
- `DungeonRoom3D.new()` 在 headless 里可用（`_ready` 只建 spawn point 与 stream state），可拿来做房间级单测。
- **新增 `verify_*.tscn` 要登记两处**：`docs/v0.1/feature_registry.json` 的
  `<FEATURE>.verification`（`{kind:"scene", id:"…"}`）+ `scripts/run_verification_suite.sh`
  的 `core_scenes` 数组。只补 JSON 时 `check_documentation_contracts` 仍红（它把
  `check_verification_registry.py` 的输出原样收进 issues，报 `unregistered: verify_xxx`）。
  两处补齐后 `VERIFICATION_REGISTRY_OK scenes=290` / `FEATURE_TRACEABILITY_OK features=46`。
- `check_documentation_contracts` 内部 `subprocess` 调 PATH 上的 `python3`，
  即使父进程用带 openpyxl 的隔离 venv，`check_media_asset_domains` 仍会 `ModuleNotFoundError`。
  跑这个门禁用 `~/.workbuddy/binaries/python/envs/default/Scripts/python.exe`，并把它的 Scripts 目录
  放进 PATH 让 `python3` 也命中，否则永远有一条假红。
- 门禁脚本在 `scripts/` 下，不在 `tools/asset_pipeline/`（我按旧印象写路径白跑两次 `Errno 2`）。

## 既有红项（非本批，别再查一遍）

- `enemies` 账本 R 列 `==LOWER(...)`（多一个 `=`）、S 列数组公式：40 条 → 某次编辑器保存留下的损坏。
- `vfx` 账本总览 8 格 `==COUNTA(...$61)`：既多 `=` 又少扩一行（应 `$62`）。
- `PRP-3D-REWARD-CHEST-ADVANCED/NORMAL` 未进 `ledger_split_baseline`（`extra_assets`）。
- 建议单独开一次事务修上述三处，别混进功能改动。

## 未做

无真渲染出图。暗房里 energy 1.1 够不够、三只箱子同房会不会堆白斑，必须真窗口看一眼才敢说完成。
