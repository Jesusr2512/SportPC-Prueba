class_name MotionFusion
extends RefCounted

const GYRO_DEADZONE := 0.04
const SWING_THRESHOLD := 2.75
const SWING_COOLDOWN := 0.14
const STEADY_THRESHOLD := 2.0
const BIAS_ALPHA := 0.06
const GRAVITY_BLEND := 0.07
const YAW_SPRING_STILL := 0.90

var raw_orientation: Quaternion = Quaternion.IDENTITY
var recenter_offset: Quaternion = Quaternion.IDENTITY
var orientation: Quaternion = Quaternion.IDENTITY

var gyro_bias: Vector3 = Vector3.ZERO
var gyro: Vector3 = Vector3.ZERO
var accel: Vector3 = Vector3.ZERO
var linear_accel: Vector3 = Vector3.ZERO
var gravity: Vector3 = Vector3(0.0, -9.81, 0.0)

var pitch_rad: float = 0.0
var yaw_rad: float = 0.0
var roll_rad: float = 0.0
var blade_roll_rad: float = 0.0
var snapped_blade_roll_rad: float = 0.0

var angular_speed: float = 0.0
var is_steady: bool = true
var has_centered_once: bool = false
var swing_cooldown_timer: float = 0.0
var last_slash_dir: Vector2 = Vector2.RIGHT
var last_slash_power: float = 0.0
var just_swung: bool = false

var _ref_gravity: Vector3 = Vector3(0.0, -1.0, 0.0)
var _bias_samples_left: int = 0
var _bias_accum: Vector3 = Vector3.ZERO
var _bias_count: int = 0
var _swing_armed: bool = true
var _peak_gyro: Vector3 = Vector3.ZERO
var _peak_timer: float = 0.0


func reset_pose() -> void:
	raw_orientation = Quaternion.IDENTITY
	recenter_offset = Quaternion.IDENTITY
	orientation = Quaternion.IDENTITY
	pitch_rad = 0.0
	yaw_rad = 0.0
	roll_rad = 0.0
	blade_roll_rad = 0.0
	snapped_blade_roll_rad = 0.0
	_ref_gravity = Vector3(0.0, -1.0, 0.0)


func recenter() -> void:
	if gravity.length() > 1.0:
		_ref_gravity = gravity.normalized()
	else:
		_ref_gravity = Vector3(0.0, -1.0, 0.0)
	recenter_offset = raw_orientation.inverse()
	pitch_rad = 0.0
	yaw_rad = 0.0
	roll_rad = 0.0
	blade_roll_rad = 0.0
	snapped_blade_roll_rad = 0.0
	orientation = Quaternion.IDENTITY
	has_centered_once = true


func recenter_yaw() -> void:
	yaw_rad = 0.0
	orientation = Quaternion.from_euler(Vector3(pitch_rad, yaw_rad, -roll_rad)).normalized()


func start_bias_calibration(sample_frames: int = 25) -> void:
	_bias_samples_left = sample_frames
	_bias_accum = Vector3.ZERO
	_bias_count = 0


func update(delta: float, raw_gyro: Vector3, raw_accel: Vector3, raw_gravity: Vector3) -> void:
	just_swung = false
	if delta <= 0.0 or delta > 0.15:
		delta = 0.016

	swing_cooldown_timer = maxf(0.0, swing_cooldown_timer - delta)
	accel = raw_accel
	if raw_gravity.length() > 0.5:
		gravity = gravity.lerp(raw_gravity, 0.35) if gravity.length() > 0.5 else raw_gravity
	linear_accel = raw_accel - raw_gravity

	if _bias_samples_left > 0:
		_bias_accum += raw_gyro
		_bias_count += 1
		_bias_samples_left -= 1
		if _bias_samples_left == 0 and _bias_count > 0:
			gyro_bias = _bias_accum / float(_bias_count)

	# Adaptive zero-velocity bias tracking when controller rests still
	if raw_gyro.length() < 0.25 and linear_accel.length() < 1.35:
		gyro_bias = gyro_bias.lerp(raw_gyro, BIAS_ALPHA)

	var corrected := raw_gyro - gyro_bias
	if corrected.length() < GYRO_DEADZONE:
		corrected = Vector3.ZERO
	gyro = corrected
	angular_speed = gyro.length()
	is_steady = angular_speed < STEADY_THRESHOLD

	var angle := angular_speed * delta
	if angle > 0.0001:
		var axis := gyro / angular_speed
		var dq := Quaternion(axis, angle)
		raw_orientation = (raw_orientation * dq).normalized()

	# Decoupled integration in centered sword frame (+roll = 2 o'clock / screen right)
	pitch_rad = clampf(pitch_rad + gyro.x * delta, -1.15, 1.15)
	yaw_rad = clampf(yaw_rad + gyro.y * delta, -1.05, 1.05)
	roll_rad = clampf(roll_rad + gyro.z * delta, -1.70, 1.70)

	# Sagittal-plane gravity anchor: works cleanly from flat (0 deg) up to upright (85 deg) with zero yaw coupling
	var g_len := gravity.length()
	var ref_yz := Vector2(_ref_gravity.y, _ref_gravity.z)
	if g_len > 6.0 and g_len < 13.5 and linear_accel.length() < 3.2 and angular_speed < 3.6 and ref_yz.length() > 0.25:
		var gn := gravity / g_len
		var d0_yz := ref_yz.normalized()
		var perp_yz := Vector2(-d0_yz.y, d0_yz.x)
		var gn_yz := Vector2(gn.y, gn.z)
		var sag := gn_yz.dot(d0_yz)
		if sag > 0.15 or absf(gn.x) > 0.25:
			var ref_roll := atan2(_ref_gravity.x, ref_yz.length())
			var now_roll := atan2(gn.x, maxf(sag, 0.05) if absf(gn.x) < 0.9 else sag)
			var grav_roll := clampf(wrapf(now_roll - ref_roll, -PI, PI), -1.65, 1.65)
			roll_rad = lerp_angle(roll_rad, grav_roll, GRAVITY_BLEND)

		var grav_pitch := clampf(atan2(-gn_yz.dot(perp_yz), maxf(absf(sag), 0.1)), -1.10, 1.10)
		pitch_rad = lerp_angle(pitch_rad, grav_pitch, GRAVITY_BLEND * 0.85)

	# Soft yaw spring return when stationary so aim stays centered during combat
	if angular_speed < 0.55:
		yaw_rad = lerpf(yaw_rad, 0.0, clampf(delta * YAW_SPRING_STILL, 0.0, 1.0))

	orientation = Quaternion.from_euler(Vector3(pitch_rad, yaw_rad, -roll_rad)).normalized()
	blade_roll_rad = clampf(roll_rad, -PI * 0.55, PI * 0.55)
	snapped_blade_roll_rad = _compute_snapped_roll(blade_roll_rad)
	_detect_swing(delta)


