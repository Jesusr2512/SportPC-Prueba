extends Node3D

const AvatarFighterScene := preload("res://scenes/AvatarFighter.tscn")
const DojoStageScript := preload("res://scripts/game/DojoStage.gd")

enum MatchPhase { CALIBRATE_ENTRY, INTRO, FIGHTING, ROUND_OVER, MATCH_OVER }

@onready var arena_visuals: Node3D = $ArenaVisuals
@onready var world_env: WorldEnvironment = $WorldEnvironment
@onready var sun_light: DirectionalLight3D = $DirectionalLight3D
@onready var cam: Camera3D = $Camera3D
@onready var ui_layer: CanvasLayer = $UI

@onready var score_p1_lbl: Label = $UI/HUD/TopCard/TopVBox/TopBar/ScoreP1
@onready var timer_lbl: Label = $UI/HUD/TopCard/TopVBox/TopBar/TimerLabel
@onready var score_p2_lbl: Label = $UI/HUD/TopCard/TopVBox/TopBar/ScoreP2
@onready var ring_bar: Control = $UI/HUD/TopCard/TopVBox/RingBalanceBar
@onready var banner_lbl: Label = $UI/HUD/BannerLabel
@onready var reticle_hud: Control = $UI/HUD/ReticleRow/ReticleHUD

@onready var status_p1_lbl: Label = $UI/HUD/BottomCard/BottomInfo/StatusP1
@onready var status_p2_lbl: Label = $UI/HUD/BottomCard/BottomInfo/StatusP2
@onready var recenter_p2_btn: Button = $UI/HUD/BottomCard/BottomInfo/RecenterP2
@onready var calib_panel: PanelContainer = $UI/CalibPanel
@onready var calib_title: Label = $UI/CalibPanel/VBox/CalibTitle
@onready var calib_desc: Label = $UI/CalibPanel/VBox/CalibDesc
@onready var calib_progress: ProgressBar = $UI/CalibPanel/VBox/CalibProgress
@onready var victory_panel: PanelContainer = $UI/VictoryPanel
@onready var victory_title: Label = $UI/VictoryPanel/VBox/VictoryTitle

var f1: AvatarFighter
var f2: AvatarFighter

var phase: MatchPhase = MatchPhase.CALIBRATE_ENTRY
var phase_timer: float = 0.0
var round_time: float = 45.0
var round_number: int = 1
var score_p1: int = 0
var score_p2: int = 0

var _hub: Node
var _sfx: Node
var _stage_refs: Dictionary = {}
var _stage_type: int = GameConfig.ArenaStage.SUN_ISLAND
var _sparks: Array[Dictionary] = []
var _waves: Array[Dictionary] = []

var _shake_timer: float = 0.0
var _shake_strength: float = 0.0
var _hitstop_timer: float = 0.0
var _slowmo_timer: float = 0.0
var _cam_fov_punch: float = 0.0
var _shader_time: float = 0.0

var _calib_steady_time: float = 0.0
var _calib_total_time: float = 0.0
var _last_calib_pips: int = 0
var script_ai_and_input_enabled: bool = true

# AI state
var _ai_timer: float = 0.85
var _ai_target_roll: float = 0.0
var _ai_move: Vector2 = Vector2.ZERO
var _ai_strafe_timer: float = 0.0
var _ai_guard_pressure: float = 0.0

# Optional 2P split-screen rig
var _split_root: HBoxContainer
var _split_cam_p1: Camera3D
var _split_cam_p2: Camera3D


func _ready() -> void:
	_hub = get_node_or_null("/root/MotionHub")
	_sfx = get_node_or_null("/root/SoundFX")
	if _hub != null:
		_hub.mouse_combat_enabled = true
	Engine.time_scale = 1.0

	_stage_type = GameConfig.arena_stage
	_build_arena()
	_spawn_fighters()
	_setup_cameras()
	_style_hud()

	ring_bar.draw.connect(_on_draw_ring_bar)
	reticle_hud.draw.connect(_on_draw_reticle)

	recenter_p2_btn.visible = (GameConfig.match_mode == "2p")
	begin_entry_calibration(false)


func _exit_tree() -> void:
	Engine.time_scale = 1.0
	if _hub != null:
		_hub.mouse_combat_enabled = true


func _build_arena() -> void:
	_stage_refs = DojoStageScript.build_stage(arena_visuals, _stage_type)
	if world_env and world_env.environment:
		var env := world_env.environment
		if env.sky and env.sky.sky_material is ProceduralSkyMaterial:
			var sky_mat: ProceduralSkyMaterial = env.sky.sky_material
			match _stage_type:
				GameConfig.ArenaStage.VOLCANIC_BRIDGE:
					sky_mat.sky_top_color = Color(0.18, 0.05, 0.04)
					sky_mat.sky_horizon_color = Color(0.75, 0.28, 0.12)
					env.ambient_light_color = Color(1.0, 0.68, 0.52)
					if sun_light:
						sun_light.light_color = Color(1.0, 0.78, 0.58)
				GameConfig.ArenaStage.SKY_SANCTUARY:
					sky_mat.sky_top_color = Color(0.08, 0.38, 0.88)
					sky_mat.sky_horizon_color = Color(0.84, 0.94, 1.0)
					env.ambient_light_color = Color(0.92, 0.96, 1.0)
					if sun_light:
						sun_light.light_color = Color(1.0, 0.98, 0.92)
				_:
					sky_mat.sky_top_color = Color(0.12, 0.50, 0.92)
					sky_mat.sky_horizon_color = Color(0.74, 0.92, 1.0)
					env.ambient_light_color = Color(0.95, 0.97, 1.0)


func _spawn_fighters() -> void:
	f1 = AvatarFighterScene.instantiate()
	f1.fighter_name = "Jugador 1"
	f1.team_color = Color(0.06, 0.80, 0.96)
	add_child(f1)

	f2 = AvatarFighterScene.instantiate()
	f2.fighter_name = "Jugador 2" if GameConfig.match_mode == "2p" else "IA (%s)" % GameConfig.get_ai_name()
	f2.team_color = Color(0.98, 0.34, 0.22)
	add_child(f2)

	var use_twins := GameConfig.combat_style == GameConfig.CombatStyle.TWIN_BLADES
	for f: AvatarFighter in [f1, f2]:
		f.configure_stage(_stage_type)
		f.set_twin_blades(use_twins)
		f.slash_executed.connect(_on_fighter_slash)
		f.slash_impact.connect(_on_fighter_impact)
		f.dodge_started.connect(_on_fighter_dodge)
		f.fell_off_ring.connect(_on_fighter_fell)

	_place_fighters_at_spawn()


