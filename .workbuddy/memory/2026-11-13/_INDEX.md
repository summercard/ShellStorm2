# 2026-11-13 索引

| 时间 | 事务 | 文件 |
|---|---|---|
| 11:14 | 修「右下武器栏备弹数拾取后不更新」：备弹是独立物品，拾取只发 `inventory_changed` 不发 `ammo_changed`，HUD 没被通知；连通主背包 + 快捷栏信号后同帧重推。含反向对照与 runner GBK 预检绕行姿势 | [1114_hud_reserve_ammo_refresh.md](1114_hud_reserve_ammo_refresh.md) |
