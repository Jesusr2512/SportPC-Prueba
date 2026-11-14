extends Control

@onready var mobile_card: PanelContainer = $Margin/Root/MobileCard
@onready var controllers_card: PanelContainer = $Margin/Root/ControllersCard
@onready var btn_calibration: Button = $Margin/Root/ActionsCard/BtnCalibration
@onready var btn_chambara_1p: Button = $Margin/Root/ActionsCard/RowAI/BtnChambara1P
@onready var btn_chambara_2p: Button = $Margin/Root/ActionsCard/BtnChambara2P
@onready var p1_label: Label = $Margin/Root/ControllersCard/Grid/P1Info
@onready var p2_label: Label = $Margin/Root/ControllersCard/Grid/P2Info
@onready var url_label: Label = $Margin/Root/MobileCard/HBox/UrlLabel
@onready var device_picker_p1: OptionButton = $Margin/Root/ControllersCard/Grid/P1Select
@onready var device_picker_p2: OptionButton = $Margin/Root/ControllersCard/Grid/P2Select
@onready var ai_picker: OptionButton = $Margin/Root/ActionsCard/RowAI/AiDifficulty


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	MotionHub.slots_changed.connect(_refresh_devices)
	_apply_menu_theme()

	ai_picker.clear()
	ai_picker.add_item("IA: Novato", 0)
	ai_picker.add_item("IA: Pro", 1)
	ai_picker.add_item("IA: Campeón", 2)
	ai_picker.selected = GameConfig.ai_difficulty

	_refresh_devices()
	_refresh_url()


func _apply_menu_theme() -> void:
	var card_style := StyleBoxFlat.new()
	card_style.bg_color = Color(0.09, 0.16, 0.28, 0.92)
	card_style.border_color = Color(0.24, 0.64, 0.92, 0.45)
	card_style.set_border_width_all(2)
	card_style.set_corner_radius_all(14)
	card_style.set_content_margin_all(14)
	mobile_card.add_theme_stylebox_override("panel", card_style)
	controllers_card.add_theme_stylebox_override("panel", card_style)

	var primary_btn := StyleBoxFlat.new()
	primary_btn.bg_color = Color(0.06, 0.56, 0.78, 1.0)
	primary_btn.border_color = Color(0.45, 0.90, 1.0, 0.9)
	primary_btn.set_border_width_all(2)
	primary_btn.set_corner_radius_all(14)
	var primary_hover := primary_btn.duplicate() as StyleBoxFlat
	primary_hover.bg_color = Color(0.10, 0.66, 0.88, 1.0)
	btn_chambara_1p.add_theme_stylebox_override("normal", primary_btn)
	btn_chambara_1p.add_theme_stylebox_override("hover", primary_hover)

	var sec_btn := StyleBoxFlat.new()
	sec_btn.bg_color = Color(0.13, 0.21, 0.35, 1.0)
	sec_btn.border_color = Color(0.35, 0.52, 0.75, 0.55)
	sec_btn.set_border_width_all(2)
	sec_btn.set_corner_radius_all(14)
	var sec_hover := sec_btn.duplicate() as StyleBoxFlat
	sec_hover.bg_color = Color(0.18, 0.28, 0.46, 1.0)
	btn_calibration.add_theme_stylebox_override("normal", sec_btn)
	btn_calibration.add_theme_stylebox_override("hover", sec_hover)
	btn_chambara_2p.add_theme_stylebox_override("normal", sec_btn)
	btn_chambara_2p.add_theme_stylebox_override("hover", sec_hover)


func _process(_delta: float) -> void:
	var s1: MotionHub.PlayerSlot = MotionHub.slots[0]
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
