# 21:00 主角换角色（女仆 maid01）验收与修复

**事务**：`Player3D.tscn` 的 Avatar3D 由 bunny01 v021 换成 maid01（clip 装配），做验收并修缺陷。

## 装配
- 女仆 `assets/art/characters/player/external/maid01/chr_maid01_root_v001.tscn`，`assembly_version=clip`、`motion_driver=clip`，65 骨、128 剪辑（与兔子同名同数）。
- 备用查克2 同结构。驱动 = 新增 `src/player3d/ClipMotionLibrary3D.gd`（继承 CharacterMotionLibrary3D，同形接口）。

## 判据教训（重要）
**静态探针读数与 tscn rest 值逐位吻合（1e-5）——那也正是「骨架没被驱动」的读数，两者不可区分。**
必须用两条独立判据：① 跨真帧骨骼摆幅（`tools/ss2_clip_motion_probe.gd`，冻结≈1e-6、驱动≥1e-3）；② 真渲染出图。

## 修了 4 处真缺陷
1. **武器大 1.65 倍**（最显眼）：`_apply_bunny_attachment_scale()` 入口 `if not _is_bunny_avatar(): return`，clip 装配整条路径无缩放。武器按 2.475m 角色空间建模，需乘 `BUNNY_LINEAR_SCALE=1.5/2.475≈0.6061`。
   修法：提 `get_attachment_scale()` 作真源，`_apply_attachment_scale()` 任何装配都跑；新增 `_apply_attachment_scale_group()` 管换弹环/挂件/StateVFX。实测 0.853/1.072/1.241 → **0.517/0.649/0.751**。
   **连带契约**：`_ensure_wearable_nodes()` 里兔耳 reparent 按 `1.0/BUNNY_LINEAR_SCALE` 反向抵消，两侧必须同值。
2. **叙事钉帧缺失**：`ClipMotionLibrary3D` 没读 `pose_lock_*` ⇒ 开场 `nar_tower_opening_01_wake` 的「趴地→起身」会站着播死亡动画。修法：`seek(phase×剪辑长)` + `speed_scale=0`（不用 `pause()`，幂等）；`_play_clip` 里加保护（钉帧时不改 speed_scale、不淡化）。
3. **换弹上报缺失**：`active_overlay` 被后面一行清空 ⇒ 验收读不出「换弹在播」。修法：换弹分支同时写 `active_overlay`，删掉清空行（顺序错了）。
4. **快照标志位旧判据**：`animation_driver`/`legacy_procedural_motion_enabled`/`_get_missing_authored_action()` 全写死 v021 ⇒ clip 装配假绿灯。改为按 `AUTHORED_ASSEMBLY_VERSIONS` 判。

## 非缺陷（测了才知道）
- 整机 AABB 高 3.01 = `ReloadProgress3D` 悬 y=2.92，世界环已退役（`RELOAD_RING_IN_WORLD=false`），非缺陷。
- `weapon_support_error_m` 报 0.17~0.31m 像「左手没扶枪」——实测左手到**枪身包围盒**距离全为 **0.0000**。那是度量口径（量到护木名义挂点），视觉无缺陷，不改。

## 遗留：旧验收用例写死兔子契约
`avatar_bounds`（10 网格）、`diy_flow`（Bunny slot 材质）、`head_accessory_flow`（`HeadJoint/Model`、`ChibiAnime`）、`directional_motion`/`melee_motion`（读 JSON 库 `clips`/`motion_library_version`）—— 后两条是**硬崩**（读不存在键），优先修。
修复后 `firing_motion` 133→82、`reload_motion` 56→47。**未擅自放宽阈值**。

## 新增工具
`tools/ss2_clip_motion_probe.tscn`（判活）、`ss2_clip_fix_check.tscn`（19 项专项）、`ss2_clip_avatar_render.tscn`（12 格真渲染）、`ss2_assembly_scale_probe.tscn`（尺度）、`ss2_support_hand_probe.tscn`（支撑手）。
清理：13 个临时输出 + 7 个 bat 移出仓库（备份 `I:\ShellStorm2-work\charswap_backup\`）。