func _setup_cameras() -> void:
	if _split_root != null:
		_split_root.queue_free()
		_split_root = null
		_split_cam_p1 = null
		_split_cam_p2 = null

	if GameConfig.match_mode == "2p":
		cam.current = false
		_split_root = HBoxContainer.new()
		_split_root.name = "SplitScreenRoot"
		_split_root.set_anchors_preset(Control.PRESET_FULL_RECT)
		_split_root.add_theme_constant_override("separation", 4)
		_split_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ui_layer.add_child(_split_root)
		ui_layer.move_child(_split_root, 0)

		var shared_world := get_viewport().find_world_3d()
		for i in 2:
			var svc := SubViewportContainer.new()
			svc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			svc.size_flags_vertical = Control.SIZE_EXPAND_FILL
			svc.stretch = true
			svc.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_split_root.add_child(svc)

			var sv := SubViewport.new()
			sv.world_3d = shared_world
			sv.handle_input_locally = false
			svc.add_child(sv)

			var sc := Camera3D.new()
			sc.fov = 52.0
			sv.add_child(sc)
			if i == 0:
				_split_cam_p1 = sc
			else:
				_split_cam_p2 = sc
	else:
		cam.current = true


func _style_hud() -> void:
	var top_card := get_node_or_null("UI/HUD/TopCard")
	if top_card is PanelContainer:
		var st := StyleBoxFlat.new()
		st.bg_color = Color(0.05, 0.11, 0.21, 0.78)
		st.corner_radius_top_left = 14
		st.corner_radius_top_right = 14
		st.corner_radius_bottom_left = 14
		st.corner_radius_bottom_right = 14
		st.content_margin_left = 16
		st.content_margin_right = 16
		st.content_margin_top = 8
		st.content_margin_bottom = 8
		top_card.add_theme_stylebox_override("panel", st)

	var bot_card := get_node_or_null("UI/HUD/BottomCard")
	if bot_card is PanelContainer:
		var st2 := StyleBoxFlat.new()
		st2.bg_color = Color(0.05, 0.11, 0.21, 0.78)
		st2.corner_radius_top_left = 12
		st2.corner_radius_top_right = 12
		st2.corner_radius_bottom_left = 12
		st2.corner_radius_bottom_right = 12
		st2.content_margin_left = 14
		st2.content_margin_right = 14
		st2.content_margin_top = 7
		st2.content_margin_bottom = 7
		bot_card.add_theme_stylebox_override("panel", st2)


func _place_fighters_at_spawn() -> void:
	# Both 1P and 2P spawn along Z so narrow bridges work symmetrically and split cameras align!
	f1.reset_for_round(Vector3(0.0, 0.0, 0.92), Vector2(0.0, -1.0))
	f2.reset_for_round(Vector3(0.0, 0.0, -0.92), Vector2(0.0, 1.0))


func begin_entry_calibration(skip_recenter: bool = false) -> void:
	Engine.time_scale = 1.0
	_slowmo_timer = 0.0
	_hitstop_timer = 0.0
	if not skip_recenter and _hub != null:
		_hub.recenter_slot(0)
		_hub.recenter_slot(1)
	phase = MatchPhase.CALIBRATE_ENTRY
	_calib_steady_time = 0.0
	_calib_total_time = 0.0
	_last_calib_pips = 0
	calib_panel.visible = true
	calib_progress.value = 0.0
	calib_title.text = "CENTRA TU ESPADA (%s)" % GameConfig.get_stage_name().to_upper()
	calib_desc.text = (
		"Apunta el móvil o mando hacia el centro de la pantalla.\n" +
		"Se calibrará al quedarte quieto 0.4s — o pulsa GUARDIA / Botón para entrar ya."
	)
	banner_lbl.text = ""
	victory_panel.visible = false
	_place_fighters_at_spawn()


func _complete_entry_calibration() -> void:
	if _hub != null:
		_hub.recenter_slot(0)
		if GameConfig.match_mode == "2p":
			_hub.recenter_slot(1)
		_hub.trigger_rumble(0, 0.65, 0.14)
	if _sfx != null and _sfx.has_method("play_bell"):
		_sfx.play_bell()
	calib_panel.visible = false
	score_p1 = 0
	score_p2 = 0
	round_number = 1
	_start_round()


func _start_round() -> void:
	Engine.time_scale = 1.0
	_slowmo_timer = 0.0
	_hitstop_timer = 0.0
	_clear_active_waves()
	_place_fighters_at_spawn()
	round_time = 45.0
	phase = MatchPhase.INTRO
	phase_timer = 1.35
	victory_panel.visible = false
	calib_panel.visible = false
	_ai_timer = randf_range(0.6, 1.05)
	_ai_guard_pressure = 0.0
	banner_lbl.text = "¡RONDA %d!" % round_number
	if _sfx != null and _sfx.has_method("play_bell"):
		_sfx.play_bell()


func _process(delta: float) -> void:
	var real_dt := (delta / maxf(Engine.time_scale, 0.05)) if Engine.time_scale < 0.99 else delta

	_shader_time += real_dt
	var wmat: ShaderMaterial = _stage_refs.get("water_mat")
	if wmat != null:
		wmat.set_shader_parameter("u_time", _shader_time)

	_cam_fov_punch = maxf(0.0, _cam_fov_punch - real_dt * 18.0)

	# Slow-motion countdown uses unscaled real_dt so it never deadlocks!
	if _slowmo_timer > 0.0:
		_slowmo_timer = maxf(0.0, _slowmo_timer - real_dt)
		if _slowmo_timer <= 0.0:
			Engine.time_scale = 1.0

	if _shake_timer > 0.0:
		_shake_timer = maxf(0.0, _shake_timer - real_dt)

	_step_sparks(real_dt)
	_step_waves(delta)
	_step_stage_physics(real_dt)

	if _hitstop_timer > 0.0:
		_hitstop_timer = maxf(0.0, _hitstop_timer - real_dt)
		_update_camera(real_dt)
		_update_hud()
		return

	if phase == MatchPhase.CALIBRATE_ENTRY:
		_step_entry_calibration(real_dt)
		f1.step_fighter(delta, Vector2.ZERO, f2.position, false)
		f2.step_fighter(delta, Vector2.ZERO, f1.position, false)
		_update_camera(real_dt)
		_update_hud()
		return

	if _hub != null and _hub.slots[0].just_recenter_pressed:
		_hub.recenter_slot(0)
	if GameConfig.match_mode == "2p" and _hub != null and _hub.slots[1].just_recenter_pressed:
		_hub.recenter_slot(1)

	var can_act := (phase == MatchPhase.FIGHTING)
	var move_p1 := Vector2.ZERO
	var move_p2 := Vector2.ZERO

	if can_act and _hub != null and script_ai_and_input_enabled:
		move_p1 = _drive_human_slot(0, f1, delta)
		if GameConfig.match_mode == "2p":
			move_p2 = _drive_human_slot(1, f2, delta)
		else:
			move_p2 = _drive_ai(delta)

	f1.step_fighter(delta, move_p1, f2.position, can_act)
	f2.step_fighter(delta, move_p2, f1.position, can_act)

	if _hub != null:
		_hub.slots[0].hud_guard_meter = f1.guard_meter
		_hub.slots[0].hud_spirit = f1.spirit
		if GameConfig.match_mode == "2p":
			_hub.slots[1].hud_guard_meter = f2.guard_meter
			_hub.slots[1].hud_spirit = f2.spirit

	if can_act:
		_enforce_3d_duel_spacing(delta)

	match phase:
		MatchPhase.INTRO:
			phase_timer -= delta
			if phase_timer < 0.45:
				banner_lbl.text = "¡DUELO!"
			if phase_timer <= 0.0:
				phase = MatchPhase.FIGHTING
				banner_lbl.text = ""
		MatchPhase.FIGHTING:
			round_time = maxf(0.0, round_time - delta)
			if round_time <= 10.0:
				var rim_mat: StandardMaterial3D = _stage_refs.get("rim_mat")
				if rim_mat != null:
					rim_mat.emission_enabled = true
					rim_mat.emission = Color(1.0, 0.25, 0.15) * (0.45 + 0.35 * sin(_shader_time * 9.0))
				if banner_lbl.text == "" and round_time > 9.3:
					banner_lbl.text = "¡MUERTE SÚBITA! (+Empuje)"
			if round_time <= 0.0:
				_resolve_timeout()
		MatchPhase.ROUND_OVER:
			phase_timer -= delta
			if phase_timer <= 0.0:
				if score_p1 >= 2 or score_p2 >= 2:
					_finish_match()
				else:
					round_number += 1
					_start_round()
		MatchPhase.MATCH_OVER:
			pass

	_update_camera(real_dt)
	_update_hud()
	ring_bar.queue_redraw()
	reticle_hud.queue_redraw()


