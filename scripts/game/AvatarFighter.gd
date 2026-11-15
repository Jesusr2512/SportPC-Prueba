@tool
class_name AvatarFighter
extends Node3D

const DojoStageScript := preload("res://scripts/game/DojoStage.gd")

signal slash_executed(fighter: AvatarFighter, slash_dir: Vector2, power: float)
signal slash_impact(fighter: AvatarFighter, slash_dir: Vector2, power: float, attack_type: int)
signal dodge_started(fighter: AvatarFighter, dodge_dir: Vector2)
signal fell_off_ring(fighter: AvatarFighter)

const FALL_WATER_Y := -1.45
const BASE_SLASH_DURATION := 0.19
const HIT_ARC_START := 0.22
const HIT_ARC_END := 0.58

enum State { NORMAL, WINDUP, SLASHING, STUNNED, FALLING, DODGING }
enum AttackType { CUT = 0, THRUST = 1, WAVE = 2 }

@export var fighter_name: String = "Jugador 1"
@export var team_color: Color = Color(0.05, 0.78, 0.92)
@export var facing_dir: Vector2 = Vector2.RIGHT

var state: State = State.NORMAL
var attack_type: int = AttackType.CUT
var active_slash_dir: Vector2 = Vector2.RIGHT
var active_slash_power: float = 1.0
var windup_slash_dir: Vector2 = Vector2.RIGHT
var windup_attack_type: int = AttackType.CUT

var is_guarding: bool = false
var is_charged: bool = false
var auto_guard_ready: bool = false
var guard_held_time: float = 99.0
var guard_meter: float = 100.0
var spirit: float = 0.0
var twin_blades_enabled: bool = false

var blade_orientation: Quaternion = Quaternion.IDENTITY
var blade_roll_rad: float = 0.0

var velocity_xz: Vector2 = Vector2.ZERO
var vertical_vel: float = 0.0
var stun_timer: float = 0.0
var slash_timer: float = 0.0
var _slash_duration: float = BASE_SLASH_DURATION
var windup_timer: float = 0.0
var guard_break_timer: float = 0.0
var _windup_duration: float = 0.55
var hit_flash_timer: float = 0.0
var _hit_resolved_this_swing: bool = false

var dodge_timer: float = 0.0
var dodge_cooldown_timer: float = 0.0
var iframe_timer: float = 0.0
var dodge_dir_xz: Vector2 = Vector2.ZERO

var stage_type: int = GameConfig.ArenaStage.SUN_ISLAND
var arena_radius_override: float = -1.0

var _splash_emitted: bool = false
var _idle_t: float = 0.0
var _slash_start_side: float = 1.0
var _camera_translucent: bool = false
var _prev_guarding: bool = false

var _visual_root: Node3D
var _upper_body: Node3D
var _arm_pivot: Node3D
var _sword_tilt_pivot: Node3D
var _blade_roll_pivot: Node3D
var _hilt_marker: Node3D
var _tip_marker: Node3D
var _hand_l: MeshInstance3D

var _offhand_pivot: Node3D
var _offhand_blade_root: Node3D

var _guard_halo: MeshInstance3D
var _telegraph_bar: MeshInstance3D
var _telegraph_mat: StandardMaterial3D
var _stun_ring: Node3D
var _body_mesh: MeshInstance3D
var _head_node: Node3D
var _sword_mat: StandardMaterial3D
var _offhand_mat: StandardMaterial3D
var _body_mat: StandardMaterial3D
var _white_mat: StandardMaterial3D
var _skin_mat: StandardMaterial3D
var _visor_mat: StandardMaterial3D
var _halo_mat: StandardMaterial3D

var _ribbon_mesh_inst: MeshInstance3D
var _ribbon_mesh: ImmediateMesh
var _ribbon_mat: StandardMaterial3D
var _trail_samples: Array[Dictionary] = []
var _trail_hold_timer: float = 0.0


func _ready() -> void:
	var old := get_node_or_null("VisualRoot")
	if old != null:
		old.free()
	var old_rib := get_node_or_null("SwordRibbonTrail")
	if old_rib != null:
		old_rib.free()
	_build_visuals()
	if _camera_translucent:
		set_camera_translucent(true)


