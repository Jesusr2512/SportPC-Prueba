@tool
extends Node3D

const AVATAR_SCENE := preload("res://scenes/AvatarFighter.tscn")
const DojoStageScript := preload("res://scripts/game/DojoStage.gd")

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
var _active_step: int = 0
var _auto_timer: float = 0.0
var _step_t: float = 0.0
var _shader_time: float = 0.0
var _slash_fired_cycle: int = -1
var _guard_fx_cycle: int = -1
var _swing_flash_timer: float = 0.0
var _last_attack_label: String = ""

var _stage_refs: Dictionary = {}
var _sparks: Array[Dictionary] = []

var _coach_avatar: AvatarFighter
var _live_avatar: AvatarFighter
var _dummy_avatar: AvatarFighter
var _dummy_home: Vector3 = Vector3(0.92, 0.0, -1.85)
var _dummy_guard_timer: float = 0.0
var _dummy_guard_angles: Array[float] = [0.0, PI * 0.5, PI * 0.25, -PI * 0.25]
var _dummy_angle_idx: int = 0
var _dummy_hits: int = 0

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
	var hub := get_node_or_null("/root/MotionHub")
	if hub != null:
		hub.mouse_combat_enabled = true
		hub.recenter_slot(0)


func _build_stage() -> void:
	_stage_refs = DojoStageScript.build_stage(stage_root, GameConfig.arena_stage, 4.1)

	var divider := MeshInstance3D.new()
	var dm := BoxMesh.new()
	dm.size = Vector3(0.05, 0.02, 6.2)
	divider.mesh = dm
	var dmat := StandardMaterial3D.new()
	dmat.albedo_color = Color(0.18, 0.74, 0.96, 0.85)
	dmat.emission_enabled = true
	dmat.emission = Color(0.18, 0.74, 0.96) * 0.45
	divider.material_override = dmat
	divider.position = Vector3(-0.18, 0.02, 0.0)
	stage_root.add_child(divider)

	# Left: Animated Instructor Fighter + 3D Floating Smartphone Diagram
	_coach_avatar = AVATAR_SCENE.instantiate() as AvatarFighter
	_coach_avatar.fighter_name = "Instructor"
	_coach_avatar.team_color = Color(0.10, 0.86, 0.75)
	stage_root.add_child(_coach_avatar)
	_coach_avatar.configure_stage(GameConfig.arena_stage, 4.0)
	_coach_avatar.reset_for_round(Vector3(-1.45, 0.0, -0.35), Vector2(0.15, -0.98))

	var coach_phone_nodes := _create_phone_rig(Vector3(-1.42, 1.52, 1.58), Color(0.10, 0.88, 0.78), true)
	_coach_phone_roll = coach_phone_nodes["roll"]
	_coach_phone_tilt = coach_phone_nodes["tilt"]
	_coach_thumb_dot = coach_phone_nodes["thumb"]
	_coach_thrust_arrow = coach_phone_nodes["arrow"]
	_coach_enemy_bar = coach_phone_nodes["enemy_bar"]
	_coach_enemy_mat = coach_phone_nodes["enemy_mat"]
	_coach_parry_ring = coach_phone_nodes["parry_ring"]

	# Right: Player 1 Live Avatar + Sparring Dummy + 3D Smartphone Mirror
	_live_avatar = AVATAR_SCENE.instantiate() as AvatarFighter
	_live_avatar.fighter_name = "Jugador 1"
	_live_avatar.team_color = Color(0.05, 0.78, 0.92)
	stage_root.add_child(_live_avatar)
	_live_avatar.configure_stage(GameConfig.arena_stage, 4.0)
	_live_avatar.set_twin_blades(GameConfig.combat_style == GameConfig.CombatStyle.TWIN_BLADES)
	_live_avatar.reset_for_round(Vector3(1.25, 0.0, -0.20), Vector2(-0.20, -0.98))
	_live_avatar.slash_impact.connect(_on_live_slash_impact)

	_dummy_avatar = AVATAR_SCENE.instantiate() as AvatarFighter
	_dummy_avatar.fighter_name = "Muñeco Dojo"
	_dummy_avatar.team_color = Color(0.95, 0.62, 0.16)
	stage_root.add_child(_dummy_avatar)
	_dummy_avatar.configure_stage(GameConfig.arena_stage, 4.0)
	_dummy_avatar.reset_for_round(_dummy_home, Vector2(0.20, 0.98))

	var live_phone_nodes := _create_phone_rig(Vector3(1.42, 1.52, 1.58), Color(0.08, 0.80, 0.98), false)
	_live_phone_roll = live_phone_nodes["roll"]
	_live_phone_tilt = live_phone_nodes["tilt"]
	_live_thumb_dot = live_phone_nodes["thumb"]
	_live_screen_mat = live_phone_nodes["screen_mat"]


