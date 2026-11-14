extends Node3D

const AVATAR_SCENE := preload("res://scenes/AvatarFighter.tscn")
const ROUND_DURATION := 45.0
const MAX_WINS := 2
const CALIB_STEADY_REQUIRED := 0.45
const DUEL_DISTANCE := 1.52

enum MatchPhase { CALIBRATE_ENTRY, INTRO, FIGHTING, ROUND_END, MATCH_OVER }

@onready var cam: Camera3D = $Camera3D
@onready var arena_root: Node3D = $ArenaVisuals
@onready var top_card: PanelContainer = $UI/HUD/TopCard
@onready var bottom_card: PanelContainer = $UI/HUD/BottomCard
@onready var banner_label: Label = $UI/HUD/BannerLabel
@onready var score_p1_label: Label = $UI/HUD/TopCard/TopVBox/TopBar/ScoreP1
@onready var score_p2_label: Label = $UI/HUD/TopCard/TopVBox/TopBar/ScoreP2
@onready var timer_label: Label = $UI/HUD/TopCard/TopVBox/TopBar/TimerLabel
@onready var ring_bar: Control = $UI/HUD/TopCard/TopVBox/RingBalanceBar
@onready var reticle_hud: Control = $UI/HUD/ReticleRow/ReticleHUD
@onready var p1_status_label: Label = $UI/HUD/BottomCard/BottomInfo/StatusP1
@onready var p2_status_label: Label = $UI/HUD/BottomCard/BottomInfo/StatusP2
@onready var recenter_p2_btn: Button = $UI/HUD/BottomCard/BottomInfo/RecenterP2
@onready var calib_panel: PanelContainer = $UI/CalibPanel
@onready var calib_desc: Label = $UI/CalibPanel/VBox/CalibDesc
@onready var calib_progress: ProgressBar = $UI/CalibPanel/VBox/CalibProgress
@onready var victory_panel: PanelContainer = $UI/VictoryPanel
@onready var victory_title: Label = $UI/VictoryPanel/VBox/VictoryTitle

var f1: AvatarFighter
var f2: AvatarFighter

var phase: MatchPhase = MatchPhase.CALIBRATE_ENTRY
var phase_timer: float = 1.25
var round_timer: float = ROUND_DURATION
var round_number: int = 1
var wins_p1: int = 0
var wins_p2: int = 0
var sudden_death: bool = false

var _calib_steady_time: float = 0.0
var _hitstop_timer: float = 0.0
var _shake_amount: float = 0.0
var _clash_flash: MeshInstance3D
var _clash_timer: float = 0.0
var _banner_timer: float = 0.0
var _water_ring: MeshInstance3D
var _fx_time: float = 0.0
var _sparks: Array[Dictionary] = []

# AI state
var _ai_think_timer: float = 0.4
var _ai_guard_hold_timer: float = 0.0
var _ai_target_roll: float = 0.0


func _ready() -> void:
	_build_arena_geometry()
	_apply_ui_theme()
	_spawn_fighters()
	ring_bar.draw.connect(_on_draw_ring_bar)
	reticle_hud.draw.connect(_on_draw_reticle)
	victory_panel.visible = false
	calib_panel.visible = false
	recenter_p2_btn.visible = (GameConfig.match_mode == "2p")
	p2_status_label.visible = true

	if MotionHub.slots[0].source_type != MotionHub.SourceType.MOUSE:
		begin_entry_calibration(true)
	else:
		MotionHub.recenter_slot(0)
		_start_round()


func _apply_ui_theme() -> void:
	var hud_box := StyleBoxFlat.new()
	hud_box.bg_color = Color(0.05, 0.11, 0.22, 0.80)
	hud_box.border_color = Color(0.24, 0.68, 0.94, 0.42)
	hud_box.set_border_width_all(2)
	hud_box.set_corner_radius_all(14)
	hud_box.set_content_margin_all(10)
	top_card.add_theme_stylebox_override("panel", hud_box)
	bottom_card.add_theme_stylebox_override("panel", hud_box)

	var modal_box := StyleBoxFlat.new()
	modal_box.bg_color = Color(0.06, 0.12, 0.24, 0.94)
	modal_box.border_color = Color(0.32, 0.78, 1.0, 0.75)
	modal_box.set_border_width_all(3)
	modal_box.set_corner_radius_all(20)
	modal_box.set_content_margin_all(24)
	calib_panel.add_theme_stylebox_override("panel", modal_box)
	victory_panel.add_theme_stylebox_override("panel", modal_box)

	var bar_bg := StyleBoxFlat.new()
	bar_bg.bg_color = Color(0.12, 0.18, 0.30, 0.9)
	bar_bg.set_corner_radius_all(10)
	var bar_fill := StyleBoxFlat.new()
	bar_fill.bg_color = Color(0.14, 0.82, 0.94, 1.0)
	bar_fill.set_corner_radius_all(10)
	calib_progress.add_theme_stylebox_override("background", bar_bg)
	calib_progress.add_theme_stylebox_override("fill", bar_fill)