func _step_stage_physics(real_dt: float) -> void:
	if _stage_type != GameConfig.ArenaStage.SKY_SANCTUARY:
		return
	var pivot: Node3D = _stage_refs.get("platform_pivot")
	if pivot == null:
		return
	var com := (f1.position + f2.position) * 0.5
	var target_rx := clampf(com.z * 0.025, -0.08, 0.08)
	var target_rz := clampf(-com.x * 0.025, -0.08, 0.08)
	pivot.rotation.x = lerpf(pivot.rotation.x, target_rx, clampf(real_dt * 4.0, 0.0, 1.0))
	pivot.rotation.z = lerpf(pivot.rotation.z, target_rz, clampf(real_dt * 4.0, 0.0, 1.0))


func _step_entry_calibration(delta: float) -> void:
	_calib_total_time += delta
	if _hub == null:
		calib_progress.value = 100.0
		_complete_entry_calibration()
		return

	var s0 = _hub.slots[0]
	f1.blade_orientation = s0.fusion.orientation
	f1.blade_roll_rad = s0.fusion.blade_roll_rad

	var is_quiet: bool = s0.fusion.angular_speed < 0.72 and not s0.fusion.just_swung
	if is_quiet:
		_calib_steady_time += delta
	else:
		_calib_steady_time = maxf(0.0, _calib_steady_time - delta * 1.1)

	var pct := clampf(_calib_steady_time / 0.42, 0.0, 1.0)
	calib_progress.value = pct * 100.0

	var pips := int(pct * 3.0)
	if pips > _last_calib_pips and pips < 3:
		_last_calib_pips = pips
		if _sfx != null:
			_sfx.play("parry", 0.9 + pips * 0.15, -10.0)

	if s0.just_guard_pressed or s0.just_strike_pressed or Input.is_action_just_pressed("ui_accept") or _calib_steady_time >= 0.42 or _calib_total_time >= 4.0:
		_complete_entry_calibration()


func _drive_human_slot(slot_idx: int, fighter: AvatarFighter, _delta: float) -> Vector2:
	var s = _hub.slots[slot_idx]
	fighter.blade_orientation = s.fusion.orientation
	fighter.blade_roll_rad = s.fusion.blade_roll_rad
	fighter.is_guarding = s.is_guarding
	fighter.auto_guard_ready = (not s.is_guarding) and s.fusion.is_steady

	# Stream latest flick acceleration so early-threshold swings still hit with full arm speed!
	if fighter.state == AvatarFighter.State.SLASHING and not fighter._hit_resolved_this_swing:
		var live_p: float = s.fusion.compute_live_power_from_peak(s.fusion.active_peak_speed)
		fighter.update_live_slash_power(live_p)

	if fighter.state == AvatarFighter.State.NORMAL:
		if s.just_dodge_pressed:
			fighter.trigger_dodge(s.move_axis)
			return Vector2.ZERO
		if s.buffered_strike_timer > 0.0:
			var atk_t: int = s.buffered_strike_type
			var dir: Vector2 = s.buffered_strike_dir
			var pow_val: float = s.buffered_strike_power
			s.buffered_strike_timer = 0.0
			fighter.trigger_slash(dir, pow_val, atk_t)
		elif s.fusion.just_swung:
			fighter.trigger_slash(s.fusion.last_slash_dir, s.fusion.last_slash_power, s.fusion.last_slash_type)
			s.buffered_strike_timer = 0.0

	var mv: Vector2 = s.move_axis
	if slot_idx == 0 and mv.length() < 0.05:
		var kx := Input.get_axis("ui_left", "ui_right")
		var ky := Input.get_axis("ui_up", "ui_down")
		mv = Vector2(kx, ky).limit_length(1.0)
	if Input.is_action_just_pressed("ui_accept") and slot_idx == 0 and s.source_type != MotionHub.SourceType.MOUSE:
		fighter.trigger_dodge(mv)
	return mv