func _create_phone_rig(pos: Vector3, tint: Color, is_coach: bool) -> Dictionary:
	var mount := Node3D.new()
	mount.position = pos
	stage_root.add_child(mount)

	# Correct Euler parenting: tilt pitch forward FIRST, then child twists cleanly along the tilted phone shaft!
	var tilt_pivot := Node3D.new()
	mount.add_child(tilt_pivot)

	var roll_pivot := Node3D.new()
	tilt_pivot.add_child(roll_pivot)

	var body := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.24, 0.44, 0.036)
	body.mesh = bm
	var body_mat := StandardMaterial3D.new()
	body_mat.albedo_color = Color(0.10, 0.12, 0.16)
	body_mat.roughness = 0.25
	body.material_override = body_mat
	roll_pivot.add_child(body)

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
	roll_pivot.add_child(screen)

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
	roll_pivot.add_child(blade)

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
	roll_pivot.add_child(thumb)

	var out := {
		"roll": roll_pivot,
		"tilt": tilt_pivot,
		"thumb": thumb,
		"screen_mat": screen_mat
	}

	if is_coach:
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

	_shader_time += delta
	var wmat: ShaderMaterial = _stage_refs.get("water_mat")
	if wmat != null:
		wmat.set_shader_parameter("u_time", _shader_time)

	_step_sparks(delta)
	_animate_coach(delta)
	_update_live_player(delta)
	_update_sparring_dummy(delta)


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
	var target_pitch := -0.68
	var target_z_offset := 0.0
	var guarding := false

	match _active_step:
		0:
			target_roll = 0.0
			target_pitch = -0.68 + sin(_step_t * 2.5) * 0.03
		1:
			var poses := [0.0, PI * 0.25, PI * 0.5, -PI * 0.25]
			var idx := int(floor(_step_t / 0.85)) % poses.size()
			target_roll = poses[idx]
			target_pitch = -0.68
		2:
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
		3:
			var sub_len := 3.4
			var sub_cyc := int(floor(_step_t / sub_len))
			var sp := fmod(_step_t, sub_len)
			if sp < 1.75:
				guarding = true
				target_roll = 0.0
				target_pitch = -0.68
				_coach_thumb_dot.visible = true
				_coach_enemy_bar.visible = true
				_coach_enemy_bar.rotation.z = 0.0
				if sp > 0.95 and sp < 1.50:
					_coach_parry_ring.visible = true
					_coach_parry_ring.scale = Vector3.ONE * (0.9 + (sp - 0.95) * 1.4)
			else:
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

	_coach_phone_tilt.rotation.x = lerpf(_coach_phone_tilt.rotation.x, target_pitch, clampf(delta * 18.0, 0.0, 1.0))
	_coach_phone_tilt.position.z = lerpf(_coach_phone_tilt.position.z, target_z_offset, clampf(delta * 18.0, 0.0, 1.0))
	_coach_phone_roll.rotation.z = lerp_angle(_coach_phone_roll.rotation.z, -target_roll, clampf(delta * 14.0, 0.0, 1.0))

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
		if _live_avatar.state == AvatarFighter.State.SLASHING and not _live_avatar._hit_resolved_this_swing:
			_live_avatar.update_live_slash_power(s0.fusion.compute_live_power_from_peak(s0.fusion.active_peak_speed))
		if _live_avatar.state == AvatarFighter.State.NORMAL:
			if s0.just_dodge_pressed:
				_live_avatar.trigger_dodge(s0.move_axis)
			elif s0.buffered_strike_timer > 0.0 or s0.fusion.just_swung:
				var atk_t := s0.buffered_strike_type if s0.buffered_strike_timer > 0.0 else s0.fusion.last_slash_type
				var dir := s0.buffered_strike_dir if s0.buffered_strike_timer > 0.0 else s0.fusion.last_slash_dir
				var pwr := s0.buffered_strike_power if s0.buffered_strike_timer > 0.0 else s0.fusion.last_slash_power
				s0.buffered_strike_timer = 0.0
				_live_avatar.trigger_slash(dir, pwr, atk_t)
				_swing_flash_timer = 1.35
				var spd_tier := "¡CRÍTICO!" if pwr >= 1.35 else ("Rápido" if pwr >= 0.85 else "Suave")
				var kind_txt := "⚡ ESTOCADA" if atk_t == AvatarFighter.AttackType.THRUST else _describe_slash_dir(dir)
				_last_attack_label = "✅ %s (%s | %.1fx)" % [kind_txt, spd_tier, pwr]
				MotionHub.trigger_rumble(0, 0.5, 0.09)

		var target_dummy_pos := _dummy_avatar.position if _dummy_avatar else Vector3(0.9, 0.0, -2.0)
		_live_avatar.step_fighter(delta, s0.move_axis * 0.4, target_dummy_pos, true)
		_live_avatar.position = _live_avatar.position.lerp(Vector3(1.25, 0.0, -0.20), clampf(delta * 4.5, 0.0, 1.0))

	if _live_phone_roll and _live_phone_tilt:
		var roll_s := s0.fusion.get_snapped_blade_roll_rad()
		_live_phone_tilt.rotation.x = lerpf(_live_phone_tilt.rotation.x, -0.68 + clampf(s0.fusion.pitch_rad * 0.85, -0.95, 0.75), clampf(delta * 18.0, 0.0, 1.0))
		_live_phone_tilt.rotation.y = lerpf(_live_phone_tilt.rotation.y, clampf(s0.fusion.yaw_rad * 0.7, -0.7, 0.7), clampf(delta * 16.0, 0.0, 1.0))
		_live_phone_roll.rotation.z = lerp_angle(_live_phone_roll.rotation.z, -roll_s, clampf(delta * 20.0, 0.0, 1.0))
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
		swing_badge.text = "Vel. Punta: %.0f%% (Muñeco hits: %d)" % [pct, _dummy_hits]
		swing_badge.add_theme_color_override("font_color", Color(0.75, 0.92, 1.0))

	p1_stats.text = "J1 [%s] | Vel %.1f | Empuje %.1f m/s² | Hoja %.0f° | Guardia: %s" % [
		s0.device_name,
		s0.fusion.tip_speed,
		s0.fusion.dynamic_accel_mag,
		s0.fusion.get_blade_angle_deg(),
		"ACTIVA" if s0.is_guarding else "Libre"
	]

	var s1: MotionHub.PlayerSlot = MotionHub.slots[1]
	p2_stats.text = "Muñeco Dojo: Guardia %.0f° | J2 [%s]" % [
		rad_to_deg(_dummy_avatar.blade_roll_rad) if _dummy_avatar else 0.0,
		s1.device_name
	]


