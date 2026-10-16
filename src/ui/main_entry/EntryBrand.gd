extends Control
## 启动页品牌图形（棱镜线框版）：左侧「弹壳风暴 2」白线字标 + 贯穿细线。
## 全部用 Control._draw 自绘（中文使用默认系统字体，无需外部字体资源）。
##
## 旧版（斜切 + 青色/品红霓虹发光 + 呼吸脉冲）按规范 §11 反面清单移除：
## 棱镜语言零辉光、零渐变，字标只保留近白正文 + 一条天蓝强调（语义色）与结构细线。

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)


func _draw() -> void:
	var h := size.y
	if h <= 4.0:
		return
	var font := UIStyleFactory.make_prism_font(4)
	if font == null:
		font = _font()
	if font == null:
		return
	var base := h * 0.44
	var title := "弹壳风暴"
	var two := "2"
	var title_w := font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, int(base)).x
	var start_x := 12.0
	var baseline := h * 0.50
	# 字标：近白正文 + 天蓝强调的「2」（唯一彩色，起强调作用，不作装饰铺陈）。
	draw_string(
		font, Vector2(start_x, baseline), title,
		HORIZONTAL_ALIGNMENT_LEFT, -1, int(base), UIPalette.PRISM_TEXT
	)
	draw_string(
		font, Vector2(start_x + title_w + base * 0.18, baseline), two,
		HORIZONTAL_ALIGNMENT_LEFT, -1, int(base), UIPalette.PRISM_ACCENT
	)
	# 结构细线：字标下方一条贯穿白线 + 一条更短的次级弱线。
	var rule_y := baseline + base * 0.24
	var rule_w := size.x - start_x - 6.0
	draw_rect(Rect2(start_x, rule_y, rule_w, 1.0), Color(1.0, 1.0, 1.0, 0.30), true)
	draw_rect(Rect2(start_x, rule_y + 7.0, rule_w * 0.40, 1.0), Color(1.0, 1.0, 1.0, 0.14), true)
	# 左侧 2px 竖线：与常驻 HUD 的引导竖线同构，表明"这一块属于品牌区"。
	draw_rect(Rect2(start_x - 9.0, h * 0.10, 2.0, h * 0.34), Color(1.0, 1.0, 1.0, 0.55), true)


func _font() -> Font:
	var f := get_theme_font("font")
	if f == null:
		f = ThemeDB.fallback_font
	return f
