# 轮次 329 — 2026-05-28 16:41 UTC+8

### 维度
**sniper/launcher/charge 武器 elite_floor 掉落权重补全**

---

## 一、问题发现

审查 ItemRegistry 完整掉落表发现：

| 武器 | elite_floor_1 | elite_floor_2 | 备注 |
|---|---|---|---|
| weapon_pistol | ❌ 缺失 | ❌ 缺失 | Tier 0 低稀有度，可接受 |
| weapon_shotgun | ❌ 缺失 | ❌ 缺失 | Tier 1，较低稀有度 |
| weapon_rifle | ✅ 1.5 | ✅ 2.0 | 完整 |
| weapon_machinegun | ✅ 1.5 | ✅ 2.5 | 完整 |
| weapon_sniper | ❌ 缺失 | ❌ 缺失 | Tier 2 高稀有度，**精英不产** ❌ |
| weapon_launcher | ❌ 缺失 | ✅ 2.5 | Tier 2，**缺 elite_floor_1** |
| weapon_charge | ❌ 缺失 | ✅ 3.0 | Tier 3（Epic），**缺 elite_floor_1** |

问题：Sniper 作为第二关常见高稀有度枪械，精英怪完全不掉落。Launcher 和 Charge 作为后期强势武器，精英掉落也只有 floor_2 没有 floor_1。

---

## 二、本轮改动

### 文件：`src/base/ItemRegistry.gd`

#### 改动1：weapon_sniper — 新增 `elite_floor_1` + `elite_floor_2` 权重

```diff
  "floor_loot_weights": {
      "loot_floor_3_4": 0.5,
      "loot_floor_5": 1.5,
      "loot_abyss": 2.5,
      "boss_floor_1": 2.0,
      "boss_floor_2": 4.0,
      "scavenge_floor_5": 2.0,
+     "elite_floor_1": 1.5,
+     "elite_floor_2": 2.0,
  },
```

#### 改动2：weapon_launcher — 新增 `elite_floor_1` 权重（已有 elite_floor_2）

```diff
  "floor_loot_weights": {
      "loot_floor_5": 1.5,
      "loot_abyss": 2.5,
      "boss_floor_1": 2.5,
      "boss_floor_2": 4.0,
      "scavenge_floor_5": 2.0,
+     "elite_floor_1": 2.0,
      "elite_floor_2": 2.5,
  },
```

#### 改动3：weapon_charge — 新增 `elite_floor_1` 权重（已有 elite_floor_2）

```diff
  "floor_loot_weights": {
      "loot_floor_5": 0.8,
      "loot_abyss": 2.0,
      "boss_floor_2": 4.0,
      "scavenge_floor_5": 1.0,
      "elite_floor_2": 3.0,
+     "elite_floor_1": 2.0,
  },
```

---

## 三、验证

- [x] Godot headless --check-only --quit: **EXIT 0** ✅
- [x] weapon_sniper 现在有 elite_floor_1 + elite_floor_2 ✅
- [x] weapon_launcher 现在有 elite_floor_1 + elite_floor_2 ✅
- [x] weapon_charge 现在有 elite_floor_1 + elite_floor_2 ✅
- [ ] 人类试玩：第一/二关精英怪击杀后检查 sniper/launcher/charge 掉落

---

## 四、下轮最可能方向

1. **第二关怪物种类扩增**（当前精英只有几种，需要更多差异化怪物）
2. **人类试玩验证**（最高且唯一优先级）
3. **第二关关卡设计**（精英房/Boss房的几何布局深化）

---

## 五、循环状态

- 状态：`running`
- 已完成轮次：329
- 当前设计文档：`docs/PH06_怪物系统.md`
- 方向：游戏打磨 / 内容扩充 / 第二关 / 怪物种类 / 武器差异性 / 关卡设计