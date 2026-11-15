class_name MotionFusion
extends RefCounted

enum SlashType { CUT = 0, THRUST = 1 }

const GYRO_DEADZONE := 0.04
const SWING_THRESHOLD := 2.75
const SWING_PRIMED_THRESHOLD := 2.20
const COMBO_THRESHOLD := 2.45
const SWING_REFRACTORY := 0.115
const THRUST_ACCEL_THRESHOLD := 5.8
const STEADY_THRESHOLD := 1.9

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
var aim_dir: Vector2 = Vector2.ZERO
var aim_forward: Vector3 = Vector3.FORWARD

var angular_speed: float = 0.0
var tip_vel: Vector2 = Vector2.ZERO
var tip_speed: float = 0.0
var dynamic_accel_mag: float = 0.0
var forward_thrust_accel: float = 0.0
var motion_energy: float = 0.0
var is_steady: bool = true
var has_centered_once: bool = false
var swing_cooldown_timer: float = 0.0
var last_slash_dir: Vector2 = Vector2.RIGHT
var last_slash_power: float = 0.0
var last_slash_type: int = SlashType.CUT
var last_swing_source: String = ""
var just_swung: bool = false

# Live speed streaming up to impact frame so full arm acceleration registers even after early threshold crossing
var active_peak_speed: float = 0.0

var _level_q: Quaternion = Quaternion.IDENTITY
var _prev_accel: Vector3 = Vector3(0.0, -9.81, 0.0)
var _lp_accel: Vector3 = Vector3.ZERO
var _bias_samples_left: int = 0
var _bias_accum: Vector3 = Vector3.ZERO
var _bias_count: int = 0

var _refract_timer: float = 0.0
var _same_dir_rearmed: bool = true
var _last_strike_dir: Vector2 = Vector2.RIGHT
var _reversal_travel: float = 0.0
var _backswing_dir: Vector2 = Vector2.ZERO
var _backswing_timer: float = 0.0
var _thrust_rearmed: bool = true


func reset_pose() -> void:
	raw_orientation = Quaternion.IDENTITY
	recenter_offset = Quaternion.IDENTITY
	orientation = Quaternion.IDENTITY
	_level_q = Quaternion.IDENTITY
	pitch_rad = 0.0
	yaw_rad = 0.0
	roll_rad = 0.0
	blade_roll_rad = 0.0
	snapped_blade_roll_rad = 0.0
	aim_dir = Vector2.ZERO
	aim_forward = Vector3.FORWARD
	_prev_accel = Vector3(0.0, -9.81, 0.0)
	_lp_accel = Vector3.ZERO
	tip_vel = Vector2.ZERO
	tip_speed = 0.0
	dynamic_accel_mag = 0.0
	forward_thrust_accel = 0.0
	motion_energy = 0.0
	active_peak_speed = 0.0
	_refract_timer = 0.0
	_same_dir_rearmed = true
	_reversal_travel = 0.0
	_backswing_timer = 0.0
	_thrust_rearmed = true


func recenter() -> void:
	if gravity.length() > 1.0:
		_level_q = _from_to_rotation(gravity.normalized(), Vector3.DOWN)
	else:
		_level_q = Quaternion.IDENTITY
	if accel.length() > 0.5:
		_prev_accel = accel
		_lp_accel = accel
	else:
		_lp_accel = Vector3.ZERO
	recenter_offset = raw_orientation.inverse()
	orientation = Quaternion.IDENTITY
	pitch_rad = 0.0
	yaw_rad = 0.0
	roll_rad = 0.0
	blade_roll_rad = 0.0
	snapped_blade_roll_rad = 0.0
	aim_dir = Vector2.ZERO
	aim_forward = Vector3.FORWARD
	has_centered_once = true
	active_peak_speed = 0.0
	swing_cooldown_timer = 0.0
	_refract_timer = 0.0
	_same_dir_rearmed = true
	_reversal_travel = 0.0
	_backswing_timer = 0.0
	_thrust_rearmed = true


func recenter_yaw() -> void:
	var e := orientation.get_euler()
	yaw_rad = 0.0
	orientation = Quaternion.from_euler(Vector3(e.x, 0.0, e.z)).normalized()
	recenter_offset = (orientation * raw_orientation.inverse()).normalized()


func start_bias_calibration(sample_frames: int = 25) -> void:
	_bias_samples_left = sample_frames
	_bias_accum = Vector3.ZERO
	_bias_count = 0


