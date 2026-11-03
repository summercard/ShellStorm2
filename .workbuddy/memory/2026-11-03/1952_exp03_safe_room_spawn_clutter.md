# 19:52 远征03 安全屋：出生点归中 + 中央五件易碎件撤除

## 业主诉求（原文）

「远征03，安全屋，玩家进入后要出现在安全屋的正中间。还有中间五个易碎物品，之前说了要拿掉，还在。帮我拿掉。」

两条都是明确裁定，无取舍空间。两件事占同一处空间（五件落点全在房心 ±2.16 m 内），
只改一件会让玩家落地与罐子重叠 ⇒ 同批处理。

## 🔴 关键发现：11-02 记录声称已修，但实现根本没落地

`docs/v0.1/development/2026-11-02_expedition03_prop_scale_and_rug_matte.md` 第 1 条与
`2026-11-02_lobby_lounge_and_fixture_lighting.md` 第 1 条都写着「已通过
`furnishing.fixed_lobby_clutter_enabled=false` 关闭中央五件」，后者还附了实测读数
`central_fixed_clutter: 0`。

**但该键在全仓不存在：**

| 检查 | 结果 |
|---|---|
| `src/` + `data/` 全量 grep | 0 命中 |
| `git log --all -S "fixed_lobby_clutter" -- src/ data/` | 空（从未进任何提交） |
| 各分支 `git grep`（0.1.1 / 0.1.2 / main / origin/0.1.2 / xuniyaogan） | 全无命中 |

⇒ 记录写了、实现没落地，所以业主一直看得见那五件。**这是"文档与实现漂移"的实例：
记录里的实测数字（`central_fixed_clutter: 0`）无法被工作区复现，属于不可信读数。**
已在两份记录顶部加更正指针（不改原文，保留留痕）。

## 改了什么（8 个文件）

| 文件 | 改动 |
|---|---|
| `src/world3d/DungeonRoom3D.gd` | 新增 `fixed_lobby_clutter_enabled`（缺省 true）→ `configure()` 接收 → `get_room_snapshot()` 导出 → `_build_interactive_clutter()` 的 STAIR_LOBBY 固定分支按它提前返回 |
| `src/world3d/TowerDescent3D.gd` | ① 出生点 ID 名单 `["expedition_01"]` → `+ "expedition_03"`；② `_append_plan_room_record()` 从 `furnishing` 段透传新键；③ `_instantiate_dynamic_room()` 的 configure 透传 |
| `src/world3d/Dungeon3D.gd` | `_prepare_layout_rooms()` 的 configure 透传（与 `procedural_furniture_enabled` 同路径） |
| `data/level_plans/expedition_03/level_plan.json` | `furnishing` 段加 `"fixed_lobby_clutter_enabled": false` + 更新 note 自解释 |
| `tests/verification/probe_exp03_safe_room_spawn_and_clutter.{gd,tscn}` | 新探针（未进套件，手动跑） |
| `docs/v0.1/关卡接入规范.md` | §4.1 表 + §4.2 范例 → `01 / 03 = 房心` |
| `docs/v0.1/design/远征关卡03设计.md` | 新增 §7.5.5；原 7.5.5 顺延为 7.5.6 |
| `docs/v0.1/development/*` | 新记录 + README/CHANGELOG 登记 + 两份 11-02 记录加更正 |

设计取向：出生点按关卡 ID 分支（合规，属"关卡专属内容"，收口在单一函数、有默认分支）；
五件走**能力段**（代码里不含 `expedition_03` 字样），满足 `check_level_decoupling` 零容忍。

## 验收（真实远征03 场景，隔离副本内跑）

改前 → 改后：

| 判据 | 改前 | 改后 |
|---|---|---|
| 出生点偏移 | **4.000 m ❌** | 0.000 m ✅ |
| 玩家真实坐标距房心 | **4.000 m ❌** | 0.000 m ✅（含脚下地面命中） |
| 房心 2.2 m 内易碎件 | **5 件 ❌** | 0 件 ✅ |
| 流送卸载重建后 | **又冒 5 件 ❌** | 0 件 ✅ |
| 开关对照（同规格房 true/false） | — | 5 / 0 ✅ |

**牙齿**（防假绿）：
- C 段开关对照：另建同规格 STAIR_LOBBY，true 摆 5 件 / false 摆 0 件。否则若 `interactive_clutter`
  段哪天覆盖安全房，B 段照样全绿而业主诉求已破。
- A 段旧口径对照：在同一真实入口房上算旧口径（4.00 m），断言它**超出**容差。
  门向判断写坏时会红，不会出现"新旧口径都落房心"的假绿。
- C 段还断言固定五件最远落点 ≤ 2.2 m（实测 2.16），把 B 段判定半径钉在实测值上。

**未误伤对照**：随机撒点 713 件 / 18 间房（前后逐数一致）；入口房作者件 24 件（保持）；
远征01 中央五件 5 件（`furnishing: {}`，未声明 ⇒ 缺省 true）；远征02 出生点不变。

**存档不失配**：`expedition_03` 的 `layout_id = f00_b5641fb3a7ead30d`，与 11-02 记录值
**逐字相同**；`valid=true`、`used_fallback=false`、`entry_side=east`/`exit_side=west` 均未变。
机理：`furnishing` 属"顶层透传、不进 canonical"，加键不改几何指纹。

## 门禁

| 项 | 结果 |
|---|---|
| `check_level_decoupling.py` | exit 0，violations=0 |
| `check_asset_runtime_naming.py` | exit 0（既有欠账 289/13，只拦新增） |
| `check_documentation_contracts.py` | exit 0；15 条既有百度断链（乱码路径等），本轮新增未报 |
| `check_verification_registry.py` | 报 4 项既有未注册（10-18 / 11-02 的文件），**我的探针未被点名** |
| `git diff --check` | 干净 |
| 行尾 | 9 个被改/新增文件全纯 CRLF（探针 .gd/.tscn 依 tests/ 惯例用 LF） |

## 环境笔记（可复用）

- **隔离验证工作区**：`python scripts/verification_workspace.py create <base>/shellstorm-verification.<name>`
  会建 junction 链接（不复制文件），随后**必须**改 `project/project.godot` 加
  `config/use_custom_user_dir=true` + `custom_user_dir_name`，并 robocopy 播种 `.godot/imported`。
  直接 `cp -r` 会中途被 SIGTERM 掐断（5740/6548 文件）⇒ 用 robocopy。
- 隔离用户目录落在 `%APPDATA%\<name>`（不在 `app_userdata\` 下）；cleanup 后两处都不残留。
- 本机 bash 里 `cp` 大目录易被 SIGTERM；`robocopy /MT:16` 稳。

## 未执行

完整通关、全量战斗/寻路/结算套件、真实渲染截图、`core`/`aggregate` 完整套件 ——
**不宣称整关状态提升**。探针未登记进 `core_scenes`（与 `probe_clutter_coin_drop` 同口径）。
