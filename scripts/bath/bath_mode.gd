extends Control

# 洗澡模式：背景 + 水声 + 退出 + 水雾开关
# 水雾 = 多个"云团"，每团由多个径向渐变粒子组成

const BATH_BACKGROUND := "res://assets/images/bath/1.png"
const BATH_AUDIO := "res://assets/audio/bath/water.mp3"

# ============ 水雾参数（硬编码） ============
const CLUSTER_COUNT := 15              # 云团数量
const PUFFS_PER_CLUSTER_MIN := 8      # 每团最少粒子
const PUFFS_PER_CLUSTER_MAX := 12     # 每团最多粒子
const CLUSTER_SPREAD := 130.0         # 团内粒子分布半径
const PUFF_RADIUS_MIN := 60.0         # 粒子最小半径
const PUFF_RADIUS_MAX := 140.0        # 粒子最大半径
const PUFF_ALPHA_MIN := 0.06          # 粒子最小透明度
const PUFF_ALPHA_MAX := 0.20          # 粒子最大透明度
const CLUSTER_DRIFT := 50.0           # 云团整体漂移幅度
const PUFF_DRIFT := 14.0              # 粒子局部抖动幅度
const CLUSTER_DRIFT_SPEED_MIN := 0.10 # 云团漂移速度
const CLUSTER_DRIFT_SPEED_MAX := 0.25
const PUFF_DRIFT_SPEED_MIN := 0.4
const PUFF_DRIFT_SPEED_MAX := 1.2

@onready var background_image: TextureRect = $BackgroundImage
@onready var water_player: AudioStreamPlayer = $WaterPlayer
@onready var exit_button: Button = $ExitButton
@onready var fog_toggle: CheckButton = $FogToggle
@onready var fog_texture: TextureRect = $BackgroundImage/Fog
@onready var fog_container: Control = $BackgroundImage/FogContainer

var fog_enabled: bool = true
var fog_clusters: Array = []           # 云团数组


func _ready():
	var texture = load(BATH_BACKGROUND)
	if texture:
		background_image.texture = texture
	else:
		push_error("无法加载洗澡背景图片: " + BATH_BACKGROUND)

	var stream = load(BATH_AUDIO)
	if stream:
		stream.loop = true
		water_player.stream = stream
		water_player.play()
	else:
		push_error("无法加载洗澡音频: " + BATH_AUDIO)

	exit_button.pressed.connect(_on_exit_button_pressed)
	fog_toggle.toggled.connect(_on_fog_toggled)

	_init_fog_clusters()

	if has_node("/root/SceneTransition"):
		var transition = get_node("/root/SceneTransition")
		await transition.fade_in()

	print("洗澡模式已启动")


func _init_fog_clusters():
	"""初始化多个云团，每个云团由若干粒子组成"""
	await get_tree().process_frame

	var viewport_size = get_viewport_rect().size
	var center = viewport_size / 2.0

	fog_clusters.clear()

	for c in range(CLUSTER_COUNT):
		# 云团基准位置：全屏随机
		var cluster_base = Vector2(
			randf_range(0, viewport_size.x),
			randf_range(0, viewport_size.y)
		)

		var puffs: Array = []
		var puff_count = randi_range(PUFFS_PER_CLUSTER_MIN, PUFFS_PER_CLUSTER_MAX)

		for i in range(puff_count):
			# 团内粒子：围绕云团中心随机分布（高斯感：用两次随机均值）
			var angle = randf_range(0.0, TAU)
			var dist = randf_range(0.0, CLUSTER_SPREAD) * sqrt(randf())  # sqrt 让分布更均匀
			var local_offset = Vector2(cos(angle), sin(angle)) * dist

			var puff = {
				"local_offset": local_offset,
				"radius": randf_range(PUFF_RADIUS_MIN, PUFF_RADIUS_MAX),
				"alpha": randf_range(PUFF_ALPHA_MIN, PUFF_ALPHA_MAX),
				# 粒子自身抖动
				"drift_dir": Vector2(randf_range(-1, 1), randf_range(-1, 1)).normalized(),
				"drift_phase": randf_range(0.0, TAU),
				"drift_speed": randf_range(PUFF_DRIFT_SPEED_MIN, PUFF_DRIFT_SPEED_MAX),
			}
			puffs.append(puff)

		var cluster = {
			"base_pos": cluster_base,
			"puffs": puffs,
			# 云团整体漂移
			"drift_dir": Vector2(randf_range(-1, 1), randf_range(-1, 1)).normalized(),
			"drift_phase": randf_range(0.0, TAU),
			"drift_speed": randf_range(CLUSTER_DRIFT_SPEED_MIN, CLUSTER_DRIFT_SPEED_MAX),
		}
		fog_clusters.append(cluster)

	fog_container.queue_redraw()


func _process(_delta):
	if fog_enabled and fog_container.visible:
		fog_container.queue_redraw()


func _on_fog_toggled(pressed: bool):
	fog_enabled = pressed
	fog_container.visible = pressed
	fog_texture.visible = pressed
	print("水雾: ", "开启" if pressed else "关闭")


func _on_exit_button_pressed():
	print("退出洗澡模式")
	if water_player:
		water_player.stop()
	if has_node("/root/SceneTransition"):
		var transition = get_node("/root/SceneTransition")
		await transition.change_scene_with_fade("res://scripts/main.tscn")
	else:
		get_tree().change_scene_to_file("res://scripts/main.tscn")