func _drive_ai(delta: float) -> Vector2:
	if f2.state == AvatarFighter.State.STUNNED or f2.state == AvatarFighter.State.FALLING:
		f2.is_guarding = false
		return Vector2.ZERO

	_ai_timer -= delta
	_ai_strafe_timer -= delta
	var level := clampi(GameConfig.ai_difficulty, 0, 3)
	var diff_reaction: float = [0.22, 0.14, 0.075, 0.03][level]
	var guard_chance: float = [0.35, 0.56, 0.78, 0.90][level]
	var atk_rate_min: float = [1.15, 0.78, 0.52, 0.35][level]
	var atk_rate_max: float = [1.65, 1.25, 0.85, 0.58][level]
	var windup_dur: float = [0.68, 0.50, 0.36, 0.25][level]

	var to_p1 := Vector2(f1.position.x - f2.position.x, f1.position.z - f2.position.z)
	var dist := to_p1.length()
	var f2_pos := Vector2(f2.position.x, f2.position.z)
	var edge_danger := DojoStageScript.get_edge_ratio(f2_pos, _stage_type)

	if f1.is_guarding:
		_ai_guard_pressure += delta
	else:
		_ai_guard_pressure = maxf(0.0, _ai_guard_pressure - delta * 2.0)

	if _ai_strafe_timer <= 0.0:
		_ai_strafe_timer = randf_range(0.55, 1.15)
		_ai_move.x = randf_range(-0.85, 0.85)

	# Footwork: hold sweetspot distance ~1.8m, stay centered away from abyss/lava
	if edge_danger > 0.68:
		var back_to_center := -f2_pos.normalized()
		var fwd := f2.facing_dir
		var right := Vector2(-fwd.y, fwd.x)
		_ai_move = Vector2(back_to_center.dot(right), -back_to_center.dot(fwd)).limit_length(1.0)
		if level >= 2 and edge_danger > 0.80 and f2.state == AvatarFighter.State.NORMAL and f2.dodge_cooldown_timer <= 0.0:
			f2.trigger_dodge(_ai_move)
	elif dist > 2.35:
		_ai_move.y = -0.78
	elif dist < 1.38:
		_ai_move.y = 0.65
	else:
		_ai_move.y = 0.0

	if f2.state == AvatarFighter.State.NORMAL:
		if f1.state == AvatarFighter.State.STUNNED and _ai_timer > 0.28:
			_ai_timer = 0.14

		if f1.state == AvatarFighter.State.SLASHING and f1.attack_type == AvatarFighter.AttackType.CUT:
			f2.is_guarding = (randf() < guard_chance)
			var perp_roll := wrapf(atan2(f1.active_slash_dir.y, f1.active_slash_dir.x), -PI * 0.5, PI * 0.5)
			if level <= 1 and randf() < 0.35:
				perp_roll += PI * 0.5
			_ai_target_roll = clampf(perp_roll, -PI * 0.5, PI * 0.5)
		elif f1.is_guarding and level >= 1 and _ai_timer < 0.25:
			f2.is_guarding = false
			var p1_guard_axis := atan2(f1.get_guard_blade_dir_2d().y, f1.get_guard_blade_dir_2d().x)
			_ai_target_roll = clampf(wrapf(p1_guard_axis, -PI * 0.5, PI * 0.5), -PI * 0.5, PI * 0.5)
		elif _ai_timer < diff_reaction:
			f2.is_guarding = false

		f2.blade_roll_rad = lerp_angle(f2.blade_roll_rad, _ai_target_roll, clampf(delta * 10.5, 0.0, 1.0))

		if _ai_timer <= 0.0 and dist < 2.95:
			_ai_timer = randf_range(atk_rate_min, atk_rate_max)
			var use_thrust := (_ai_guard_pressure > 1.25 and level >= 1 and randf() < 0.55)
			var dirs: Array[Vector2] = [
				Vector2(1.0, 0.0), Vector2(-1.0, 0.0),
				Vector2(0.0, 1.0), Vector2(0.0, -1.0),
				Vector2(0.707, 0.707), Vector2(-0.707, 0.707),
				Vector2(0.707, -0.707), Vector2(-0.707, -0.707)
			]
			var chosen: Vector2 = dirs[randi() % dirs.size()]
			if level >= 1 and f1.is_guarding and not use_thrust:
				var p1_blade := f1.get_guard_blade_dir_2d()
				chosen = p1_blade if randf() < 0.78 else chosen
			if use_thrust:
				_ai_guard_pressure = 0.0
				f2.start_windup(Vector2(0.0, -1.0), windup_dur * 0.9, AvatarFighter.AttackType.THRUST)
			else:
				f2.start_windup(chosen, windup_dur, AvatarFighter.AttackType.CUT)

	return _ai_move


func _on_fighter_slash(attacker: AvatarFighter, _slash_dir: Vector2, power: float) -> void:
	if phase != MatchPhase.FIGHTING:
		return
	var step_spd := (1.85 + power * 0.72) if attacker.attack_type == AvatarFighter.AttackType.THRUST else (1.15 + power * 0.55)
	attacker.velocity_xz += attacker.facing_dir * step_spd

	# Release Master Blade Crescent Energy Wave when swinging at 100% Spirit!
	if attacker.spirit >= 100.0 and attacker.attack_type != AvatarFighter.AttackType.WAVE:
		attacker.spirit = 0.0
		_spawn_spirit_wave(attacker, attacker.active_slash_dir, maxf(power, 1.25))


func _on_fighter_dodge(fighter: AvatarFighter, dodge_dir: Vector2) -> void:
	_spawn_sparks(fighter.position + Vector3(0.0, 0.3, 0.0) - Vector3(dodge_dir.x, 0.0, dodge_dir.y) * 0.25, Color(0.55, 0.95, 1.0), 8)


func _on_fighter_impact(attacker: AvatarFighter, slash_dir: Vector2, power: float, atk_type: int) -> void:
	if phase != MatchPhase.FIGHTING:
		return
	var defender: AvatarFighter = f2 if attacker == f1 else f1
	_resolve_melee_exchange(attacker, defender, slash_dir, power, atk_type)


