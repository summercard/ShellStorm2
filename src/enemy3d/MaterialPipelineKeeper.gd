class_name MaterialPipelineKeeper
extends RefCounted
## 把「每种材质变体」留一份**长命引用**，避免管线缓存随实例销毁一起丢。
##
## ## 为什么需要（2026-10-31 实测，真渲染 / `--disable-vsync`）
##
## Godot 4 的管线缓存**挂在使用中的材质实例上**：同一变体的新材质在「旧材质还活着」时
## 是 0.15 ms，把旧材质全释放之后再建同样的材质，又要重付一次编译。
##
## ```
## 第一次        101.15 ms   ← 编译
## 第二次          0.15 ms   ← 旧材质还在
## 全释放后再建    96.41 ms   ← 缓存跟着材质一起没了
## 再建            0.15 ms
## ```
##
## 后果是**每只怪都要重编译**：`EnemyAvatar3D._rebuild()` 每次都新建
## `_shell_material`（无自发光）与 `_core_material`（有自发光）+ 预警环
## （ALPHA + 自发光）—— 三个变体，实测每次生成 **200~320 ms**：
##
## | 怪种 | 每次 `configure()` |
## |---|---:|
## | summoner / shielded / exploder（程序化壳） | ~200 ms |
## | melee_chaser / ranged_caster（正式 GLB） | ~310 ms |
##
## 而 headless 里同一段只要 2 ms —— 因为它根本不编译管线，
## 所以这个开销在无渲染的验收里**永远是零**。
##
## ## 做法
##
## 把每种变体的**第一份**材质按签名留下来（不释放）。之后任何实例新建同变体材质都
## 命中缓存。签名取的是 `MaterialKey` 的那些位（透明/着色模式/自发光开关/贴图有无…），
## 不含颜色、能量这些 uniform —— 只改 uniform 不改变体，也不需要重新编译。
##
## ## 它不改渲染
##
## 被留住的只是**引用**：各实例仍然用自己的那份材质、仍然各自改自己的颜色。
## 留住的可能是某只怪的那份 —— 那只怪照样闪白、照样回收，只是它的材质不会跟着消失。
##
## ## 上限
##
## `MAX_ENTRIES` 是硬上限：异常输入（例如每帧造一份带随机贴图的材质）不该让这里无限长。
## 到上限后**静默停止登记**（不报错、不抛异常）—— 这是缓存优化，失败只是慢一点，
## 不该影响玩法。

const MAX_ENTRIES := 96

static var _pinned: Dictionary = {}


## 登记一份材质。返回是否**新登记**（第一次见到这个变体）。
static func pin(material: Material) -> bool:
	var base := material as BaseMaterial3D
	if base == null:
		return false
	var key := signature(base)
	if _pinned.has(key):
		return false
	if _pinned.size() >= MAX_ENTRIES:
		return false
	_pinned[key] = base
	return true


## 变体签名。**只放会进 `MaterialKey` 的位**（也就是"改了要重编译"的那些）。
##
## 刻意排除：颜色、自发光颜色/能量、粗糙度、金属度、UV 偏移 —— 这些是 uniform，
## 换了不换变体，放进签名只会把同一份变体登记成很多份、白白吃掉 `MAX_ENTRIES`。
static func signature(base: BaseMaterial3D) -> String:
	return "%d|%d|%d|%d|%d|%d|%d|%d|%d|%d|%d|%d" % [
		base.transparency,
		base.shading_mode,
		1 if base.emission_enabled else 0,
		1 if base.emission_texture != null else 0,
		1 if base.albedo_texture != null else 0,
		1 if base.vertex_color_use_as_albedo else 0,
		base.billboard_mode,
		1 if base.no_depth_test else 0,
		base.depth_draw_mode,
		1 if base.disable_receive_shadows else 0,
		base.cull_mode,
		1 if base.normal_enabled else 0,
	]


## 已登记的变体数（探针读数用）。
static func pinned_count() -> int:
	return _pinned.size()


## 清空登记。**只给探针用** —— 用来复现"缓存丢了"的原始行为做反向对照。
static func clear_for_test() -> void:
	_pinned.clear()
