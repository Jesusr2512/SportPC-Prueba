@tool
extends Node3D

const AVATAR_SCENE := preload("res://scenes/AvatarFighter.tscn")
const DojoStageScript := preload("res://scripts/game/DojoStage.gd")

@onready var cam: Camera3D = $Camera3D
@onready var preview_world: Node3D = $PreviewWorld
@onready var mobile_card: PanelContainer = $UI/Margin/Root/MobileCard
@onready var controllers_card: PanelContainer = $UI/Margin/Root/ControllersCard
@onready var btn_calibration: Button = $UI/Margin/Root/ActionsCard/BtnCalibration
@onready var btn_chambara_1p: Button = $UI/Margin/Root/ActionsCard/RowAI/BtnChambara1P
@onready var btn_chambara_2p: Button = $UI/Margin/Root/ActionsCard/BtnChambara2P
@onready var p1_label: Label = $UI/Margin/Root/ControllersCard/Grid/P1Info
@onready var p2_label: Label = $UI/Margin/Root/ControllersCard/Grid/P2Info
@onready var url_label: Label = $UI/Margin/Root/MobileCard/HBox/UrlLabel
@onready var device_picker_p1: OptionButton = $UI/Margin/Root/ControllersCard/Grid/P1Select
@onready var device_picker_p2: OptionButton = $UI/Margin/Root/ControllersCard/Grid/P2Select
@onready var stage_picker: OptionButton = $UI/Margin/Root/ActionsCard/RowOptions/StageSelect
@onready var style_picker: OptionButton = $UI/Margin/Root/ActionsCard/RowOptions/StyleSelect
@onready var ai_picker: OptionButton = $UI/Margin/Root/ActionsCard/RowAI/AiDifficulty

var _stage_refs: Dictionary = {}
var _preview_f1: AvatarFighter
var _preview_f2: AvatarFighter
var _cam_angle: float = 0.0
var _shader_time: float = 0.0


func _ready() -> void:
	_build_3d_preview_stage()
	_apply_menu_theme()
	if Engine.is_editor_hint():
		return

	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	Engine.time_scale = 1.0
	var hub := get_node_or_null("/root/MotionHub")
	if hub != null:
		hub.mouse_combat_enabled = false
		hub.slots_changed.connect(_refresh_devices)
		hub.recenter_slot(0)

	ai_picker.clear()
	ai_picker.add_item("IA: Novato", 0)
	ai_picker.add_item("IA: Pro", 1)
	ai_picker.add_item("IA: Campeón", 2)
	ai_picker.add_item("IA: Leyenda", 3)
	ai_picker.selected = clampi(GameConfig.ai_difficulty, 0, 3)

	stage_picker.clear()
	stage_picker.add_item("Arena: Isla del Sol", GameConfig.ArenaStage.SUN_ISLAND)
	stage_picker.add_item("Arena: Puente Volcánico", GameConfig.ArenaStage.VOLCANIC_BRIDGE)
	stage_picker.add_item("Arena: Santuario Flotante", GameConfig.ArenaStage.SKY_SANCTUARY)
	stage_picker.selected = clampi(GameConfig.arena_stage, 0, 2)

	style_picker.clear()
	style_picker.add_item("Estilo: Chambara Clásico", GameConfig.CombatStyle.CLASSIC)
	style_picker.add_item("Estilo: Espadas Gemelas", GameConfig.CombatStyle.TWIN_BLADES)
	style_picker.selected = clampi(GameConfig.combat_style, 0, 1)

	_refresh_devices()
	_refresh_url()


func _build_3d_preview_stage() -> void:
	_stage_refs = DojoStageScript.build_stage(preview_world, GameConfig.arena_stage, 3.55)

	var use_twins := GameConfig.combat_style == GameConfig.CombatStyle.TWIN_BLADES
	_preview_f1 = AVATAR_SCENE.instantiate() as AvatarFighter
	_preview_f1.fighter_name = "Jugador 1"
	_preview_f1.team_color = Color(0.05, 0.78, 0.92)
	preview_world.add_child(_preview_f1)
	_preview_f1.configure_stage(GameConfig.arena_stage, 3.55)
	_preview_f1.set_twin_blades(use_twins)
	_preview_f1.reset_for_round(Vector3(0.0, 0.0, 0.85), Vector2(0.0, -1.0))

	_preview_f2 = AVATAR_SCENE.instantiate() as AvatarFighter
	_preview_f2.fighter_name = "IA"
	_preview_f2.team_color = Color(0.98, 0.44, 0.52)
	preview_world.add_child(_preview_f2)
	_preview_f2.configure_stage(GameConfig.arena_stage, 3.55)
	_preview_f2.set_twin_blades(use_twins)
	_preview_f2.reset_for_round(Vector3(0.0, 0.0, -0.85), Vector2(0.0, 1.0))