func update(delta: float, raw_gyro: Vector3, raw_accel: Vector3, raw_gravity: Vector3, peak_gyro: Vector3 = Vector3.ZERO) -> void:
	just_swung = false
	if delta <= 0.0 or delta > 0.15:
		delta = 0.016

	swing_cooldown_timer = maxf(0.0, swing_cooldown_timer - delta)
	_refract_timer = maxf(0.0, _refract_timer - delta)
	_backswing_timer = maxf(0.0, _backswing_timer - delta)

	accel = raw_accel
	var has_valid_grav := raw_gravity.length() > 1.5
	var raw_lin := (raw_gravity - raw_accel) if has_valid_grav else Vector3.ZERO
	if has_valid_grav:
		linear_accel = raw_lin
		if raw_lin.length() < 16.0:
			gravity = gravity.lerp(raw_gravity, 0.35) if gravity.length() > 1.5 else raw_gravity
	else:
		linear_accel = Vector3.ZERO

	if _bias_samples_left > 0:
		_bias_accum += raw_gyro
		_bias_count += 1
		_bias_samples_left -= 1
		if _bias_samples_left == 0 and _bias_count > 0:
			gyro_bias = _bias_accum / float(_bias_count)

	# Only learn gyro bias when clearly motionless so intentional slow aiming isn't swallowed
	if raw_gyro.length() < 0.09 and linear_accel.length() < 0.85:
		gyro_bias = gyro_bias.lerp(raw_gyro, 0.04)

	var corrected := raw_gyro - gyro_bias
	if corrected.length() < GYRO_DEADZONE:
		corrected = Vector3.ZERO
	gyro = corrected
	angular_speed = gyro.length()

	# True 3D quaternion integration in right-handed sword frame (+gyro.z = clockwise twist -> -Z axis rot)
	var omega_body := Vector3(gyro.x, gyro.y, -gyro.z)
	var angle := omega_body.length() * delta
	if angle > 0.0001:
		var axis := omega_body / omega_body.length()
		raw_orientation = (raw_orientation * Quaternion(axis, angle)).normalized()

	orientation = (recenter_offset * raw_orientation).normalized()

	# World-frame linear thrust & brisk-whip estimation (rotation-invariant: pure wrist twists NEVER fake acceleration!)
	var dyn_accel := linear_accel.length()
	var world_lin_est := orientation * linear_accel
	if raw_accel.length() > 0.5:
		var world_accel := orientation * raw_accel
		if _lp_accel.length() < 0.5:
			_lp_accel = world_accel
		var hp_world_vec := -(world_accel - _lp_accel)
		var hp_world := hp_world_vec.length()
		var mag_dev := absf(raw_accel.length() - 9.81)
		if world_lin_est.length() < hp_world * 0.75 and mag_dev >= 1.15:
			world_lin_est = hp_world_vec
		if dyn_accel < THRUST_ACCEL_THRESHOLD and mag_dev >= 1.15:
			dyn_accel = maxf(dyn_accel, maxf(hp_world, mag_dev * 1.45))
		var lp_alpha := 0.36 if (angular_speed < 0.45 and (world_accel - _prev_accel).length() < 0.8) else 0.14
		_lp_accel = _lp_accel.lerp(world_accel, lp_alpha)
		_prev_accel = world_accel
	dynamic_accel_mag = dyn_accel

	# 3D Earth-leveled complementary tilt correction: fixes pitch/horizon drift without EVER fighting yaw or tilted forearm roll
	if raw_accel.length() > 6.5 and raw_accel.length() < 13.0 and dyn_accel < 1.8 and angular_speed < 2.2:
		var q_earth := (_level_q * orientation).normalized()
		var g_meas_earth := (q_earth * raw_accel).normalized()
		var tilt_err_earth := g_meas_earth.cross(Vector3.DOWN)
		var err_sin := tilt_err_earth.length()
		if err_sin > 0.0005:
			var corr_ang := asin(clampf(err_sin, -0.7, 0.7)) * clampf(delta * 2.2, 0.0, 0.12)
			var dq_earth := Quaternion(tilt_err_earth / err_sin, corr_ang)
			var dq_sword := (_level_q.inverse() * dq_earth * _level_q).normalized()
			recenter_offset = (dq_sword * recenter_offset).normalized()
			orientation = (recenter_offset * raw_orientation).normalized()

	_sync_derived_angles_from_orientation()

	var eff_gyro := gyro
	if peak_gyro.length() > angular_speed:
		eff_gyro = peak_gyro - gyro_bias
	_compute_tip_and_detect(delta, eff_gyro, orientation * linear_accel if linear_accel.length() >= 0.4 else world_lin_est)


