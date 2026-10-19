# 2026-10-19 19:05 暗门破板木块飞溅特效

## 业主口径

- 「做一个门被打碎的木头飞出来的特效，**大块一点**的，做完带入然后更新账本」
- 「大块一点」是主约束：不是加一堆小粒子，而是**少量、体积明显**的木片。

## 落地

- 新资产 `VFX-BOARD-DEBRIS-3D`（FX01-33）：
  - Prefab `assets/art/vfx/combat_3d/vfx_board_debris_root_top3d.tscn`（根 + `DebrisLight`）
  - 脚本 `src/vfx/VfxBoardDebris3D.gd`
  - 池常量 `VfxPool3D.FX01_BOARD_DEBRIS`
- 件数与尺寸：8 大块 `0.36~0.58 × 0.16~0.26 × 0.07~0.10m`（门宽 2.38m 的 1/6~1/4）+ 5 片小碎屑。
- 与弹壳同族（抛出物）：不绑 `context.follow`、无碰撞体、解析式越线落地；抛物 → 弹 1 次 → 贴地滑行 → 放平静止，`2.85s`。
- `context` 键：`forward`（局部 -Z 对齐，碎块朝房间侧崩）、`floor_y`（门自己世界 y，**绝不以 0 兜底**）、`seed`。
- 随机化只活在调用方：脚本内无 `randf()`，逐片参数由 seed 确定性派生，同 seed 逐位可复现。
- 灯：`DebrisLight` 峰值 1.5 / 范围 3.6m / 无阴影 / **0.55s 归零**（塔内夜间光，无灯碎块是黑块）。
- 材质：木质 `metallic=0.0` / `roughness=0.86` + **自发光 0.38**（暗房里纯受光会读成黑剪影，实拍核对后补）。
- 接线：`SecretDoor3D._break_open()`（拆木板之前）；`open_silently()`（读档恢复 / 从子图穿回主图）**不播**。

## 踩的两个坑

1. **尺寸必须乘进 `basis`**：先写 `piece.scale` 再写 `piece.basis` 会被整矩阵覆盖抹成 1m 大方块（比门板还大）。**当次验收是绿的** —— 只写了「最大单片 ≥ 0.30m」，`1.0 ≥ 0.30` 照样过。是补的**上限 0.65m** 抓出来的。⇒ 凡「尺寸落在某区间」的定档，断言必须双向。
2. **相机站错侧**：探针把相机放在 `target - room_side * 7`，而 `room_side = -basis.z` 已是房间侧 ⇒ 相机跑到墙外，碎块全被墙挡住，图里什么都没有。加 `_report_geometry`（打印门三轴 / 位点 normal / 房间中心与 `-basis.z` 的点积）后一眼定位。⇒ 「图里没东西」先打印几何关系，别猜。

## 验收

- 新增 `tests/verification/verify_board_debris_vfx.tscn`，9 条：资产身份 / 无碰撞体 / 灯真相与归零 / **大块双向尺寸** / forward 消费（含反向对照）/ **非零地面 `y=5.0`** 落地不穿地 / 同 seed 可重放 + 不同 seed 真散开 / 复借复位 / 端到端破板即触发且读档不重播 → `BOARD_DEBRIS_VFX_OK`。
- 四组反向对照（不消费 forward / 灯不灭 / 尺寸抹 1m / `floor_y` 兜底 0）全部精准变红后还原复绿，数值自洽（`-0.851m` / `1.327` / `1.000m` / `0.022 vs 5.00`）。
- 回归：`verify_vfx_pool_lifecycle` → `VFX_POOL_LIFECYCLE_OK`；`verify_combat_vfx_toon_v002` → `COMBAT_VFX_TOON_V002_OK`。
- 真渲染：`tests/verification/probe_board_debris_shot.tscn`（真实远征流程，`test_mode=false`，种子 1122239949，room_03 的 S1）→ `outputs/board_debris_shots/{before,geom_80ms_fill,real_160ms,late_550ms}.png`。
- 已登记 `scripts/run_verification_suite.sh` 的 `core_scenes`。

## 账本 / 文档

- 特效账本：资产主表 r53（`asset_count` 47 → **48**）、3D-特效 r53（FX01-33）、总览区间 `$6:$52 → $6:$53`、域变更日志 r37 = `v0.1.29`。回写脚本 `scripts/register_board_debris_vfx.py`（幂等）。
- `docs/v0.1/14.6_特效系统与制作规范.md`：新增 **§3.9 抛出物类碎块** + 版本历史 `v003.12`。
- `docs/v0.1/MODULE_INDEX.md`：`VFX-POOL` 行补验收脚本与本条说明。
- `docs/v0.1/development/CHANGELOG.md` 顶部一条；新记录 `docs/v0.1/development/2026-10-19_board_debris_vfx.md`。

## 未做 / 待业主定

- 门板本体仍是缩放消失，没做「板上留缺口」（要改门板美术与碰撞）。
- 破板无音效（属音效域）。
- 门禁 `--ledger vfx` 的 `sha_mismatch: 5`（r48–r52 命运系四件 + 伤害数字）**在本次改动前就存在**，用备份账本复算确认；要不要重算等业主定。
- `verify_base_lamp_dynamics` / `verify_base_lamp_visual` 未登记进套件（既有，非本次）。