func _resolve_melee_exchange(attacker: AvatarFighter, defender: AvatarFighter, slash_dir: Vector2, power: float, atk_type: int) -> void:
	if defender.state == AvatarFighter.State.FALLING or attacker.state == AvatarFighter.State.FALLING:
		return

	var att_idx := 0 if attacker == f1 else 1
	var def_idx := 1 if attacker == f1 else 0
	var dir_to_def := Vector2(defender.position.x - attacker.position.x, defender.position.z - attacker.position.z)
	var dist_xz := dir_to_def.length()
	var max_reach := 3.15 if atk_type == AvatarFighter.AttackType.THRUST else (2.72 if attacker.twin_blades_enabled else 2.85)
	if dist_xz > max_reach:
		return

	var push_dir := dir_to_def.normalized() if dist_xz > 0.05 else attacker.facing_dir
	var mid := (attacker.position + defender.position) * 0.5 + Vector3(0.0, 1.15, 0.0)
	var sd_mult := 1.22 if round_time <= 10.0 else 1.0

	# 1. Sidestep dodge i-frames!
	if defender.iframe_timer > 0.0:
		defender.spirit = minf(100.0, defender.spirit + 20.0)
		attacker.velocity_xz += push_dir * 0.7
		_spawn_sparks(mid, Color(0.5, 0.96, 1.0), 10)
		if _sfx:
			_sfx.play("dash", 1.25, -4.0)
		banner_lbl.text = "¡ESQUIVA PERFECTA! (%s)" % defender.fighter_name
		return

	# 2. Simultaneous Sword Clash!
	if defender.state == AvatarFighter.State.SLASHING or (defender.state == AvatarFighter.State.WINDUP and defender.windup_timer < 0.26):
		attacker.cancel_attack_from_clash(-push_dir * 1.45)
		defender.cancel_attack_from_clash(push_dir * 1.45)
		attacker.spirit = minf(100.0, attacker.spirit + 12.0)
		defender.spirit = minf(100.0, defender.spirit + 12.0)
		_spawn_sparks(mid, Color(1.0, 0.95, 0.55), 18)
		_hitstop_timer = 0.045
		_trigger_shake(0.16, 0.11)
		if _sfx:
			_sfx.play("parry", 0.92, -1.5)
		if _hub != null:
			_hub.trigger_rumble(0, 0.7, 0.12)
			_hub.trigger_rumble(1, 0.7, 0.12)
		banner_lbl.text = "¡CHOQUE DE ESPADAS!"
		return

	# 3. Follow-up strike on STUNNED opponent!
	if defender.state == AvatarFighter.State.STUNNED:
		defender.stun_timer -= 0.45
		if defender.stun_timer <= 0.05:
			defender.state = AvatarFighter.State.NORMAL
			defender.stun_timer = 0.0
		var charged_mult := 1.65 if attacker.is_charged else 1.0
		attacker.is_charged = false
		var heavy_imp := push_dir * (4.4 * clampf(power, 0.72, 1.65) * charged_mult * sd_mult)
		defender.apply_knockback(heavy_imp)
		attacker.spirit = minf(100.0, attacker.spirit + (10.0 if charged_mult > 1.1 else 22.0))
		_spawn_sparks(mid, Color(1.0, 0.78, 0.22), 18)
		_hitstop_timer = 0.055 if charged_mult > 1.1 else 0.035
		_cam_fov_punch = 3.5 if charged_mult > 1.1 else 1.8
		_trigger_shake(0.24, 0.16)
		if _sfx:
			_sfx.play("hit", randf_range(1.05, 1.28), 0.5)
		if _hub != null:
			_hub.trigger_haptic_pattern(att_idx, [35, 25, 65])
			_hub.trigger_rumble(def_idx, 1.0, 0.22)
		banner_lbl.text = "¡GOLPE CRÍTICO!" if charged_mult > 1.1 else "¡REMATE EN ATURDIMIENTO!"
		return

	# 4. Guard, Perfect Parry, Passive Deflect, or Piercing Thrust!
	var can_guard_slot := true
	var slot_steady := defender.auto_guard_ready
	if _hub != null and (def_idx == 0 or GameConfig.match_mode == "2p"):
		slot_steady = _hub.slots[def_idx].fusion.is_steady
	var has_active_guard := defender.is_guarding and defender.guard_break_timer <= 0.0 and can_guard_slot
	var has_passive_guard := (not defender.is_guarding) and slot_steady and defender.guard_break_timer <= 0.0

	if has_active_guard or (has_passive_guard and atk_type != AvatarFighter.AttackType.THRUST):
		var blade_axis := defender.get_world_blade_axis()
		var slash_axis := attacker.get_world_slash_axis(slash_dir)
		var dot := absf(blade_axis.dot(slash_axis))
		var is_perp := (dot <= 0.62)

		if atk_type == AvatarFighter.AttackType.THRUST:
			# Estocada pierces static guards unless defender hit a Timed Perfect Parry!
			if has_active_guard and defender.guard_held_time <= 0.22:
				_trigger_perfect_parry(attacker, defender, push_dir, mid, att_idx, def_idx)
				return
			else:
				defender.guard_meter = maxf(0.0, defender.guard_meter - 35.0)
				defender.guard_break_timer = 0.20
				defender.apply_knockback(push_dir * (3.9 * power * sd_mult))
				attacker.spirit = minf(100.0, attacker.spirit + 22.0)
				_spawn_sparks(mid, Color(1.0, 0.6, 0.25), 14)
				_trigger_shake(0.18, 0.12)
				if _sfx:
					_sfx.play("hit", 1.1, -1.0)
				banner_lbl.text = "¡ESTOCADA PERFORA GUARDIA!"
				return

		if is_perp:
			if has_active_guard:
				if defender.guard_held_time <= 0.22:
					_trigger_perfect_parry(attacker, defender, push_dir, mid, att_idx, def_idx)
				else:
					# Solid Block (held Guard early)
					attacker.apply_knockback(-push_dir * 2.15)
					defender.apply_knockback(push_dir * 1.15)
					defender.guard_meter = maxf(0.0, defender.guard_meter - 14.0)
					defender.spirit = minf(100.0, defender.spirit + 18.0)
					_spawn_sparks(mid, Color(0.45, 0.90, 1.0), 14)
					_hitstop_timer = 0.032
					_trigger_shake(0.12, 0.08)
					if _sfx:
						_sfx.play("block", randf_range(0.95, 1.1), -2.0)
					if _hub != null:
						_hub.trigger_rumble(att_idx, 0.55, 0.10)
						_hub.trigger_rumble(def_idx, 0.45, 0.09)
					banner_lbl.text = "¡BLOQUEADO!"
			else:
				# Zero-button Passive Glancing Deflect (safe buffer, no free 1.65s stun)
				defender.apply_knockback(push_dir * (1.85 * power * sd_mult))
				attacker.apply_knockback(-push_dir * 1.05)
				defender.spirit = minf(100.0, defender.spirit + 8.0)
				_spawn_sparks(mid, Color(0.75, 0.95, 1.0), 10)
				_trigger_shake(0.08, 0.05)
				if _sfx:
					_sfx.play("parry", 0.95, -5.0)
				banner_lbl.text = "Desvío Pasivo (Usa GUARDIA para Parry)"
			return

		elif has_active_guard:
			# Parallel strike overcomes active guard!
			var gm_cost := 45.0 * clampf(power, 0.8, 1.5)
			defender.guard_meter = maxf(0.0, defender.guard_meter - gm_cost)
			defender.guard_break_timer = 0.22
			defender.apply_knockback(push_dir * (3.6 * clampf(power, 0.8, 1.5) * sd_mult))
			attacker.spirit = minf(100.0, attacker.spirit + 18.0)
			if defender.guard_meter <= 0.0:
				defender.apply_stun(1.65)
				_spawn_sparks(mid, Color(1.0, 0.35, 0.18), 22)
				_hitstop_timer = 0.06
				_trigger_shake(0.24, 0.15)
				if _sfx:
					_sfx.play("guard_break", 0.85, 0.0)
				banner_lbl.text = "💥 ¡ROTURA DE GUARDIA TOTAL!"
			else:
				_spawn_sparks(mid, Color(1.0, 0.5, 0.2), 14)
				_trigger_shake(0.18, 0.12)
				if _sfx:
					_sfx.play("hit", 0.82, -1.5)
				if _hub != null:
					_hub.trigger_rumble(def_idx, 0.85, 0.16)
				banner_lbl.text = "¡GUARDIA SUPERADA! %s" % defender.fighter_name
			return

	# 5. Clean Direct Hit!
	var mult := (1.65 if attacker.is_charged else 1.0) * sd_mult
	var thrust_bonus := 1.15 if atk_type == AvatarFighter.AttackType.THRUST else 1.0
	attacker.is_charged = false
	var impulse := push_dir * (4.4 * clampf(power, 0.72, 1.65) * mult * thrust_bonus)
	defender.apply_knockback(impulse)
	attacker.spirit = minf(100.0, attacker.spirit + 22.0)
	defender.spirit = minf(100.0, defender.spirit + 10.0)
	_spawn_sparks(mid, Color(1.0, 0.65, 0.25), 14)
	_hitstop_timer = 0.045
	_cam_fov_punch = 2.4 if mult > 1.2 else 1.1
	_trigger_shake(0.18, 0.12)
	if _sfx:
		_sfx.play("hit", randf_range(0.88, 1.14), -1.0)
	if _hub != null:
		_hub.trigger_rumble(att_idx, 0.45, 0.09)
		_hub.trigger_rumble(def_idx, 0.90, 0.18)


