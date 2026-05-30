# 轮次 326 — 2026-05-28 16:05 UTC+8

### 维度
**第二关武器装备还原 + elite_floor 掉落表补全**

---

## 一、问题发现

审查 `GameUIManager._item_for_weapon_root()` 发现：

```gdscript
match root.node_name:
    "GunBody_Pistol": item_id = "weapon_pistol"
    "GunBody_Shotgun": item_id = "weapon_shotgun"
    "GunBody_Rifle": item_id = "weapon_rifle"
    _:
        item_id = ""  # ❌ machinegun/sniper/launcher/charge 全漏！
```

玩家用 Rifle/Machinegun/Sniper/Launcher/Charge 武器撤离后死亡，取回装备时无法还原为 `weapon_machinegun`/`weapon_sniper`/`weapon_launcher`/`weapon_charge`，只会返回空字典导致装备丢失（系统当"没有旧武器"处理，物品直接消失）。

同时发现 `elite_floor_2` 掉落表完全缺失（精英房只有 `elite_floor_1`），第二关精英房没有独立掉落。

---

## 二、本轮改动

### 文件1：`src/ui/GameUIManager.gd`（_item_for_weapon_root）

补全 match 分支，识别全部 6 把成品枪械：

```gdscript
"GunBody_Machinegun": item_id = "weapon_machinegun"
"GunBody_Sniper":     item_id = "weapon_sniper"
"GunBody_Launcher":   item_id = "weapon_launcher"
"GunBody_Charge":     item_id = "weapon_charge"
```

这 4 把枪在 `_register_weapon_drops()` 中已注册，对应 `assembly_id` 为 `bp_machinegun`/`bp_sniper`/`bp_launcher`/`bp_charge`。

### 文件2：`src/base/ItemRegistry.gd`（_register_room_key_item）

给钥匙房和精英房的掉落表补充 floor=2 的权重：

```gdscript
"floor_loot_weights": {
    "loot_common": 1.0,
    "loot_floor_1_2": 1.8,
    "scavenge_floor_1": 2.4,
    "scavenge_floor_2": 2.0,
    "combat_floor_1": 1.2,
    "combat_floor_2": 1.0,    # 新增
    "elite_floor_1": 1.0,
    "elite_floor_2": 1.0,    # 新增（elite_floor_2 之前没有）
}
```

---

## 三、验证

- [x] Godot headless --check-only --quit: **EXIT 0** ✅
- [x] `_item_for_weapon_root` 覆盖全部 6 种枪身 ✅
- [x] `elite_floor_2` 掉落权重已注册 ✅
- [ ] 人类试玩：Rifle → 死亡 → 拾取回原枪（武器还原验证）

---

## 四、下轮最可能方向

1. **第二关专属怪物掉落表**（elite_floor_2 掉落内容实际质量审查）
2. **精英挂枪视觉深化**（当前 emoji badge → 实际 AttachGunToBullet 射击）
3. **人类试玩验证**（最高且唯一优先级）

---

## 五、循环状态

- 状态：`running`
- 已完成轮次：326
- 当前设计文档：`docs/PH06_怪物系统.md`
- 方向：游戏打磨 / 内容扩充 / 第二关 / 怪物种类 / 武器差异性 / 关卡设计