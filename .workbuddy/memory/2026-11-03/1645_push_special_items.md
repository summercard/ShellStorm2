# 16:4x 推送 d54e1462（7 提交 / 207 项，工作区清空）

判据：`HEAD == origin/0.1.2 == d54e1462b9`，`git status -uall` 无输出。
LFS 上传 6 个对象 655 KB（`special_items_recordings/source/*.wav`）。

## 提交拆分

| 提交 | 内容 |
|---|---|
| `9daba80b` | 公馆陈设受击状态机（ReactiveProp3D / ReactiveLamp3D / LampFirePatch3D / FurnishingSupport3D）+ 书柜落地烟尘 + 13 个 manor_* Prefab 接 script |
| `17c5ce64` | 特殊道具系统：手雷/燃烧瓶/汽油瓶、装备槽、HUD、14 资产 ID、独立账本 |
| `95439f6b` | 远征03 台灯/插花拆分（94 处）、桌面盆栽 ×0.5、双人床 ×1.5，11 份房间重烘焙 |
| `40167e14` | 子弹实际弹道点燃油迹 + HUD 收成图标计数 + combat_enabled 门 |
| `3bd0fe38` | 六本账本同步 + SPECIAL-ITEMS 登记 + 4 篇 11-02 文档追加「未落地」 |
| `29443d3f` | 燃烧瓶火场与台灯落地火共用 `create_ground_flames`（`_finish` 递归收 Array） |
| `d54e1462` | r3 燃烧瓶半径 2.4→1.25 落到账本正文 |

## ⚠ 本轮全程与另一条会话并发（重要经验）

提交途中工作区被另一个会话持续改写，**至少三轮**：我先提交完一批，
回头 `git status` 又出现新的 special_items 改动。处理方式：每轮重新 `git status` →
重新归类 → 单独成提交，**绝不 `git add -A` 一把梭**（否则会把别人半成品混进我的主题）。

**但出现了一个事实漂移**：`17c5ce64` 的 message 写「燃烧瓶半径 2.4 m」，
两小时后被 r3 改成 **1.25 m**。提交信息是历史快照，不等于终态 ——
下次引用数值必须回读 `data/special_items/catalog.json`，不能读 commit message。

## 门禁读数（实跑，不美化）

| 门禁 | 退出码 | 读数 |
|---|---|---|
| `verify_ledger_split` | 0 | assets=1433 ledgers=9 failure_count=0 |
| `audio_full` | 0 | assets=184 ledgers=1 |
| `runtime_naming` | 0 | 欠账 289 文件 / 13 目录 |
| `check_level_decoupling` | 0 | violations 0 |
| `check_documentation_contracts` | 1 | 4 条 unregistered（3 既有 + 孤儿 verify_enemy_action_recovery） |
| 资产 ui_full | 1 | issues=5（哈希漂移，单列待核对） |
| 资产 vfx_full | 1 | issues=7（同上） |
| `art_source_layout` | 1 | 6 个 `.blend1` 被 .gitignore 挡在 Git 外 —— **既有状态，非本次引入** |

## 资产数 1418 → 1433（+15）全部可归因

props +3（三件道具模型）、vfx +4（3 特殊道具特效 + 书柜烟尘）、
ui +2（装备槽/HUD）、audio +6（录音音效）。其余五本行数不变。

⚠ `ledger_split_baseline.json` 的 `baseline_captured_at` 仍是 11-02T17:51:12，
行内容已扩到 1433 但时间戳没刷新 —— 不影响校验，但会误导下一个人「基线没动过」。
**待清理项**。

## 房间挂载门禁又救了一次

`check_room_script_mounts.py`（`.workbuddy/tmp/`）：11 份改动房间
script 挂载计数全部持平。节点数下降是重叠陈设删除（94 处台灯/插花），
**不是** 11-02 那种挂载丢失。判据必须同时看 `nodes` 与 `script` 两个数。