func _trigger_perfect_parry(attacker: AvatarFighter, defender: AvatarFighter, push_dir: Vector2, mid: Vector3, att_idx: int, def_idx: int) -> void:
	attacker.apply_stun(1.65)
	defender.is_charged = true
	defender.spirit = minf(100.0, defender.spirit + 38.0)
	attacker.apply_knockback(-push_dir * 0.8)
	_spawn_sparks(mid, Color(0.28, 0.96, 1.0), 26)
	Engine.time_scale = 0.25
	_slowmo_timer = 0.26
	_cam_fov_punch = 4.2
	_trigger_shake(0.26, 0.16)
	if _sfx:
		_sfx.play("perfect_parry", randf_range(0.96, 1.08), 0.5)
	if _hub != null:
		_hub.trigger_haptic_pattern(def_idx, [22, 25, 95])
		_hub.trigger_rumble(att_idx, 0.95, 0.25)
	banner_lbl.text = "⚡ ¡PARRY PERFECTO! CONTRAATAQUE LISTO"


func _spawn_spirit_wave(attacker: AvatarFighter, slash_dir: Vector2, power: float) -> void:
	var wave := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(1.55, 0.14, 0.36)
	wave.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.95, 0.98, 1.0, 0.92)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.84, 0.25) * 2.4
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	wave.material_override = mat

	var forward_dir := attacker.facing_dir
	wave.position = attacker.position + Vector3(forward_dir.x * 0.8, 1.05, forward_dir.y * 0.8)
	var yaw := atan2(-forward_dir.y, forward_dir.x)
	var roll_tilt := atan2(slash_dir.y, slash_dir.x)
	wave.rotation = Vector3(0.0, yaw, roll_tilt)
	add_child(wave)

	if _sfx:
		_sfx.play("charge", 1.15, -2.0)
	banner_lbl.text = "🔥 ¡ONDA DE ESPADA MAESTRA! (%s)" % attacker.fighter_name

	_waves.append({
		"mesh": wave,
		"attacker": attacker,
		"dir": forward_dir,
		"power": power,
		"life": 0.42
	})


func _step_waves(delta: float) -> void:
	for i in range(_waves.size() - 1, -1, -1):
		var w := _waves[i]
		var mesh: MeshInstance3D = w["mesh"]
		var dir: Vector2 = w["dir"]
		var att: AvatarFighter = w["attacker"]
		var def: AvatarFighter = f2 if att == f1 else f1
		w["life"] -= delta

		if not is_instance_valid(mesh) or phase != MatchPhase.FIGHTING:
			if is_instance_valid(mesh):
				mesh.queue_free()
			_waves.remove_at(i)
			continue

		mesh.position.x += dir.x * 12.5 * delta
		mesh.position.z += dir.y * 12.5 * delta
		mesh.scale.x += delta * 2.8

		var to_def := Vector2(def.position.x - mesh.position.x, def.position.z - mesh.position.z)
		if to_def.length() < 0.85:
			if def.iframe_timer <= 0.0:
				var imp := dir * (5.6 * clampf(float(w["power"]), 1.0, 1.65))
				def.apply_knockback(imp)
				_spawn_sparks(mesh.position, Color(1.0, 0.85, 0.25), 22)
				_trigger_shake(0.24, 0.16)
				if _sfx:
					_sfx.play("hit", 1.18, 0.5)
			else:
				banner_lbl.text = "¡ONDA ESQUIVADA!"
			mesh.queue_free()
			_waves.remove_at(i)
			continue

		if w["life"] <= 0.0:
			mesh.queue_free()
			_waves.remove_at(i)


func _clear_active_waves() -> void:
	for w in _waves:
		var m = w.get("mesh")
		if is_instance_valid(m):
			m.queue_free()
	_waves.clear()


func _enforce_3d_duel_spacing(_delta: float) -> void:
	if f1.state == AvatarFighter.State.FALLING or f2.state == AvatarFighter.State.FALLING:
		return
	var diff := Vector2(f2.position.x - f1.position.x, f2.position.z - f1.position.z)
	var dist := diff.length()
	var n := diff.normalized() if dist > 0.05 else Vector2(0.0, -1.0)
	# Only push apart overlapping fighter bodies (< 1.12m); NEVER pull players together magnetically!
	if dist < 1.12:
		var push := (1.12 - dist) * 0.5
		f1.position.x -= n.x * push
		f1.position.z -= n.y * push
		f2.position.x += n.x * push
		f2.position.z += n.y * push


func _on_fighter_fell(loser: AvatarFighter) -> void:
	if phase != MatchPhase.FIGHTING:
		return
	var ring: MeshInstance3D = _stage_refs.get("ripple_ring")
	if ring != null:
		ring.position = Vector3(loser.position.x, -1.56, loser.position.z)
		ring.scale = Vector3(0.4, 1.0, 0.4)
		ring.visible = true
	Engine.time_scale = 1.0
	_slowmo_timer = 0.0

	if loser == f2:
		score_p1 += 1
		banner_lbl.text = "¡JUGADOR 1 GANA EL ASALTO!"
	else:
		score_p2 += 1
		banner_lbl.text = "¡%s GANA EL ASALTO!" % ("JUGADOR 2" if GameConfig.match_mode == "2p" else "LA IA")

	if _sfx and _sfx.has_method("play_win"):
		_sfx.play_win()
	phase = MatchPhase.ROUND_OVER
	phase_timer = 2.15


