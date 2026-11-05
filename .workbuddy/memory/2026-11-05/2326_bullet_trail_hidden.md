# 23:26 子弹尾迹先隐藏（开关一个常量，不删实现）

业主原话：「所有子弹特效那个后面有个小拖尾那个小尾巴帮我先去掉看看效果，啊先隐藏掉不要直接去删掉，
回头如果觉得不行的话再给它加回来。」

## 做法

- `src/framework/GameDesignConfig.gd` 加 `const BULLET_TRAIL_VISIBLE := false`（唯一开关）。
- `VfxBulletBody3D`（八弹种基类）与 `VfxBulletVisual3D`（通用弹体）各两处：
  建造期设 `visible`，**`activate()` 复借复位也按开关** —— 只改建造期会漏掉池化复借把尾巴带回来的间歇性 bug。
- 隐藏时 `_animate_trail()` 早退；快照加 `trail_visible` 字段（几何/位置字段一律不动）。
- **零删除**：几何、材质、构图、面数、`trail_parts` / `trail_is_behind` 全部照旧 ⇒ 恢复只需把常量改 `true`。

## 验收

- `godot --headless --path . res://tests/verification/verify_bullet_vfx_profiles.tscn`
  → `BULLET_VFX_PROFILES_OK … (samples=69)`（与改前一致；尾迹段数硬编码表全过）
- `verify_combat_vfx_toon_v002` → `COMBAT_VFX_TOON_V002_OK … (samples=16)`
- `python3 scripts/check_documentation_contracts.py` → 仅存量问题（断链 / 4 个未注册场景 / 缺 openpyxl），本事务文件未入列。
- 三个改动文件 `--check-only` 均无解析错误。

## 文档

`docs/v0.1/development/2026-11-05_bullet_trail_hidden.md` + `CHANGELOG.md` 顶部一条（CRLF 保持，5939 行无孤立 LF）。

## 留了口子

没做**关卡内**实机截图（只有隔离工作台棚拍）；也没动 `14.6` 与 `MODULE_INDEX` 的设计正文 ——
若最终确定不要尾巴，再决定是「永久 false」还是「删建造代码 + 同步收紧 `EXPECTED_TRAIL_PARTS` 与面数预算」。

## 23:31 追加：真渲染截图（业主「要角色和怪物同时出现子弹的那个画」）

新工具 `tools/_bullet_trail_shot.{gd,tscn}`，出两张：

- `outputs/bullet_trail_hidden_shot.png` —— 全景三格，角色＋怪＋子弹同框（弹道 30/58/84%）
- `outputs/bullet_trail_hidden_ab.png` —— 特写 A/B，左＝尾巴关（产品现状）右＝临时点亮

跑法：`godot --path . res://tools/_bullet_trail_shot.tscn -- <全景.png> <特写.png>`（**不能 `--headless`**）

### 三个踩过的坑（下次直接用）

1. **别自己实例化枪**：先试了独立 `WeaponModel3D` + `_fire_now()`，出来是一把**悬空的枪**（脱离手部）。
   正解：`player.start_with_weapon = true` 让它走 `_ensure_weapon_model()` 挂到 `avatar.weapon_socket`，
   开火用 `weapon.try_fire(dir, player)`；弹道起点读**投射物真实出生点**，不估算枪口。
2. **改 `speed` 抓不住子弹**：`Projectile3D._physics_process` 每帧 `velocity = direction * speed` 重算，
   改 `speed` 会被下一帧覆盖。正解：开火后 `set_physics_process(false)` + 手动 `global_position`。
3. **机位按公式反算**：fov 38°/16:9 ⇒ 水平半 fov 31.45°；先前 5.35m 把角色和怪**两侧各裁掉一半**，
   7.4m 才装得下 4.6m 间距 + 头顶血条。第一次拍还漏了垂直方向（血条被切顶）。

另外工作区有一处**既有编译错误**（不是本次引入）：`src/world3d/TreasureChest3D.gd:226`
`Identifier "LID_OPEN_SECONDS" not declared` —— 另一会话的未提交改动（宝箱动画重构）把常量删了但还在引用，
连带 `DungeonRoom3D → MonsterAIManager → Projectile3D` 一串编译失败。截图工具运气好没踩到这条链，
但 `--headless` 跑验证时它会冒出来。**不动它**（不是我的事务），但要告诉主人。