func _build_arena_geometry() -> void:
	# Ocean water plane
	var water := MeshInstance3D.new()
	var wm := PlaneMesh.new()
	wm.size = Vector2(180.0, 180.0)
	water.mesh = wm
	var wmat := StandardMaterial3D.new()
	wmat.albedo_color = Color(0.06, 0.56, 0.84)
	wmat.roughness = 0.14
	wmat.metallic = 0.1
	water.material_override = wmat
	water.position = Vector3(0.0, -1.45, 0.0)
	arena_root.add_child(water)

	# Animated water ripple ring around platform
	_water_ring = MeshInstance3D.new()
	var wrm := TorusMesh.new()
	wrm.inner_radius = AvatarFighter.PLATFORM_RADIUS + 0.15
	wrm.outer_radius = AvatarFighter.PLATFORM_RADIUS + 0.45
	wrm.rings = 48
	_water_ring.mesh = wrm
	var wrmat := StandardMaterial3D.new()
	wrmat.albedo_color = Color(0.75, 0.96, 1.0, 0.42)
	wrmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_water_ring.material_override = wrmat
	_water_ring.rotation_degrees = Vector3(90, 0, 0)
	_water_ring.scale = Vector3(1.0, 1.0, 0.12)
	_water_ring.position = Vector3(0.0, -1.42, 0.0)
	arena_root.add_child(_water_ring)

	# Stone base beneath wooden deck
	var base := MeshInstance3D.new()
	var bm := CylinderMesh.new()
	bm.top_radius = AvatarFighter.PLATFORM_RADIUS + 0.12
	bm.bottom_radius = AvatarFighter.PLATFORM_RADIUS * 0.86
	bm.height = 1.45
	bm.radial_segments = 48
	base.mesh = bm
	var bmat := StandardMaterial3D.new()
	bmat.albedo_color = Color(0.32, 0.36, 0.44)
	bmat.roughness = 0.85
	base.material_override = bmat
	base.position = Vector3(0.0, -0.78, 0.0)
	arena_root.add_child(base)

	# Warm wooden dojo top deck
	var plat := MeshInstance3D.new()
	var pm := CylinderMesh.new()
	pm.top_radius = AvatarFighter.PLATFORM_RADIUS
	pm.bottom_radius = AvatarFighter.PLATFORM_RADIUS
	pm.height = 0.14
	pm.radial_segments = 48
	plat.mesh = pm
	var pmat := StandardMaterial3D.new()
	pmat.albedo_color = Color(0.89, 0.78, 0.60)
	pmat.roughness = 0.55
	plat.material_override = pmat
	plat.position = Vector3(0.0, -0.07, 0.0)
	arena_root.add_child(plat)

	# Outer warning rim
	var rim := MeshInstance3D.new()
	var rm := TorusMesh.new()
	rm.inner_radius = AvatarFighter.PLATFORM_RADIUS - 0.35
	rm.outer_radius = AvatarFighter.PLATFORM_RADIUS
	rm.rings = 48
	rim.mesh = rm
	var rmat := StandardMaterial3D.new()
	rmat.albedo_color = Color(0.96, 0.40, 0.25)
	rmat.emission_enabled = true
	rmat.emission = Color(0.96, 0.35, 0.2) * 0.25
	rim.material_override = rmat
	rim.rotation_degrees = Vector3(90, 0, 0)
	rim.scale = Vector3(1.0, 1.0, 0.18)
	rim.position = Vector3(0.0, 0.01, 0.0)
	arena_root.add_child(rim)

	# Inner center ring
	var center_ring := MeshInstance3D.new()
	var cm := TorusMesh.new()
	cm.inner_radius = 1.65
	cm.outer_radius = 1.78
	cm.rings = 48
	center_ring.mesh = cm
	var cmat := StandardMaterial3D.new()
	cmat.albedo_color = Color(0.12, 0.74, 0.92)
	cmat.emission_enabled = true
	cmat.emission = Color(0.12, 0.74, 0.92) * 0.3
	center_ring.material_override = cmat
	center_ring.rotation_degrees = Vector3(90, 0, 0)
	center_ring.scale = Vector3(1.0, 1.0, 0.15)
	center_ring.position = Vector3(0.0, 0.015, 0.0)
	arena_root.add_child(center_ring)

	# Switch Sports 1D combat track lane + red danger end zones
	var lane := MeshInstance3D.new()
	var lane_m := BoxMesh.new()
	var track_len := (AvatarFighter.PLATFORM_RADIUS - 0.14) * 2.0
	if GameConfig.match_mode == "1p":
		lane_m.size = Vector3(1.36, 0.018, track_len)
	else:
		lane_m.size = Vector3(track_len, 0.018, 1.36)
	lane.mesh = lane_m
	var lane_mat := StandardMaterial3D.new()
	lane_mat.albedo_color = Color(0.16, 0.22, 0.30, 0.92)
	lane_mat.roughness = 0.65
	lane.material_override = lane_mat
	lane.position = Vector3(0.0, 0.01, 0.0)
	arena_root.add_child(lane)

	var danger_mat := StandardMaterial3D.new()
	danger_mat.albedo_color = Color(0.95, 0.28, 0.22)
	danger_mat.emission_enabled = true
	danger_mat.emission = Color(0.92, 0.25, 0.18) * 0.35
	for end_sign in [-1.0, 1.0]:
		var end_strip := MeshInstance3D.new()
		var em := BoxMesh.new()
		if GameConfig.match_mode == "1p":
			em.size = Vector3(1.36, 0.022, 0.72)
			end_strip.position = Vector3(0.0, 0.014, end_sign * 4.02)
		else:
			em.size = Vector3(0.72, 0.022, 1.36)
			end_strip.position = Vector3(end_sign * 4.02, 0.014, 0.0)
		end_strip.mesh = em
		end_strip.material_override = danger_mat
		arena_root.add_child(end_strip)

	# 4 Decorative perimeter lanterns outside ring
	var pillar_mat := StandardMaterial3D.new()
	pillar_mat.albedo_color = Color(0.24, 0.28, 0.36)
	var lantern_mat := StandardMaterial3D.new()
	lantern_mat.albedo_color = Color(1.0, 0.9, 0.55)
	lantern_mat.emission_enabled = true
	lantern_mat.emission = Color(1.0, 0.82, 0.35) * 1.4

	for k in 4:
		var ang := PI * 0.25 + k * PI * 0.5
		var dist := AvatarFighter.PLATFORM_RADIUS + 1.05
		var px := cos(ang) * dist
		var pz := sin(ang) * dist
		var post := MeshInstance3D.new()
		var post_m := CylinderMesh.new()
		post_m.top_radius = 0.16
		post_m.bottom_radius = 0.22
		post_m.height = 2.4
		post.mesh = post_m
		post.material_override = pillar_mat
		post.position = Vector3(px, -0.35, pz)
		arena_root.add_child(post)

		var lamp := MeshInstance3D.new()
		var lm := BoxMesh.new()
		lm.size = Vector3(0.32, 0.38, 0.32)
		lamp.mesh = lm
		lamp.material_override = lantern_mat
		lamp.position = Vector3(px, 1.0, pz)
		arena_root.add_child(lamp)

	# Distant tropical island silhouettes
	var island_mat := StandardMaterial3D.new()
	island_mat.albedo_color = Color(0.24, 0.52, 0.44)
	for info in [
		[Vector3(-18.0, -1.0, -28.0), Vector3(11.0, 4.5, 9.0)],
		[Vector3(22.0, -1.1, -34.0), Vector3(14.0, 6.0, 12.0)],
		[Vector3(2.0, -1.2, -45.0), Vector3(20.0, 7.5, 10.0)]
	]:
		var isl := MeshInstance3D.new()
		var im := SphereMesh.new()
		im.radius = 1.0
		im.height = 1.4
		isl.mesh = im
		isl.material_override = island_mat
		isl.position = info[0]
		isl.scale = info[1]
		arena_root.add_child(isl)

	# Clash spark burst mesh
	_clash_flash = MeshInstance3D.new()
	var fm := SphereMesh.new()
	fm.radius = 0.42
	fm.height = 0.84
	_clash_flash.mesh = fm
	var fmat := StandardMaterial3D.new()
	fmat.albedo_color = Color(1.0, 0.94, 0.35, 0.85)
	fmat.emission_enabled = true
	fmat.emission = Color(1.0, 0.88, 0.25) * 1.8
	fmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_clash_flash.material_override = fmat
	_clash_flash.visible = false
	arena_root.add_child(_clash_flash)


