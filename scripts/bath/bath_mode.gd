extends Control

# 洗澡模式（最简示例）
# 显示洗澡背景图片，循环播放水声音频，左上角提供退出按钮

const BATH_BACKGROUND := "res://assets/images/bath/1.png"
const BATH_AUDIO := "res://assets/audio/bath/water.mp3"

@onready var background_image: TextureRect = $BackgroundImage
@onready var water_player: AudioStreamPlayer = $WaterPlayer
@onready var exit_button: Button = $ExitButton


func _ready():
	# 设置背景图片
	var texture = load(BATH_BACKGROUND)
	if texture:
		background_image.texture = texture
	else:
		push_error("无法加载洗澡背景图片: " + BATH_BACKGROUND)

	# 循环播放水声
	var stream = load(BATH_AUDIO)
	if stream:
		stream.loop = true
		water_player.stream = stream
		water_player.play()
	else:
		push_error("无法加载洗澡音频: " + BATH_AUDIO)

	# 连接退出按钮
	exit_button.pressed.connect(_on_exit_button_pressed)

	# 淡入
	if has_node("/root/SceneTransition"):
		var transition = get_node("/root/SceneTransition")
		await transition.fade_in()

	print("洗澡模式已启动")


func _on_exit_button_pressed():
	"""退出洗澡模式，返回主场景"""
	print("退出洗澡模式")

	if water_player:
		water_player.stop()

	if has_node("/root/SceneTransition"):
		var transition = get_node("/root/SceneTransition")
		await transition.change_scene_with_fade("res://scripts/main.tscn")
	else:
		get_tree().change_scene_to_file("res://scripts/main.tscn")