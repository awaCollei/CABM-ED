extends Control

## 求签面板

signal omikuji_closed

@onready var mask: ColorRect = $Mask
@onready var panel: PanelContainer = $Panel
@onready var omikuji_bako: TextureRect = $Panel/VBox/OmikujiBako
@onready var fortune_container: VBoxContainer = $Panel/VBox/FortuneContainer
@onready var fortune_name: Label = $Panel/VBox/FortuneContainer/FortuneName
@onready var fortune_description: RichTextLabel = $Panel/VBox/FortuneContainer/FortuneDescription
@onready var fortune_advice: RichTextLabel = $Panel/VBox/FortuneContainer/FortuneAdvice
@onready var close_button: Button = $Panel/VBox/CloseButton
@onready var draw_button: Button = $Panel/VBox/DrawButton
@onready var hint_label: Label = $Panel/VBox/HintLabel

var outdoor_id: String = ""
var is_drawn: bool = false
var current_fortune: Dictionary = {}
var rng := RandomNumberGenerator.new()

const OMIKUJI_SCENE = preload("res://scenes/omikuji_panel.tscn")

# 抽签前的签筒
const OMIKUJI_BAKO_TEXTURE = preload("res://assets/images/outdoor/omikuji_bako.png")

# 抽到签后的图片（你自己的签图）
const OMIKUJI_RESULT_TEXTURE = preload("res://assets/images/outdoor/omikuji.png")

func _ready():
	rng.randomize()
	_setup_ui()
	_connect_signals()

	# 初始状态
	omikuji_bako.texture = OMIKUJI_BAKO_TEXTURE
	fortune_container.visible = false
	hint_label.visible = false

func _setup_ui():
	mask.gui_input.connect(_on_mask_input)
	close_button.pressed.connect(_on_close_pressed)
	draw_button.pressed.connect(_on_draw_pressed)

	# 点击签图
	omikuji_bako.gui_input.connect(_on_omikuji_bako_clicked)

func _connect_signals():
	pass

func show_panel(p_outdoor_id: String):
	outdoor_id = p_outdoor_id
	visible = true

	# outdoor_id 设置后再读取存档
	_load_saved_fortune()

	_fade_in()

func _fade_in():
	modulate = Color(1, 1, 1, 0)
	var tween = create_tween()
	tween.tween_property(self, "modulate:a", 1.0, 0.2)

func _load_saved_fortune():
	# 检查今天是否已经抽过签
	if not has_node("/root/SaveManager"):
		_show_draw_button()
		return
	
	var sm = get_node("/root/SaveManager")
	var today = Time.get_datetime_string_from_system().split("T")[0]
	var saved_date = sm.get_omikuji_date()
	var saved_outdoor = sm.get_omikuji_outdoor_id()
	
	if saved_date == today and saved_outdoor == outdoor_id:
		# 今天已经抽过了，显示结果
		var fortune_id = sm.get_omikuji_fortune_id()
		if fortune_id != "":
			_show_existing_fortune(fortune_id)
		else:
			_show_draw_button()
	else:
		_show_draw_button()

func _show_draw_button():
	is_drawn = false
	draw_button.visible = true
	fortune_container.visible = false

func _show_existing_fortune(fortune_id: String):
	var fortune = _get_fortune_by_id(fortune_id)
	if fortune.is_empty():
		_show_draw_button()
		return
	
	is_drawn = true
	current_fortune = fortune
	draw_button.visible = false
	fortune_container.visible = true
	fortune_name.text = fortune.get("name", "")
	fortune_description.text = fortune.get("description", "")
	fortune_advice.text = fortune.get("advice", "")
	
	# 显示签筒（带结果）
	omikuji_bako.texture = load("res://assets/images/outdoor/omikuji.png")

func _on_mask_input(event: InputEvent):
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_on_close_pressed()

func _on_close_pressed():
	_fade_out()
	await get_tree().create_timer(0.2).timeout
	queue_free()
	omikuji_closed.emit()

func _on_draw_pressed():
	# 摇晃动画
	_play_shake_animation()
	await get_tree().create_timer(1.2).timeout
	_draw_fortune()

func _play_shake_animation():
	var tween = create_tween()
	var original_pos = omikuji_bako.position
	
	# 摇晃动画
	for i in range(20):
		var offset_x = rng.randf_range(-15, 15)
		var offset_y = rng.randf_range(-5, 5)
		var target_pos = original_pos + Vector2(offset_x, offset_y)
		tween.tween_property(omikuji_bako, "position", target_pos, 0.05)
	
	# 回位
	tween.tween_property(omikuji_bako, "position", original_pos, 0.1)

func _draw_fortune():
	# 切换到抽签结果图片
	omikuji_bako.texture = load("res://assets/images/outdoor/omikuji.png")
	
	# 随机抽取一个签
	var fortune = _get_random_fortune()
	current_fortune = fortune
	is_drawn = true
	
	# 保存结果
	_save_fortune(fortune)
	
	# 显示结果
	draw_button.visible = false
	fortune_container.visible = true
	
	# 淡入显示结果
	fortune_container.modulate = Color(1, 1, 1, 0)
	var tween = create_tween()
	tween.tween_property(fortune_container, "modulate:a", 1.0, 0.3)
	
	fortune_name.text = fortune.get("name", "")
	fortune_description.text = fortune.get("description", "")
	fortune_advice.text = fortune.get("advice", "")

func _get_random_fortune() -> Dictionary:
	var fortunes = _load_fortunes()
	if fortunes.is_empty():
		return {}
	
	var index = rng.randi_range(0, fortunes.size() - 1)
	return fortunes[index]

func _get_fortune_by_id(fortune_id: String) -> Dictionary:
	var fortunes = _load_fortunes()
	for f in fortunes:
		if f.get("id", "") == fortune_id:
			return f
	return {}

func _load_fortunes() -> Array:
	var config_path = "res://config/omikuji_fortunes.json"
	if not FileAccess.file_exists(config_path):
		return []
	
	var f = FileAccess.open(config_path, FileAccess.READ)
	if f == null:
		return []
	
	var js = f.get_as_text()
	f.close()
	
	var j = JSON.new()
	if j.parse(js) != OK:
		return []
	
	return j.data.get("fortunes", [])

func _save_fortune(fortune: Dictionary):
	if not has_node("/root/SaveManager"):
		return
	
	var sm = get_node("/root/SaveManager")
	var today = Time.get_datetime_string_from_system().split("T")[0]
	sm.set_omikuji_data(today, outdoor_id, fortune.get("id", ""))

func _fade_out():
	var tween = create_tween()
	tween.tween_property(self, "modulate:a", 0.0, 0.2)

func _on_omikuji_bako_clicked(event: InputEvent):
	if not is_drawn:
		return

	if event is InputEventMouseButton \
	and event.button_index == MOUSE_BUTTON_LEFT \
	and event.pressed:

		# 已经显示结果时不再处理
		if fortune_container.visible:
			return

		# 隐藏签图
		omikuji_bako.visible = false
		hint_label.visible = false

		# 显示文字
		fortune_container.visible = true
		fortune_container.modulate = Color(1, 1, 1, 0)

		var tween = create_tween()
		tween.tween_property(
			fortune_container,
			"modulate:a",
			1.0,
			0.25
		)
		
static func instantiate() -> Control:
	return OMIKUJI_SCENE.instantiate()