func _spawn_fighters() -> void:
	f1 = AVATAR_SCENE.instantiate() as AvatarFighter
	f1.fighter_name = "Jugador 1"
	f1.team_color = Color(0.05, 0.78, 0.92)
	add_child(f1)
	f1.slash_executed.connect(_on_fighter_slash)
	f1.fell_off_ring.connect(_on_fighter_fell)
	f1.set_camera_translucent(GameConfig.match_mode == "1p")

	f2 = AVATAR_SCENE.instantiate() as AvatarFighter
	f2.fighter_name = "Jugador 2" if GameConfig.match_mode == "2p" else "IA"
	f2.team_color = Color(0.98, 0.44, 0.52)
	add_child(f2)
	f2.slash_executed.connect(_on_fighter_slash)
	f2.fell_off_ring.connect(_on_fighter_fell)


func _place_fighters_at_spawn() -> void:
	var half_dist := DUEL_DISTANCE * 0.5
	if GameConfig.match_mode == "1p":
		f1.reset_for_round(Vector3(0.0, 0.0, half_dist), Vector2(0.0, -1.0))
		f2.reset_for_round(Vector3(0.0, 0.0, -half_dist), Vector2(0.0, 1.0))
	else:
		f1.reset_for_round(Vector3(-half_dist, 0.0, 0.0), Vector2(1.0, 0.0))
		f2.reset_for_round(Vector3(half_dist, 0.0, 0.0), Vector2(-1.0, 0.0))


func begin_entry_calibration(_force: bool = true) -> void:
	_place_fighters_at_spawn()
	phase = MatchPhase.CALIBRATE_ENTRY
	_calib_steady_time = 0.0
	calib_progress.value = 0.0
	calib_panel.visible = true
	banner_label.visible = false
	var dev := MotionHub.slots[0].device_name
	calib_desc.text = "Dispositivo J1: %s\nApunta hacia la pantalla con el mando o móvil recto.\nMantén quieto 0.5s o pulsa la pantalla para centrar." % dev
	_update_hud()


func confirm_entry_calibration() -> void:
	MotionHub.recenter_slot(0)
	if GameConfig.match_mode == "2p":
		MotionHub.recenter_slot(1)
	calib_panel.visible = false
	_play_sfx("bell", 1.25, -4.0)
	MotionHub.trigger_rumble(0, 0.45, 0.08)
	_start_round()


func _start_round() -> void:
	_place_fighters_at_spawn()
	MotionHub.recenter_yaw_slot(0)
	if GameConfig.match_mode == "2p":
		MotionHub.recenter_yaw_slot(1)
	calib_panel.visible = false
	round_timer = ROUND_DURATION
	sudden_death = false
	_ai_think_timer = 0.55
	_ai_guard_hold_timer = 1.25
	_ai_target_roll = 0.0
	if GameConfig.match_mode == "1p":
		f2.is_guarding = true
	phase = MatchPhase.INTRO
	phase_timer = 1.15
	_show_banner("RONDA %d — ¡LISTOS!" % round_number, 1.15)
	_update_hud()


