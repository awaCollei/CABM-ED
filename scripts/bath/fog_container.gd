extends Control

# 水雾渲染：多个云团，每团多个径向渐变粒子
# 用 GradientTexture2D 做径向渐变，天然平滑无分层

@onready var bath_mode = get_parent().get_parent()

var fog_texture: GradientTexture2D


func _ready():
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	fog_texture = _make_fog_texture()


func _make_fog_texture() -> GradientTexture2D:
	"""生成一张径向渐变贴图，模拟单个烟雾粒子的柔软边缘"""
	var gradient = Gradient.new()
	# 中心到边缘的多段渐变，比线性更柔和
	gradient.offsets = PackedFloat32Array([0.0, 0.25, 0.5, 0.75, 1.0])
	gradient.colors = PackedColorArray([
		Color(1, 1, 1, 1.0),
		Color(1, 1, 1, 0.85),
		Color(1, 1, 1, 0.55),
		Color(1, 1, 1, 0.22),
		Color(1, 1, 1, 0.0),
	])

	var tex = GradientTexture2D.new()
	tex.gradient = gradient
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = 128
	tex.height = 128
	return tex


func _draw():
	var clusters = bath_mode.fog_clusters
	if clusters.is_empty():
		return

	var time = Time.get_ticks_msec() / 1000.0

	for cluster in clusters:
		# 云团整体漂移
		var cluster_offset = cluster.drift_dir * sin(time * cluster.drift_speed + cluster.drift_phase) * bath_mode.CLUSTER_DRIFT
		var cluster_pos = cluster.base_pos + cluster_offset

		for puff in cluster.puffs:
			# 粒子局部抖动
			var puff_offset = puff.drift_dir * sin(time * puff.drift_speed + puff.drift_phase) * bath_mode.PUFF_DRIFT
			var pos = cluster_pos + puff.local_offset + puff_offset
			var r = puff.radius
			var a = puff.alpha

			# 画一张径向渐变贴图（每个粒子一张，天然平滑）
			draw_texture_rect(
				fog_texture,
				Rect2(pos - Vector2(r, r), Vector2(r * 2, r * 2)),
				false,
				Color(1, 1, 1, a)
			)