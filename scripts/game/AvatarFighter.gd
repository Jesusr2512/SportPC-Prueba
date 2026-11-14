@tool
class_name AvatarFighter
extends Node3D

signal slash_executed(fighter: AvatarFighter, slash_dir: Vector2, power: float)
signal fell_off_ring(fighter: AvatarFighter)

const PLATFORM_RADIUS := 4.6
const FALL_WATER_Y := -1.35
const SLASH_DURATION := 0.20

enum State { NORMAL, WINDUP, SLASHING, STUNNED, FALLING }

@export var fighter_name: String = "Jugador 1"
@export var team_color: Color = Color(0.05, 0.78, 0.92)
@export var facing_dir: Vector2 = Vector2.RIGHT

var state: State = State.NORMAL
var is_guarding: bool = false
var is_charged: bool = false
var auto_guard_ready: bool = false
var blade_orientation: Quaternion = Quaternion.IDENTITY
var blade_roll_rad: float = 0.0
var windup_slash_dir: Vector2 = Vector2.RIGHT

var velocity_xz: Vector2 = Vector2.ZERO
var vertical_vel: float = 0.0
var stun_timer: float = 0.0
var slash_timer: float = 0.0
var windup_timer: float = 0.0
var guard_break_timer: float = 0.0
var _windup_duration: float = 0.7
var hit_flash_timer: float = 0.0
var _splash_emitted: bool = false
var _idle_t: float = 0.0
var _slash_angle: float = 0.0
var _slash_start_side: float = 1.0
var _camera_translucent: bool = false

var _visual_root: Node3D
var _upper_body: Node3D
var _arm_pivot: Node3D
var _sword_tilt_pivot: Node3D
var _blade_roll_pivot: Node3D
var _hand_l: MeshInstance3D
var _guard_halo: MeshInstance3D
var _slash_arc: MeshInstance3D
var _telegraph_bar: MeshInstance3D
var _telegraph_mat: StandardMaterial3D
var _stun_ring: Node3D
var _body_mesh: MeshInstance3D
var _head_node: Node3D
var _sword_mat: StandardMaterial3D
var _body_mat: StandardMaterial3D
var _white_mat: StandardMaterial3D
var _skin_mat: StandardMaterial3D
var _visor_mat: StandardMaterial3D
var _halo_mat: StandardMaterial3D


func _ready() -> void:
	var old := get_node_or_null("VisualRoot")
	if old != null:
		old.free()
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
	_body_mat.roughness = 0.42

	_skin_mat = StandardMaterial3D.new()
	_skin_mat.albedo_color = Color(0.98, 0.85, 0.74)
	_skin_mat.roughness = 0.65

	var dark_mat := StandardMaterial3D.new()
	dark_mat.albedo_color = Color(0.11, 0.13, 0.18)
	dark_mat.roughness = 0.5

	_white_mat = StandardMaterial3D.new()
	_white_mat.albedo_color = Color(0.96, 0.98, 1.0)
	_white_mat.roughness = 0.35

	_visor_mat = StandardMaterial3D.new()
	_visor_mat.albedo_color = Color(0.08, 0.1, 0.15)
	_visor_mat.metallic = 0.8
	_visor_mat.roughness = 0.14

	# Feet (planted on lower body)
	for side in [-1.0, 1.0]:
		var foot := MeshInstance3D.new()
		var fm := SphereMesh.new()
		fm.radius = 0.115
		fm.height = 0.15
		foot.mesh = fm
		foot.material_override = _white_mat
		foot.position = Vector3(0.06 if side > 0 else -0.04, 0.08, side * 0.15)
		_visual_root.add_child(foot)

	# Torso (relative to _upper_body at y=0.42)
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

	# Sporty belt
	var belt := MeshInstance3D.new()
	var belt_mesh := CylinderMesh.new()
	belt_mesh.top_radius = 0.252
	belt_mesh.bottom_radius = 0.252
	belt_mesh.height = 0.085
	belt.mesh = belt_mesh
	belt.material_override = _white_mat
	belt.position = Vector3(0.0, 0.01, 0.0)
	_upper_body.add_child(belt)

	# Head
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

	# Headband
	var band := MeshInstance3D.new()
	var bm := CylinderMesh.new()
	bm.top_radius = 0.228
	bm.bottom_radius = 0.228
	bm.height = 0.075
	band.mesh = bm
	band.material_override = _body_mat
	band.position = Vector3(0.0, 0.09, 0.0)
	_head_node.add_child(band)

	# Sporty visor
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

	# Decoupled Sword Rig
	_arm_pivot = Node3D.new()
	_arm_pivot.position = Vector3(0.36, 0.42, 0.06)
	_upper_body.add_child(_arm_pivot)

	_blade_roll_pivot = Node3D.new()
	_blade_roll_pivot.name = "BladeRollPivot"
	_arm_pivot.add_child(_blade_roll_pivot)

	_sword_tilt_pivot = Node3D.new()
	_sword_tilt_pivot.rotation_degrees = Vector3(0.0, 0.0, -24.0)
	_blade_roll_pivot.add_child(_sword_tilt_pivot)

	# Right hand (stays on hilt) & Left hand (braces upper blade during guard)
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
	_sword_mat.emission = team_color * 0.85

	var blade := MeshInstance3D.new()
	var blade_m := BoxMesh.new()
	blade_m.size = Vector3(0.095, 1.24, 0.035)
	blade.mesh = blade_m
	blade.material_override = _sword_mat
	blade.position = Vector3(0.0, 0.84, 0.0)
	_sword_tilt_pivot.add_child(blade)

	var core := MeshInstance3D.new()
	var core_m := BoxMesh.new()
	core_m.size = Vector3(0.04, 1.20, 0.042)
	core.mesh = core_m
	var core_mat := StandardMaterial3D.new()
	core_mat.albedo_color = Color.WHITE
	core_mat.emission_enabled = true
	core_mat.emission = Color.WHITE * 1.35
	core.material_override = core_mat
	core.position = Vector3(0.0, 0.83, 0.0)
	_sword_tilt_pivot.add_child(core)

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

	# Telegraph attack plane indicator (visible in 3D world space during WINDUP)
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

	# Slash arc flash
	_slash_arc = MeshInstance3D.new()
	var arc_m := BoxMesh.new()
	arc_m.size = Vector3(0.07, 1.95, 0.44)
	_slash_arc.mesh = arc_m
	var arc_mat := StandardMaterial3D.new()
	arc_mat.albedo_color = Color(1.0, 1.0, 1.0, 0.9)
	arc_mat.emission_enabled = true
	arc_mat.emission = team_color * 1.7
	arc_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_slash_arc.material_override = arc_mat
	_slash_arc.position = Vector3(0.75, 0.96, 0.0)
	_slash_arc.visible = false
	_visual_root.add_child(_slash_arc)


