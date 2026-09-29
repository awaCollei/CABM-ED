@tool
extends Control

## 用代码绘制"日记本纸页"的细节：纸纹、红色装订边线、左侧书脊缝线，以及右侧的笔记本外壳。
## 不需要任何图片素材。纸页始终按展开宽度绘制，侧边栏靠平移收起，由屏幕边缘裁切。

@export var ruled_line_color: Color = Color(0.647059, 0.729412, 0.827451, 0.42)
@export var margin_line_color: Color = Color(0.803922, 0.403922, 0.403922, 0.55)
@export var margin_line_x: float = 30.0
@export var fiber_color: Color = Color(0.686275, 0.611765, 0.462745, 0.14)
@export var stitch_color: Color = Color(0.592157, 0.494118, 0.337255, 0.35)

## 右侧笔记本外壳
@export var cover_width: float = 30.0
@export var cover_color: Color = Color(0.290196, 0.215686, 0.168627)
@export var cover_highlight_color: Color = Color(0.482353, 0.376471, 0.294118)
@export var cover_stitch_color: Color = Color(0.760784, 0.658824, 0.517647, 0.50)

## 书签：从外壳边缘伸出来的一条缎带，作为展开/收起按钮的底衬
@export var bookmark_color: Color = Color(0.752941, 0.372549, 0.301961)
@export var bookmark_out_width: float = 26.0    # 伸出外壳的部分
@export var bookmark_in_width: float = 22.0     # 压在纸页上的部分
@export var bookmark_half_height: float = 52.0
@export var bookmark_notch: float = 15.0        # 底部的 V 形缺口

var bookmark_hovered: bool = false

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)

func _draw() -> void:
	var w: float = size.x
	var h: float = size.y
	if w <= 2.0 or h <= 2.0:
		return

	var paper_width: float = maxf(4.0, w - cover_width)

	_draw_margin_line(h)
	_draw_fibers(paper_width, h)
	_draw_spine(h)
	_draw_cover(w, h)
	_draw_bookmark(w, h)

func _draw_margin_line(h: float) -> void:
	draw_line(Vector2(margin_line_x, 0.0), Vector2(margin_line_x, h), margin_line_color, 1.0)

func _draw_fibers(paper_width: float, h: float) -> void:
	# 固定随机种子，保证纸纹稳定不闪烁
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260929
	var count: int = int(paper_width * h / 9000.0)
	for i in count:
		var p := Vector2(rng.randf() * paper_width, rng.randf() * h)
		var length: float = rng.randf_range(3.0, 10.0)
		var angle: float = rng.randf_range(-0.35, 0.35)
		draw_line(p, p + Vector2(cos(angle), sin(angle)) * length, fiber_color, 1.0)

func _draw_spine(h: float) -> void:
	# 左侧书脊：由外向内逐渐变淡的阴影
	for i in 12:
		var fade: float = 1.0 - float(i) / 12.0
		draw_rect(
			Rect2(float(i), 0.0, 1.0, h),
			Color(stitch_color.r, stitch_color.g, stitch_color.b, stitch_color.a * 0.30 * fade)
		)

	# 装订缝线（虚线段）
	var y: float = 8.0
	while y < h:
		draw_line(Vector2(7.0, y), Vector2(7.0, minf(y + 7.0, h)), stitch_color, 1.0)
		y += 16.0

func _draw_cover(w: float, h: float) -> void:
	var x0: float = w - cover_width

	# 皮革底色：左侧折痕处偏亮，向右逐渐加深
	for i in int(cover_width):
		var t: float = float(i) / cover_width
		var c: Color = cover_color.lerp(cover_highlight_color, (1.0 - t) * 0.40)
		draw_rect(Rect2(x0 + float(i), 0.0, 1.0, h), c)

	# 皮革纹理：固定的深色竖纹
	var rng := RandomNumberGenerator.new()
	rng.seed = 771103
	for i in 26:
		var sx: float = x0 + rng.randf_range(2.0, cover_width - 2.0)
		var sy: float = rng.randf_range(0.0, h * 0.6)
		draw_line(Vector2(sx, sy), Vector2(sx, minf(sy + rng.randf_range(40.0, 160.0), h)), Color(0, 0, 0, 0.06), 1.0)

	# 与纸页交界的暗影，让纸"陷"进外壳里
	for i in 5:
		draw_rect(Rect2(x0 - float(i) - 1.0, 0.0, 1.0, h), Color(0, 0, 0, 0.10 * (1.0 - float(i) / 5.0)))

	# 折痕高光
	draw_line(Vector2(x0 + 0.5, 0.0), Vector2(x0 + 0.5, h), Color(1, 1, 1, 0.16), 1.0)

	# 两道缝线
	var sx1: float = x0 + cover_width * 0.24
	var sx2: float = x0 + cover_width * 0.76
	var y: float = 6.0
	while y < h:
		draw_line(Vector2(sx1, y), Vector2(sx1, minf(y + 9.0, h)), cover_stitch_color, 1.0)
		draw_line(Vector2(sx2, y), Vector2(sx2, minf(y + 9.0, h)), cover_stitch_color, 1.0)
		y += 15.0

func _draw_bookmark(w: float, h: float) -> void:
	var left: float = w - bookmark_in_width
	var right: float = w + bookmark_out_width
	var mid_x: float = (left + right) * 0.5
	var top: float = h * 0.5 - bookmark_half_height
	var bottom: float = h * 0.5 + bookmark_half_height
	var notch: float = bookmark_notch

	var base: Color = bookmark_color
	if bookmark_hovered:
		base = bookmark_color.lightened(0.12)

	# 缎带轮廓：方正的顶部 + 底部 V 形缺口
	var outline := PackedVector2Array([
		Vector2(left, top),
		Vector2(right, top),
		Vector2(right, bottom),
		Vector2(mid_x, bottom - notch),
		Vector2(left, bottom),
	])

	# 投影
	var shadow := PackedVector2Array()
	for p in outline:
		shadow.append(p + Vector2(2.0, 3.0))
	draw_colored_polygon(shadow, Color(0.10, 0.07, 0.05, 0.30))

	# 底色（偏暗，作为右侧的厚度）
	draw_colored_polygon(outline, base.darkened(0.20))

	# 内层（亮面），露出右侧暗边和缺口内缘，形成立体感
	var inset := PackedVector2Array([
		Vector2(left + 3.0, top + 3.0),
		Vector2(right - 7.0, top + 3.0),
		Vector2(right - 7.0, bottom - 4.0),
		Vector2(mid_x, bottom - 4.0 - notch),
		Vector2(left + 3.0, bottom - 4.0),
	])
	draw_colored_polygon(inset, base)

	# 左侧高光
	draw_line(Vector2(left + 6.0, top + 8.0), Vector2(left + 6.0, bottom - 8.0), base.lightened(0.22), 1.0)