func _process(delta: float) -> void:
	_fx_time += delta
	if _water_ring:
		var pulse := 1.0 + sin(_fx_time * 2.2) * 0.035
		_water_ring.scale = Vector3(pulse, pulse, 0.12)

	_update_clash_fx(delta)
	_update_banner(delta)

	if _hitstop_timer > 0.0:
		_hitstop_timer -= delta
		_update_camera(delta)
		return

	match phase:
		MatchPhase.CALIBRATE_ENTRY:
			var s0: MotionHub.PlayerSlot = MotionHub.slots[0]
			if s0.fusion.angular_speed < 0.95:
				_calib_steady_time += delta
			else:
				_calib_steady_time = maxf(0.0, _calib_steady_time - delta * 1.5)
			calib_progress.value = clampf((_calib_steady_time / CALIB_STEADY_REQUIRED) * 100.0, 0.0, 100.0)
			f1.step_fighter(delta, Vector2.ZERO, f2.position, false)
			f2.step_fighter(delta, Vector2.ZERO, f1.position, false)
			if _calib_steady_time >= CALIB_STEADY_REQUIRED or s0.just_guard_pressed or s0.just_recenter_pressed:
				confirm_entry_calibration()

		MatchPhase.INTRO:
			phase_timer -= delta
			_drive_fighter_from_slot(f1, 0, delta, f2.position, false)
			if GameConfig.match_mode == "2p":
				_drive_fighter_from_slot(f2, 1, delta, f1.position, false)
			else:
				f2.step_fighter(delta, Vector2.ZERO, f1.position, false)
			if phase_timer <= 0.0:
				phase = MatchPhase.FIGHTING
				_play_sfx("bell", 1.15, -4.0)
				_show_banner("¡COMBATE!", 0.75)

		MatchPhase.FIGHTING:
			round_timer -= delta
			if round_timer <= 0.0 and not sudden_death:
				round_timer = 0.0
				sudden_death = true
				_play_sfx("bell", 1.4, -3.0)
				_show_banner("¡MUERTE SÚBITA! (Empuje x1.8)", 1.8)

			_update_auto_guard_preview()
			_drive_fighter_from_slot(f1, 0, delta, f2.position, true)
			if GameConfig.match_mode == "2p":
				_drive_fighter_from_slot(f2, 1, delta, f1.position, true)
			else:
				_drive_ai(delta)
			_enforce_duel_track(delta)

		MatchPhase.ROUND_END:
			phase_timer -= delta
			f1.step_fighter(delta, Vector2.ZERO, f2.position, false)
			f2.step_fighter(delta, Vector2.ZERO, f1.position, false)
			if phase_timer <= 0.0:
				if wins_p1 >= MAX_WINS or wins_p2 >= MAX_WINS:
					_finish_match()
				else:
					round_number += 1
					_start_round()

		MatchPhase.MATCH_OVER:
			f1.step_fighter(delta, Vector2.ZERO, f2.position, false)
			f2.step_fighter(delta, Vector2.ZERO, f1.position, false)

	_update_camera(delta)
	_update_hud()


func _update_auto_guard_preview() -> void:
	if f2.state == AvatarFighter.State.WINDUP or f2.state == AvatarFighter.State.SLASHING:
		var atk_axis := f2.get_world_slash_axis(f2.windup_slash_dir)
		var def_axis := f1.get_world_blade_axis()
		var align := absf(atk_axis.dot(def_axis))
		var s0: MotionHub.PlayerSlot = MotionHub.slots[0]
		f1.auto_guard_ready = (f1.state == AvatarFighter.State.NORMAL and not f1.is_guarding and s0.fusion.is_steady and align < 0.52)
	else:
		f1.auto_guard_ready = false


func _enforce_duel_track(delta: float) -> void:
	if f1.state == AvatarFighter.State.FALLING or f2.state == AvatarFighter.State.FALLING:
		return
	var track := Vector2(0.0, -1.0) if GameConfig.match_mode == "1p" else Vector2(1.0, 0.0)
	var lat := Vector2(-track.y, track.x)
	var p1 := Vector2(f1.position.x, f1.position.z)
	var p2 := Vector2(f2.position.x, f2.position.z)

	var s1 := p1.dot(track)
	var s2 := p2.dot(track)
	var l1 := lerpf(p1.dot(lat), 0.0, clampf(delta * 16.0, 0.0, 1.0))
	var l2 := lerpf(p2.dot(lat), 0.0, clampf(delta * 16.0, 0.0, 1.0))

	var sep := s2 - s1
	var min_sep := DUEL_DISTANCE * 0.88
	if sep < min_sep:
		var push_apart := (min_sep - sep) * 0.5
		s1 -= push_apart
		s2 += push_apart
	elif sep > DUEL_DISTANCE:
		if absf(s1) >= AvatarFighter.PLATFORM_RADIUS or absf(s2) >= AvatarFighter.PLATFORM_RADIUS:
			return
		var excess := sep - DUEL_DISTANCE
		var v1_back := -f1.velocity_xz.dot(track)
		var v2_back := f2.velocity_xz.dot(track)
		var max_step := (10.5 if (v1_back > 0.25 or v2_back > 0.25) else 5.5) * delta
		var step := minf(excess, max_step)
		if v2_back > 0.20 or f2.guard_break_timer > 0.0 or (f2.state == AvatarFighter.State.STUNNED and v2_back >= v1_back):
			s1 += step
		elif v1_back > 0.20 or f1.guard_break_timer > 0.0 or (f1.state == AvatarFighter.State.STUNNED and v1_back > v2_back):
			s2 -= step
		elif f1.state == AvatarFighter.State.SLASHING and f2.state != AvatarFighter.State.SLASHING:
			s1 += step
		elif f2.state == AvatarFighter.State.SLASHING and f1.state != AvatarFighter.State.SLASHING:
			s2 -= step
		else:
			s1 += step * 0.5
			s2 -= step * 0.5

	var final_1 := track * s1 + lat * l1
	var final_2 := track * s2 + lat * l2
	f1.position.x = final_1.x
	f1.position.z = final_1.y
	f2.position.x = final_2.x
	f2.position.z = final_2.y