func set_camera_translucent(enabled: bool) -> void:
	_camera_translucent = enabled
	if _body_mat == null:
		return
	var alpha := 0.40 if enabled else 1.0
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
	is_guarding = false
	is_charged = false
	auto_guard_ready = false
	velocity_xz = Vector2.ZERO
	vertical_vel = 0.0
	stun_timer = 0.0
	slash_timer = 0.0
	windup_timer = 0.0
	guard_break_timer = 0.0
	hit_flash_timer = 0.0
	_splash_emitted = false
	blade_roll_rad = 0.0
	blade_orientation = Quaternion.IDENTITY
	if _upper_body:
		_upper_body.rotation = Vector3.ZERO
	if _blade_roll_pivot:
		_blade_roll_pivot.rotation = Vector3.ZERO
	if _hand_l:
		_hand_l.position = Vector3(-0.02, -0.03, -0.02)
	if _stun_ring:
		_stun_ring.visible = false
	if _slash_arc:
		_slash_arc.visible = false
	if _telegraph_bar:
		_telegraph_bar.visible = false
	if _guard_halo:
		_guard_halo.visible = false


func trigger_slash(slash_dir: Vector2, power: float) -> void:
	if state == State.STUNNED or state == State.FALLING:
		return
	state = State.SLASHING
	slash_timer = SLASH_DURATION
	windup_timer = 0.0
	is_guarding = false
	auto_guard_ready = false
	_slash_start_side = -_slash_start_side
	_telegraph_bar.visible = false

	_slash_angle = atan2(slash_dir.y, slash_dir.x)
	_slash_arc.visible = true
	_slash_arc.rotation = Vector3(_slash_angle + PI * 0.5, 0.0, 0.0)
	_slash_arc.scale = Vector3.ONE

	_play_sfx("slash", randf_range(0.95, 1.22), -5.0)
	slash_executed.emit(self, slash_dir.normalized(), power)


func start_windup(slash_dir: Vector2, duration: float) -> void:
	if state != State.NORMAL:
		return
	state = State.WINDUP
	windup_slash_dir = slash_dir.normalized()
	_windup_duration = maxf(duration, 0.1)
	windup_timer = _windup_duration
	is_guarding = false
	auto_guard_ready = false

	var cut_ang := atan2(windup_slash_dir.y, windup_slash_dir.x)
	_telegraph_bar.visible = true
	_telegraph_bar.rotation = Vector3(cut_ang + PI * 0.5, 0.0, 0.0)
	var sfx := get_node_or_null("/root/SoundFX")
	if sfx != null and sfx.has_method("play_windup"):
		sfx.play_windup()


