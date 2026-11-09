# 2026-11-09 21:12 开场弹药三项（取消备弹 / 手枪无限 / 远征01 保底枪）

- **业主三条**：①去掉初始那几百发普通弹药 ②豌豆手枪子弹无限（形态=弹匣无限、保留换弹）③远征01 第一个或第二个房间的宝箱，随机一间必掉最低品质霰弹枪/步枪 + 100 发弹药。
- **落地**：`Dungeon3D.GUARANTEED_LOADOUT_AMMO_ROUNDS` 删除、两个查询接口恒返回 0；枪身 `infinite_ammo=true` 走 `WeaponModel3D`（开火不扣弹/换弹不吃备弹/HUD `∞`）；`clear_drops.room_guarantees` 能力段 + `ClearDropService.guaranteed_items_for_room()` + `ChestRewardService._resolve_guaranteed_items()`。
- **验收**：新增 `verify_expedition01_room_guarantee`（core）；改写 `verify_guaranteed_loadout_ammo_flow` 为反向门禁；`verify_finite_ammo_flow` 样本枪换步枪。8 项用例 exit 0。
- **两个坑（记下来别再踩）**：
  1. `data/level_plans/**` 是 **`art_source/` 的字节投影**。直接改 `data/` 会被 `sync_runtime_design_data.py` 覆盖回源，配置静默消失。正确顺序：改 `art_source` → sync → `--check` 归零。
  2. `ChestRewardService` 里接保底 grants 不能用 `as Array[Dictionary]` 强转未类型化数组 —— 无保底条目时会失败，把整只普通箱判成「解析失败」。
- 记录：`docs/v0.1/development/2026-11-09_opening_ammo_infinite_pistol_room_guarantee.md`
