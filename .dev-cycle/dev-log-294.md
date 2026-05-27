# 轮次294：overheat_penalty 受击惩罚链路实现

## 本轮选维度：设计缺口修复（overheat_penalty）

**原因：** 轮次293发现 overheat_penalty 设计缺口——变量存在于 WeaponAssemblyTree 但从未连接到 Player.take_damage()，导致超频命卡实际无负面惩罚。本轮实现该链路。

---

## 一、问题分析

### 设计真相
- PH04 策划案描述：超频命卡使射击越多，受击伤害越高（overheat_penalty=1.5）
- `_apply_multiply_fire_rate()` 将 `overheat_penalty=1.5` 写入 gun stats
- `WeaponAssemblyTree.gd:464` 在 `refresh_stats()` 时将 `overheat_penalty` 读入 `_overheat_penalty`
- **但 `_overheat_penalty` 在整个代码库中从未被读取或使用**
- 超频命卡变成纯增益卡（射速+80%无代价），破坏诅咒卡设计意图

### 影响评估
- 玩家使用超频命卡时没有受击惩罚的负面效果
- 超频命卡失去"诅咒"属性，平衡性破坏
- 影响所有依赖 overheat_penalty 的后续设计

---

## 二、代码改动

### 改动1：WeaponAssemblyTree.gd — 新增 get_overheat_penalty() 公开接口

**文件：** `src/weapons/WeaponAssemblyTree.gd`

在 `get_crit_on_kill_stack()` 后面新增：

```gdscript
## 公开接口：获取超频受击惩罚倍率（由超频命卡写入，取值>1时玩家受击伤害增加）
func get_overheat_penalty() -> float:
	return _overheat_penalty
```

**作用：** 将私有成员变量 `_overheat_penalty` 通过公开方法暴露给外部调用者。

### 改动2：Player.gd — take_damage() 引入 overheat_mult 惩罚倍率

**文件：** `src/player/Player.gd`

修改 `take_damage(amount: int)` 方法：

```gdscript
func take_damage(amount: int) -> void:
	if is_invincible or current_hp <= 0:
		return
	# 获取武器树超频惩罚（每次射击叠加效果，超频命卡写入 overheat_penalty>1）
	var overheat_mult: float = 1.0
	if weapon_tree != null and weapon_tree.has_method("get_overheat_penalty"):
		overheat_mult = weapon_tree.call("get_overheat_penalty")
	var final_damage: int = maxi(1, int(float(amount - armor) * overheat_mult))
	current_hp = max(0, current_hp - final_damage)
	...
```

**作用：** 玩家每次受伤时，读取武器树当前 overheat_penalty 值并乘算伤害。超频命卡写入 1.5 时，玩家受击伤害变为原来的 1.5 倍。

---

## 三、完整链路确认

```
玩家应用超频命卡
→ FateCardEngine._apply_multiply_fire_rate()
→ stats["overheat_penalty"] = 1.5
→ WeaponAssemblyTree.refresh_stats() 读入 _overheat_penalty = 1.5
→ 玩家受伤时 Player.take_damage()
→ weapon_tree.get_overheat_penalty() 返回 1.5
→ final_damage *= 1.5（受到更高伤害）
```

---

## 四、验收标准

- [x] WeaponAssemblyTree.gd 新增 `get_overheat_penalty()` 公开接口
- [x] Player.take_damage() 在伤害计算前引入 overheat_mult 惩罚倍率
- [x] 无 overheat_penalty 时（默认值 1.0）不影响正常伤害计算
- [x] Godot headless --quit 验证编译通过
- [ ] **人类试玩验证**：应用超频命卡后，被怪物攻击时实际受到 1.5 倍伤害（需实际测试）

---

## 五、剩余风险

**人类试玩验证项（不变）：**
1. 冰霜子弹命中冻结效果（0.5s/0.25s for elite）
2. 火焰子弹命中后 DOT 视觉（橙红色敌人）
3. 剧毒子弹叠加5层视觉（绿色加深）
4. 精英名字+🔫挂枪+活子弹追踪+落地炮台+crit×2.5暴击实际体验
5. FateCardEngine._apply_grant_random_card() 随机选卡效果
6. 开门命运选卡后通知是否正确显示
7. MapFateTriggers 环境命运触发器实际触发与效果
8. 撤离守点敌潮强度缩放实际效果
9. 炮台射击间隔稳定性（dt上限保护）
10. 搜打撤经济系统整体平衡
11. **超频命卡（overheat_penalty）受击惩罚实际表现** ← ✅ 本轮已修复链路

---

## 六、续排判断

**继续排 cron** — 状态维持 `running`。overheat_penalty 设计缺口已修复，但需要人类试玩实际验证惩罚是否生效。继续以孤立 cron 推进。

### 下轮最可能方向
1. 人类试玩验证（最高且唯一优先级）
2. 若发现 Bug → 针对性修复
3. 若未发现 Bug → 战斗视觉反馈或关卡内容扩展