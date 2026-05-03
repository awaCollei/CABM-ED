extends Control

@onready var background: TextureRect = $Background
@onready var time_label: Label = $TimeLabel
@onready var open_map_button: Button = $OpenMapButton

var outdoor_id: String = "beach"
var current_time_id: String = ""

func _ready():
	_resolve_outdoor_id()
	_update_by_system_time()
	open_map_button.pressed.connect(_on_open_map_pressed)
	
	var refresh_timer = Timer.new()
	refresh_timer.wait_time = 30.0
	refresh_timer.autostart = true
	refresh_timer.timeout.connect(_update_by_system_time)
	add_child(refresh_timer)
	# 执行淡入动画
	if has_node("/root/SceneTransition"):
		get_node("/root/SceneTransition").fade_in()

func _resolve_outdoor_id():
	if not has_node("/root/SaveManager"):
		return
	var sm = get_node("/root/SaveManager")
	if sm.has_meta("outdoor_current_id"):
		outdoor_id = str(sm.get_meta("outdoor_current_id"))
	if sm.has_meta("outdoor_target_id"):
		outdoor_id = str(sm.get_meta("outdoor_target_id"))
	sm.set_meta("outdoor_current_id", outdoor_id)

func _update_by_system_time():
	var time_dict = Time.get_time_dict_from_system()
	var hour = int(time_dict.get("hour", 12))
	var time_id = TimeUtil.get_time_period_from_hour(hour)
	if time_id != current_time_id:
		current_time_id = time_id
		_apply_background()
	_update_time_label(hour)

func _apply_background():
	var time_path = "res://assets/images/scenes_outdoor/%s/%s.png" % [outdoor_id, current_time_id]
	var fallback_path = "res://assets/images/scenes_outdoor/%s/day.png" % outdoor_id
	var load_path = time_path if ResourceLoader.exists(time_path) else fallback_path
	if ResourceLoader.exists(load_path):
		background.texture = load(load_path)
	else:
		background.texture = null

func _update_time_label(hour: int):
	var time_name := TimeUtil.get_time_period(hour)
	time_label.text = "%02d:00  %s" % [hour, time_name]

func _on_open_map_pressed():
	if has_node("/root/SaveManager"):
		var sm = get_node("/root/SaveManager")
		sm.set_meta("open_map_on_load", true)
		sm.set_meta("map_origin", "outdoor")
		sm.set_meta("outdoor_current_id", outdoor_id)
	if has_node("/root/SceneTransition"):
		get_node("/root/SceneTransition").change_scene_with_fade("res://scripts/main.tscn")
	else:
		get_tree().change_scene_to_file("res://scripts/main.tscn")