func _build_visuals() -> void:
	_visual_root = Node3D.new()
	_visual_root.name = "VisualRoot"
	add_child(_visual_root)

	_upper_body = Node3D.new()
	_upper_body.name = "UpperBody"
	_upper_body.position = Vector3(0.0, 0.42, 0.0)
	_visual_root.add_child(_upper_body)

	_body_mat = StandardMaterial3D.new()
	_body_mat.albedo_color = team_color
	_body_mat.roughness = 0.40

	_skin_mat = StandardMaterial3D.new()
	_skin_mat.albedo_color = Color(0.98, 0.85, 0.74)
	_skin_mat.roughness = 0.62

	var dark_mat := StandardMaterial3D.new()
	dark_mat.albedo_color = Color(0.11, 0.13, 0.18)
	dark_mat.roughness = 0.48

	_white_mat = StandardMaterial3D.new()
	_white_mat.albedo_color = Color(0.96, 0.98, 1.0)
	_white_mat.roughness = 0.34

	_visor_mat = StandardMaterial3D.new()
	_visor_mat.albedo_color = Color(0.08, 0.1, 0.15)
	_visor_mat.metallic = 0.82
	_visor_mat.roughness = 0.12

	# Feet
	for side in [-1.0, 1.0]:
		var foot := MeshInstance3D.new()
		var fm := SphereMesh.new()
		fm.radius = 0.115
		fm.height = 0.15
		foot.mesh = fm
		foot.material_override = _white_mat
		foot.position = Vector3(0.08 if side > 0 else -0.05, 0.08, side * 0.15)
		_visual_root.add_child(foot)

	# Torso
	_body_mesh = MeshInstance3D.new()
	var torso := CapsuleMesh.new()
	torso.radius = 0.24
	torso.height = 0.76
	_body_mesh.mesh = torso
	_body_mesh.material_override = _body_mat
	_body_mesh.position = Vector3(0.0, 0.20, 0.0)
	_upper_body.add_child(_body_mesh)

	# Shoulder pads
	for side in [-1.0, 1.0]:
		var sh := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.12
		sm.height = 0.21
		sh.mesh = sm
		sh.material_override = _white_mat
		sh.position = Vector3(0.02, 0.46, side * 0.24)
		_upper_body.add_child(sh)

	# Belt
	var belt := MeshInstance3D.new()
	var belt_mesh := CylinderMesh.new()
	belt_mesh.top_radius = 0.252
	belt_mesh.bottom_radius = 0.252
	belt_mesh.height = 0.085
	belt.mesh = belt_mesh
	belt.material_override = _white_mat
	belt.position = Vector3(0.0, 0.01, 0.0)
	_upper_body.add_child(belt)

	# Head & Visor
	_head_node = Node3D.new()
	_head_node.position = Vector3(0.0, 0.82, 0.0)
	_upper_body.add_child(_head_node)

	var head := MeshInstance3D.new()
	var hm := SphereMesh.new()
	hm.radius = 0.22
	hm.height = 0.44
	head.mesh = hm
	head.material_override = _skin_mat
	_head_node.add_child(head)

	var band := MeshInstance3D.new()
	var bm := CylinderMesh.new()
	bm.top_radius = 0.228
	bm.bottom_radius = 0.228
	bm.height = 0.075
	band.mesh = bm
	band.material_override = _body_mat
	band.position = Vector3(0.0, 0.09, 0.0)
	_head_node.add_child(band)

	var visor := MeshInstance3D.new()
	var vm := BoxMesh.new()
	vm.size = Vector3(0.11, 0.085, 0.30)
	visor.mesh = vm
	visor.material_override = _visor_mat
	visor.position = Vector3(0.175, 0.015, 0.0)
	_head_node.add_child(visor)

	# Stun stars ring
	_stun_ring = Node3D.new()
	_stun_ring.position = Vector3(0.0, 0.34, 0.0)
	_stun_ring.visible = false
	_head_node.add_child(_stun_ring)
	var star_mat := StandardMaterial3D.new()
	star_mat.albedo_color = Color(1.0, 0.85, 0.15)
	star_mat.emission_enabled = true
	star_mat.emission = Color(1.0, 0.8, 0.1) * 1.4
	for k in 3:
		var ang := k * TAU / 3.0
		var star := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.06
		sm.height = 0.12
		star.mesh = sm
		star.material_override = star_mat
		star.position = Vector3(cos(ang) * 0.28, 0.0, sin(ang) * 0.28)
		_stun_ring.add_child(star)

	# Main Sword Rig
	_arm_pivot = Node3D.new()
	_arm_pivot.position = Vector3(0.36, 0.42, 0.06)
	_upper_body.add_child(_arm_pivot)

	_blade_roll_pivot = Node3D.new()
	_blade_roll_pivot.name = "BladeRollPivot"
	_arm_pivot.add_child(_blade_roll_pivot)

	_sword_tilt_pivot = Node3D.new()
	_sword_tilt_pivot.rotation_degrees = Vector3(0.0, 0.0, -24.0)
	_blade_roll_pivot.add_child(_sword_tilt_pivot)

	var hand_mesh := SphereMesh.new()
	hand_mesh.radius = 0.072
	hand_mesh.height = 0.144
	var hand_mat := StandardMaterial3D.new()
	hand_mat.albedo_color = Color(0.98, 0.85, 0.74)
	hand_mat.roughness = 0.55

	var hand_r := MeshInstance3D.new()
	hand_r.mesh = hand_mesh
	hand_r.material_override = hand_mat
	hand_r.position = Vector3(0.0, 0.11, 0.0)
	_sword_tilt_pivot.add_child(hand_r)

	_hand_l = MeshInstance3D.new()
	_hand_l.mesh = hand_mesh
	_hand_l.material_override = hand_mat
	_hand_l.position = Vector3(-0.02, -0.03, -0.02)
	_sword_tilt_pivot.add_child(_hand_l)

	var hilt := MeshInstance3D.new()
	var hilt_m := CylinderMesh.new()
	hilt_m.top_radius = 0.032
	hilt_m.bottom_radius = 0.036
	hilt_m.height = 0.30
	hilt.mesh = hilt_m
	hilt.material_override = dark_mat
	hilt.position = Vector3(0.0, 0.04, 0.0)
	_sword_tilt_pivot.add_child(hilt)

	var cross := MeshInstance3D.new()
	var cross_m := CylinderMesh.new()
	cross_m.top_radius = 0.125
	cross_m.bottom_radius = 0.125
	cross_m.height = 0.036
	cross.mesh = cross_m
	var cross_mat := StandardMaterial3D.new()
	cross_mat.albedo_color = Color(0.96, 0.98, 1.0)
	cross.material_override = cross_mat
	cross.position = Vector3(0.0, 0.21, 0.0)
	_sword_tilt_pivot.add_child(cross)

	_sword_mat = StandardMaterial3D.new()
	_sword_mat.albedo_color = team_color
	_sword_mat.emission_enabled = true
	_sword_mat.emission = team_color * 0.90

	var blade := MeshInstance3D.new()
	var blade_m := BoxMesh.new()
	blade_m.size = Vector3(0.095, 1.26, 0.035)
	blade.mesh = blade_m
	blade.material_override = _sword_mat
	blade.position = Vector3(0.0, 0.85, 0.0)
	_sword_tilt_pivot.add_child(blade)

	var core := MeshInstance3D.new()
	var core_m := BoxMesh.new()
	core_m.size = Vector3(0.04, 1.22, 0.042)
	core.mesh = core_m
	var core_mat := StandardMaterial3D.new()
	core_mat.albedo_color = Color.WHITE
	core_mat.emission_enabled = true
	core_mat.emission = Color.WHITE * 1.4
	core.material_override = core_mat
	core.position = Vector3(0.0, 0.84, 0.0)
	_sword_tilt_pivot.add_child(core)

	_hilt_marker = Node3D.new()
	_hilt_marker.position = Vector3(0.0, 0.26, 0.0)
	_sword_tilt_pivot.add_child(_hilt_marker)

	_tip_marker = Node3D.new()
	_tip_marker.position = Vector3(0.0, 1.48, 0.0)
	_sword_tilt_pivot.add_child(_tip_marker)

	# Offhand Twin Blade (shown in Espadas Gemelas style)
	_offhand_pivot = Node3D.new()
	_offhand_pivot.position = Vector3(0.24, 0.36, -0.26)
	_upper_body.add_child(_offhand_pivot)

	_offhand_blade_root = Node3D.new()
	_offhand_blade_root.rotation_degrees = Vector3(-16.0, 0.0, -32.0)
	_offhand_pivot.add_child(_offhand_blade_root)

	_offhand_mat = StandardMaterial3D.new()
	_offhand_mat.albedo_color = team_color.lightened(0.22)
	_offhand_mat.emission_enabled = true
	_offhand_mat.emission = team_color * 0.85

	var oh_hilt := MeshInstance3D.new()
	oh_hilt.mesh = hilt_m
	oh_hilt.material_override = dark_mat
	_offhand_blade_root.add_child(oh_hilt)

	var oh_blade := MeshInstance3D.new()
	var oh_m := BoxMesh.new()
	oh_m.size = Vector3(0.075, 0.94, 0.028)
	oh_blade.mesh = oh_m
	oh_blade.material_override = _offhand_mat
	oh_blade.position = Vector3(0.0, 0.62, 0.0)
	_offhand_blade_root.add_child(oh_blade)
	_offhand_pivot.visible = twin_blades_enabled

	# Guard Halo
	_guard_halo = MeshInstance3D.new()
	var halo_m := TorusMesh.new()
	halo_m.inner_radius = 0.34
	halo_m.outer_radius = 0.46
	_guard_halo.mesh = halo_m
	_halo_mat = StandardMaterial3D.new()
	_halo_mat.albedo_color = Color(team_color.r, team_color.g, team_color.b, 0.72)
	_halo_mat.emission_enabled = true
	_halo_mat.emission = team_color * 1.5
	_halo_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_guard_halo.material_override = _halo_mat
	_guard_halo.rotation_degrees = Vector3(0.0, 0.0, 90.0)
	_guard_halo.position = Vector3(0.24, 0.48, 0.0)
	_guard_halo.visible = false
	_blade_roll_pivot.add_child(_guard_halo)

	# Telegraph attack plane indicator (visible during WINDUP)
	_telegraph_bar = MeshInstance3D.new()
	var tele_m := BoxMesh.new()
	tele_m.size = Vector3(0.08, 1.88, 0.13)
	_telegraph_bar.mesh = tele_m
	_telegraph_mat = StandardMaterial3D.new()
	_telegraph_mat.albedo_color = Color(1.0, 0.88, 0.2, 0.85)
	_telegraph_mat.emission_enabled = true
	_telegraph_mat.emission = Color(1.0, 0.55, 0.15) * 1.8
	_telegraph_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_telegraph_bar.material_override = _telegraph_mat
	_telegraph_bar.position = Vector3(0.66, 0.96, 0.0)
	_telegraph_bar.visible = false
	_visual_root.add_child(_telegraph_bar)

	# Dynamic ImmediateMesh Sword Ribbon Trail (world space)
	_ribbon_mesh = ImmediateMesh.new()
	_ribbon_mat = StandardMaterial3D.new()
	_ribbon_mat.vertex_color_use_as_albedo = true
	_ribbon_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ribbon_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ribbon_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_ribbon_mat.emission_enabled = true
	_ribbon_mat.emission = team_color * 1.35

	_ribbon_mesh_inst = MeshInstance3D.new()
	_ribbon_mesh_inst.name = "SwordRibbonTrail"
	_ribbon_mesh_inst.top_level = true
	_ribbon_mesh_inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ribbon_mesh_inst.mesh = _ribbon_mesh
	_ribbon_mesh_inst.material_override = _ribbon_mat
	_ribbon_mesh_inst.visible = false
	add_child(_ribbon_mesh_inst)


