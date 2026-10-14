class_name VfxDeathBlast3D
extends VfxGooDeathBase3D
## FX01-17 / VFX-DEATH-BLAST-3D 胖子僵尸死亡自爆特效
##
## 用途：`Enemy3D._detonate_death_explosion()` / `_spawn_fat_death_burst()` 在胖子僵尸
## 被打死瞬间生成的一次性死亡视觉。
##
## 业主口径（2026-10-14 第一轮）：「胖子僵尸被打死后自爆没有特效，需要增加一个，
## 并且在地上留一个持续伤害的范围效果，持续3秒」。
## 业主口径（2026-10-14 第二轮）：「**把小僵尸的死亡特效放大两倍给胖子僵尸用**，
## 然后带一个绿色冲击波的效果，同样去掉胖子僵尸的倒地动画播放」。
##
## ⇒ 本件 = **FX01-19 的那套死亡表现（绿方块爆开 + 抛物线飞溅 + 地面液体）×2 + 3 层绿色冲击波**。
##    身体完全来自 `VfxGooDeathBase3D`（与小僵尸死亡件是同一段代码），
##    本文件只覆盖三点：
##      · `_asset_id()`          → `VFX-DEATH-BLAST-3D`
##      · `_asset_version()`     → `v002`（从「亮芯+星芒+碎屑」重做为现在这套 ⇒ 升版）
##      · `_shockwave_enabled()` → **true**（业主：只有胖子僵尸死亡有冲击波）
##
## ⚠ **尺寸由调用方给**：`Enemy3D.FAT_DEATH_EFFECT_SIZE = 2.0`（业主「放大两倍」）。
##    与 v001 的差别要说清：v001 的环外缘是**按伤害半径**反推的（radius × 0.6），
##    现在这一版按业主指定**固定 2.0**，因此冲击波外缘（≈1.548 × 2.0 = 3.1m）
##    **不再等于**远征01 的 5.0m 伤害半径 —— 它是一条风格元素，不再充当半径指示。
##
## 与 FX01-19 `VFX-ZOMBIE-GOO-DEATH-3D` 的差别只有两点：**尺寸**（2.0 vs 1.0）
## 与**冲击波**（有 vs 无）。两者共用基类身体，所以配色 / 节奏 / 落地数学不可能漂移。
##
## ⚠ 与 FX01-18 `VFX-BLAST-ZONE-3D` 的分工没变：那件仍是自爆后**留在地上的持续伤害场**
##   的视觉层（由玩法节点 `DeathBlastZone3D` 持有、刻意不进 `VfxPool3D`），本件只管爆开那一下。


func _asset_id() -> String:
	return "VFX-DEATH-BLAST-3D"


func _asset_version() -> String:
	return "v002"


## 业主指定：只有胖子僵尸死亡带绿色冲击波
func _shockwave_enabled() -> bool:
	return true
