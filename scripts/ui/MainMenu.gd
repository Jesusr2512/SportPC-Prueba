@tool
extends Node3D

const AVATAR_SCENE := preload("res://scenes/AvatarFighter.tscn")
const DojoStageScript := preload("res://scripts/game/DojoStage.gd")
const SimpleQRScript := preload("res://scripts/ui/SimpleQR.gd")

@onready var cam: Camera3D = $Camera3D
@onready var preview_world: Node3D = $PreviewWorld
@onready var mobile_card: PanelContainer = $UI/Margin/Root/MobileCard
@onready var controllers_card: PanelContainer = $UI/Margin/Root/ControllersCard
@onready var btn_calibration: Button = $UI/Margin/Root/ActionsCard/BtnCalibration
@onready var btn_chambara_1p: Button = $UI/Margin/Root/ActionsCard/RowAI/BtnChambara1P
@onready var btn_chambara_2p: Button = $UI/Margin/Root/ActionsCard/BtnChambara2P
@onready var p1_label: Label = $UI/Margin/Root/ControllersCard/Grid/P1Info
@onready var p2_label: Label = $UI/Margin/Root/ControllersCard/Grid/P2Info
@onready var qr_rect: TextureRect = $UI/Margin/Root/MobileCard/HBox/QRRect
@onready var mobile_status_label: Label = $UI/Margin/Root/MobileCard/HBox/InfoCol/MobileStatus
@onready var url_label: Label = $UI/Margin/Root/MobileCard/HBox/InfoCol/UrlLabel
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
	_preview_f1.silent_sfx = true
	preview_world.add_child(_preview_f1)
	_preview_f1.configure_stage(GameConfig.arena_stage, 3.55)
	_preview_f1.set_twin_blades(use_twins)
	_preview_f1.reset_for_round(Vector3(0.0, 0.0, 0.85), Vector2(0.0, -1.0))

	_preview_f2 = AVATAR_SCENE.instantiate() as AvatarFighter
	_preview_f2.fighter_name = "IA"
	_preview_f2.team_color = Color(0.98, 0.44, 0.52)
	_preview_f2.silent_sfx = true
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
	var s2: MotionHub.PlayerSlot = MotionHub.slots[1]
	if _preview_f1 and _preview_f2:
		_preview_f1.blade_orientation = s1.fusion.orientation
		_preview_f1.blade_roll_rad = s1.fusion.get_snapped_blade_roll_rad()
		_preview_f1.is_guarding = s1.is_guarding
		if _preview_f1.state == AvatarFighter.State.NORMAL:
			if s1.just_dodge_pressed:
				_preview_f1.trigger_dodge(s1.move_axis)
			elif s1.fusion.just_swung and s1.source_type != MotionHub.SourceType.MOUSE:
				_preview_f1.trigger_slash(s1.fusion.last_slash_dir, s1.fusion.last_slash_power, s1.fusion.last_slash_type)
		_preview_f1.step_fighter(delta, Vector2.ZERO, _preview_f2.position, true)
		var p1_xz := Vector2(_preview_f1.position.x, _preview_f1.position.z)
		if p1_xz.length() > 2.2:
			p1_xz = p1_xz.normalized() * 2.2
			_preview_f1.position.x = p1_xz.x
			_preview_f1.position.z = p1_xz.y

		if s2.source_type != MotionHub.SourceType.NONE:
			_preview_f2.blade_orientation = s2.fusion.orientation
			_preview_f2.blade_roll_rad = s2.fusion.get_snapped_blade_roll_rad()
			_preview_f2.is_guarding = s2.is_guarding
		else:
			_preview_f2.is_guarding = true
			_preview_f2.blade_roll_rad = sin(_cam_angle * 1.4) * 0.45
		_preview_f2.step_fighter(delta, Vector2.ZERO, _preview_f1.position, true)

	if s1.has_motion_sensors or s2.has_motion_sensors:
		_update_slot_labels()


func _refresh_url() -> void:
	if MotionHub.mobile_server and MotionHub.mobile_server.is_running:
		var primary := MotionHub.mobile_server.get_primary_url()
		qr_rect.texture = SimpleQRScript.make_texture(primary, 4, 2)
		qr_rect.visible = qr_rect.texture != null
		var urls := MotionHub.mobile_server.get_all_urls()
		if urls.is_empty():
			url_label.text = primary
		else:
			url_label.text = "URLs locales: " + "  |  ".join(urls)
	else:
		qr_rect.visible = false
		url_label.text = "Servidor móvil HTTPS no disponible en puertos 8443-8450"