func apply_external_orientation(target_q: Quaternion, delta: float, raw_gyro: Vector3, raw_linear: Vector3) -> void:
	just_swung = false
	if delta <= 0.0 or delta > 0.15:
		delta = 0.016
	swing_cooldown_timer = maxf(0.0, swing_cooldown_timer - delta)
	_refract_timer = maxf(0.0, _refract_timer - delta)
	_backswing_timer = maxf(0.0, _backswing_timer - delta)
	raw_orientation = target_q.normalized()
	orientation = (recenter_offset * raw_orientation).normalized()
	_sync_derived_angles_from_orientation()
	gyro = raw_gyro
	linear_accel = raw_linear
	angular_speed = raw_gyro.length()
	dynamic_accel_mag = raw_linear.length()
	_compute_tip_and_detect(delta, gyro, orientation * linear_accel)


func _compute_tip_and_detect(delta: float, eff_gyro: Vector3, world_lin_est: Vector3) -> void:
	# Compute true 3D tip velocity from angular velocity cross blade tip vector!
	# Pure wrist roll along blade spine produces ZERO tip velocity (0 false swings while turning guard!).
	var w_world := orientation * Vector3(eff_gyro.x, eff_gyro.y, -eff_gyro.z)
	var tip_world := orientation * Vector3.FORWARD
	var v_tip := w_world.cross(tip_world)
	var tip_speed_3d := v_tip.length()

	# Project 3D tip sweep onto the duel plane, preserving chops/sweeps from UP, DOWN, LEFT, RIGHT holds
	var proj_vel := Vector2(v_tip.x + v_tip.z * tip_world.x, -v_tip.y - v_tip.z * tip_world.y)

	# Split world linear acceleration into forward blade stab vs orthogonal brisk arm whip
	var along_blade := maxf(0.0, world_lin_est.dot(tip_world))
	var fwd_push := maxf(0.0, -world_lin_est.z)
	var lin_perp := world_lin_est - tip_world * world_lin_est.dot(tip_world)

	var roll_rate := absf(eff_gyro.z)
	var is_pure_roll := (roll_rate > 1.8) and (tip_speed_3d < roll_rate * 0.42) and (lin_perp.length() < 7.5)
	var eff_tip_speed := tip_speed_3d * (0.55 if is_pure_roll else 1.0)
	if not is_pure_roll:
		var lin_cut_boost := maxf(0.0, lin_perp.length() - 5.2) * 0.34
		if lin_cut_boost > 0.05:
			eff_tip_speed += lin_cut_boost
			var lin_proj := Vector2(lin_perp.x + lin_perp.z * tip_world.x, -lin_perp.y - lin_perp.z * tip_world.y)
			if lin_proj.length() > 0.4:
				proj_vel += lin_proj.normalized() * (lin_cut_boost * 1.45)

	var sens := clampf(GameConfig.dual_sense_sensitivity, 0.65, 1.55)
	eff_tip_speed *= sens
	dynamic_accel_mag *= sens
	forward_thrust_accel = maxf(along_blade, fwd_push * 0.9) * sens
	if lin_perp.length() * sens > forward_thrust_accel * 1.35:
		forward_thrust_accel *= 0.45

	var dir2 := proj_vel.normalized() if proj_vel.length() > 0.02 else Vector2.ZERO
	tip_vel = dir2 * tip_speed_3d
	tip_speed = tip_speed_3d

	is_steady = eff_tip_speed < STEADY_THRESHOLD and dynamic_accel_mag < 3.5
	_detect_swing_v2(delta, eff_tip_speed, proj_vel)


func _sync_derived_angles_from_orientation() -> void:
	var right := orientation * Vector3.RIGHT
	var up := orientation * Vector3.UP
	var fwd := orientation * Vector3.FORWARD

	aim_forward = fwd
	aim_dir = Vector2(fwd.x, fwd.y)
	pitch_rad = clampf(asin(clampf(fwd.y, -0.99, 0.99)), -1.45, 1.45)
	yaw_rad = clampf(atan2(-fwd.x, maxf(-fwd.z, 0.15)), -1.45, 1.45)
	if absf(right.y) > 0.04 or absf(up.y) > 0.04:
		roll_rad = clampf(atan2(-right.y, up.y), -PI * 0.85, PI * 0.85)
	blade_roll_rad = clampf(roll_rad, -PI * 0.65, PI * 0.65)
	snapped_blade_roll_rad = blade_roll_rad


func get_aim_label() -> String:
	var fwd := aim_forward
	if fwd.z > 0.45 and absf(fwd.x) < 0.55 and absf(fwd.y) < 0.55:
		return "HACIA ATRAS"
	if fwd.y >= 0.42:
		if absf(fwd.x) >= 0.38:
			return "ARRIBA-DER" if fwd.x > 0.0 else "ARRIBA-IZQ"
		return "ARRIBA"
	if fwd.y <= -0.42:
		if absf(fwd.x) >= 0.38:
			return "ABAJO-DER" if fwd.x > 0.0 else "ABAJO-IZQ"
		return "ABAJO"
	if fwd.x >= 0.38:
		return "DERECHA"
	if fwd.x <= -0.38:
		return "IZQUIERDA"
	return "AL FRENTE"


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


