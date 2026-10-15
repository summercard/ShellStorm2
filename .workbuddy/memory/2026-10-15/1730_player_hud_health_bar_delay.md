# 1720 玩家主界面血条延迟白段（同源 Boss / 小怪口径）

- 业主口径：「这个血条表现效果，角色的血条主界面的也要找个表现」——「这个」= 10-14 的延迟扣血白段。
- **改动**（`src/world3d/Dungeon3D.gd`）：`ReferenceCombatHUD/PlayerStatusBlock` 的生命条改两层叠放——下层白延迟条 `PlayerHealthBarDelayed`、上层红真实条 `HPBar`（背景 alpha 0 露白段），父节点 `PlayerHealthBarStack`（原条 `220×22`）⇒ 块内布局零位移。新增 `get_player_vitals_bar_snapshot()` 与 `_tick_player_health_bar_delay(delta)`（可传 delta 供验收定点步进）。
- **语义对齐**：`L ← move_toward(L, H, Δt × 1.8)`，只有受伤留白（治疗/初始化/复活/读档当帧对齐）；白段只活在 `_player_delayed_ratio`，**不写入 `player.current_hp`、不进存档**。
- **常量改名**：`BOSS_HEALTH_BAR_DELAY_SPEED/_COLOR` → `HUD_HEALTH_BAR_DELAY_SPEED/_COLOR`（真源仍是 `Enemy3D.HEALTH_BAR_DELAY_*`；现喂 Boss 屏条＋玩家条两条，旧名只剩 Boss 反成误导）。旧名仅存于历史记录，按「历史不改写」保留。
- **验收**：`verify_reference_hud_fate_visual` 新增 5 组断言（被动覆盖层 / 受伤红条即落 / 白段满血留驻 / 追赶不越过 / 全局矩形完全叠放）**全绿**；`--check-only` 无解析错误；渲染模式实拍 `outputs/verification/reference_combat_hud.png`（08:59:34 重拍）——72/100 红条右侧白段肉眼可见。套件 rc=1 的 3 个 ERROR 均为塔罗牌翻面/悬停**既有红项**，与血条无关。
- **文档**：`docs/v0.1/development/2026-10-15_player_hud_health_bar_delay.md`（新）、CHANGELOG、`04_技术施工_战斗与局内成长.md` L630。
- **未提交**：工作区仍有并发会话改动（level_plan、room_02 等），提交由主人定。