func _format_slot_label(title: String, s: MotionHub.PlayerSlot, is_p1: bool) -> String:
	match s.source_type:
		MotionHub.SourceType.MOBILE:
			if s.has_motion_sensors:
				var guard_tag := " | BLOQUEO" if s.is_guarding else ""
				return "%s: 📱 %s [%s | %.0f°%s]" % [title, s.device_name, s.fusion.get_aim_label(), s.fusion.get_blade_angle_deg(), guard_tag]
			return "%s: 📱 %s [Conectado · Activa Sensores en móvil]" % [title, s.device_name]
		MotionHub.SourceType.GAMEPAD:
			if s.has_motion_sensors:
				return "%s: 🎮 %s [6-Axis | %.0f°]" % [title, s.device_name, s.fusion.get_blade_angle_deg()]
			return "%s: 🎮 %s [Stick/Botones]" % [title, s.device_name]
		MotionHub.SourceType.MOUSE:
			return "%s: 🖱️ %s" % [title, s.device_name]
		_:
			return "%s: Sin asignar%s" % [title, "" if is_p1 else " (IA en 1P)"]


func _update_slot_labels() -> void:
	var s1: MotionHub.PlayerSlot = MotionHub.slots[0]
	var s2: MotionHub.PlayerSlot = MotionHub.slots[1]
	p1_label.text = _format_slot_label("Jugador 1 (Azul)", s1, true)
	p2_label.text = _format_slot_label("Jugador 2 (Coral)", s2, false)


func _refresh_devices() -> void:
	_update_slot_labels()
	var connected_mobiles := MotionHub.get_connected_mobile_peers()
	if connected_mobiles.is_empty():
		mobile_status_label.text = "📲 Escanea el QR o abre la URL desde el móvil para convertirlo en Jugador 1"
		mobile_status_label.add_theme_color_override("font_color", Color(0.65, 0.90, 1.0))
	else:
		var parts: Array[String] = []
		for pid in connected_mobiles:
			var info := MotionHub.get_mobile_peer_info(pid)
			var slot_idx := int(info.get("slot", -1))
			var role := "J1 (Azul)" if slot_idx == 0 else ("J2 (Coral)" if slot_idx == 1 else "En espera")
			var imu := "6-Axis" if bool(info.get("sensors", true)) else "Sin activar IMU"
			parts.append("Móvil #%d → %s (%s)" % [pid, role, imu])
		mobile_status_label.text = "✅ " + "  |  ".join(parts)
		mobile_status_label.add_theme_color_override("font_color", Color(0.45, 0.98, 0.72))

	_populate_picker(device_picker_p1, 0)
	_populate_picker(device_picker_p2, 1)


func _populate_picker(picker: OptionButton, slot_idx: int) -> void:
	picker.clear()
	if slot_idx == 1:
		picker.add_item("Sin asignar (IA / Libre)", -2)
	picker.add_item("Ratón + Teclado", -1)
	for gp in MotionHub.get_available_gamepads():
		var tag := " (6-Axis)" if gp["motion"] else " (Sin Gyro)"
		picker.add_item("Mando #%d: %s%s" % [gp["id"], gp["name"], tag], gp["id"])
	if MotionHub.has_method("get_connected_mobile_peers"):
		for pid in MotionHub.get_connected_mobile_peers():
			var info := MotionHub.get_mobile_peer_info(pid)
			var tag := " (6-Axis)" if bool(info.get("sensors", true)) else " (En espera)"
			picker.add_item("📱 Móvil Wi-Fi #%d%s" % [pid, tag], 1000 + pid)

	var slot_obj: MotionHub.PlayerSlot = MotionHub.slots[slot_idx]
	var target_id := -2 if slot_idx == 1 else -1
	match slot_obj.source_type:
		MotionHub.SourceType.NONE:
			target_id = -2 if slot_idx == 1 else -1
		MotionHub.SourceType.MOUSE:
			target_id = -1
		MotionHub.SourceType.GAMEPAD:
			target_id = slot_obj.device_id
		MotionHub.SourceType.MOBILE:
			target_id = 1000 + slot_obj.device_id

	var selected_idx := 0
	for i in picker.item_count:
		if picker.get_item_id(i) == target_id:
			selected_idx = i
			break
	picker.selected = selected_idx
	picker.set_meta("slot_idx", slot_idx)


func _on_p1_select_item_selected(index: int) -> void:
	_apply_picker(device_picker_p1, index, 0)


func _on_p2_select_item_selected(index: int) -> void:
	_apply_picker(device_picker_p2, index, 1)


func _apply_picker(picker: OptionButton, index: int, slot_idx: int) -> void:
	var id := picker.get_item_id(index)
	if id == -2:
		MotionHub.unassign_slot(slot_idx)
	elif id == -1:
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
	if MotionHub.slots[1].source_type == MotionHub.SourceType.NONE:
		if MotionHub.slots[0].source_type != MotionHub.SourceType.MOUSE:
			MotionHub.assign_mouse(1)
	GameConfig.match_mode = "2p"
	var sfx := get_node_or_null("/root/SoundFX")
	if sfx != null:
		sfx.play("bell", 1.2, -6.0)
	get_tree().change_scene_to_file("res://scenes/ChambaraArena.tscn")


func _on_btn_refresh_pressed() -> void:
	_refresh_devices()
	_refresh_url()
