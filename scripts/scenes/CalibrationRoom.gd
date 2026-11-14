extends Node3D

@onready var p1_pivot: Node3D = $RigP1/SwordPivot
@onready var p2_pivot: Node3D = $RigP2/SwordPivot
@onready var p1_guard_mesh: MeshInstance3D = $RigP1/SwordPivot/GuardHalo
@onready var p2_guard_mesh: MeshInstance3D = $RigP2/SwordPivot/GuardHalo
@onready var p1_stats: Label = $UI/HUD/TopCards/CardP1/LabelP1
@onready var p2_stats: Label = $UI/HUD/TopCards/CardP2/LabelP2
@onready var event_log: Label = $UI/HUD/BottomBar/EventLog

var _p1_flash: float = 0.0
var _p2_flash: float = 0.0


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_build_sword_rig(p1_pivot, p1_guard_mesh, Color(0.05, 0.78, 0.92))
	_build_sword_rig(p2_pivot, p2_guard_mesh, Color(0.98, 0.44, 0.52))


func _build_sword_rig(pivot: Node3D, halo: MeshInstance3D, tint: Color) -> void:
	var handle := MeshInstance3D.new()
	var handle_mesh := CylinderMesh.new()
	handle_mesh.top_radius = 0.06
	handle_mesh.bottom_radius = 0.065
	handle_mesh.height = 0.38
	handle.mesh = handle_mesh
	var dark_mat := StandardMaterial3D.new()
	dark_mat.albedo_color = Color(0.14, 0.16, 0.22)
	handle.material_override = dark_mat
	handle.position = Vector3(0.0, -0.15, 0.0)
	pivot.add_child(handle)

	var guard := MeshInstance3D.new()
	var guard_mesh := CylinderMesh.new()
	guard_mesh.top_radius = 0.16
	guard_mesh.bottom_radius = 0.16
	guard_mesh.height = 0.045
	guard.mesh = guard_mesh
	var guard_mat := StandardMaterial3D.new()
	guard_mat.albedo_color = Color(0.92, 0.95, 1.0)
	guard.material_override = guard_mat
	guard.position = Vector3(0.0, 0.06, 0.0)
	pivot.add_child(guard)

	var blade := MeshInstance3D.new()
	var blade_mesh := BoxMesh.new()
	blade_mesh.size = Vector3(0.08, 1.15, 0.14)
	blade.mesh = blade_mesh
	var blade_mat := StandardMaterial3D.new()
	blade_mat.albedo_color = tint
	blade_mat.emission_enabled = true
	blade_mat.emission = tint * 0.45
	blade.material_override = blade_mat
	blade.position = Vector3(0.0, 0.68, 0.0)
	pivot.add_child(blade)

	var halo_mesh := TorusMesh.new()
	halo_mesh.inner_radius = 0.48
	halo_mesh.outer_radius = 0.55
	halo.mesh = halo_mesh
	var halo_mat := StandardMaterial3D.new()
	halo_mat.albedo_color = Color(tint.r, tint.g, tint.b, 0.65)
	halo_mat.emission_enabled = true
	halo_mat.emission = tint
	halo_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	halo.material_override = halo_mat
	halo.rotation_degrees = Vector3(90, 0, 0)
	halo.position = Vector3(0.0, 0.45, 0.0)
	halo.visible = false


func _process(delta: float) -> void:
	_update_rig(0, p1_pivot, p1_guard_mesh, p1_stats, delta)
	_update_rig(1, p2_pivot, p2_guard_mesh, p2_stats, delta)

	_p1_flash = maxf(0.0, _p1_flash - delta * 3.0)
	_p2_flash = maxf(0.0, _p2_flash - delta * 3.0)
	p1_pivot.scale = Vector3.ONE * (1.0 + _p1_flash * 0.18)
	p2_pivot.scale = Vector3.ONE * (1.0 + _p2_flash * 0.18)


func _update_rig(slot_idx: int, pivot: Node3D, halo: MeshInstance3D, lbl: Label, _delta: float) -> void:
	var s: MotionHub.PlayerSlot = MotionHub.slots[slot_idx]
	pivot.quaternion = s.fusion.orientation
	halo.visible = s.is_guarding

	if s.fusion.just_swung:
		if slot_idx == 0:
			_p1_flash = 1.0
		else:
			_p2_flash = 1.0
		SoundFX.play("slash", randf_range(0.95, 1.15), -7.0)
		MotionHub.trigger_rumble(slot_idx, 0.4, 0.07)
		event_log.text = "J%d SWING detectado | Dirección: (%.2f, %.2f) | Fuerza: %.2f" % [
			slot_idx + 1, s.fusion.last_slash_dir.x, s.fusion.last_slash_dir.y, s.fusion.last_slash_power
		]

	lbl.text = (
		"Jugador %d: %s\n" +
		"Gyro: %.2f, %.2f, %.2f rad/s\n" +
		"Vel. lineal: %.2f m/s² | Guard: %s\n" +
		"Ángulo hoja: %.0f°"
	) % [
		slot_idx + 1,
		s.device_name,
		s.fusion.gyro.x, s.fusion.gyro.y, s.fusion.gyro.z,
		s.fusion.linear_accel.length(),
		"ACTIVA" if s.is_guarding else "No",
		s.fusion.get_blade_angle_deg()
	]


func _on_recenter_p1_pressed() -> void:
	MotionHub.recenter_slot(0)
	SoundFX.play("bell", 1.2, -10.0)


func _on_recenter_p2_pressed() -> void:
	MotionHub.recenter_slot(1)
	SoundFX.play("bell", 1.3, -10.0)


func _on_bias_p1_pressed() -> void:
	MotionHub.calibrate_bias_slot(0)
	event_log.text = "Calibrando reposo J1 (deja el mando quieto 0.5s)..."


func _on_rumble_p1_pressed() -> void:
	MotionHub.trigger_rumble(0, 0.9, 0.18)


func _on_rumble_p2_pressed() -> void:
	MotionHub.trigger_rumble(1, 0.9, 0.18)


func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/MainMenu.tscn")