func set_twin_blades(enabled: bool) -> void:
	twin_blades_enabled = enabled
	if _offhand_pivot:
		_offhand_pivot.visible = enabled


func configure_stage(p_stage_type: int, radius_override: float = -1.0) -> void:
	stage_type = p_stage_type
	arena_radius_override = radius_override


func set_camera_translucent(enabled: bool) -> void:
	_camera_translucent = enabled
	if _body_mat == null:
		return
	var alpha := 0.42 if enabled else 1.0
	var mode := BaseMaterial3D.TRANSPARENCY_ALPHA if enabled else BaseMaterial3D.TRANSPARENCY_DISABLED
	for mat: StandardMaterial3D in [_body_mat, _white_mat, _skin_mat, _visor_mat]:
		mat.transparency = mode
		var c: Color = mat.albedo_color
		c.a = alpha
		mat.albedo_color = c


func reset_for_round(spawn_pos: Vector3, look_dir_xz: Vector2) -> void:
	position = spawn_pos
	facing_dir = look_dir_xz.normalized() if look_dir_xz.length() > 0.01 else Vector2.RIGHT
	rotation = Vector3(0.0, atan2(-facing_dir.y, facing_dir.x), 0.0)
	state = State.NORMAL
	attack_type = AttackType.CUT
	is_guarding = false
	_prev_guarding = false
	guard_held_time = 99.0
	is_charged = false
	auto_guard_ready = false
	guard_meter = 100.0
	spirit = 0.0
	velocity_xz = Vector2.ZERO
	vertical_vel = 0.0
	stun_timer = 0.0
	slash_timer = 0.0
	_slash_duration = BASE_SLASH_DURATION
	windup_timer = 0.0
	guard_break_timer = 0.0
	hit_flash_timer = 0.0
	dodge_timer = 0.0
	dodge_cooldown_timer = 0.0
	iframe_timer = 0.0
	_hit_resolved_this_swing = false
	_splash_emitted = false
	blade_roll_rad = 0.0
	blade_orientation = Quaternion.IDENTITY
	_trail_samples.clear()
	_trail_hold_timer = 0.0
	if _upper_body:
		_upper_body.rotation = Vector3.ZERO
	if _blade_roll_pivot:
		_blade_roll_pivot.rotation = Vector3.ZERO
	if _offhand_pivot:
		_offhand_pivot.visible = twin_blades_enabled
	if _hand_l:
		_hand_l.visible = not twin_blades_enabled
		_hand_l.position = Vector3(-0.02, -0.03, -0.02)
	if _stun_ring:
		_stun_ring.visible = false
	if _ribbon_mesh_inst:
		_ribbon_mesh.clear_surfaces()
		_ribbon_mesh_inst.visible = false
	if _telegraph_bar:
		_telegraph_bar.visible = false
	if _guard_halo:
		_guard_halo.visible = false


