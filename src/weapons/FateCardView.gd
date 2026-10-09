extends RefCounted
class_name FateCardView

## FateCardView — 命运卡的**图卡呈现层**（只负责表现，不碰任何玩法数据）
##
## 卡面取自 `assets/art/ui/fate_cards/ui_fate_card_<id>_v001.png`，
## 卡背统一取 `ui_fate_card_back_v001.png`。
##
## 缺图容错：`art_for()` 在找不到对应美术时返回 null，调用方据此回退到
## 程序绘制的卡面，保证补图完成前功能与画面都不崩。补图落地后无需改代码即自动生效。
##
## 逆位规则：**卡面图案绕中心旋转 180°，卡下功能文字保持正向**。
## 文字层不参与旋转，因此直接读 `card.short_description` 即为该方位的效果描述。

const ART_DIR := "res://assets/art/ui/fate_cards"
const ART_FMT := ART_DIR + "/ui_fate_card_%s_v001.png"
const BACK_PATH := ART_DIR + "/ui_fate_card_back_v001.png"

## 贴图缓存：stable_card_id -> Texture2D（null 表示确认无图，避免反复探测磁盘）
static var _art_cache: Dictionary = {}
static var _back_texture: Texture2D = null
static var _back_probed := false


## 卡面贴图；没有对应美术时返回 null
static func art_for(card: FateCard) -> Texture2D:
	if card == null:
		return null
	var key := card.get_stable_card_id()
	if _art_cache.has(key):
		return _art_cache[key]
	var tex: Texture2D = null
	if not key.is_empty():
		var path := ART_FMT % key.trim_prefix("fate_")
		if ResourceLoader.exists(path):
			tex = load(path) as Texture2D
	_art_cache[key] = tex
	return tex


## 所有命运卡共用的卡背贴图
static func back_texture() -> Texture2D:
	if not _back_probed:
		_back_probed = true
		if ResourceLoader.exists(BACK_PATH):
			_back_texture = load(BACK_PATH) as Texture2D
	return _back_texture


static func has_art(card: FateCard) -> bool:
	return art_for(card) != null


## 卡下文字：作用域图标 + 功能短说明；武器卡可追加当前枪械命运槽信息。
static func caption_text(card: FateCard, target_detail := "") -> String:
	if card == null:
		return ""
	var effect_text := card.short_description
	if effect_text.is_empty():
		effect_text = card.description
	var lines := ["%s  %s" % [FateCard.scope_symbol(card.scope), effect_text]]
	if not target_detail.is_empty():
		lines.append(target_detail)
	return "\n".join(lines)


## 铺一层等比居中的贴图到 host，返回该层。
## reversed = true 时图案绕中心旋转 180°（文字层不在此层内，故不受影响）。
static func build_art_layer(
	host: Control, tex: Texture2D, reversed: bool, layer_name: String
) -> TextureRect:
	var rect := TextureRect.new()
	rect.name = layer_name
	rect.texture = tex
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	host.add_child(rect)
	# 枢轴同步用 lambda 而不是静态 Callable：静态方法的 Callable 在 bind 到不同
	# 控件时会被引擎判为「同一连接」而拒绝重复连接，导致只有首帧设对了枢轴，
	# 之后布局变化仍绕旧轴心旋转（表现为逆位卡面飞出容器）。
	var sync := func() -> void:
		if is_instance_valid(rect):
			rect.pivot_offset = rect.size * 0.5
	sync.call()
	rect.resized.connect(sync)
	host.resized.connect(sync)
	if reversed:
		rect.rotation = PI
	return rect


## 卡背层（同一张背图，逆位与否都相同）
static func build_back_layer(host: Control, layer_name := "TarotCardBack") -> TextureRect:
	var tex := back_texture()
	if tex == null:
		return null
	var rect := build_art_layer(host, tex, false, layer_name)
	return rect


## 翻面揭示：显示卡面层、隐藏卡背层；逆位时把**卡面图案**绕中心倒置。
## 只对贴图层做倒置——卡下功能文字不在这一层里，因此天然保持正向可读。
static func reveal(face: Control, back: Control, is_reversed: bool) -> void:
	if face != null and is_instance_valid(face):
		if face is TextureRect:
			face.pivot_offset = face.size * 0.5
			face.rotation = PI if is_reversed else 0.0
		face.visible = true
	if back != null and is_instance_valid(back):
		back.visible = false


## 卡下功能文字（统一排版：居中、可换行、不参与卡面旋转）
static func build_caption(card: FateCard, font_size: int, min_width: float, target_detail := "") -> Label:
	var label := Label.new()
	label.name = "FateFunctionCaption"
	label.text = caption_text(card, target_detail)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(min_width, 0)
	label.add_theme_color_override("font_color", Color(0.87, 0.91, 0.95))
	label.add_theme_font_size_override("font_size", font_size)
	return label