func apply_stun(duration: float = 1.65) -> void:
	state = State.STUNNED
	stun_timer = duration
	is_guarding = false
	auto_guard_ready = false
	_slash_arc.visible = false
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
	_slash_arc.visible = false
	_telegraph_bar.visible = false
	velocity_xz += recoil_impulse
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


func step_fighter(delta: float, move_input: Vector2, opponent_pos: Vector3, can_act: bool) -> void:
	_idle_t += delta
	if guard_break_timer > 0.0:
		guard_break_timer = maxf(0.0, guard_break_timer - delta)

	if state == State.FALLING:
		vertical_vel -= 18.0 * delta
		position.y += vertical_vel * delta
		position.x += velocity_xz.x * delta
		position.z += velocity_xz.y * delta
		rotation.x += 2.6 * delta
		if not _splash_emitted and position.y <= FALL_WATER_Y:
			_splash_emitted = true
			_play_sfx("splash", 1.0, -2.0)
			fell_off_ring.emit(self)
		return

	var to_opp := Vector2(opponent_pos.x - position.x, opponent_pos.z - position.z)
	if to_opp.length() > 0.12:
		facing_dir = to_opp.normalized()
	var target_yaw := atan2(-facing_dir.y, facing_dir.x)
	rotation.y = lerp_angle(rotation.y, target_yaw, clampf(delta * 14.0, 0.0, 1.0))

	if can_act and state == State.NORMAL and move_input.length() > 0.05:
		var fwd := Vector2(facing_dir.x, facing_dir.y).normalized()
		var right := Vector2(-fwd.y, fwd.x)
		var move_xz := right * (move_input.x * 2.35) + fwd * (-move_input.y * 1.85)
		position.x += move_xz.x * delta
		position.z += move_xz.y * delta

	if hit_flash_timer > 0.0:
		hit_flash_timer = maxf(0.0, hit_flash_timer - delta)
		_body_mat.emission_enabled = true
		_body_mat.emission = Color.WHITE * (hit_flash_timer * 3.5)
	else:
		_body_mat.emission_enabled = false

	_visual_root.position.y = sin(_idle_t * 4.5) * 0.015

	var base_sword_emission := (Color(1.0, 0.78, 0.18) * 1.95) if is_charged else (team_color * 0.85)
	var effective_guard := is_guarding and can_act and guard_break_timer <= 0.0

	match state:
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
			_sword_mat.emission = team_color * 0.5
			if stun_timer <= 0.0:
				state = State.NORMAL
				_stun_ring.visible = false
		State.WINDUP:
			windup_timer -= delta
			var tele_angle := atan2(windup_slash_dir.y, windup_slash_dir.x) + PI * 0.5
			blade_roll_rad = wrapf(tele_angle, -PI, PI)
			var progress := 1.0 - clampf(windup_timer / _windup_duration, 0.0, 1.0)
			_hand_l.position = _hand_l.position.lerp(Vector3(-0.02, -0.03, -0.02), delta * 14.0)
			_upper_body.rotation = _upper_body.rotation.lerp(Vector3(0.0, -0.35, 0.16), delta * 12.0)
			_arm_pivot.position = _arm_pivot.position.lerp(Vector3(0.18, 0.62, 0.18), delta * 14.0)
			_blade_roll_pivot.rotation = _blade_roll_pivot.rotation.lerp(Vector3(tele_angle, 0.0, 0.0), delta * 18.0)
			_sword_tilt_pivot.rotation = _sword_tilt_pivot.rotation.lerp(Vector3(0.0, 0.0, 0.65), delta * 14.0)
			_sword_mat.emission = Color(1.0, 0.4 + 0.45 * (1.0 - progress), 0.15) * (1.2 + progress * 1.4)
			_telegraph_mat.albedo_color = Color(1.0, 0.9 - progress * 0.68, 0.18, 0.88)
			_telegraph_mat.emission = Color(1.0, 0.85 - progress * 0.65, 0.15) * (1.6 + progress * 1.2)
			_telegraph_bar.visible = true
			_telegraph_bar.scale = Vector3(1.0, 0.85 + progress * 0.35, 1.0 + progress * 0.7)
			if windup_timer <= 0.0:
				_sword_mat.emission = base_sword_emission
				_telegraph_bar.visible = false
				trigger_slash(windup_slash_dir, 1.0)
		State.SLASHING:
			slash_timer -= delta
			_telegraph_bar.visible = false
			var progress := 1.0 - clampf(slash_timer / SLASH_DURATION, 0.0, 1.0)
			var plane_angle := _slash_angle + PI * 0.5
			if _slash_start_side < 0.0:
				plane_angle += PI
			var sweep_z := lerpf(0.55, -2.40, progress)
			_hand_l.position = _hand_l.position.lerp(Vector3(-0.02, -0.03, -0.02), delta * 24.0)
			_upper_body.rotation = _upper_body.rotation.lerp(Vector3(0.0, 0.38 * _slash_start_side, -0.22), delta * 24.0)
			_arm_pivot.position = _arm_pivot.position.lerp(Vector3(0.58, 0.44, 0.0), delta * 26.0)
			_blade_roll_pivot.rotation = Vector3(plane_angle, 0.0, 0.0)
			_sword_tilt_pivot.rotation = Vector3(0.0, 0.0, sweep_z)
			_sword_mat.emission = (Color(1.0, 0.85, 0.2) * 2.4) if is_charged else (team_color * 1.55)
			_slash_arc.scale.x = 1.0 + progress * 1.2
			_slash_arc.scale.y = 1.0 + progress * 0.18
			if slash_timer <= 0.0:
				state = State.NORMAL
				_slash_arc.visible = false
		State.NORMAL:
			_telegraph_bar.visible = false
			var e := blade_orientation.get_euler()
			if effective_guard:
				_sword_mat.emission = Color(0.35, 0.92, 1.0) * 1.55 if not is_charged else Color(1.0, 0.82, 0.2) * 2.0
				# Switch Sports Two-Handed Guard with full 3D depth tilt/yaw
				_hand_l.position = _hand_l.position.lerp(Vector3(0.0, 0.68, 0.0), delta * 20.0)
				_upper_body.rotation = _upper_body.rotation.lerp(Vector3(clampf(e.x * 0.16, -0.18, 0.18), -0.10 + clampf(e.y * 0.22, -0.22, 0.22), -0.08), delta * 16.0)
				_arm_pivot.position = _arm_pivot.position.lerp(Vector3(0.46 + clampf(-e.x * 0.08, -0.06, 0.10), 0.48 + clampf(e.x * 0.10, -0.08, 0.10), clampf(-e.y * 0.16, -0.14, 0.14)), delta * 18.0)
				_blade_roll_pivot.rotation = _blade_roll_pivot.rotation.lerp(Vector3(blade_roll_rad, 0.0, 0.0), delta * 26.0)
				_sword_tilt_pivot.rotation = _sword_tilt_pivot.rotation.lerp(
					Vector3(0.0, clampf(e.y * 0.45, -0.45, 0.45), clampf(-0.04 + e.x * 0.35, -0.42, 0.38)),
					delta * 20.0
				)
			else:
				_sword_mat.emission = (Color(0.35, 1.0, 0.65) * 1.25) if (auto_guard_ready and not is_charged) else base_sword_emission
				_hand_l.position = _hand_l.position.lerp(Vector3(-0.02, -0.03, -0.02), delta * 18.0)
				_upper_body.rotation = _upper_body.rotation.lerp(Vector3(clampf(e.x * 0.18, -0.22, 0.22), clampf(e.y * 0.28, -0.28, 0.28), 0.0), delta * 12.0)
				_arm_pivot.position = _arm_pivot.position.lerp(Vector3(0.38 + clampf(-e.x * 0.10, -0.08, 0.12), 0.42 + clampf(e.x * 0.12, -0.10, 0.12), 0.05 + clampf(-e.y * 0.20, -0.18, 0.18)), delta * 16.0)
				_blade_roll_pivot.rotation = _blade_roll_pivot.rotation.lerp(Vector3(blade_roll_rad, 0.0, 0.0), delta * 28.0)
				_sword_tilt_pivot.rotation = _sword_tilt_pivot.rotation.lerp(
					Vector3(0.0, clampf(e.y * 0.72, -0.72, 0.72), clampf(-0.36 + e.x * 0.55, -1.15, 0.48)),
					delta * 20.0
				)

	_guard_halo.visible = (state == State.NORMAL and effective_guard)

	velocity_xz = velocity_xz.lerp(Vector2.ZERO, clampf(delta * 8.2, 0.0, 1.0))
	position.x += velocity_xz.x * delta
	position.z += velocity_xz.y * delta

	if Vector2(position.x, position.z).length() > PLATFORM_RADIUS:
		state = State.FALLING
		vertical_vel = 1.2
		_guard_halo.visible = false
		_slash_arc.visible = false
		_telegraph_bar.visible = false
		_stun_ring.visible = false


func _play_sfx(sound_name: String, pitch: float, volume_db: float) -> void:
	var sfx := get_node_or_null("/root/SoundFX")
	if sfx != null:
		sfx.play(sound_name, pitch, volume_db)
