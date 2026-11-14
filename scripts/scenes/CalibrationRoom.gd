@tool
extends Node3D

const AVATAR_SCENE := preload("res://scenes/AvatarFighter.tscn")

enum DemoMode { AUTO, POSTURE, TWIST, SLASH, GUARD }

@onready var stage_root: Node3D = $StageRoot
@onready var coach_card: PanelContainer = $UI/HUD/CoachCard
@onready var diag_card: PanelContainer = $UI/HUD/DiagCard
@onready var instruction_label: Label = $UI/HUD/CoachCard/VBox/InstructionLabel
@onready var energy_bar: ProgressBar = $UI/HUD/DiagCard/DiagVBox/EnergyRow/EnergyBar
@onready var swing_badge: Label = $UI/HUD/DiagCard/DiagVBox/EnergyRow/SwingBadge
@onready var p1_stats: Label = $UI/HUD/DiagCard/DiagVBox/StatsRow/LabelP1
@onready var p2_stats: Label = $UI/HUD/DiagCard/DiagVBox/StatsRow/LabelP2

@onready var btn_auto: Button = $UI/HUD/CoachCard/VBox/StepButtons/BtnAuto
@onready var btn_s1: Button = $UI/HUD/CoachCard/VBox/StepButtons/BtnStep1
@onready var btn_s2: Button = $UI/HUD/CoachCard/VBox/StepButtons/BtnStep2
@onready var btn_s3: Button = $UI/HUD/CoachCard/VBox/StepButtons/BtnStep3
@onready var btn_s4: Button = $UI/HUD/CoachCard/VBox/StepButtons/BtnStep4

var _demo_mode: DemoMode = DemoMode.AUTO
var _active_step: int = 0 # 0=Posture, 1=Twist, 2=Slash, 3=Guard
var _auto_timer: float = 0.0
var _step_t: float = 0.0
var _slash_fired_cycle: int = -1
var _guard_fx_cycle: int = -1
var _swing_flash_timer: float = 0.0
var _last_attack_label: String = ""

var _coach_avatar: AvatarFighter
var _live_avatar: AvatarFighter
var _coach_phone_roll: Node3D
var _coach_phone_tilt: Node3D
var _coach_thumb_dot: MeshInstance3D
var _coach_thrust_arrow: Node3D
var _coach_enemy_bar: MeshInstance3D
var _coach_enemy_mat: StandardMaterial3D
var _coach_parry_ring: MeshInstance3D

var _live_phone_roll: Node3D
var _live_phone_tilt: Node3D
var _live_thumb_dot: MeshInstance3D
var _live_screen_mat: StandardMaterial3D


func _ready() -> void:
	_build_stage()
	_apply_theme()
	_refresh_step_ui()
	if Engine.is_editor_hint():
		return

	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	MotionHub.recenter_slot(0)