func _drive_fighter_from_slot(fighter: AvatarFighter, slot_idx: int, delta: float, opp_pos: Vector3, can_act: bool) -> void:
	var s: MotionHub.PlayerSlot = MotionHub.slots[slot_idx]
	fighter.blade_orientation = s.fusion.orientation
	fighter.blade_roll_rad = s.fusion.get_snapped_blade_roll_rad()
	fighter.is_guarding = s.is_guarding

	if can_act and fighter.state == AvatarFighter.State.NORMAL:
		if s.fusion.just_swung:
			fighter.trigger_slash(s.fusion.last_slash_dir, s.fusion.last_slash_power)

	fighter.step_fighter(delta, s.move_axis, opp_pos, can_act)


func _drive_ai(delta: float) -> void:
	var diff := GameConfig.ai_difficulty
	var windup_dur := 0.88 if diff == 0 else (0.72 if diff == 1 else 0.56)
	var think_interval := 0.72 if diff == 0 else (0.55 if diff == 1 else 0.42)
	var guard_poses: Array[float] = [0.0, PI * 0.25, -PI * 0.25, PI * 0.5]
	var slash_angles: Array[Vector2] = [
		Vector2(1.0, 0.0),
		Vector2(0.0, 1.0),
		Vector2(0.7071, 0.7071),
		Vector2(0.7071, -0.7071)
	]

	_ai_guard_hold_timer = maxf(0.0, _ai_guard_hold_timer - delta)
	_ai_think_timer -= delta
	if f2.state == AvatarFighter.State.NORMAL and f1.state == AvatarFighter.State.STUNNED and f2.is_guarding:
		_ai_think_timer = minf(_ai_think_timer, 0.20)

	if f2.state == AvatarFighter.State.NORMAL and _ai_think_timer <= 0.0:
		var dist := f1.position.distance_to(f2.position)
		if f1.state == AvatarFighter.State.STUNNED and dist < 2.6:
			f2.is_guarding = false
			_ai_guard_hold_timer = 0.0
			_ai_think_timer = 0.66
			var punish_dir := slash_angles[randi() % slash_angles.size()]
			f2.start_windup(punish_dir, 0.36)
			_play_sfx("windup", 1.15, -7.0)
		elif _ai_guard_hold_timer <= 0.0:
			_ai_think_timer = think_interval * randf_range(0.85, 1.15)
			var atk_prob := 0.36 if diff == 0 else (0.46 if diff == 1 else 0.56)
			if dist < 2.65 and randf() < atk_prob:
				f2.is_guarding = false
				_ai_think_timer = windup_dur + 0.32
				var atk_dir := slash_angles[randi() % slash_angles.size()]
				f2.start_windup(atk_dir, windup_dur)
				_play_sfx("windup", 0.95 + diff * 0.08, -7.5)
			elif randf() < (0.68 if diff == 0 else (0.78 if diff == 1 else 0.85)):
				f2.is_guarding = true
				var choices := guard_poses.duplicate()
				choices.shuffle()
				for p in choices:
					if absf(p - _ai_target_roll) > 0.15:
						_ai_target_roll = p
						break
				_ai_guard_hold_timer = randf_range(1.05, 1.50)
				_ai_think_timer = _ai_guard_hold_timer
			else:
				f2.is_guarding = false
				_ai_guard_hold_timer = 0.45
				_ai_think_timer = 0.45

	if f2.state == AvatarFighter.State.NORMAL:
		f2.blade_roll_rad = lerp_angle(f2.blade_roll_rad, _ai_target_roll, clampf(delta * 10.0, 0.0, 1.0))
	f2.step_fighter(delta, Vector2.ZERO, f1.position, true)