func trigger_slash(slash_dir: Vector2, power: float, p_attack_type: int = AttackType.CUT) -> void:
	if state == State.STUNNED or state == State.FALLING:
		return
	var norm_dir := slash_dir.normalized() if slash_dir.length() > 0.05 else Vector2.RIGHT
	state = State.SLASHING
	attack_type = p_attack_type
	active_slash_dir = norm_dir
	active_slash_power = clampf(power, 0.45, 2.0)

	# Faster whip swings complete crisper and quicker (0.135s..0.24s)
	var base_dur := 0.24 if twin_blades_enabled else 0.255
	var min_dur := 0.125 if twin_blades_enabled else 0.145
	_slash_duration = clampf(base_dur - (active_slash_power - 0.5) * 0.075, min_dur, base_dur)
	slash_timer = _slash_duration
	windup_timer = 0.0
	dodge_timer = 0.0
	iframe_timer = 0.0
	is_guarding = false
	auto_guard_ready = false
	_hit_resolved_this_swing = false
	_slash_start_side = -_slash_start_side
	_telegraph_bar.visible = false
	_trail_samples.clear()
	_trail_hold_timer = 0.12

	if attack_type == AttackType.THRUST:
		_play_sfx("thrust", randf_range(0.96, 1.16), -4.0)
	else:
		var pitch := clampf(0.88 + active_slash_power * 0.28, 0.85, 1.38)
		_play_sfx("slash", pitch, -4.5)

	slash_executed.emit(self, norm_dir, active_slash_power)


func update_live_slash_power(live_power: float) -> void:
	# Allow late wrist-snap acceleration during early startup/active arc to boost strike impulse!
	if state == State.SLASHING and not _hit_resolved_this_swing:
		active_slash_power = maxf(active_slash_power, clampf(live_power, 0.45, 2.0))


