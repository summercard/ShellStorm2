# 1153 推送 0.2 五项收口（71 文件）

## 业主口述

> 「推送」

## 做了什么

`e404920a` 推上 `origin/0.2`（`d4cc5a21..e404920a`，71 文件 / +2019 行）。
整批是**五条并行会话**的成果，我只负责收口，没有改任何源码：

| # | 事务 | 关键词 |
|---|---|---|
| ① | 敌弹回退 3D 弹体 | `ENEMY_BULLET_BILLBOARD=false`、`ICON_SCALE=0.70`、`_billboard_override` 三态 |
| ② | 南墙收镜 / 鼠标前瞻 | 只屏蔽朝南前瞻，其余方向保留 |
| ③ | 远征锁居中 | 关卡牌居中红锁、后排放大、主线资产补记 |
| ④ | 主线 3.1—3.3 + 四钥匙 | `nar_main_031/032/033`、`MainStoryChapter3D`、3 个新探针 |
| ⑤ | 玩家血条四件 | 翻滚冷却环、受击震动、空槽底纹、回血补条 |

## 并发处理（关键）

暂存时发现**另一会话正在写「对话空格快进」**（`DialogueUI`、`NarrativeAdapter/NpcCharacter`、
两个气泡脚本、`docs 18`、新测试 `verify_dialogue_space_fast_forward`），文件 mtime 距今 < 15 min、
2 个 Godot 进程在跑测试。问过业主后选「只推已收尾的 5 项」：

- 新测试三件 + `docs/18` 退出暂存，留给对方会话；
- `NarrativeAdapter3D` / `NpcCharacter3D` / `DialogueUI` / `气泡` / `对话与战斗信息呈现设计.md`
  两边改动混在同一文件，按 hunk 切会切坏，**整文件提交**（业主已知情并同意）。
- 提交后对方仍在写 `docs/08`、`NarrativeDirector3D`，说明它没被我打断。

⇒ **教训**：多会话并发时，`git add -A` 之后必须立刻 `git status` 复核新增文件清单 ——
11:49 那次 `git add` 比 11:44 的 `status` 多出 3 个文件，就是对方在这 5 分钟里新建的。

## 账本门禁是红的，但不是这批引入的

`verify_ledger_split` → `failure_count=227`（`missing=0 / extra=2`）。两种失败：

1. R 列公式读出来是 `==LOWER(...)`（双等号）；
2. S 列读出来是 `<openpyxl.worksheet.formula.ArrayFormula object>`。

用 `git show HEAD:...敌人账本...` 比对：**HEAD 版本就是双等号 + 数组公式**，
且 `敌人账本` 根本不在本次改动清单里 ⇒ 存量问题，xlsx 被外部编辑器（WPS/Excel）重存所致，
不是 `Projection3D` 那批代码的事。**该改的是账本写入端/重存流程，不是放宽门禁。**

`extra_assets` = `PRP-3D-REWARD-CHEST-ADVANCED` / `-NORMAL`：账本里有、基线里没有
（baseline 1443 / union 1445）⇒ 基线漏刷两行，`--baseline-only` 可补，但那 227 条不解决仍红，
所以这次没动。

## 门禁读数

| 门禁 | 结果 |
|---|---|
| `check_level_decoupling` | violations **0** |
| `check_verification_registry` | **OK scenes=300**（core 243 / visual 42 / smoke 6 / manual 9） |
| `check_asset_runtime_naming` | **OK**，欠账 289/13 未增 |
| `verify_ledger_split` | **红 227**（HEAD 存量，见上） |

## 未提交（留在工作区）

`docs/08`、`docs/18`、`NarrativeDirector3D.gd`、`verify_dialogue_space_fast_forward.{gd,uid,tscn}`
—— 对话快进会话自己的活。

另有两个我自己留下的垃圾没清：`_probe_loop.txt`（0 字节，11-08）、
`override.cfg.disabled_20261109`（11-09 改名留存），都不在 `.gitignore`，也都没跟踪。
下次谁要清就删，不影响构建。