func _update_sparring_dummy(delta: float) -> void:
	if _dummy_avatar == null:
		return
	_dummy_guard_timer += delta
	if _dummy_guard_timer >= 2.2:
		_dummy_guard_timer = 0.0
		_dummy_angle_idx = (_dummy_angle_idx + 1) % _dummy_guard_angles.size()
	_dummy_avatar.is_guarding = true
	_dummy_avatar.blade_roll_rad = lerp_angle(_dummy_avatar.blade_roll_rad, _dummy_guard_angles[_dummy_angle_idx], clampf(delta * 9.0, 0.0, 1.0))
	_dummy_avatar.step_fighter(delta, Vector2.ZERO, _live_avatar.position if _live_avatar else Vector3(1.25, 0.0, -0.20), true)
	_dummy_avatar.position = _dummy_avatar.position.lerp(_dummy_home, clampf(delta * 4.5, 0.0, 1.0))


func _on_live_slash_impact(_att: AvatarFighter, slash_dir: Vector2, power: float, atk_type: int) -> void:
	if _dummy_avatar == null:
		return
	_dummy_hits += 1
	var mid := (_live_avatar.position + _dummy_avatar.position) * 0.5 + Vector3(0.0, 1.05, 0.0)
	var sfx := get_node_or_null("/root/SoundFX")

	if atk_type == AvatarFighter.AttackType.THRUST:
		_dummy_avatar.apply_knockback(Vector2(-0.2, -1.0) * (3.2 * power))
		_spawn_sparks(mid, Color(1.0, 0.85, 0.25), 14)
		if sfx:
			sfx.play("hit", 1.15, -3.0)
		_last_attack_label = "⚡ ¡ESTOCADA AL MUÑECO! (Perfora guardia)"
	else:
		var dot := absf(_dummy_avatar.get_world_blade_axis().dot(_live_avatar.get_world_slash_axis(slash_dir)))
		if dot > 0.62:
			_dummy_avatar.apply_knockback(Vector2(-0.2, -1.0) * (3.6 * power))
			_spawn_sparks(mid, Color(1.0, 0.45, 0.2), 16)
			if sfx:
				sfx.play("guard_break", 0.95, -3.0)
			_last_attack_label = "💥 ¡ROMPISTE LA GUARDIA DEL MUÑECO!"
		else:
			_dummy_avatar.apply_knockback(Vector2(-0.2, -1.0) * 1.1)
			_spawn_sparks(mid, Color(0.35, 0.94, 1.0), 12)
			if sfx:
				sfx.play("block", 1.05, -4.0)
			_last_attack_label = "🛡️ ¡MUÑECO BLOQUEÓ EN CRUZ! (Gira muñeca para romper)"
	_swing_flash_timer = 1.4