func _on_fighter_slash(attacker: AvatarFighter, slash_dir: Vector2, power: float) -> void:
	if phase != MatchPhase.FIGHTING:
		return
	var defender := f2 if attacker == f1 else f1
	var attacker_slot := 0 if attacker == f1 else 1
	var defender_slot := 1 if attacker == f1 else 0

	if defender.state == AvatarFighter.State.FALLING:
		return

	var dist_xz := Vector2(attacker.position.x - defender.position.x, attacker.position.z - defender.position.z).length()
	if dist_xz > 2.75:
		return

	var push_dir := attacker.facing_dir
	var mult := 1.8 if sudden_death else 1.0
	var attacker_is_human := (attacker == f1) or (GameConfig.match_mode == "2p")
	var defender_is_human := (defender == f1) or (GameConfig.match_mode == "2p")

	# Switch Sports Sword Clash: simultaneous swing or colliding late in opponent windup
	if defender.state == AvatarFighter.State.SLASHING or (defender.state == AvatarFighter.State.WINDUP and defender.windup_timer < 0.20):
		attacker.cancel_attack_from_clash(-push_dir * 1.45)
		defender.cancel_attack_from_clash(push_dir * 1.45)
		_spawn_clash_fx((attacker.position + defender.position) * 0.5 + Vector3(0.0, 0.98, 0.0), Color(1.0, 0.96, 0.85))
		_play_sfx("parry", 1.25, -2.5)
		if attacker_is_human:
			MotionHub.trigger_rumble(attacker_slot, 0.72, 0.11)
		if defender_is_human:
			MotionHub.trigger_rumble(defender_slot, 0.72, 0.11)
		_hitstop_timer = 0.065
		_shake_amount = 0.22
		_show_banner("⚡ ¡CHOQUE DE ESPADAS!", 0.75)
		return

	var slash_axis := attacker.get_world_slash_axis(slash_dir)
	var guard_axis := defender.get_world_blade_axis()
	var alignment := absf(slash_axis.dot(guard_axis))

	var is_active_guard := (defender.state == AvatarFighter.State.NORMAL and defender.is_guarding)
	var def_slot: MotionHub.PlayerSlot = MotionHub.slots[defender_slot]
	var is_passive_guard := defender_is_human and defender.state == AvatarFighter.State.NORMAL and not defender.is_guarding and def_slot.fusion.is_steady

	if (is_active_guard and alignment < 0.62) or (is_passive_guard and alignment < 0.52):
		# Perpendicular Parry -> stun attacker 1.65s + charge defender's next counter-strike!
		attacker.is_charged = false
		attacker.apply_stun(1.65)
		defender.is_charged = true
		defender.apply_knockback(push_dir * 0.75)
		_spawn_clash_fx((attacker.position + defender.position) * 0.5 + Vector3(0.0, 0.98, 0.0), Color(1.0, 0.92, 0.28))
		_play_sfx("parry", randf_range(0.95, 1.10), -1.5)
		if attacker_is_human:
			MotionHub.trigger_rumble(attacker_slot, 0.95, 0.16)
		if defender_is_human:
			MotionHub.trigger_rumble(defender_slot, 0.80, 0.14)
		_hitstop_timer = 0.11
		_shake_amount = 0.28
		_show_banner("⚡ ¡BLOQUEO! ¡CONTRAATACA!" if is_active_guard else "⚡ ¡AUTOBLOQUEO! ¡CONTRAATACA!", 1.15)
	elif is_active_guard:
		# Parallel Guard Overcome -> knocks defender back cleanly without freezing them in stun stars
		var charge_mult := 1.65 if attacker.is_charged else 1.0
		attacker.is_charged = false
		defender.guard_break_timer = 0.16
		defender.apply_knockback(push_dir * (3.6 * mult * charge_mult))
		_spawn_clash_fx(defender.position + Vector3(0.0, 0.95, 0.0), Color(1.0, 0.55, 0.25))
		_play_sfx("guard_break", 1.05, -2.0)
		if attacker_is_human:
			MotionHub.trigger_rumble(attacker_slot, 0.65, 0.12)
		if defender_is_human:
			MotionHub.trigger_rumble(defender_slot, 0.95, 0.16)
		_hitstop_timer = 0.055
		_shake_amount = 0.24
		_show_banner("¡GUARDIA SUPERADA!", 0.80)
	else:
		# Direct Hit / Multi-hit Stun Combo
		var was_stunned := defender.state == AvatarFighter.State.STUNNED
		var was_charged := attacker.is_charged
		var charge_mult := 1.65 if was_charged else 1.0
		attacker.is_charged = false
		if defender.state == AvatarFighter.State.WINDUP:
			defender.state = AvatarFighter.State.NORMAL
		var force := 4.2 * power * mult * charge_mult
		defender.apply_knockback(push_dir * force)
		if was_stunned:
			defender.stun_timer = maxf(0.0, defender.stun_timer - 0.45)
			if defender.stun_timer <= 0.0:
				defender.state = AvatarFighter.State.NORMAL
		_spawn_clash_fx(defender.position + Vector3(0.0, 0.95, 0.0), Color(1.0, 0.85, 0.2) if was_charged else attacker.team_color)
		_play_sfx("hit", 0.82 if was_charged else (0.92 if was_stunned else 1.05), -1.8)
		if attacker_is_human:
			MotionHub.trigger_rumble(attacker_slot, 0.78 if was_charged else 0.65, 0.12)
		if defender_is_human:
			MotionHub.trigger_rumble(defender_slot, 1.0, 0.20)
		_hitstop_timer = 0.075 if was_charged else (0.045 if was_stunned else 0.035)
		_shake_amount = 0.38 if was_charged else (0.28 if was_stunned else 0.18)
		if was_charged:
			_show_banner("🔥 ¡GOLPE CARGADO!", 0.85)
		elif was_stunned:
			_show_banner("⚡ ¡COMBO DE CONTRAATAQUE!", 0.75)


func _on_fighter_fell(loser: AvatarFighter) -> void:
	if phase != MatchPhase.FIGHTING:
		return
	phase = MatchPhase.ROUND_END
	phase_timer = 2.0
	if loser == f2:
		wins_p1 += 1
		_show_banner("¡RONDA PARA JUGADOR 1!", 1.9)
	else:
		wins_p2 += 1
		var name2 := "JUGADOR 2" if GameConfig.match_mode == "2p" else "LA IA"
		_show_banner("¡RONDA PARA %s!" % name2, 1.9)
	_play_sfx("bell", 0.9, -3.0)


func _finish_match() -> void:
	phase = MatchPhase.MATCH_OVER
	_play_sfx("win", 1.0, -3.0)
	var winner := "Jugador 1 (Azul)" if wins_p1 > wins_p2 else ("Jugador 2 (Coral)" if GameConfig.match_mode == "2p" else "IA (Coral)")
	victory_title.text = "¡Victoria para %s! (%d - %d)" % [winner, wins_p1, wins_p2]
	victory_panel.visible = true


func _spawn_clash_fx(pos: Vector3, tint: Color) -> void:
	_clash_flash.position = pos
	_clash_flash.scale = Vector3.ONE * 0.45
	_clash_flash.visible = true
	_clash_timer = 0.16

	var mat := StandardMaterial3D.new()
	mat.albedo_color = tint
	mat.emission_enabled = true
	mat.emission = tint * 1.8
	for i in 12:
		var sp := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.06, 0.06, 0.16)
		sp.mesh = bm
		sp.material_override = mat
		sp.position = pos
		arena_root.add_child(sp)
		var vel := Vector3(randf_range(-4.8, 4.8), randf_range(1.2, 5.2), randf_range(-4.8, 4.8))
		_sparks.append({"node": sp, "vel": vel, "life": 0.36})