func _build_stage() -> void:
	for ch in stage_root.get_children():
		ch.free()

	# Ocean water plane
	var water := MeshInstance3D.new()
	var wm := PlaneMesh.new()
	wm.size = Vector2(140.0, 140.0)
	water.mesh = wm
	var wmat := StandardMaterial3D.new()
	wmat.albedo_color = Color(0.06, 0.56, 0.84)
	wmat.roughness = 0.14
	water.material_override = wmat
	water.position = Vector3(0.0, -1.35, 0.0)
	stage_root.add_child(water)

	# Dojo wooden platform
	var base := MeshInstance3D.new()
	var bm := CylinderMesh.new()
	bm.top_radius = 4.1
	bm.bottom_radius = 3.6
	bm.height = 1.35
	bm.radial_segments = 48
	base.mesh = bm
	var bmat := StandardMaterial3D.new()
	bmat.albedo_color = Color(0.32, 0.36, 0.44)
	base.material_override = bmat
	base.position = Vector3(0.0, -0.72, 0.0)
	stage_root.add_child(base)

	var plat := MeshInstance3D.new()
	var pm := CylinderMesh.new()
	pm.top_radius = 4.0
	pm.bottom_radius = 4.0
	pm.height = 0.14
	pm.radial_segments = 48
	plat.mesh = pm
	var pmat := StandardMaterial3D.new()
	pmat.albedo_color = Color(0.89, 0.78, 0.60)
	pmat.roughness = 0.55
	plat.material_override = pmat
	plat.position = Vector3(0.0, -0.07, 0.0)
	stage_root.add_child(plat)

	# Center divider stripe separating Coach (left) and Player (right)
	var divider := MeshInstance3D.new()
	var dm := BoxMesh.new()
	dm.size = Vector3(0.05, 0.02, 6.8)
	divider.mesh = dm
	var dmat := StandardMaterial3D.new()
	dmat.albedo_color = Color(0.18, 0.74, 0.96, 0.85)
	dmat.emission_enabled = true
	dmat.emission = Color(0.18, 0.74, 0.96) * 0.45
	divider.material_override = dmat
	divider.position = Vector3(0.0, 0.01, 0.0)
	stage_root.add_child(divider)

	# Left: Animated Instructor Fighter + 3D Floating Smartphone Diagram
	_coach_avatar = AVATAR_SCENE.instantiate() as AvatarFighter
	_coach_avatar.fighter_name = "Instructor"
	_coach_avatar.team_color = Color(0.10, 0.86, 0.75)
	stage_root.add_child(_coach_avatar)
	_coach_avatar.reset_for_round(Vector3(-1.35, 0.0, -0.35), Vector2(0.30, -0.95))

	var coach_phone_nodes := _create_phone_rig(Vector3(-1.32, 1.52, 1.60), Color(0.10, 0.88, 0.78), true)
	_coach_phone_roll = coach_phone_nodes["roll"]
	_coach_phone_tilt = coach_phone_nodes["tilt"]
	_coach_thumb_dot = coach_phone_nodes["thumb"]
	_coach_thrust_arrow = coach_phone_nodes["arrow"]
	_coach_enemy_bar = coach_phone_nodes["enemy_bar"]
	_coach_enemy_mat = coach_phone_nodes["enemy_mat"]
	_coach_parry_ring = coach_phone_nodes["parry_ring"]

	# Right: Player 1 Live Avatar + 3D Smartphone Mirror
	_live_avatar = AVATAR_SCENE.instantiate() as AvatarFighter
	_live_avatar.fighter_name = "Jugador 1"
	_live_avatar.team_color = Color(0.05, 0.78, 0.92)
	stage_root.add_child(_live_avatar)
	_live_avatar.reset_for_round(Vector3(1.35, 0.0, -0.35), Vector2(-0.30, -0.95))

	var live_phone_nodes := _create_phone_rig(Vector3(1.32, 1.52, 1.60), Color(0.08, 0.80, 0.98), false)
	_live_phone_roll = live_phone_nodes["roll"]
	_live_phone_tilt = live_phone_nodes["tilt"]
	_live_thumb_dot = live_phone_nodes["thumb"]
	_live_screen_mat = live_phone_nodes["screen_mat"]