func _spawn_sparks(world_pos: Vector3, col: Color, count: int) -> void:
	var smat := StandardMaterial3D.new()
	smat.albedo_color = col
	smat.emission_enabled = true
	smat.emission = col * 2.1
	var smesh := SphereMesh.new()
	smesh.radius = 0.045
	smesh.height = 0.09
	for i in count:
		var sp := MeshInstance3D.new()
		sp.mesh = smesh
		sp.material_override = smat
		sp.position = world_pos
		stage_root.add_child(sp)
		_sparks.append({"node": sp, "vel": Vector3(randf_range(-4.0, 4.0), randf_range(0.8, 4.2), randf_range(-4.0, 4.0)), "life": randf_range(0.16, 0.30)})


func _step_sparks(delta: float) -> void:
	for i in range(_sparks.size() - 1, -1, -1):
		var s := _sparks[i]
		s["life"] -= delta
		var n: MeshInstance3D = s["node"]
		if s["life"] <= 0.0 or not is_instance_valid(n):
			if is_instance_valid(n):
				n.queue_free()
			_sparks.remove_at(i)
		else:
			s["vel"].y -= 14.0 * delta
			n.position += s["vel"] * delta


func _describe_slash_dir(d: Vector2) -> String:
	var ax := absf(d.x)
	var ay := absf(d.y)
	if ax > ay * 1.8:
		return "HORIZONTAL —"
	if ay > ax * 1.8:
		return "VERTICAL |"
	return "DIAGONAL \\" if (d.x * d.y > 0.0) else "DIAGONAL /"


func _refresh_step_ui() -> void:
	var captions := [
		"PASO 1 — POSTURA BASE: Sujeta el móvil a ~45° apuntando a la pantalla como empuñadura y pulsa 🎯 CENTRAR.",
		"PASO 2 — GIRAR LA HOJA: Gira SOLO la muñeca (el eje de la hoja no dispara falsos golpes) y alinea contra el Muñeco Dojo.",
		"PASO 3 — VELOCIDAD REAL: Arma hacia atrás o da un látigo rápido de muñeca/brazo (o ⚡ Estocada) para golpear al Muñeco Dojo.",
		"PASO 4 — GUARDIA Y PARRY: Pulsa GUARDIA justo al impacto (<0.22s) para Parry Dorado, o Esquiva (Espacio / ◀ ▶)."
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