func _resolve_timeout() -> void:
	Engine.time_scale = 1.0
	_slowmo_timer = 0.0
	var d1 := DojoStageScript.get_edge_ratio(Vector2(f1.position.x, f1.position.z), _stage_type)
	var d2 := DojoStageScript.get_edge_ratio(Vector2(f2.position.x, f2.position.z), _stage_type)
	if absf(d1 - d2) < 0.06:
		score_p1 += 1
		score_p2 += 1
		banner_lbl.text = "¡TIEMPO! EMPATE TÉCNICO"
	elif d1 < d2:
		score_p1 += 1
		banner_lbl.text = "¡TIEMPO! JUGADOR 1 DOMINA EL CENTRO"
	else:
		score_p2 += 1
		banner_lbl.text = "¡TIEMPO! %s DOMINA EL CENTRO" % ("JUGADOR 2" if GameConfig.match_mode == "2p" else "LA IA")
	phase = MatchPhase.ROUND_OVER
	phase_timer = 2.0


func _finish_match() -> void:
	Engine.time_scale = 1.0
	_slowmo_timer = 0.0
	phase = MatchPhase.MATCH_OVER
	victory_panel.visible = true
	if score_p1 > score_p2:
		victory_title.text = "🏆 ¡VICTORIA DEL JUGADOR 1! (%d - %d)" % [score_p1, score_p2]
	elif score_p2 > score_p1:
		victory_title.text = "🏆 ¡VICTORIA DE %s! (%d - %d)" % ["JUGADOR 2" if GameConfig.match_mode == "2p" else "LA IA", score_p2, score_p1]
	else:
		victory_title.text = "⚖️ ¡EMPATE FINAL! (%d - %d)" % [score_p1, score_p2]
	if _sfx and _sfx.has_method("play_win"):
		_sfx.play_win()


func _spawn_sparks(world_pos: Vector3, col: Color, count: int) -> void:
	var smat := StandardMaterial3D.new()
	smat.albedo_color = col
	smat.emission_enabled = true
	smat.emission = col * 2.2
	var smesh := SphereMesh.new()
	smesh.radius = 0.045
	smesh.height = 0.09
	for i in count:
		var sp := MeshInstance3D.new()
		sp.mesh = smesh
		sp.material_override = smat
		sp.position = world_pos
		add_child(sp)
		var vel := Vector3(randf_range(-4.8, 4.8), randf_range(0.9, 5.2), randf_range(-4.8, 4.8))
		_sparks.append({"node": sp, "vel": vel, "life": randf_range(0.18, 0.36)})


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
			n.scale = Vector3.ONE * clampf(s["life"] * 4.0, 0.1, 1.0)


func _trigger_shake(strength: float, duration: float) -> void:
	_shake_strength = maxf(_shake_strength, strength)
	_shake_timer = maxf(_shake_timer, duration)


func _update_camera(delta: float) -> void:
	var ripple: MeshInstance3D = _stage_refs.get("ripple_ring")
	if ripple != null and ripple.visible:
		ripple.scale += Vector3(4.5, 0.0, 4.5) * delta
		if ripple.scale.x > 6.0:
			ripple.visible = false

	var shake := Vector3.ZERO
	if _shake_timer > 0.0:
		shake = Vector3(
			randf_range(-_shake_strength, _shake_strength),
			randf_range(-_shake_strength, _shake_strength) * 0.65,
			randf_range(-_shake_strength, _shake_strength) * 0.5
		)

	var mid := (f1.position + f2.position) * 0.5 + Vector3(0.0, 1.02, 0.0)
	if GameConfig.match_mode == "2p" and _split_cam_p1 and _split_cam_p2:
		_aim_fighter_camera(_split_cam_p1, f1, f2, shake, delta)
		_aim_fighter_camera(_split_cam_p2, f2, f1, shake, delta)
	else:
		var fwd_z := Vector2(f2.position.x - f1.position.x, f2.position.z - f1.position.z).normalized()
		if fwd_z.length() < 0.05:
			fwd_z = Vector2(0.0, -1.0)
		var right_z := Vector2(-fwd_z.y, fwd_z.x)
		# Crisp off-left shoulder camera so P1 sword & opponent windups are unobstructed without ghosting P1
		var target_pos := (
			f1.position
			- Vector3(fwd_z.x, 0.0, fwd_z.y) * 2.55
			- Vector3(right_z.x, 0.0, right_z.y) * 0.96
			+ Vector3(0.0, 1.88, 0.0)
			+ shake
		)
		cam.position = cam.position.lerp(target_pos, clampf(delta * 9.0, 0.0, 1.0))
		cam.look_at(mid + Vector3(0.0, 0.14, 0.0), Vector3.UP)
		cam.fov = lerpf(cam.fov, 50.0 - _cam_fov_punch, clampf(delta * 12.0, 0.0, 1.0))


func _aim_fighter_camera(sc: Camera3D, self_f: AvatarFighter, opp_f: AvatarFighter, shake: Vector3, delta: float) -> void:
	var fwd_xz := Vector2(opp_f.position.x - self_f.position.x, opp_f.position.z - self_f.position.z).normalized()
	if fwd_xz.length() < 0.05:
		fwd_xz = self_f.facing_dir
	var right_xz := Vector2(-fwd_xz.y, fwd_xz.x)
	var eye_pos := (
		self_f.position
		- Vector3(fwd_xz.x, 0.0, fwd_xz.y) * 2.25
		- Vector3(right_xz.x, 0.0, right_xz.y) * 0.92
		+ Vector3(0.0, 1.82, 0.0)
		+ shake * 0.65
	)
	var target := (self_f.position + opp_f.position) * 0.5 + Vector3(0.0, 1.08, 0.0)
	if sc.position.length_squared() < 0.01:
		sc.position = eye_pos
	else:
		sc.position = sc.position.lerp(eye_pos, clampf(delta * 10.0, 0.0, 1.0))
	sc.look_at(target, Vector3.UP)
	sc.fov = 52.0 - _cam_fov_punch * 0.65