func trigger_dodge(dir_input: Vector2) -> bool:
	if state == State.FALLING or state == State.STUNNED or dodge_cooldown_timer > 0.0:
		return false
	var lateral := Vector2(-facing_dir.y, facing_dir.x)
	var move_world: Vector2
	if absf(dir_input.x) > 0.15:
		move_world = lateral * signf(dir_input.x)
	else:
		move_world = lateral * _slash_start_side

	state = State.DODGING
	dodge_dir_xz = move_world
	dodge_timer = 0.22
	dodge_cooldown_timer = 0.58
	iframe_timer = 0.15
	is_guarding = false
	windup_timer = 0.0
	slash_timer = 0.0
	_telegraph_bar.visible = false
	velocity_xz = move_world * 5.6
	_play_sfx("dash", randf_range(0.95, 1.12), -6.0)
	dodge_started.emit(self, move_world)
	return true


func start_windup(slash_dir: Vector2, duration: float, p_attack_type: int = AttackType.CUT) -> void:
	if state != State.NORMAL:
		return
	state = State.WINDUP
	windup_slash_dir = slash_dir.normalized() if slash_dir.length() > 0.05 else Vector2.RIGHT
	windup_attack_type = p_attack_type
	_windup_duration = maxf(duration, 0.1)
	windup_timer = _windup_duration
	is_guarding = false
	auto_guard_ready = false

	var cut_ang := atan2(windup_slash_dir.y, windup_slash_dir.x)
	_telegraph_bar.visible = true
	if p_attack_type == AttackType.THRUST:
		_telegraph_bar.rotation = Vector3(0.0, 0.0, PI * 0.5)
	else:
		_telegraph_bar.rotation = Vector3(cut_ang + PI * 0.5, 0.0, 0.0)
	var sfx := get_node_or_null("/root/SoundFX")
	if sfx != null and sfx.has_method("play_windup"):
		sfx.play_windup()


func apply_stun(duration: float = 1.65) -> void:
	state = State.STUNNED
	stun_timer = duration
	is_guarding = false
	auto_guard_ready = false
	dodge_timer = 0.0
	iframe_timer = 0.0
	_hit_resolved_this_swing = true
	_telegraph_bar.visible = false
	_stun_ring.visible = true
	velocity_xz -= facing_dir * 2.2


func apply_knockback(impulse_xz: Vector2) -> void:
	velocity_xz += impulse_xz
	hit_flash_timer = 0.18


func cancel_attack_from_clash(recoil_impulse: Vector2) -> void:
	state = State.NORMAL
	slash_timer = 0.0
	windup_timer = 0.0
	is_guarding = false
	_hit_resolved_this_swing = true
	_telegraph_bar.visible = false
	velocity_xz = recoil_impulse
	hit_flash_timer = 0.14


func get_guard_blade_dir_2d() -> Vector2:
	return Vector2(-sin(blade_roll_rad), cos(blade_roll_rad)).normalized()


func get_world_blade_axis(roll_override: float = NAN) -> Vector3:
	var r := blade_roll_rad if is_nan(roll_override) else roll_override
	var local_dir := Vector3(0.0, cos(r), sin(r))
	return (global_transform.basis * local_dir).normalized()


func get_world_slash_axis(slash_dir: Vector2) -> Vector3:
	var ang := atan2(slash_dir.y, slash_dir.x) + PI * 0.5
	var local_dir := Vector3(0.0, cos(ang), sin(ang))
	return (global_transform.basis * local_dir).normalized()


func get_blade_segment_world() -> Array[Vector3]:
	if _hilt_marker and _tip_marker and is_inside_tree():
		return [_hilt_marker.global_position, _tip_marker.global_position]
	return [global_position + Vector3(0, 0.8, 0), global_position + Vector3(0, 1.8, 0)]


func is_in_active_hit_window() -> bool:
	if state != State.SLASHING or _hit_resolved_this_swing:
		return false
	var progress := 1.0 - clampf(slash_timer / maxf(_slash_duration, 0.01), 0.0, 1.0)
	return progress >= HIT_ARC_START and progress <= HIT_ARC_END


func consume_active_hit() -> void:
	_hit_resolved_this_swing = true