func apply_external_orientation(target_q: Quaternion, delta: float, raw_gyro: Vector3, raw_linear: Vector3) -> void:
	just_swung = false
	if delta <= 0.0 or delta > 0.15:
		delta = 0.016
	swing_cooldown_timer = maxf(0.0, swing_cooldown_timer - delta)
	raw_orientation = target_q.normalized()
	orientation = (recenter_offset * raw_orientation).normalized()
	var e := orientation.get_euler()
	pitch_rad = e.x
	yaw_rad = e.y
	roll_rad = -e.z
	blade_roll_rad = clampf(roll_rad, -PI * 0.55, PI * 0.55)
	snapped_blade_roll_rad = _compute_snapped_roll(blade_roll_rad)
	gyro = raw_gyro
	linear_accel = raw_linear
	angular_speed = raw_gyro.length()
	is_steady = angular_speed < STEADY_THRESHOLD
	_detect_swing(delta)


func quantize_4_angles(angle_rad: float) -> float:
	var targets := [-PI * 0.5, -PI * 0.25, 0.0, PI * 0.25, PI * 0.5]
	var best: float = 0.0
	var best_dist: float = INF
	for t in targets:
		var d := absf(angle_rad - t)
		if d < best_dist:
			best_dist = d
			best = t
	return best


func _compute_snapped_roll(raw_roll: float) -> float:
	var targets := [-PI * 0.5, -PI * 0.25, 0.0, PI * 0.25, PI * 0.5]
	var snap_zone := 0.24
	var best := raw_roll
	var best_dist := snap_zone
	for t in targets:
		var d := absf(raw_roll - t)
		if d < best_dist:
			best_dist = d
			best = t
	if best == raw_roll:
		return raw_roll
	var closeness := 1.0 - (best_dist / snap_zone)
	return lerpf(raw_roll, best, closeness * closeness * 0.88)


func _detect_swing(delta: float) -> void:
	var motion_energy := angular_speed + linear_accel.length() * 0.28

	if not _swing_armed:
		if motion_energy < SWING_THRESHOLD * 0.48 and swing_cooldown_timer <= 0.0:
			_swing_armed = true
		return

	if _peak_timer > 0.0:
		_peak_timer -= delta
		if angular_speed > _peak_gyro.length():
			_peak_gyro = gyro
		if _peak_timer <= 0.0:
			just_swung = true
			_swing_armed = false
			swing_cooldown_timer = SWING_COOLDOWN

			# Switch Sports cut direction logic: blade orientation defines the cut plane!
			# Only pure horizontal swipes from a vertical stance override to horizontal cut.
			var horiz := -_peak_gyro.y
			var vert := _peak_gyro.x
			if absf(snapped_blade_roll_rad) < 0.26 and absf(horiz) > absf(vert) * 1.25 and absf(horiz) > 1.0:
				last_slash_dir = Vector2(signf(horiz), 0.0)
			else:
				var cut_ang := quantize_4_angles(snapped_blade_roll_rad) - PI * 0.5
				last_slash_dir = Vector2(cos(cut_ang), sin(cut_ang)).normalized()

			last_slash_power = clampf(_peak_gyro.length() / 9.8, 0.45, 1.45)
	elif swing_cooldown_timer <= 0.0 and motion_energy >= SWING_THRESHOLD:
		_peak_gyro = gyro
		_peak_timer = 0.028


func get_blade_roll_rad() -> float:
	return blade_roll_rad


func get_snapped_blade_roll_rad() -> float:
	return snapped_blade_roll_rad


func get_blade_angle_deg() -> float:
	return rad_to_deg(blade_roll_rad)