func _create_phone_rig(pos: Vector3, tint: Color, is_coach: bool) -> Dictionary:
	var mount := Node3D.new()
	mount.position = pos
	stage_root.add_child(mount)

	var roll_pivot := Node3D.new()
	mount.add_child(roll_pivot)

	var tilt_pivot := Node3D.new()
	roll_pivot.add_child(tilt_pivot)

	# Smartphone chassis
	var body := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.24, 0.44, 0.036)
	body.mesh = bm
	var body_mat := StandardMaterial3D.new()
	body_mat.albedo_color = Color(0.10, 0.12, 0.16)
	body_mat.roughness = 0.25
	body.material_override = body_mat
	tilt_pivot.add_child(body)

	# Smartphone screen facing back toward the player (+Z)
	var screen := MeshInstance3D.new()
	var sm := BoxMesh.new()
	sm.size = Vector3(0.21, 0.39, 0.008)
	screen.mesh = sm
	var screen_mat := StandardMaterial3D.new()
	screen_mat.albedo_color = Color(0.06, 0.22, 0.36)
	screen_mat.emission_enabled = true
	screen_mat.emission = tint * 0.42
	screen.material_override = screen_mat
	screen.position = Vector3(0.0, 0.0, 0.020)
	tilt_pivot.add_child(screen)

	# Glowing Katana extension coming out top edge (+Y) of the phone
	var blade := MeshInstance3D.new()
	var blm := BoxMesh.new()
	blm.size = Vector3(0.042, 0.56, 0.020)
	blade.mesh = blm
	var blade_mat := StandardMaterial3D.new()
	blade_mat.albedo_color = tint
	blade_mat.emission_enabled = true
	blade_mat.emission = tint * 1.15
	blade.material_override = blade_mat
	blade.position = Vector3(0.0, 0.48, 0.0)
	tilt_pivot.add_child(blade)

	# Thumb touch indicator dot on screen (illuminates when Guarding)
	var thumb := MeshInstance3D.new()
	var tm := SphereMesh.new()
	tm.radius = 0.048
	tm.height = 0.096
	thumb.mesh = tm
	var tmat := StandardMaterial3D.new()
	tmat.albedo_color = Color(0.45, 0.96, 1.0)
	tmat.emission_enabled = true
	tmat.emission = Color(0.35, 0.92, 1.0) * 1.6
	thumb.material_override = tmat
	thumb.position = Vector3(0.0, -0.02, 0.055)
	thumb.visible = false
	tilt_pivot.add_child(thumb)

	var out := {
		"roll": roll_pivot,
		"tilt": tilt_pivot,
		"thumb": thumb,
		"screen_mat": screen_mat
	}

	if is_coach:
		# Yellow/green forward swing motion arrow hovering above the phone
		var arrow_root := Node3D.new()
		arrow_root.position = Vector3(0.24, 0.20, 0.0)
		arrow_root.visible = false
		roll_pivot.add_child(arrow_root)

		var shaft := MeshInstance3D.new()
		var shm := BoxMesh.new()
		shm.size = Vector3(0.035, 0.36, 0.035)
		shaft.mesh = shm
		var amat := StandardMaterial3D.new()
		amat.albedo_color = Color(0.35, 1.0, 0.55)
		amat.emission_enabled = true
		amat.emission = Color(0.35, 1.0, 0.55) * 1.5
		shaft.material_override = amat
		shaft.rotation_degrees = Vector3(-55.0, 0.0, 0.0)
		arrow_root.add_child(shaft)

		var tip := MeshInstance3D.new()
		var tipm := CylinderMesh.new()
		tipm.top_radius = 0.0
		tipm.bottom_radius = 0.065
		tipm.height = 0.14
		tip.mesh = tipm
		tip.material_override = amat
		tip.position = Vector3(0.0, -0.15, -0.19)
		tip.rotation_degrees = Vector3(-145.0, 0.0, 0.0)
		arrow_root.add_child(tip)
		out["arrow"] = arrow_root

		# Red enemy telegraph bar (shown during Step 4 Guard/Parry demo)
		var enemy_bar := MeshInstance3D.new()
		var ebm := BoxMesh.new()
		ebm.size = Vector3(0.75, 0.055, 0.055)
		enemy_bar.mesh = ebm
		var emat := StandardMaterial3D.new()
		emat.albedo_color = Color(1.0, 0.26, 0.22)
		emat.emission_enabled = true
		emat.emission = Color(1.0, 0.26, 0.22) * 1.8
		enemy_bar.material_override = emat
		enemy_bar.position = Vector3(0.0, 0.34, -0.18)
		enemy_bar.visible = false
		mount.add_child(enemy_bar)
		out["enemy_bar"] = enemy_bar
		out["enemy_mat"] = emat

		# Golden parry ring
		var parry_ring := MeshInstance3D.new()
		var prm := TorusMesh.new()
		prm.inner_radius = 0.28
		prm.outer_radius = 0.36
		parry_ring.mesh = prm
		var pmat := StandardMaterial3D.new()
		pmat.albedo_color = Color(1.0, 0.90, 0.25)
		pmat.emission_enabled = true
		pmat.emission = Color(1.0, 0.85, 0.20) * 1.9
		parry_ring.material_override = pmat
		parry_ring.rotation_degrees = Vector3(90.0, 0.0, 0.0)
		parry_ring.position = Vector3(0.0, 0.34, -0.12)
		parry_ring.visible = false
		mount.add_child(parry_ring)
		out["parry_ring"] = parry_ring

	return out


func _apply_theme() -> void:
	var card_style := StyleBoxFlat.new()
	card_style.bg_color = Color(0.05, 0.11, 0.22, 0.84)
	card_style.border_color = Color(0.24, 0.68, 0.94, 0.45)
	card_style.set_border_width_all(2)
	card_style.set_corner_radius_all(12)
	card_style.set_content_margin_all(10)
	coach_card.add_theme_stylebox_override("panel", card_style)
	diag_card.add_theme_stylebox_override("panel", card_style)

	var bar_bg := StyleBoxFlat.new()
	bar_bg.bg_color = Color(0.10, 0.15, 0.25, 0.95)
	bar_bg.set_corner_radius_all(8)
	var bar_fill := StyleBoxFlat.new()
	bar_fill.bg_color = Color(0.12, 0.84, 0.96, 1.0)
	bar_fill.set_corner_radius_all(8)
	energy_bar.add_theme_stylebox_override("background", bar_bg)
	energy_bar.add_theme_stylebox_override("fill", bar_fill)