func _detect_swing_v2(delta: float, eff_tip_speed: float, raw_tip_vec: Vector2) -> void:
	var thrust_energy := forward_thrust_accel * 0.58
	motion_energy = maxf(eff_tip_speed, thrust_energy)

	if eff_tip_speed > active_peak_speed:
		active_peak_speed = eff_tip_speed

	# Track quiet pullback/backswing so the real forward chop feels effortless and extra punchy
	if _refract_timer <= 0.0 and eff_tip_speed > 1.05 and eff_tip_speed < SWING_THRESHOLD and raw_tip_vec.length() > 0.1:
		_backswing_dir = raw_tip_vec.normalized()
		_backswing_timer = 0.35

	# Forward thrust trigger ("Empuje frontal / Estocada")
	if forward_thrust_accel < THRUST_ACCEL_THRESHOLD * 0.45:
		_thrust_rearmed = true
	if _refract_timer <= 0.0 and _thrust_rearmed and forward_thrust_accel >= THRUST_ACCEL_THRESHOLD and eff_tip_speed < 3.05:
		_thrust_rearmed = false
		_refract_timer = SWING_REFRACTORY
		swing_cooldown_timer = SWING_REFRACTORY
		_same_dir_rearmed = false
		_reversal_travel = 0.0
		var cut_ang := quantize_4_angles(blade_roll_rad) - PI * 0.5
		last_slash_dir = Vector2(cos(cut_ang), sin(cut_ang)).normalized()
		_last_strike_dir = last_slash_dir
		last_slash_power = clampf(0.55 + (forward_thrust_accel - THRUST_ACCEL_THRESHOLD) / 9.5, 0.55, 1.75)
		last_slash_type = SlashType.THRUST
		last_swing_source = "Empuje frontal"
		just_swung = true
		active_peak_speed = eff_tip_speed
		return

	if eff_tip_speed < 1.25:
		_same_dir_rearmed = true

	if _refract_timer > 0.0:
		return

	var strike_dir := raw_tip_vec.normalized() if raw_tip_vec.length() > 0.1 else Vector2.RIGHT
	var align := strike_dir.dot(_last_strike_dir)
	var is_reverse_combo := (not _same_dir_rearmed) and (align < -0.25)
	if is_reverse_combo:
		_reversal_travel += eff_tip_speed * delta

	var is_primed_forward := (_backswing_timer > 0.0 and strike_dir.dot(_backswing_dir) < -0.25)
	var threshold := COMBO_THRESHOLD if is_reverse_combo else (SWING_PRIMED_THRESHOLD if is_primed_forward else SWING_THRESHOLD)
	var allowed := _same_dir_rearmed or (is_reverse_combo and _reversal_travel >= 0.20)

	if allowed and eff_tip_speed >= threshold:
		_refract_timer = SWING_REFRACTORY
		swing_cooldown_timer = SWING_REFRACTORY
		_same_dir_rearmed = false
		_reversal_travel = 0.0
		_backswing_timer = 0.0

		last_slash_dir = strike_dir
		_last_strike_dir = strike_dir
		var bonus := 0.15 if is_primed_forward else 0.0
		last_slash_power = clampf(0.45 + (eff_tip_speed - threshold) / 9.5 + bonus, 0.45, 1.85)
		last_slash_type = SlashType.CUT
		last_swing_source = "Combo" if is_reverse_combo else "Tajo 1:1"
		active_peak_speed = eff_tip_speed
		just_swung = true


func compute_live_power_from_peak(peak_spd: float) -> float:
	return clampf(0.45 + maxf(peak_spd - 2.2, 0.0) / 9.5, 0.45, 1.85)


func get_blade_roll_rad() -> float:
	return blade_roll_rad


func get_snapped_blade_roll_rad() -> float:
	return snapped_blade_roll_rad


func get_blade_angle_deg() -> float:
	return rad_to_deg(blade_roll_rad)


func _from_to_rotation(from_dir: Vector3, to_dir: Vector3) -> Quaternion:
	var f := from_dir.normalized()
	var t := to_dir.normalized()
	var d := f.dot(t)
	if d > 0.9999:
		return Quaternion.IDENTITY
	if d < -0.9999:
		var ortho := f.cross(Vector3.RIGHT)
		if ortho.length_squared() < 0.001:
			ortho = f.cross(Vector3.FORWARD)
		return Quaternion(ortho.normalized(), PI)
	return Quaternion(f, t).normalized()
