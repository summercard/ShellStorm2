class_name VfxZombieGooDeath3D
extends VfxGooDeathBase3D
## FX01-19 / VFX-ZOMBIE-GOO-DEATH-3D 小僵尸 / 警察僵尸死亡「绿色方块爆开」特效
##
## 用途：小僵尸（`melee_chaser`）与警察僵尸（`ranged_caster`）被打死瞬间的一次性表现。
##
## 业主口径（2026-10-14 第一轮）：「绿色方块爆开的粒子，掉落地面，然后地面上有方形像液体一样的
## 扁平模型，停留 0.5 秒后慢慢下沉消失；特效由三部分组成 —— 爆炸的粒子、飞溅出去的粒子、
## 地上的液体；节奏自己把控好，要有打击力度感、节奏感；粒子不要太小，可以大一点，
## 需要有大小的变化动画。」
## 业主口径（2026-10-14 第二轮）：「**小僵尸的死亡特效不要改变**」——
## 所以本件就是第一轮那一版（v001），**没有任何视觉改动**。
## （中途曾被改成「放大 2 倍 + 绿色冲击波」，业主随后明确那条是**给胖子僵尸用的**；
##   那套表现落在 FX01-17 `VfxDeathBlast3D`，与本件共用 `VfxGooDeathBase3D` 的身体。）
##
## 本文件只剩三个覆盖点，全部身体在基类里：
##   · `_asset_id()`          → `VFX-ZOMBIE-GOO-DEATH-3D`
##   · `_asset_version()`     → `v001`（未改版）
##   · `_shockwave_enabled()` → **false**（业主：小僵尸死亡没有冲击波）
##
## 尺寸：调用方 `Enemy3D.GOO_DEATH_EFFECT_SIZE = 1.0`（规格尺寸；放大留给胖子僵尸那条）。
## 四部分 / 节奏 / 地面契约 / 池化纪律全部见基类文件头。


func _asset_id() -> String:
	return "VFX-ZOMBIE-GOO-DEATH-3D"


func _asset_version() -> String:
	return "v001"


func _shockwave_enabled() -> bool:
	return false