func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return

	_animate_coach(delta)
	_update_live_player(delta)


func _animate_coach(delta: float) -> void:
	if _demo_mode == DemoMode.AUTO:
		_auto_timer += delta
		if _auto_timer >= 3.8:
			_auto_timer = 0.0
			_active_step = (_active_step + 1) % 4
			_step_t = 0.0
			_slash_fired_cycle = -1
			_guard_fx_cycle = -1
			_refresh_step_ui()
	else:
		_active_step = int(_demo_mode) - 1

	_step_t += delta
	_coach_thrust_arrow.visible = false
	_coach_enemy_bar.visible = false
	_coach_parry_ring.visible = false
	_coach_thumb_dot.visible = false

	var target_roll := 0.0
	var target_pitch := -0.68 # ~40 deg pointing forward-up toward monitor
	var target_z_offset := 0.0
	var guarding := false

	match _active_step:
		0: # Paso 1: Postura Base (~45°) y Centrar
			target_roll = 0.0
			target_pitch = -0.68 + sin(_step_t * 2.5) * 0.03
		1: # Paso 2: Girar solo la muñeca (4 ángulos)
			var poses := [0.0, PI * 0.25, PI * 0.5, -PI * 0.25]
			var idx := int(floor(_step_t / 0.85)) % poses.size()
			target_roll = poses[idx]
			target_pitch = -0.68
		2: # Paso 3: Atacar hacia delante (corte de muñeca / empuje)
			var cycle_len := 1.75
			var cyc := int(floor(_step_t / cycle_len))
			var p := fmod(_step_t, cycle_len)
			var pose_cycle := [0.0, PI * 0.5, PI * 0.25]
			target_roll = pose_cycle[cyc % pose_cycle.size()]
			if p < 0.58:
				target_pitch = lerpf(-0.68, -0.45, p / 0.58)
				_coach_thrust_arrow.visible = true
				_coach_thrust_arrow.position.y = lerpf(0.24, 0.16, p / 0.58)
			elif p < 0.86:
				var sp := (p - 0.58) / 0.28
				target_pitch = lerpf(-0.45, -1.48, sp)
				target_z_offset = -0.22 * sin(sp * PI)
				_coach_thrust_arrow.visible = true
				_coach_thrust_arrow.position.y = 0.10 - sp * 0.18
				if _slash_fired_cycle != cyc:
					_slash_fired_cycle = cyc
					var cut_ang := target_roll - PI * 0.5
					_coach_avatar.blade_roll_rad = target_roll
					_coach_avatar.trigger_slash(Vector2(cos(cut_ang), sin(cut_ang)), 1.0)
			else:
				var rp := (p - 0.86) / 0.89
				target_pitch = lerpf(-1.48, -0.68, rp)
		3: # Paso 4: Bloquear (+) y Cortar en Paralelo (=)
			var sub_len := 3.4
			var sub_cyc := int(floor(_step_t / sub_len))
			var sp := fmod(_step_t, sub_len)
			if sp < 1.75:
				# Parry perpendicular: enemy attacks HORIZONTAL, coach holds VERTICAL + thumb pressed!
				guarding = true
				target_roll = 0.0
				target_pitch = -0.68
				_coach_thumb_dot.visible = true
				_coach_enemy_bar.visible = true
				_coach_enemy_bar.rotation.z = 0.0 # Horizontal red attack line
				if sp > 0.95 and sp < 1.50:
					_coach_parry_ring.visible = true
					_coach_parry_ring.scale = Vector3.ONE * (0.9 + (sp - 0.95) * 1.4)
			else:
				# Parallel guard break: enemy blocks HORIZONTAL, coach rotates HORIZONTAL and slashes!
				target_roll = PI * 0.5
				_coach_enemy_bar.visible = true
				_coach_enemy_bar.rotation.z = 0.0
				_coach_thrust_arrow.visible = sp < 2.65
				if sp > 2.45 and sp < 2.75:
					var slash_t := (sp - 2.45) / 0.30
					target_pitch = lerpf(-0.50, -1.42, slash_t)
					target_z_offset = -0.20 * sin(slash_t * PI)
					if _guard_fx_cycle != sub_cyc:
						_guard_fx_cycle = sub_cyc
						_coach_avatar.blade_roll_rad = PI * 0.5
						_coach_avatar.trigger_slash(Vector2(1.0, 0.0), 1.0)
				else:
					target_pitch = -0.68

	_coach_phone_roll.rotation.z = lerp_angle(_coach_phone_roll.rotation.z, -target_roll, clampf(delta * 14.0, 0.0, 1.0))
	_coach_phone_tilt.rotation.x = lerpf(_coach_phone_tilt.rotation.x, target_pitch, clampf(delta * 18.0, 0.0, 1.0))
	_coach_phone_tilt.position.z = lerpf(_coach_phone_tilt.position.z, target_z_offset, clampf(delta * 18.0, 0.0, 1.0))

	_coach_avatar.is_guarding = guarding
	if _coach_avatar.state == AvatarFighter.State.NORMAL:
		_coach_avatar.blade_roll_rad = target_roll
		_coach_avatar.blade_orientation = Quaternion.from_euler(Vector3(target_pitch + 0.68, 0.0, -target_roll))
	_coach_avatar.step_fighter(delta, Vector2.ZERO, Vector3(-0.3, 0.0, -4.0), true)