func step_fighter(delta: float, move_input: Vector2, opponent_pos: Vector3, can_act: bool) -> void:
	_idle_t += delta
	if guard_break_timer > 0.0:
		guard_break_timer = maxf(0.0, guard_break_timer - delta)
	if dodge_cooldown_timer > 0.0:
		dodge_cooldown_timer = maxf(0.0, dodge_cooldown_timer - delta)
	if iframe_timer > 0.0:
		iframe_timer = maxf(0.0, iframe_timer - delta)

	# Track precise guard hold duration for Timed Perfect Parry window
	if is_guarding and can_act and state == State.NORMAL and guard_break_timer <= 0.0:
		if not _prev_guarding:
			guard_held_time = 0.0
		else:
			guard_held_time += delta
		_prev_guarding = true
	else:
		_prev_guarding = false
		guard_held_time = 99.0

	if state == State.FALLING:
		vertical_vel -= 18.0 * delta
		position.y += vertical_vel * delta
		position.x += velocity_xz.x * delta
		position.z += velocity_xz.y * delta
		rotation.x += 2.6 * delta
		_clear_ribbon()
		if not _splash_emitted and position.y <= FALL_WATER_Y:
			_splash_emitted = true
			_play_sfx("splash", 1.0, -2.0)
			fell_off_ring.emit(self)
		return

	var to_opp := Vector2(opponent_pos.x - position.x, opponent_pos.z - position.z)
	if to_opp.length() > 0.12:
		facing_dir = to_opp.normalized()
	var target_yaw := atan2(-facing_dir.y, facing_dir.x)
	rotation.y = lerp_angle(rotation.y, target_yaw, clampf(delta * 15.0, 0.0, 1.0))

	if hit_flash_timer > 0.0:
		hit_flash_timer = maxf(0.0, hit_flash_timer - delta)
		_body_mat.emission_enabled = true
		_body_mat.emission = Color.WHITE * (hit_flash_timer * 3.5)
	else:
		_body_mat.emission_enabled = false

	_visual_root.position.y = sin(_idle_t * 4.5) * 0.015

	var spirit_ready := spirit >= 100.0
	var base_sword_emission := (Color(1.0, 0.80, 0.22) * 2.15) if (is_charged or spirit_ready) else (team_color * 0.90)
	var effective_guard := is_guarding and can_act and guard_break_timer <= 0.0
	if state == State.NORMAL and not effective_guard:
		guard_meter = minf(100.0, guard_meter + 15.0 * delta)
	elif effective_guard:
		guard_meter = minf(100.0, guard_meter + 4.5 * delta)

	match state:
		State.DODGING:
			dodge_timer -= delta
			_telegraph_bar.visible = false
			_hand_l.visible = not twin_blades_enabled
			_upper_body.rotation = _upper_body.rotation.lerp(Vector3(0.0, 0.0, -0.34), delta * 20.0)
			_arm_pivot.position = _arm_pivot.position.lerp(Vector3(0.28, 0.36, 0.14), delta * 18.0)
			_sword_tilt_pivot.rotation = _sword_tilt_pivot.rotation.lerp(Vector3(0.0, 0.0, 0.35), delta * 18.0)
			_sword_mat.emission = Color(0.45, 0.95, 1.0) * 1.45
			if dodge_timer <= 0.0:
				state = State.NORMAL
		State.STUNNED:
			stun_timer -= delta
			_stun_ring.visible = true
			_stun_ring.rotation.y += delta * 7.0
			_telegraph_bar.visible = false
			_hand_l.position = _hand_l.position.lerp(Vector3(-0.02, -0.03, -0.02), delta * 14.0)
			_upper_body.rotation = _upper_body.rotation.lerp(Vector3(0.0, 0.20, 0.26), delta * 12.0)
			_arm_pivot.position = _arm_pivot.position.lerp(Vector3(0.08, 0.30, 0.28), delta * 10.0)
			_blade_roll_pivot.rotation = _blade_roll_pivot.rotation.lerp(Vector3(0.65, 0.0, 0.0), delta * 10.0)
			_sword_tilt_pivot.rotation = _sword_tilt_pivot.rotation.lerp(Vector3(0.0, 0.0, 0.38), delta * 10.0)
			_sword_mat.emission = team_color * 0.45
			if stun_timer <= 0.0:
				state = State.NORMAL
				guard_meter = maxf(guard_meter, 55.0)
				_stun_ring.visible = false
		State.WINDUP:
			windup_timer -= delta
			var tele_angle := 0.0 if windup_attack_type == AttackType.THRUST else (atan2(windup_slash_dir.y, windup_slash_dir.x) + PI * 0.5)
			blade_roll_rad = wrapf(tele_angle, -PI, PI)
			var progress := 1.0 - clampf(windup_timer / _windup_duration, 0.0, 1.0)
			_hand_l.position = _hand_l.position.lerp(Vector3(-0.02, -0.03, -0.02), delta * 14.0)
			if windup_attack_type == AttackType.THRUST:
				_upper_body.rotation = _upper_body.rotation.lerp(Vector3(0.0, -0.22, 0.14), delta * 12.0)
				_arm_pivot.position = _arm_pivot.position.lerp(Vector3(0.06, 0.42, 0.14), delta * 14.0)
				_blade_roll_pivot.rotation = _blade_roll_pivot.rotation.lerp(Vector3(blade_roll_rad, 0.0, 0.0), delta * 16.0)
				_sword_tilt_pivot.rotation = _sword_tilt_pivot.rotation.lerp(Vector3(0.0, 0.0, -PI * 0.48), delta * 16.0)
			else:
				_upper_body.rotation = _upper_body.rotation.lerp(Vector3(0.0, -0.35, 0.18), delta * 12.0)
				_arm_pivot.position = _arm_pivot.position.lerp(Vector3(0.16, 0.62, 0.18), delta * 14.0)
				_blade_roll_pivot.rotation = _blade_roll_pivot.rotation.lerp(Vector3(tele_angle, 0.0, 0.0), delta * 18.0)
				_sword_tilt_pivot.rotation = _sword_tilt_pivot.rotation.lerp(Vector3(0.0, 0.0, 0.68), delta * 14.0)
			_sword_mat.emission = Color(1.0, 0.4 + 0.45 * (1.0 - progress), 0.15) * (1.2 + progress * 1.45)
			_telegraph_mat.albedo_color = Color(1.0, 0.9 - progress * 0.68, 0.18, 0.88)
			_telegraph_mat.emission = Color(1.0, 0.85 - progress * 0.65, 0.15) * (1.6 + progress * 1.25)
			_telegraph_bar.visible = true
			_telegraph_bar.scale = Vector3(1.0, 0.85 + progress * 0.35, 1.0 + progress * 0.7)
			if windup_timer <= 0.0:
				_sword_mat.emission = base_sword_emission
				_telegraph_bar.visible = false
				trigger_slash(windup_slash_dir, 1.05, windup_attack_type)
		State.SLASHING:
			slash_timer -= delta
			_telegraph_bar.visible = false
			var progress := 1.0 - clampf(slash_timer / maxf(_slash_duration, 0.01), 0.0, 1.0)
			_hand_l.position = _hand_l.position.lerp(Vector3(-0.02, -0.03, -0.02), delta * 24.0)

			if attack_type == AttackType.THRUST:
				var ext := sin(minf(progress * 1.35, 1.0) * PI)
				_upper_body.rotation = _upper_body.rotation.lerp(Vector3(0.0, 0.18, -0.26), delta * 26.0)
				_arm_pivot.position = Vector3(0.28 + ext * 0.64, 0.42, 0.05)
				_blade_roll_pivot.rotation = Vector3(blade_roll_rad, 0.0, 0.0)
				_sword_tilt_pivot.rotation = Vector3(0.0, 0.0, -PI * 0.5)
			else:
				# Exact sweep plane without the old +PI upside-down floor bug!
				var plane_angle := atan2(-active_slash_dir.x, active_slash_dir.y)
				var ease_t := 1.0 - pow(1.0 - progress, 2.2)
				var sweep_z := lerpf(0.62, -2.18, ease_t)
				_upper_body.rotation = _upper_body.rotation.lerp(Vector3(0.0, 0.38 * _slash_start_side, -0.22), delta * 26.0)
				_arm_pivot.position = _arm_pivot.position.lerp(Vector3(0.56, 0.44, 0.0), delta * 28.0)
				_blade_roll_pivot.rotation = Vector3(plane_angle, 0.0, 0.0)
				_sword_tilt_pivot.rotation = Vector3(0.0, 0.0, sweep_z)
				if twin_blades_enabled and _offhand_pivot:
					_offhand_blade_root.rotation = Vector3(0.0, ease_t * 1.8 * _slash_start_side, -0.8 - ease_t * 1.1)

			_sword_mat.emission = (Color(1.0, 0.86, 0.22) * 2.55) if (is_charged or spirit_ready) else (team_color * 1.65)
			_append_trail_sample()

			if not _hit_resolved_this_swing and progress >= HIT_ARC_START:
				_hit_resolved_this_swing = true
				slash_impact.emit(self, active_slash_dir, active_slash_power, attack_type)

			if slash_timer <= 0.0:
				state = State.NORMAL
		State.NORMAL:
			_telegraph_bar.visible = false
			var q_map := Quaternion(Vector3.UP, -PI * 0.5)
			var use_full_3d := not blade_orientation.is_equal_approx(Quaternion.IDENTITY)
			var q_fighter := (q_map * blade_orientation * q_map.inverse()).normalized() if use_full_3d else Quaternion.from_euler(Vector3(blade_roll_rad, 0.0, 0.0))
			var aim_f := q_fighter * Vector3.RIGHT
			if effective_guard:
				var parry_hot := guard_held_time <= 0.22
				_sword_mat.emission = (Color(1.0, 0.92, 0.35) * 2.1) if parry_hot else (
					(Color(1.0, 0.82, 0.2) * 2.0) if is_charged else (Color(0.35, 0.92, 1.0) * 1.55)
				)
				if not twin_blades_enabled:
					_hand_l.position = _hand_l.position.lerp(Vector3(0.0, 0.68, 0.0), delta * 20.0)
				_upper_body.rotation = _upper_body.rotation.lerp(Vector3(clampf(-aim_f.z * 0.16, -0.18, 0.18), -0.10 + clampf(-aim_f.z * 0.20, -0.22, 0.22), -0.06 + clampf(aim_f.y * 0.14, -0.16, 0.16)), delta * 18.0)
				_arm_pivot.position = _arm_pivot.position.lerp(Vector3(0.46, 0.48 + clampf(aim_f.y * 0.12, -0.10, 0.14), clampf(aim_f.z * 0.16, -0.14, 0.14)), delta * 20.0)
				var q_guard_yaw := Quaternion(Vector3.UP, clampf(-aim_f.z * 0.36, -0.36, 0.36))
				var q_guard_pitch := Quaternion(Vector3.BACK, clampf(aim_f.y * 0.28, -0.28, 0.28))
				var q_guard := (q_guard_yaw * q_guard_pitch * Quaternion(Vector3.RIGHT, blade_roll_rad)).normalized()
				_blade_roll_pivot.quaternion = _blade_roll_pivot.quaternion.slerp(q_guard, clampf(delta * 28.0, 0.0, 1.0))
				_sword_tilt_pivot.rotation = _sword_tilt_pivot.rotation.lerp(Vector3(0.0, 0.0, -0.18), delta * 22.0)
				if twin_blades_enabled and _offhand_pivot:
					_offhand_blade_root.rotation = _offhand_blade_root.rotation.lerp(Vector3(0.3, 0.65, -0.25), delta * 18.0)
			else:
				_sword_mat.emission = (Color(0.35, 1.0, 0.65) * 1.25) if (auto_guard_ready and not is_charged and not spirit_ready) else base_sword_emission
				_hand_l.position = _hand_l.position.lerp(Vector3(-0.02, -0.03, -0.02), delta * 18.0)
				_upper_body.rotation = _upper_body.rotation.lerp(Vector3(clampf(-aim_f.z * 0.16, -0.22, 0.22), clampf(-aim_f.z * 0.30, -0.34, 0.34), clampf(aim_f.y * 0.18, -0.20, 0.22)), delta * 16.0)
				_arm_pivot.position = _arm_pivot.position.lerp(Vector3(0.38, 0.42 + clampf(aim_f.y * 0.20, -0.16, 0.24), 0.05 + clampf(aim_f.z * 0.24, -0.22, 0.22)), delta * 20.0)
				_blade_roll_pivot.quaternion = _blade_roll_pivot.quaternion.slerp(q_fighter, clampf(delta * 30.0, 0.0, 1.0))
				_sword_tilt_pivot.rotation = _sword_tilt_pivot.rotation.lerp(Vector3(0.0, 0.0, -1.04), delta * 24.0)
				if twin_blades_enabled and _offhand_pivot:
					_offhand_blade_root.rotation = _offhand_blade_root.rotation.lerp(Vector3(-0.28, -0.15, -0.56), delta * 16.0)

	_guard_halo.visible = (state == State.NORMAL and effective_guard)
	if _guard_halo.visible:
		var gm_ratio := clampf(guard_meter / 100.0, 0.25, 1.0)
		_halo_mat.albedo_color = Color(team_color.r, team_color.g, team_color.b, 0.75 * gm_ratio)
		_guard_halo.scale = Vector3.ONE * (0.8 + gm_ratio * 0.25)

	if state != State.SLASHING:
		_trail_hold_timer = maxf(0.0, _trail_hold_timer - delta)
		if _trail_hold_timer <= 0.0 and not _trail_samples.is_empty():
			_trail_samples.remove_at(0)
	_rebuild_ribbon_mesh()

	velocity_xz = velocity_xz.lerp(Vector2.ZERO, clampf(delta * 8.2, 0.0, 1.0))
	position.x += velocity_xz.x * delta
	position.z += velocity_xz.y * delta

	var xz := Vector2(position.x, position.z)
	if DojoStageScript.is_out_of_bounds(xz, stage_type, arena_radius_override):
		state = State.FALLING
		vertical_vel = 0.25
		var push_out := xz.normalized() if xz.length() > 0.05 else -facing_dir
		velocity_xz = velocity_xz * 0.5 + push_out * 1.4
		_guard_halo.visible = false
		_telegraph_bar.visible = false
		_stun_ring.visible = false
		_clear_ribbon()