func _apply_menu_theme() -> void:
	var card_style := StyleBoxFlat.new()
	card_style.bg_color = Color(0.05, 0.10, 0.20, 0.72)
	card_style.border_color = Color(0.24, 0.74, 0.96, 0.50)
	card_style.set_border_width_all(2)
	card_style.set_corner_radius_all(14)
	card_style.set_content_margin_all(12)
	mobile_card.add_theme_stylebox_override("panel", card_style)
	controllers_card.add_theme_stylebox_override("panel", card_style)

	var primary_btn := StyleBoxFlat.new()
	primary_btn.bg_color = Color(0.06, 0.56, 0.78, 0.90)
	primary_btn.border_color = Color(0.45, 0.90, 1.0, 0.9)
	primary_btn.set_border_width_all(2)
	primary_btn.set_corner_radius_all(14)
	var primary_hover := primary_btn.duplicate() as StyleBoxFlat
	primary_hover.bg_color = Color(0.10, 0.66, 0.88, 0.96)
	btn_chambara_1p.add_theme_stylebox_override("normal", primary_btn)
	btn_chambara_1p.add_theme_stylebox_override("hover", primary_hover)

	var sec_btn := StyleBoxFlat.new()
	sec_btn.bg_color = Color(0.10, 0.18, 0.32, 0.84)
	sec_btn.border_color = Color(0.35, 0.62, 0.88, 0.60)
	sec_btn.set_border_width_all(2)
	sec_btn.set_corner_radius_all(14)
	var sec_hover := sec_btn.duplicate() as StyleBoxFlat
	sec_hover.bg_color = Color(0.16, 0.26, 0.44, 0.92)
	btn_calibration.add_theme_stylebox_override("normal", sec_btn)
	btn_calibration.add_theme_stylebox_override("hover", sec_hover)
	btn_chambara_2p.add_theme_stylebox_override("normal", sec_btn)
	btn_chambara_2p.add_theme_stylebox_override("hover", sec_hover)


func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return

	_shader_time += delta
	var wmat: ShaderMaterial = _stage_refs.get("water_mat")
	if wmat != null:
		wmat.set_shader_parameter("u_time", _shader_time)

	_cam_angle += delta * 0.22
	var cam_radius := 4.1
	cam.position = Vector3(sin(_cam_angle) * cam_radius, 2.0, cos(_cam_angle) * cam_radius)
	cam.look_at(Vector3(0.0, 0.95, 0.0), Vector3.UP)

	var s1: MotionHub.PlayerSlot = MotionHub.slots[0]
	if _preview_f1 and _preview_f2:
		_preview_f1.blade_orientation = s1.fusion.orientation
		_preview_f1.blade_roll_rad = s1.fusion.get_snapped_blade_roll_rad()
		_preview_f1.is_guarding = s1.is_guarding
		if _preview_f1.state == AvatarFighter.State.NORMAL and s1.fusion.just_swung and s1.source_type != MotionHub.SourceType.MOUSE:
			_preview_f1.trigger_slash(s1.fusion.last_slash_dir, s1.fusion.last_slash_power, s1.fusion.last_slash_type)
		_preview_f1.step_fighter(delta, s1.move_axis, _preview_f2.position, true)
		var p1_xz := Vector2(_preview_f1.position.x, _preview_f1.position.z)
		if p1_xz.length() > 2.2:
			p1_xz = p1_xz.normalized() * 2.2
			_preview_f1.position.x = p1_xz.x
			_preview_f1.position.z = p1_xz.y

		_preview_f2.is_guarding = true
		_preview_f2.blade_roll_rad = sin(_cam_angle * 1.4) * 0.45
		_preview_f2.step_fighter(delta, Vector2.ZERO, _preview_f1.position, true)

	if s1.has_motion_sensors:
		var guard_tag := " | BLOQUEO" if s1.is_guarding else ""
		p1_label.text = "Jugador 1 (Azul):  %s  [6-Axis En Vivo: %.0f°%s]" % [
			s1.device_name,
			s1.fusion.get_blade_angle_deg(),
			guard_tag
		]