func _update_clash_fx(delta: float) -> void:
	if _clash_timer > 0.0:
		_clash_timer -= delta
		_clash_flash.scale += Vector3.ONE * delta * 6.5
		if _clash_timer <= 0.0:
			_clash_flash.visible = false

	for i in range(_sparks.size() - 1, -1, -1):
		var item: Dictionary = _sparks[i]
		var sp: MeshInstance3D = item["node"]
		var vel: Vector3 = item["vel"]
		vel.y -= 14.0 * delta
		sp.position += vel * delta
		sp.scale *= 0.94
		item["vel"] = vel
		item["life"] = float(item["life"]) - delta
		if float(item["life"]) <= 0.0:
			sp.queue_free()
			_sparks.remove_at(i)


func _update_camera(delta: float) -> void:
	_shake_amount = maxf(0.0, _shake_amount - delta * 1.5)
	var shake_vec := Vector3(
		randf_range(-1.0, 1.0),
		randf_range(-1.0, 1.0),
		0.0
	) * _shake_amount * 0.22

	if GameConfig.match_mode == "1p":
		var fwd := Vector3(f1.facing_dir.x, 0.0, f1.facing_dir.y).normalized()
		var right := Vector3(-fwd.z, 0.0, fwd.x)
		var base_y := maxf(f1.position.y, -0.3)
		var desired_pos := Vector3(f1.position.x, base_y, f1.position.z) - fwd * 2.15 + right * 0.52 + Vector3(0.0, 1.72, 0.0)
		var mid := (f1.position + f2.position) * 0.5
		mid.y = maxf(mid.y, -0.3) + 0.98
		cam.position = cam.position.lerp(desired_pos + shake_vec, clampf(delta * 9.0, 0.0, 1.0))
		cam.look_at(mid, Vector3.UP)
	else:
		var mid := (f1.position + f2.position) * 0.5
		mid.y = clampf(mid.y, -0.2, 1.0)
		var dist := f1.position.distance_to(f2.position)
		var target_pos := Vector3(mid.x * 0.7, 2.75, clampf(4.8 + dist * 0.45, 5.2, 7.6))
		cam.position = cam.position.lerp(target_pos + shake_vec, clampf(delta * 6.0, 0.0, 1.0))
		cam.look_at(Vector3(mid.x * 0.85, 0.95, 0.0), Vector3.UP)


func _show_banner(msg: String, duration: float) -> void:
	banner_label.text = msg
	banner_label.visible = true
	_banner_timer = duration


func _update_banner(delta: float) -> void:
	if _banner_timer > 0.0:
		_banner_timer -= delta
		if _banner_timer <= 0.0:
			banner_label.visible = false


func _update_hud() -> void:
	score_p1_label.text = "J1 (Azul): %s" % _dots(wins_p1)
	var label2 := "J2 (Coral)" if GameConfig.match_mode == "2p" else "IA (Coral)"
	score_p2_label.text = "%s: %s" % [label2, _dots(wins_p2)]
	if phase == MatchPhase.CALIBRATE_ENTRY:
		timer_label.text = "Ronda %d  |  Centrando..." % round_number
	elif sudden_death:
		timer_label.text = "Ronda %d  |  ¡MUERTE SÚBITA!" % round_number
	else:
		timer_label.text = "Ronda %d  |  %02d s" % [round_number, ceili(round_timer)]

	var guard_txt := " | GUARDIA ACTIVA" if f1.is_guarding else (" | AUTOBLOQUEO LISTO" if f1.auto_guard_ready else "")
	var charge_txt := " | 🔥 CARGADA" if f1.is_charged else ""
	p1_status_label.text = "J1: %s | Hoja: %.0f°%s%s" % [
		MotionHub.slots[0].device_name,
		rad_to_deg(f1.blade_roll_rad),
		guard_txt,
		charge_txt
	]
	if GameConfig.match_mode == "2p":
		p2_status_label.text = "J2: %s | Hoja: %.0f°%s" % [
			MotionHub.slots[1].device_name,
			rad_to_deg(f2.blade_roll_rad),
			" | BLOQUEANDO" if f2.is_guarding else ""
		]
	else:
		p2_status_label.text = "IA (%s) | Hoja: %.0f°%s" % [
			["Novato", "Pro", "Campeón"][GameConfig.ai_difficulty],
			rad_to_deg(f2.blade_roll_rad),
			" | PREPARANDO CORTE" if f2.state == AvatarFighter.State.WINDUP else ""
		]

	reticle_hud.visible = (GameConfig.match_mode == "1p" and phase != MatchPhase.MATCH_OVER)
	ring_bar.queue_redraw()
	if reticle_hud.visible:
		reticle_hud.queue_redraw()


func _on_draw_ring_bar() -> void:
	var w := ring_bar.size.x
	var h := ring_bar.size.y
	if w < 40.0:
		return
	var cx := w * 0.5
	var bar_h := 12.0
	var y0 := (h - bar_h) * 0.5
	var half_w := cx - 54.0

	# Track background
	ring_bar.draw_rect(Rect2(54.0, y0, half_w * 2.0, bar_h), Color(0.08, 0.14, 0.26, 0.85), true)
	# Center divider
	ring_bar.draw_line(Vector2(cx, y0 - 3.0), Vector2(cx, y0 + bar_h + 3.0), Color(1.0, 1.0, 1.0, 0.7), 2.0)

	var d1 := clampf(Vector2(f1.position.x, f1.position.z).length() / AvatarFighter.PLATFORM_RADIUS, 0.0, 1.0)
	var d2 := clampf(Vector2(f2.position.x, f2.position.z).length() / AvatarFighter.PLATFORM_RADIUS, 0.0, 1.0)

	var c1 := Color(0.98, 0.35, 0.25) if d1 > 0.72 else Color(0.10, 0.82, 0.96)
	var c2 := Color(0.98, 0.35, 0.25) if d2 > 0.72 else Color(0.98, 0.45, 0.55)

	ring_bar.draw_rect(Rect2(cx - half_w * d1, y0 + 2.0, half_w * d1, bar_h - 4.0), c1, true)
	ring_bar.draw_rect(Rect2(cx, y0 + 2.0, half_w * d2, bar_h - 4.0), c2, true)

	var font := ThemeDB.fallback_font
	ring_bar.draw_string(font, Vector2(6.0, y0 + bar_h - 1.0), "AGUA J1", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.55, 0.88, 1.0))
	ring_bar.draw_string(font, Vector2(w - 50.0, y0 + bar_h - 1.0), "AGUA IA", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1.0, 0.65, 0.72))


