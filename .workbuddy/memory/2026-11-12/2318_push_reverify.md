# 2318 推送：复验收口（出怪深拷贝边界 / 宝箱提示复用 / 防抖存档并写者）

## 业主口述

> 「推送」

## 事实链

- **第三次**接手时 `HEAD == origin/0.2`、零待推送提交。工作区 10 项改动未提交，
  提交成 `388e1d1e`：`7ef18a6c..388e1d1e`，**10 文件 / +187 −62**。
- 最后写入 23:00:18，接手 23:14 —— 14 分钟无变动；存的唯一 Godot 是编辑器
  （PID 307384，18:54 起，`CommandLine` 只有 exe 路径、无 `--headless`/场景参数）⇒ 无验收在跑。

## 本批三块

| # | 块 | 关键点 |
|---|---|---|
| ① | 出怪数据深拷贝边界 | `_enemy_runtime_spawn_data()`：保留「敌人拥有独立深拷贝」边界，但先 erase 派发后即丢的 10 个逐盒候选字段再 `duplicate(true)`；wave/pending 源字典不动 |
| ② | 宝箱提示复用预热槽 | 提示文字提为 `CLOSED_PROMPT_TEXT`；预热档槽若已带 `ChestPrompt` 则 reparent 复用，否则新建；颜色按 `body_tint` 推导 |
| ③ | 防抖自动存档并入同一写者 | 0.45 s 防抖到期后主线程只冻快照，交与过房共用的后台单写者；暂停/交易/精英预约仍同步确认。文档 §09 措辞同步扩写 |

## 三关复验（种子 41021，独立进程）

| 关卡 | 读条 s | 实绘 | 开门 | 初入房 | 回访 | 受控出怪 | 首发命中 | 首箱 | >50ms |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| 01 | 115.4 | 13/13 | 97.7 | 109.9 | — | 11.6 | 17.6 | 39.4 | 6 |
| 02 | 24.7 | 26/26 | 20.9 | 18.6 | 12.4 | 6.6 | 13.7 | 55.0 | 1 |
| 03 | 26.6 | 26/26 | 56.8 | 281.6 | 184.8 | 109.4 | 30.9 | 29.9 | 31 |

03 n05：**1218.7 → 287.8 / 281.6 ms**。03 显存 868 → 1029 MiB。
03 存档 7 轮读写 6 次连续覆盖：旧 220–339 ms，新 97–108 ms，均由旧版读取器验证通过。

## 已知红项（本批未引入，记录内写明，未放宽阈值）

03 特殊房 24 种子专项退出 1：种子 77003244 与 9 的首领门打开后，**中心通行射线命中
前厅 `Theme_009_Wall_wardrobe/LayoutCollision`**，门侧两条射线通过。
⇒ 房型层实体占位问题，应在房型修，不能在探针放宽。

## 门禁

| 门禁 | 结果 |
|---|---|
| `check_verification_registry` | **OK scenes=306** |
| `check_level_decoupling` | violations **0** |
| `check_asset_runtime_naming` | **OK** 289/13 未增 |
| `sync_runtime_design_data --check` | 52 文件 **0 问题** |
| `check_documentation_contracts` | 11 条断链，全部既有 |
| `verify_ledger_split` | 红 **109** |
| `verify_chest_appear_fx_prompt` | **实跑 exit 0**，`CHEST_APPEAR_FX_PROMPT_OK`（本批改了提示逻辑，故单独重跑） |

## 新记一条检查器限制

**`godot --check-only --script` 不能当语法门禁。** 它解析不到 autoload 单例——
连未改动的 `src/ui/BaseRecoveryMenu.gd` 都报「Identifier not found: BaseManager」，
`TreasureChest3D` 报「VfxPool」。两个文件其实都正常，只是检查器不加载 autoload。
判据：拿一个**未改动**的、同样引用 autoload 的脚本跑一遍，若也报同款错，就是检查器问题。
要真验改动只能跑真实场景。

## 遗留（已挂三轮）

1. `assets/ui/fonts/dseg/` 两个 ttf 仍缺 `.import`；`EncounterCountdownRing` 的 assert
   会在导入完成前失败 ⇒ 计时环换字体至今未被验证。
2. 三个垃圾文件 `_probe_loop.txt` / `override.cfg.disabled_20261109` /
   `verify_main_story_boss_gate.report.json` —— 第六轮手动排除。