func _update_hud() -> void:
	var star := "★ "
	var empty := "☆ "
	score_p1_lbl.text = "J1: %s%s" % [star.repeat(score_p1), empty.repeat(maxi(0, 2 - score_p1))]
	var p2_tag := "J2" if GameConfig.match_mode == "2p" else "IA (%s)" % GameConfig.get_ai_name()
	score_p2_lbl.text = "%s: %s%s" % [p2_tag, star.repeat(score_p2), empty.repeat(maxi(0, 2 - score_p2))]
	timer_lbl.text = "Ronda %d  |  %d s" % [round_number, int(ceilf(round_time))]

	if _hub != null:
		var s0 = _hub.slots[0]
		var state0 := "⚡ ESPADA MAESTRA!" if f1.spirit >= 100.0 else ("🌟 CONTRAATAQUE!" if f1.is_charged else ("🛡️ BLOQUEO" if f1.is_guarding else "Listo"))
		status_p1_lbl.text = "J1 [%s] | %s | Guardia %d%% | Esp %d%%" % [
			s0.device_name, state0, int(roundf(f1.guard_meter)), int(roundf(f1.spirit))
		]
		if GameConfig.match_mode == "2p":
			var s1 = _hub.slots[1]
			var state1 := "⚡ ESPADA MAESTRA!" if f2.spirit >= 100.0 else ("🛡️ BLOQUEO" if f2.is_guarding else "Listo")
			status_p2_lbl.text = "J2 [%s] | %s | Guardia %d%% | Esp %d%%" % [
				s1.device_name, state1, int(roundf(f2.guard_meter)), int(roundf(f2.spirit))
			]
		else:
			var ai_state := "¡ATURDIDA!" if f2.state == AvatarFighter.State.STUNNED else ("⚠️ ¡CARGANDO!" if f2.state == AvatarFighter.State.WINDUP else ("Espíritu %d%%" % int(roundf(f2.spirit))))
			status_p2_lbl.text = "IA %s | Guardia %d%% | %s" % [GameConfig.get_ai_name(), int(roundf(f2.guard_meter)), ai_state]


func _on_draw_ring_bar() -> void:
	var w := ring_bar.size.x
	var h := ring_bar.size.y
	if w <= 20.0:
		return
	var pad := 16.0
	var bw := w - pad * 2.0
	ring_bar.draw_rect(Rect2(pad, h * 0.5 - 5.0, bw, 10.0), Color(0.14, 0.22, 0.34, 0.92), true)
	ring_bar.draw_rect(Rect2(pad, h * 0.5 - 5.0, bw, 10.0), Color(0.95, 0.85, 0.55, 0.75), false, 2.0)
	ring_bar.draw_line(Vector2(w * 0.5, 2.0), Vector2(w * 0.5, h - 2.0), Color(1, 1, 1, 0.45), 2.0)

	# Map ring position cleanly along arena fight axis (-Z opponent side vs +Z P1 side)
	var ratio_p1 := clampf(f1.position.z / 3.55, -0.95, 0.95)
	var ratio_p2 := clampf(f2.position.z / 3.55, -0.95, 0.95)
	if _stage_type == GameConfig.ArenaStage.VOLCANIC_BRIDGE:
		ratio_p1 = clampf(f1.position.z / 4.35, -0.95, 0.95)
		ratio_p2 = clampf(f2.position.z / 4.35, -0.95, 0.95)

	var p1_x := w * 0.5 - ratio_p1 * (bw * 0.46)
	var p2_x := w * 0.5 - ratio_p2 * (bw * 0.46)
	ring_bar.draw_circle(Vector2(p2_x, h * 0.5), 8.5, Color(0.98, 0.34, 0.22))
	ring_bar.draw_circle(Vector2(p1_x, h * 0.5), 8.5, Color(0.06, 0.82, 0.98))


func _project_world_axis_2d(world_axis: Vector3, origin_world: Vector3) -> Vector2:
	var active_cam := _split_cam_p1 if (_split_cam_p1 != null and GameConfig.match_mode == "2p") else cam
	var p0 := active_cam.unproject_position(origin_world)
	var p1 := active_cam.unproject_position(origin_world + world_axis)
	var d := p1 - p0
	return d.normalized() if d.length() > 0.001 else Vector2.UP


func _on_draw_reticle() -> void:
	var incoming := (f2.state == AvatarFighter.State.WINDUP or f2.state == AvatarFighter.State.SLASHING) and GameConfig.match_mode == "1p"
	if phase != MatchPhase.FIGHTING or not incoming:
		return

	var size := reticle_hud.size
	var cx := Vector2(size.x * 0.5, size.y * 0.52)
	var mid := (f1.position + f2.position) * 0.5 + Vector3(0.0, 1.0, 0.0)

	# Translucent backdrop badge only when threat arrives
	reticle_hud.draw_circle(cx, 54.0, Color(0.04, 0.09, 0.17, 0.72))

	var b1 := _project_world_axis_2d(f1.get_world_blade_axis(), mid) * 40.0
	var guard_col := Color(0.20, 0.88, 1.0) if f1.is_guarding else Color(0.45, 0.92, 0.72, 0.75)
	reticle_hud.draw_line(cx - b1, cx + b1, guard_col, 7.0 if f1.is_guarding else 4.5, true)

	if f2.state == AvatarFighter.State.WINDUP and f2.windup_attack_type == AvatarFighter.AttackType.THRUST:
		reticle_hud.draw_circle(cx, 26.0, Color(1.0, 0.35, 0.15, 0.9), false, 4.0)
		reticle_hud.draw_string(ThemeDB.fallback_font, Vector2(18, 22), "¡ESTOCADA! ESQUIVA / PARRY", HORIZONTAL_ALIGNMENT_CENTER, size.x - 36, 13, Color(1.0, 0.82, 0.3))
	else:
		var sdir := f2.windup_slash_dir if f2.state == AvatarFighter.State.WINDUP else f2.active_slash_dir
		var s_axis := f2.get_world_slash_axis(sdir)
		var b2 := _project_world_axis_2d(s_axis, mid) * 44.0
		var dot := absf(f1.get_world_blade_axis().dot(s_axis))
		var aligned := dot <= 0.62
		var threat_col := Color(0.28, 1.0, 0.55) if aligned else Color(1.0, 0.30, 0.22)
		reticle_hud.draw_line(cx - b2, cx + b2, threat_col, 4.5, true)
		var hint := "CRUZARÁ ✓ Pulsa Guardia!" if aligned else "GIRA TU ESPADA EN CRUZ ✕"
		reticle_hud.draw_string(ThemeDB.fallback_font, Vector2(10, 22), hint, HORIZONTAL_ALIGNMENT_CENTER, size.x - 20, 12, threat_col)


func _on_recenter_p1_pressed() -> void:
	if _hub != null:
		_hub.recenter_slot(0)


func _on_recenter_p2_pressed() -> void:
	if _hub != null:
		_hub.recenter_slot(1)


func _on_calib_confirm_pressed() -> void:
	_complete_entry_calibration()


func _on_rematch_pressed() -> void:
	Engine.time_scale = 1.0
	begin_entry_calibration(false)


func _on_guide_pressed() -> void:
	Engine.time_scale = 1.0
	get_tree().change_scene_to_file("res://scenes/CalibrationRoom.tscn")


func _on_menu_pressed() -> void:
	Engine.time_scale = 1.0
	get_tree().change_scene_to_file("res://scenes/MainMenu.tscn")