func _update_live_player(delta: float) -> void:
	var s0: MotionHub.PlayerSlot = MotionHub.slots[0]

	if _live_avatar:
		_live_avatar.blade_orientation = s0.fusion.orientation
		_live_avatar.blade_roll_rad = s0.fusion.get_snapped_blade_roll_rad()
		_live_avatar.is_guarding = s0.is_guarding
		if _live_avatar.state == AvatarFighter.State.NORMAL and s0.fusion.just_swung:
			_live_avatar.trigger_slash(s0.fusion.last_slash_dir, s0.fusion.last_slash_power)
			_swing_flash_timer = 1.35
			_last_attack_label = "✅ ¡ATAQUE! (%s) -> %s" % [
				s0.fusion.last_swing_source if s0.fusion.last_swing_source != "" else "Corte",
				_describe_slash_dir(s0.fusion.last_slash_dir)
			]
			var sfx := get_node_or_null("/root/SoundFX")
			if sfx != null:
				sfx.play("slash", randf_range(0.95, 1.15), -7.0)
			MotionHub.trigger_rumble(0, 0.45, 0.08)

		_live_avatar.step_fighter(delta, Vector2.ZERO, Vector3(0.3, 0.0, -4.0), true)

	if _live_phone_roll and _live_phone_tilt:
		var roll_s := s0.fusion.get_snapped_blade_roll_rad()
		_live_phone_roll.rotation.z = lerp_angle(_live_phone_roll.rotation.z, -roll_s, clampf(delta * 20.0, 0.0, 1.0))
		_live_phone_roll.rotation.y = lerpf(_live_phone_roll.rotation.y, clampf(s0.fusion.yaw_rad * 0.7, -0.7, 0.7), clampf(delta * 16.0, 0.0, 1.0))
		_live_phone_tilt.rotation.x = lerpf(_live_phone_tilt.rotation.x, -0.68 + clampf(s0.fusion.pitch_rad * 0.85, -0.95, 0.75), clampf(delta * 18.0, 0.0, 1.0))
		_live_thumb_dot.visible = s0.is_guarding

	_swing_flash_timer = maxf(0.0, _swing_flash_timer - delta)
	var pct := clampf((s0.fusion.motion_energy / MotionFusion.SWING_THRESHOLD) * 100.0, 0.0, 140.0)
	energy_bar.value = maxf(pct, 108.0 if _swing_flash_timer > 0.95 else 0.0)

	var fill_sb := energy_bar.get_theme_stylebox("fill") as StyleBoxFlat
	if _swing_flash_timer > 0.0:
		if fill_sb:
			fill_sb.bg_color = Color(0.22, 0.96, 0.48, 1.0)
		if _live_screen_mat:
			_live_screen_mat.emission = Color(0.22, 0.96, 0.48) * 1.4
		swing_badge.text = _last_attack_label
		swing_badge.add_theme_color_override("font_color", Color(0.38, 1.0, 0.58))
	else:
		if fill_sb:
			fill_sb.bg_color = Color(0.12, 0.84, 0.96, 1.0)
		if _live_screen_mat:
			_live_screen_mat.emission = Color(0.08, 0.80, 0.98) * 0.42
		swing_badge.text = "Fuerza actual: %.0f%% (llega a 100%% para cortar)" % pct
		swing_badge.add_theme_color_override("font_color", Color(0.75, 0.92, 1.0))

	p1_stats.text = "J1: %s | Gyro: %.1f, %.1f, %.1f rad/s | Empuje: %.1f m/s² | Hoja: %.0f° | Guardia: %s" % [
		s0.device_name,
		s0.fusion.gyro.x, s0.fusion.gyro.y, s0.fusion.gyro.z,
		s0.fusion.dynamic_accel_mag,
		s0.fusion.get_blade_angle_deg(),
		"ACTIVA" if s0.is_guarding else "Libre"
	]

	var s1: MotionHub.PlayerSlot = MotionHub.slots[1]
	p2_stats.text = "J2: %s | Gyro: %.1f rad/s | Hoja: %.0f°" % [
		s1.device_name,
		s1.fusion.angular_speed,
		s1.fusion.get_blade_angle_deg()
	]


