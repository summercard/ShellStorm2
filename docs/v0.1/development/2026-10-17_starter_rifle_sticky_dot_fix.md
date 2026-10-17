# 初始步枪「持续掉 4 点血」修复（出厂枪误挂黏黏弹）

- 日期：2026-10-17
- 类型：Bug 修复（出厂配装 / 弹体标签）
- 影响文件：
  - `src/base/BlueprintRegistry.gd`（`build_default_weapon_tree` 选弹逻辑）
  - `tests/verification/verify_starting_weapon_contract.gd`（新增出厂弹种断言）

## 现象

玩家用初始步枪打中怪物后，怪物在命中瞬间的伤害数字之外，还会**周期性再掉 4 点血**（约每 0.5 s 一次，持续 2 秒多）。看起来像「子弹自带持续伤害/流血」。

## 根因

`BlueprintRegistry.build_default_weapon_tree()` 的选弹循环写反了意图：

```gdscript
# 旧实现
var bullet_id := "mod_bullet_standard"
for b in available_bullets:
    if b["item_id"] != bullet_id:   # ← 跳过标准弹，取第一个「非标准」弹
        bullet_id = b["item_id"]
        break
```

tier0 可用子弹顺序为 `[mod_bullet_standard, mod_bullet_sticky, mod_bullet_bounce]`，
第一次迭代即命中 `mod_bullet_sticky` 并 break ⇒ **出厂初始步枪一直挂着黏黏弹**。

链式后果：

1. `WeaponModel3D.configure_from_tree()` 把子弹节点 tags 写入 `bullet_tags` ⇒ `["bullet","sticky","dot"]`。
2. `Projectile3D._apply_secondary_effect()`：
   - `sticky` ⇒ `apply_damage_over_time(max(2, damage / 3), 2.4)`；
   - 弹伤 = 枪身 50 + 弹 6 = 56 ⇒ DOT 总量 18。
3. `Enemy3D._tick_damage_over_time()`：每 0.5 s 结算 `ceil(18 × 0.2) = 4` 点，持续约 2.4 s。

即玩家看到的「4 点 4 点」= `max(2, 56/3) × 0.2` 的 DOT tick，不是步枪设计的一部分；
同一条 sticky 还会附带 `apply_slow(0.62, 2.0)`（打中后怪物变慢），弹体颜色被换成黏弹绿。

## 证据（headless 只读探针）

修复前：

```
BULLET_ORDER=["mod_bullet_standard", "mod_bullet_sticky", "mod_bullet_bounce"]
GUN=GunBody_StarterRifle
BULLET_NODE=Bullet_Sticky TAGS=["bullet", "sticky", "dot"]
PROJECTILE_DAMAGE=56 DOT_TOTAL=18 DOT_TICK=4
```

修复后：

```
BULLET_NODE=Bullet_Standard TAGS=["bullet", "kinetic", "standard"]
```

## 修法

出厂树固定挂标准弹；仅当该 tier 根本没有标准弹时才回落可用列表首个：

```gdscript
var bullet_id := "mod_bullet_standard"
var standard_available := false
for b in available_bullets:
    if str(b["item_id"]) == bullet_id:
        standard_available = true
        break
if not standard_available and not available_bullets.is_empty():
    bullet_id = str(available_bullets[0]["item_id"])
```

特殊弹（黏黏 / 反弹 / 穿透 / 爆裂…）改为**只能由玩家在包裹里手动装配**，符合
`docs/v0.1/04_技术施工_战斗与局内成长.md` §6.6「白送枪只给枪不给弹」的既有口径。

## 验收

- `verify_starting_weapon_contract`：`STARTING_WEAPON_CONTRACT_OK`，退出码 0。
  - 新增断言：`get_starting_weapon_tree()` 的子弹槽必须是 `Bullet_Standard`，缺失也报红。
- 负向自测：把选弹逻辑临时还原成旧实现 ⇒ 门禁退出码 1，报
  「出厂装配树挂的子弹是 Bullet_Sticky，期望 Bullet_Standard」；恢复后重新转绿。
- 影响面：`build_default_weapon_tree()` 全仓唯一调用方是 `get_starting_weapon_tree()`，
  后者唯一调用方是 `Player3D._ensure_weapon_tree()`（新档出生 / 死亡返城白送枪）。
  地面拾取枪、训练场选枪、背包换装均走显式 `bullet_id`，行为不变。