func _refresh_url() -> void:
	if MotionHub.mobile_server and MotionHub.mobile_server.is_running:
		var urls := MotionHub.mobile_server.get_all_urls()
		if urls.is_empty():
			url_label.text = "Móvil Wi-Fi activo: https://localhost:%d" % MotionHub.mobile_server.active_port
		else:
			url_label.text = "Abre en tu móvil (mismo Wi-Fi):  " + "   |   ".join(urls)
	else:
		url_label.text = "Servidor móvil HTTPS no disponible en puertos 8443-8450"


func _refresh_devices() -> void:
	var s1: MotionHub.PlayerSlot = MotionHub.slots[0]
	var s2: MotionHub.PlayerSlot = MotionHub.slots[1]
	p1_label.text = "Jugador 1 (Azul):  %s%s" % [
		s1.device_name,
		"  [6-Axis]" if s1.has_motion_sensors else "  [Ratón/Botones]"
	]
	p2_label.text = "Jugador 2 (Coral):  %s%s" % [
		s2.device_name,
		"  [6-Axis]" if s2.has_motion_sensors else ""
	]

	_populate_picker(device_picker_p1, 0)
	_populate_picker(device_picker_p2, 1)


func _populate_picker(picker: OptionButton, slot_idx: int) -> void:
	picker.clear()
	picker.add_item("Automático / Actual", -10)
	picker.add_item("Ratón + Teclado", -1)
	for gp in MotionHub.get_available_gamepads():
		var tag := " (6-Axis)" if gp["motion"] else " (Sin Gyro)"
		picker.add_item("Mando #%d: %s%s" % [gp["id"], gp["name"], tag], gp["id"])
	if MotionHub.has_method("get_connected_mobile_peers"):
		for pid in MotionHub.get_connected_mobile_peers():
			picker.add_item("Móvil Wi-Fi #%d (6-Axis)" % pid, 1000 + pid)
	picker.selected = 0
	picker.set_meta("slot_idx", slot_idx)


func _on_p1_select_item_selected(index: int) -> void:
	_apply_picker(device_picker_p1, index, 0)


func _on_p2_select_item_selected(index: int) -> void:
	_apply_picker(device_picker_p2, index, 1)


func _apply_picker(picker: OptionButton, index: int, slot_idx: int) -> void:
	var id := picker.get_item_id(index)
	if id == -1:
		MotionHub.assign_mouse(slot_idx)
	elif id >= 1000 and MotionHub.has_method("assign_mobile"):
		MotionHub.assign_mobile(slot_idx, id - 1000)
	elif id >= 0:
		MotionHub.assign_gamepad(slot_idx, id)


func _on_stage_select_item_selected(index: int) -> void:
	GameConfig.arena_stage = stage_picker.get_item_id(index)
	_build_3d_preview_stage()


func _on_style_select_item_selected(index: int) -> void:
	GameConfig.combat_style = style_picker.get_item_id(index)
	if _preview_f1 and _preview_f2:
		var use_twins := GameConfig.combat_style == GameConfig.CombatStyle.TWIN_BLADES
		_preview_f1.set_twin_blades(use_twins)
		_preview_f2.set_twin_blades(use_twins)


func _on_copy_url_pressed() -> void:
	DisplayServer.clipboard_set(MotionHub.mobile_server.get_primary_url())


func _on_btn_calibration_pressed() -> void:
	var sfx := get_node_or_null("/root/SoundFX")
	if sfx != null:
		sfx.play("bell", 1.15, -8.0)
	get_tree().change_scene_to_file("res://scenes/CalibrationRoom.tscn")


func _on_btn_chambara_1p_pressed() -> void:
	GameConfig.match_mode = "1p"
	GameConfig.ai_difficulty = ai_picker.get_item_id(ai_picker.selected)
	var sfx := get_node_or_null("/root/SoundFX")
	if sfx != null:
		sfx.play("bell", 1.0, -6.0)
	get_tree().change_scene_to_file("res://scenes/ChambaraArena.tscn")


func _on_btn_chambara_2p_pressed() -> void:
	GameConfig.match_mode = "2p"
	var sfx := get_node_or_null("/root/SoundFX")
	if sfx != null:
		sfx.play("bell", 1.2, -6.0)
	get_tree().change_scene_to_file("res://scenes/ChambaraArena.tscn")


func _on_btn_refresh_pressed() -> void:
	_refresh_devices()
	_refresh_url()