func _append_trail_sample() -> void:
	if not is_inside_tree() or _hilt_marker == null or _tip_marker == null:
		return
	_trail_samples.append({
		"hilt": _hilt_marker.global_position,
		"tip": _tip_marker.global_position
	})
	if _trail_samples.size() > 11:
		_trail_samples.remove_at(0)


func _clear_ribbon() -> void:
	_trail_samples.clear()
	if _ribbon_mesh:
		_ribbon_mesh.clear_surfaces()
	if _ribbon_mesh_inst:
		_ribbon_mesh_inst.visible = false


func _rebuild_ribbon_mesh() -> void:
	if _ribbon_mesh == null or _ribbon_mesh_inst == null or not is_inside_tree():
		return
	_ribbon_mesh.clear_surfaces()
	if _trail_samples.size() < 2:
		_ribbon_mesh_inst.visible = false
		return

	var base_c := Color(1.0, 0.88, 0.25) if (is_charged or spirit >= 100.0) else team_color.lightened(0.25)
	_ribbon_mat.emission = base_c * 1.55

	_ribbon_mesh_inst.visible = true
	_ribbon_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP, _ribbon_mat)
	var n := _trail_samples.size()
	for i in n:
		var t := float(i) / float(n - 1)
		var sample: Dictionary = _trail_samples[i]
		var tip_p: Vector3 = sample["tip"]
		var hilt_p: Vector3 = sample["hilt"]
		var tip_c := Color(1.0, 1.0, 1.0, t * 0.92)
		var hilt_c := Color(base_c.r, base_c.g, base_c.b, t * 0.35)
		_ribbon_mesh.surface_set_color(tip_c)
		_ribbon_mesh.surface_add_vertex(tip_p)
		_ribbon_mesh.surface_set_color(hilt_c)
		_ribbon_mesh.surface_add_vertex(hilt_p)
	_ribbon_mesh.surface_end()


func _play_sfx(sound_name: String, pitch: float, volume_db: float) -> void:
	var sfx := get_node_or_null("/root/SoundFX")
	if sfx != null:
		sfx.play(sound_name, pitch, volume_db)
