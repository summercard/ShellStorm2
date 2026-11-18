# 1415 塔楼引导卡撤除（UI-HUD）

- 业主指令（2026-11-18 截图）：「把这些内容去掉，没有用，只保留金币的数量 然后挪到电池下面」。
- 改了什么：
  - `TowerDescent3D._install_tower_hud()` 不再建 `TowerCurrentInfoHUD`（四行引导卡），
    只建 `Label "TowerBaseCurrencyHUD"` 并 `add_child` 到 `_hud_stat_column`。
  - `Dungeon3D` 把 `PlayerStatusBlock` 内的状态列命名 `PlayerStatColumn` 并暴露为
    `_hud_stat_column`（子类追加读数的唯一挂点）。锚框/居中/间距一分未改。
  - `_refresh_tower_hud()` 收敛为一句金币；`_announce_floor_arrival()` 的 HUD 哨兵
    换成 `_tower_base_currency_label`；删 `_expedition_objective()`。
  - `_journey_objective()` **保留**（`verify_tower_journey_polish` /
    `verify_opening_script_runtime` 直接调用），但不再渲染。
- 验证：headless 探针 `GUIDE_REMOVED=true / CURRENCY_FOUND=true /
  CURRENCY_PARENT=PlayerStatColumn / CURRENCY_Y=99.2 > BATTERY_END_Y=94.6 /
  HAS_PROGRESSBAR=false`，exit 0；解耦与资产命名门禁 exit 0；文档门禁 617 文档 /
  15 issue（既有集合，新增 0）。
- 没做：`verify_reference_hud_fate_visual` 完整跑（含真渲染出图）、手动目视、Android。
- 副作用：状态列居中 ⇒ 血条与电芯整体下移约 10 canvas px，headless 证明不了观感。
- 记录：`docs/v0.1/development/2026-11-18_tower_guide_card_removal.md`。
- ⚠️ 同文件并发：本轮编辑期间 `TowerDescent3D.gd` 里还有其它会话未提交的安全信标 /
  `KEY_RETURN_CALL_ID` 改动，提交时要分开，别把它们算进本事务。
