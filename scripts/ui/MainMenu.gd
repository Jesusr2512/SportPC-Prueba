@tool
extends Node3D

const AVATAR_SCENE := preload("res://scenes/AvatarFighter.tscn")

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
@onready var ai_picker: OptionButton = $UI/Margin/Root/ActionsCard/RowAI/AiDifficulty

var _preview_f1: AvatarFighter
var _preview_f2: AvatarFighter
var _cam_angle: float = 0.0


func _ready() -> void:
	_build_3d_preview_stage()
	_apply_menu_theme()
	if Engine.is_editor_hint():
		return

	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	MotionHub.slots_changed.connect(_refresh_devices)

	ai_picker.clear()
	ai_picker.add_item("IA: Novato", 0)
	ai_picker.add_item("IA: Pro", 1)
	ai_picker.add_item("IA: Campeón", 2)
	ai_picker.selected = GameConfig.ai_difficulty

	_refresh_devices()
	_refresh_url()
	MotionHub.recenter_slot(0)


func _build_3d_preview_stage() -> void:
	for ch in preview_world.get_children():
		ch.free()

	# Ocean water
	var water := MeshInstance3D.new()
	var wm := PlaneMesh.new()
	wm.size = Vector2(160.0, 160.0)
	water.mesh = wm
	var wmat := StandardMaterial3D.new()
	wmat.albedo_color = Color(0.06, 0.56, 0.84)
	wmat.roughness = 0.14
	wmat.metallic = 0.1
	water.material_override = wmat
	water.position = Vector3(0.0, -1.35, 0.0)
	preview_world.add_child(water)

	# Stone foundation
	var base := MeshInstance3D.new()
	var bm := CylinderMesh.new()
	bm.top_radius = 3.65
	bm.bottom_radius = 3.2
	bm.height = 1.35
	bm.radial_segments = 48
	base.mesh = bm
	var bmat := StandardMaterial3D.new()
	bmat.albedo_color = Color(0.32, 0.36, 0.44)
	bmat.roughness = 0.85
	base.material_override = bmat
	base.position = Vector3(0.0, -0.72, 0.0)
	preview_world.add_child(base)

	# Wooden circular dojo deck
	var plat := MeshInstance3D.new()
	var pm := CylinderMesh.new()
	pm.top_radius = 3.55
	pm.bottom_radius = 3.55
	pm.height = 0.16
	pm.radial_segments = 48
	plat.mesh = pm
	var pmat := StandardMaterial3D.new()
	pmat.albedo_color = Color(0.89, 0.78, 0.60)
	pmat.roughness = 0.52
	plat.material_override = pmat
	plat.position = Vector3(0.0, -0.08, 0.0)
	preview_world.add_child(plat)

	# Outer rim
	var rim := MeshInstance3D.new()
	var rm := TorusMesh.new()
	rm.inner_radius = 3.25
	rm.outer_radius = 3.55
	rm.rings = 48
	rim.mesh = rm
	var rmat := StandardMaterial3D.new()
	rmat.albedo_color = Color(0.12, 0.74, 0.92)
	rmat.emission_enabled = true
	rmat.emission = Color(0.12, 0.74, 0.92) * 0.3
	rim.material_override = rmat
	rim.rotation_degrees = Vector3(90, 0, 0)
	rim.scale = Vector3(1.0, 1.0, 0.18)
	rim.position = Vector3(0.0, 0.015, 0.0)
	preview_world.add_child(rim)

	# Distant island silhouettes
	var island_mat := StandardMaterial3D.new()
	island_mat.albedo_color = Color(0.24, 0.52, 0.44)
	for info in [
		[Vector3(-16.0, -0.9, -24.0), Vector3(10.0, 4.2, 8.5)],
		[Vector3(20.0, -1.0, -28.0), Vector3(13.0, 5.5, 11.0)],
		[Vector3(2.0, -1.1, -38.0), Vector3(18.0, 6.8, 9.0)]
	]:
		var isl := MeshInstance3D.new()
		var im := SphereMesh.new()
		im.radius = 1.0
		im.height = 1.4
		isl.mesh = im
		isl.material_override = island_mat
		isl.position = info[0]
		isl.scale = info[1]
		preview_world.add_child(isl)

	# Live 3D fighter diorama
	_preview_f1 = AVATAR_SCENE.instantiate() as AvatarFighter
	_preview_f1.fighter_name = "Jugador 1"
	_preview_f1.team_color = Color(0.05, 0.78, 0.92)
	preview_world.add_child(_preview_f1)
	_preview_f1.reset_for_round(Vector3(0.0, 0.0, 0.85), Vector2(0.0, -1.0))

	_preview_f2 = AVATAR_SCENE.instantiate() as AvatarFighter
	_preview_f2.fighter_name = "IA"
	_preview_f2.team_color = Color(0.98, 0.44, 0.52)
	preview_world.add_child(_preview_f2)
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

	_cam_angle += delta * 0.22
	var cam_radius := 4.1
	cam.position = Vector3(sin(_cam_angle) * cam_radius, 2.0, cos(_cam_angle) * cam_radius)
	cam.look_at(Vector3(0.0, 0.95, 0.0), Vector3.UP)

	var s1: MotionHub.PlayerSlot = MotionHub.slots[0]
	if _preview_f1 and _preview_f2:
		_preview_f1.blade_orientation = s1.fusion.orientation
		_preview_f1.blade_roll_rad = s1.fusion.get_snapped_blade_roll_rad()
		_preview_f1.is_guarding = s1.is_guarding
		if _preview_f1.state == AvatarFighter.State.NORMAL and s1.fusion.just_swung:
			_preview_f1.trigger_slash(s1.fusion.last_slash_dir, s1.fusion.last_slash_power)
		_preview_f1.step_fighter(delta, s1.move_axis, _preview_f2.position, true)
		var p1_xz := Vector2(_preview_f1.position.x, _preview_f1.position.z)
		if p1_xz.length() > 2.4:
			p1_xz = p1_xz.normalized() * 2.4
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
	elif id >= 0:
		MotionHub.assign_gamepad(slot_idx, id)


func _on_copy_url_pressed() -> void:
	DisplayServer.clipboard_set(MotionHub.mobile_server.get_primary_url())


func _on_btn_calibration_pressed() -> void:
	var sfx := get_node_or_null("/root/SoundFX")
	if sfx != null:
		sfx.play("bell", 1.15, -8.0)
	get_tree().change_scene_to_file("res://scenes/CalibrationRoom.tscn")


func _on_btn_chambara_1p_pressed() -> void:
	GameConfig.match_mode = "1p"
	GameConfig.ai_difficulty = ai_picker.selected
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