func _describe_slash_dir(d: Vector2) -> String:
	var ax := absf(d.x)
	var ay := absf(d.y)
	if ax > ay * 1.8:
		return "HORIZONTAL —"
	if ay > ax * 1.8:
		return "VERTICAL |"
	return "DIAGONAL /" if (d.x * d.y > 0.0) else "DIAGONAL \\"


func _refresh_step_ui() -> void:
	var captions := [
		"PASO 1 — POSTURA BASE: Ponte frente al monitor, sujeta el móvil a ~45° apuntando a la pantalla (como la empuñadura de una espada) y pulsa 🎯 CENTRAR.",
		"PASO 2 — GIRAR LA HOJA: Sin mover el brazo, gira SOLO la muñeca izquierda/derecha para elegir el corte: Vertical |, Diagonal / \\ o Horizontal —.",
		"PASO 3 — ATACAR HACIA DELANTE: Desde la postura (~45°), haz un golpe rápido de muñeca hacia delante/abajo (o empuje seco frontal). ¡Mira que la barra verde llegue al 100%!",
		"PASO 4 — BLOQUEAR (+) Y ROMPER (=): Mantén pulsada la pantalla para cubrirte. Cruza tu espada en PERPENDICULAR (+) contra el golpe rojo para hacer Parry; alinea en PARALELO (=) para romper guardia."
	]
	instruction_label.text = captions[_active_step]

	var btns := [btn_s1, btn_s2, btn_s3, btn_s4]
	for i in btns.size():
		btns[i].modulate = Color(0.45, 1.0, 0.72) if i == _active_step else Color(1, 1, 1)
	btn_auto.modulate = Color(0.45, 0.92, 1.0) if _demo_mode == DemoMode.AUTO else Color(1, 1, 1)


func _on_step_auto_pressed() -> void:
	_demo_mode = DemoMode.AUTO
	_auto_timer = 0.0
	_refresh_step_ui()


func _on_step_1_pressed() -> void:
	_demo_mode = DemoMode.POSTURE
	_active_step = 0
	_step_t = 0.0
	_refresh_step_ui()


func _on_step_2_pressed() -> void:
	_demo_mode = DemoMode.TWIST
	_active_step = 1
	_step_t = 0.0
	_refresh_step_ui()


func _on_step_3_pressed() -> void:
	_demo_mode = DemoMode.SLASH
	_active_step = 2
	_step_t = 0.0
	_slash_fired_cycle = -1
	_refresh_step_ui()


func _on_step_4_pressed() -> void:
	_demo_mode = DemoMode.GUARD
	_active_step = 3
	_step_t = 0.0
	_guard_fx_cycle = -1
	_refresh_step_ui()


func _on_recenter_p1_pressed() -> void:
	MotionHub.recenter_slot(0)
	var sfx := get_node_or_null("/root/SoundFX")
	if sfx != null:
		sfx.play("bell", 1.2, -10.0)


func _on_bias_p1_pressed() -> void:
	MotionHub.calibrate_bias_slot(0)
	swing_badge.text = "Calibrando reposo J1 (deja el móvil/mando quieto 0.5s)..."


func _on_rumble_p1_pressed() -> void:
	MotionHub.trigger_rumble(0, 0.9, 0.18)


func _on_play_1p_pressed() -> void:
	GameConfig.match_mode = "1p"
	get_tree().change_scene_to_file("res://scenes/ChambaraArena.tscn")


func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/MainMenu.tscn")