func _project_world_axis_2d(world_axis: Vector3) -> Vector2:
	var cam_right := cam.global_transform.basis.x
	var cam_up := cam.global_transform.basis.y
	var p := Vector2(world_axis.dot(cam_right), -world_axis.dot(cam_up))
	if p.length() < 0.05:
		return Vector2(0.0, -1.0)
	return p.normalized()


func _on_draw_reticle() -> void:
	var w := reticle_hud.size.x
	var h := reticle_hud.size.y
	var center := Vector2(w * 0.5, 52.0)
	var rad := 40.0
	var font := ThemeDB.fallback_font

	var incoming := (f2.state == AvatarFighter.State.WINDUP or f2.state == AvatarFighter.State.SLASHING)
	var p1_axis := f1.get_world_blade_axis()
	var p1_2d := _project_world_axis_2d(p1_axis)

	var ring_color := Color(0.35, 0.78, 0.96, 0.48)
	var status_text := "🛡️ GUARDIA ACTIVA" if f1.is_guarding else "⚔️ ESPADA CENTRADA"
	var status_color := Color(0.68, 0.92, 1.0)
	if f2.state == AvatarFighter.State.STUNNED:
		status_text = "⚡ ¡ATURDIDO! ¡CORTA!"
		status_color = Color(1.0, 0.90, 0.25)
		ring_color = Color(1.0, 0.88, 0.25, 0.85)
	elif f1.is_charged:
		status_text = "🔥 ¡ESPADA CARGADA!"
		status_color = Color(1.0, 0.82, 0.28)
		ring_color = Color(1.0, 0.78, 0.22, 0.85)

	var p1_line_color := Color(1.0, 0.86, 0.30) if f1.is_charged else Color(0.18, 0.88, 1.0)

	if incoming:
		var atk_axis := f2.get_world_slash_axis(f2.windup_slash_dir)
		var atk_2d := _project_world_axis_2d(atk_axis)
		var ideal_2d := Vector2(-atk_2d.y, atk_2d.x)
		var align := absf(atk_axis.dot(p1_axis))
		var ok_active := f1.is_guarding and align < 0.62
		var ok_auto := f1.auto_guard_ready

		# Ideal perpendicular green target line
		reticle_hud.draw_circle(center, rad + 4.0, Color(0.03, 0.08, 0.16, 0.68))
		reticle_hud.draw_line(center - ideal_2d * (rad - 6.0), center + ideal_2d * (rad - 6.0), Color(0.2, 0.95, 0.45, 0.45), 6.0)
		# Incoming red attack line
		reticle_hud.draw_line(center - atk_2d * (rad + 4.0), center + atk_2d * (rad + 4.0), Color(1.0, 0.30, 0.25, 0.95), 5.0)

		if ok_active or ok_auto:
			ring_color = Color(0.22, 0.96, 0.52, 0.95)
			p1_line_color = Color(0.45, 1.0, 0.72)
			status_text = "¡BLOQUEO LISTO!" if ok_active else "⚡ ¡AUTOBLOQUEO LISTO!"
			status_color = Color(0.38, 1.0, 0.64)
		else:
			ring_color = Color(1.0, 0.38, 0.28, 0.92)
			status_text = "¡GIRA PERPENDICULAR!"
			status_color = Color(1.0, 0.75, 0.45)
	else:
		reticle_hud.draw_circle(center, rad, Color(0.03, 0.08, 0.16, 0.55))

	reticle_hud.draw_arc(center, rad, 0.0, TAU, 40, ring_color, 3.0)
	# Player 1 sword line
	reticle_hud.draw_line(center - p1_2d * (rad - 8.0), center + p1_2d * (rad - 8.0), p1_line_color, 5.0, true)
	reticle_hud.draw_circle(center + p1_2d * (rad - 10.0), 4.0, Color.WHITE)
	reticle_hud.draw_string(font, Vector2(0.0, h - 10.0), status_text, HORIZONTAL_ALIGNMENT_CENTER, w, 15, status_color)


func _dots(wins: int) -> String:
	var out := ""
	for i in MAX_WINS:
		out += "★ " if i < wins else "☆ "
	return out.strip_edges()


func _play_sfx(sound_name: String, pitch: float, volume_db: float) -> void:
	var sfx := get_node_or_null("/root/SoundFX")
	if sfx != null:
		sfx.play(sound_name, pitch, volume_db)


func _on_calib_confirm_pressed() -> void:
	confirm_entry_calibration()


func _on_recenter_p1_pressed() -> void:
	MotionHub.recenter_slot(0)
	_play_sfx("bell", 1.2, -8.0)


func _on_recenter_p2_pressed() -> void:
	MotionHub.recenter_slot(1)
	_play_sfx("bell", 1.3, -8.0)


func _on_menu_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/MainMenu.tscn")


func _on_rematch_pressed() -> void:
	wins_p1 = 0
	wins_p2 = 0
	round_number = 1
	victory_panel.visible = false
	_start_round()
