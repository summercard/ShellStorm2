# HUD 备弹读数拾取后不更新（修复）

时间：2026-11-13 11:14 起
范围：`src/world3d/Dungeon3D.gd`、`tests/verification/verify_finite_ammo_flow.gd`、`docs/v0.1/`（新记录 + CHANGELOG + MODULE_INDEX）
正式记录：`docs/v0.1/development/2026-11-13_hud_reserve_ammo_refresh.md`

## 硬结论

- **备弹是独立物品 `item_ammo_pack`，拾取不发 `player.ammo_changed`**（弹匣当前数没变）。
  因此任何「依赖 `ammo_changed` 刷新弹药显示」的写法，都会漏掉拾取/丢弃/快捷栏搬移。
- `Dungeon3D._apply_weapon_hud_command()` 的 `N备弹` 是**写文本时现算** `_get_reserve_ammo_count()`，
  所以显示陈旧 = 没被通知，而不是数值算错。排查这类「显示不更新」先看**谁调 `present_weapon`**。
- `HUDPresenter3D.present_weapon()` 无去重、每次调用必 emit —— Presenter 不需要改，
  缺的永远是调用方通知（这是本项目 HUD 的通病，后续同类报障优先查这里）。
- 修法：`_setup_run_modules()` 把 `_inventory` 与 `_quick_inventory` 的 `inventory_changed`
  接到 `_on_reserve_ammo_pool_changed()` → `_refresh_hud_weapon_model(force=false)`。
  **不要放进 `_activate_runtime_persistence()`** —— 那里 `test_mode` 整段跳过，而 HUD 是表现层。
  `force=false` 有讲究：避免每拾取一次就重建 3D 枪械图标。

## 环境坑（复现）

- `scripts/run_verification_suite.sh` 在本机**必然**卡在 preflight：
  `check_expedition03_room_layouts.py` 打印 `↔` 触发 `UnicodeEncodeError: 'gbk'`，
  `PYTHONIOENCODING=utf-8` / `PYTHONUTF8=1` 均无效（已试）。
  **可行姿势**：跳过 runner，直接
  `APPDATA=<工程内scratch>/appdata LOCALAPPDATA=... godot --headless --path . --scene res://tests/verification/<场景>.tscn`，
  约 15~25 s 出结果；`test_mode=true` 由场景自带，用户目录已隔离。
- Bash 工具的 `/tmp` 不跨调用持久（写入后下一条命令读不到）。日志一律写进工程内路径。

## 验收

- 正向：exit 0 / `FINITE_AMMO_FLOW_OK` / 0 SCRIPT ERROR。
- 反向对照：处理函数临时改 `pass` → exit 1，报 `did not refresh the weapon HUD: 30 · 0备弹`，与报障同形（证明门禁会红）。
- `check_documentation_contracts.py`：11 条断链，全为既有基线，新增 0。
- `check_level_decoupling.py` / `check_verification_registry.py`（306 场景）/ `check_domain_boundaries.py` 全 exit 0。

## 未做

真实跑图人工确认、真渲染截图。未提交、未推送。
