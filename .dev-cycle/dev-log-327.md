# 轮次 327 — 2026-05-28 16:10 UTC+8

### 维度
**elite_floor_2 掉落权重补全 + item_beacon 精英掉落通道打通**

---

## 一、问题发现

轮次326标记"第二关精英掉落表补全"，发现两个具体缺口：

1. `item_room_key`（钥匙）：`elite_floor_2` 权重缺失（`elite_floor_1` 有，`elite_floor_2` 没有）
2. `item_beacon`（撤离信标）：**完全没有**任何 `elite_floor_*` 权重 → 精英怪不产信标，但 PH11 设计要求精英可掉信标

---

## 二、本轮改动

### 文件：`src/base/ItemRegistry.gd`

#### 改动1：item_room_key — 新增 `elite_floor_2` 权重

```diff
  "floor_loot_weights": {
      "loot_common": 1.0,
      "loot_floor_1_2": 1.8,
      "scavenge_floor_1": 2.4,
      "scavenge_floor_2": 2.0,
      "combat_floor_1": 1.2,
      "elite_floor_1": 1.0,
+     "elite_floor_2": 1.0,
  },
```

#### 改动2：item_beacon — 新增 `elite_floor_1` + `elite_floor_2` 权重

```diff
  "floor_loot_weights": {
      "loot_floor_1_2": 1.0,
      ...
      "scavenge_floor_5": 1.8,
+     "elite_floor_1": 1.5,
+     "elite_floor_2": 1.5,
  },
```

信标现在可通过：
- 精英怪击杀掉落（`elite_floor_1/2`，权重1.5）
- Boss击杀掉落（`boss_floor_1/2`，权重3.0-4.0）
- 搜刮房/箱子（`scavenge_floor_*`、`loot_floor_*`）
- 商人购买（`merchant_tier: 2`）

---

## 三、验证

- [x] Godot headless --quit-after 1：**EXIT 0** ✅
- [x] `elite_floor_2` 权重在 item_room_key 上已注册 ✅
- [x] `elite_floor_1/2` 权重在 item_beacon 上已注册 ✅
- [ ] 人类试玩：第二关精英怪击杀后检查是否掉落信标道具
- [ ] 人类试玩：第二关钥匙房（ELITE类型）开启后检查掉落质量

---

## 四、下轮最可能方向

1. **第二关精英掉落内容质量审查**（elite_floor_2 的掉落物品是否真的比 floor_1 更好）
2. **精英挂枪视觉深化**（当前 emoji badge → 实际 AttachGunToBullet 射击）
3. **人类试玩验证**（最高且唯一优先级）

---

## 五、循环状态

- 状态：`running`
- 已完成轮次：327
- 当前设计文档：`docs/PH06_怪物系统.md`
- 方向：游戏打磨 / 内容扩充 / 第二关 / 怪物种类 / 武器差异性 / 关卡设计
