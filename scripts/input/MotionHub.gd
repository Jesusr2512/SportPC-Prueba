extends Node

signal slots_changed

enum SourceType { NONE, GAMEPAD, MOBILE, MOUSE }

class PlayerSlot:
	var index: int = 0
	var source_type: SourceType = SourceType.NONE
	var device_id: int = -1
	var device_name: String = "Sin asignar"
	var has_motion_sensors: bool = false
	var fusion: MotionFusion = MotionFusion.new()

	var is_guarding: bool = false
	var just_guard_pressed: bool = false
	var just_strike_pressed: bool = false
	var just_recenter_pressed: bool = false
	var move_axis: Vector2 = Vector2.ZERO

	var _prev_guard: bool = false
	var _prev_strike: bool = false
	var _prev_recenter: bool = false

	func begin_frame(guard_now: bool, strike_now: bool, recenter_now: bool) -> void:
		is_guarding = guard_now
		just_guard_pressed = guard_now and not _prev_guard
		just_strike_pressed = strike_now and not _prev_strike
		just_recenter_pressed = recenter_now and not _prev_recenter
		_prev_guard = guard_now
		_prev_strike = strike_now
		_prev_recenter = recenter_now
		if just_recenter_pressed:
			fusion.recenter()

var slots: Array[PlayerSlot] = []
var mobile_server: MobileBridgeServer

var _mobile_packets: Dictionary = {}
var _mouse_accum: Vector2 = Vector2.ZERO
var _mouse_pitch: float = 0.0
var _mouse_yaw: float = 0.0
var _mouse_roll: float = 0.0


func _ready() -> void:
	for i in 2:
		var s := PlayerSlot.new()
		s.index = i
		slots.append(s)

	mobile_server = MobileBridgeServer.new()
	mobile_server.name = "MobileBridgeServer"
	add_child(mobile_server)
	mobile_server.telemetry_received.connect(_on_mobile_telemetry)
	mobile_server.peer_disconnected.connect(_on_mobile_disconnected)

	Input.joy_connection_changed.connect(_on_joy_connection_changed)
	_scan_initial_gamepads()


func _scan_initial_gamepads() -> void:
	for joy_id in Input.get_connected_joypads():
		_register_gamepad(joy_id)
	if slots[0].source_type == SourceType.NONE:
		assign_mouse(0)
	slots_changed.emit()


func _on_joy_connection_changed(device: int, connected: bool) -> void:
	if connected:
		_register_gamepad(device)
	else:
		for s in slots:
			if s.source_type == SourceType.GAMEPAD and s.device_id == device:
				s.source_type = SourceType.NONE
				s.device_id = -1
				s.device_name = "Sin asignar"
				s.has_motion_sensors = false
				s.fusion.reset_pose()
		if slots[0].source_type == SourceType.NONE:
			assign_mouse(0)
	slots_changed.emit()


func _register_gamepad(device: int) -> void:
	var has_sensors := Input.has_joy_motion_sensors(device)
	if has_sensors:
		Input.set_joy_motion_sensors_enabled(device, true)

	for s in slots:
		if s.source_type == SourceType.GAMEPAD and s.device_id == device:
			return

	var target_slot := -1
	if slots[0].source_type == SourceType.NONE or (slots[0].source_type == SourceType.MOUSE and has_sensors):
		target_slot = 0
	elif slots[1].source_type == SourceType.NONE:
		target_slot = 1

	if target_slot != -1:
		assign_gamepad(target_slot, device)


func assign_gamepad(slot_idx: int, device: int) -> void:
	if slot_idx < 0 or slot_idx >= slots.size():
		return
	var s := slots[slot_idx]
	s.source_type = SourceType.GAMEPAD
	s.device_id = device
	s.device_name = Input.get_joy_name(device)
	s.has_motion_sensors = Input.has_joy_motion_sensors(device)
	if s.has_motion_sensors:
		Input.set_joy_motion_sensors_enabled(device, true)
	s.fusion.reset_pose()
	s.fusion.start_bias_calibration(20)
	slots_changed.emit()


func assign_mouse(slot_idx: int) -> void:
	if slot_idx < 0 or slot_idx >= slots.size():
		return
	var s := slots[slot_idx]
	s.source_type = SourceType.MOUSE
	s.device_id = -1
	s.device_name = "Ratón + Teclado (Respaldo)"
	s.has_motion_sensors = false
	s.fusion.reset_pose()
	slots_changed.emit()


func get_available_gamepads() -> Array[Dictionary]:
	var list: Array[Dictionary] = []
	for joy_id in Input.get_connected_joypads():
		list.append({
			"id": joy_id,
			"name": Input.get_joy_name(joy_id),
			"motion": Input.has_joy_motion_sensors(joy_id)
		})
	return list


func _on_mobile_telemetry(peer_id: int, data: Dictionary) -> void:
	var target_slot := clampi(int(data.get("s", 0)), 0, 1)
	var s := slots[target_slot]
	if s.source_type != SourceType.MOBILE or s.device_id != peer_id:
		# Release any other slot holding this peer_id
		for other in slots:
			if other.source_type == SourceType.MOBILE and other.device_id == peer_id:
				other.source_type = SourceType.NONE
				other.device_id = -1
				other.device_name = "Sin asignar"
		s.source_type = SourceType.MOBILE
		s.device_id = peer_id
		s.device_name = "Móvil Wi-Fi #%d" % peer_id
		s.has_motion_sensors = true
		s.fusion.reset_pose()
		slots_changed.emit()

	_mobile_packets[peer_id] = data


func _on_mobile_disconnected(peer_id: int) -> void:
	_mobile_packets.erase(peer_id)
	for s in slots:
		if s.source_type == SourceType.MOBILE and s.device_id == peer_id:
			s.source_type = SourceType.NONE
			s.device_id = -1
			s.device_name = "Sin asignar"
			s.has_motion_sensors = false
	if slots[0].source_type == SourceType.NONE:
		assign_mouse(0)
	slots_changed.emit()


func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_mouse_accum += event.relative


func _process(delta: float) -> void:
	for s in slots:
		match s.source_type:
			SourceType.GAMEPAD:
				_update_gamepad_slot(s, delta)
			SourceType.MOBILE:
				_update_mobile_slot(s, delta)
			SourceType.MOUSE:
				_update_mouse_slot(s, delta)
			SourceType.NONE:
				s.begin_frame(false, false, false)
	_mouse_accum = Vector2.ZERO


func _update_gamepad_slot(s: PlayerSlot, delta: float) -> void:
	var id := s.device_id
	if not Input.get_connected_joypads().has(id):
		s.begin_frame(false, false, false)
		return

	var guard := (
		Input.is_joy_button_pressed(id, JOY_BUTTON_LEFT_SHOULDER)
		or Input.is_joy_button_pressed(id, JOY_BUTTON_RIGHT_SHOULDER)
		or Input.is_joy_button_pressed(id, JOY_BUTTON_B)
		or Input.is_joy_button_pressed(id, JOY_BUTTON_X)
		or Input.get_joy_axis(id, JOY_AXIS_TRIGGER_LEFT) > 0.35
		or Input.get_joy_axis(id, JOY_AXIS_TRIGGER_RIGHT) > 0.35
	)
	var strike := Input.is_joy_button_pressed(id, JOY_BUTTON_A)
	var recenter := (
		Input.is_joy_button_pressed(id, JOY_BUTTON_START)
		or Input.is_joy_button_pressed(id, JOY_BUTTON_BACK)
		or Input.is_joy_button_pressed(id, JOY_BUTTON_Y)
		or Input.is_joy_button_pressed(id, JOY_BUTTON_MISC1)
		or Input.is_joy_button_pressed(id, JOY_BUTTON_LEFT_STICK)
		or Input.is_joy_button_pressed(id, JOY_BUTTON_RIGHT_STICK)
	)

	s.move_axis = Vector2(
		Input.get_joy_axis(id, JOY_AXIS_LEFT_X),
		Input.get_joy_axis(id, JOY_AXIS_LEFT_Y)
	)
	if s.move_axis.length() < 0.15:
		s.move_axis = Vector2.ZERO

	if s.has_motion_sensors:
		var gyro := Input.get_joy_gyroscope(id)
		var accel := Input.get_joy_accelerometer(id)
		var gravity := Input.get_joy_gravity(id)
		# Map Godot joypad local axes (X=pitch, Y=yaw, Z=roll) into Godot 3D blade space
		var mapped_gyro := Vector3(gyro.x, gyro.y, -gyro.z)
		var mapped_accel := Vector3(-accel.x, -accel.y, accel.z)
		var mapped_gravity := Vector3(-gravity.x, -gravity.y, gravity.z)
		s.fusion.update(delta, mapped_gyro, mapped_accel, mapped_gravity)

	s.begin_frame(guard, strike, recenter)
	if s.just_strike_pressed:
		s.fusion.just_swung = true
		s.fusion.last_slash_power = 1.0
		s.fusion.last_swing_source = "Botón Mando"
		var cut_ang := s.fusion.quantize_4_angles(s.fusion.get_snapped_blade_roll_rad()) - PI * 0.5
		s.fusion.last_slash_dir = Vector2(cos(cut_ang), sin(cut_ang)).normalized()


func _update_mobile_slot(s: PlayerSlot, delta: float) -> void:
	var pkt: Dictionary = _mobile_packets.get(s.device_id, {})
	if pkt.is_empty():
		s.begin_frame(false, false, false)
		return

	var btns := int(pkt.get("b", 0))
	var guard := (btns & 1) != 0
	var strike := (btns & 2) != 0
	var recenter := (btns & 4) != 0

	var g_arr: Array = pkt.get("g", [0.0, 0.0, 0.0])
	var a_arr: Array = pkt.get("a", [0.0, 0.0, 9.81])
	var l_arr: Array = pkt.get("l", [0.0, 0.0, 0.0])

	var g_beta := float(g_arr[0])
	var g_alpha := float(g_arr[1])
	var g_gamma := float(g_arr[2])

	# Convert browser accelerationIncludingGravity (+X right, +Y top/fwd, +Z screen normal) to Godot (-Y down)
	var raw_accel := Vector3(-float(a_arr[0]), -float(a_arr[2]), float(a_arr[1]))
	var raw_linear := Vector3(-float(l_arr[0]), -float(l_arr[2]), float(l_arr[1]))
	var gravity_est := raw_accel - raw_linear

	# Smoothly adapt yaw/roll axes between flat grip (0 deg) and upright sword grip (45-85 deg)
	var up_yz := Vector2(float(a_arr[1]) - float(l_arr[1]), float(a_arr[2]) - float(l_arr[2]))
	var u_y := 0.0
	var u_z := 1.0
	if up_yz.length() > 1.5:
		var nu := up_yz.normalized()
		u_y = nu.x
		u_z = nu.y

	var gyro_yaw := g_alpha * u_z + g_gamma * u_y
	var gyro_roll := g_gamma * u_z - g_alpha * u_y
	var raw_gyro := Vector3(g_beta, gyro_yaw, gyro_roll)

	s.fusion.update(delta, raw_gyro, raw_accel, gravity_est)

	s.begin_frame(guard, strike, recenter)
	if s.just_strike_pressed:
		s.fusion.just_swung = true
		s.fusion.last_slash_power = 1.0
		s.fusion.last_swing_source = "Botón"
		var cut_ang := s.fusion.quantize_4_angles(s.fusion.get_snapped_blade_roll_rad()) - PI * 0.5
		s.fusion.last_slash_dir = Vector2(cos(cut_ang), sin(cut_ang)).normalized()


func _update_mouse_slot(s: PlayerSlot, delta: float) -> void:
	var safe_dt := maxf(delta, 0.004)
	var guard := Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT) or Input.is_key_pressed(KEY_SPACE)
	var strike := Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	var recenter := Input.is_key_pressed(KEY_R) or Input.is_mouse_button_pressed(MOUSE_BUTTON_MIDDLE)

	if recenter:
		_mouse_pitch = 0.0
		_mouse_yaw = 0.0
		_mouse_roll = 0.0

	var sensitivity := 0.0045
	if Input.is_key_pressed(KEY_Q):
		_mouse_roll += 2.6 * safe_dt
	if Input.is_key_pressed(KEY_E):
		_mouse_roll -= 2.6 * safe_dt

	_mouse_yaw = clampf(_mouse_yaw - _mouse_accum.x * sensitivity, -1.25, 1.25)
	_mouse_pitch = clampf(_mouse_pitch - _mouse_accum.y * sensitivity, -1.1, 1.1)
	if not Input.is_key_pressed(KEY_Q) and not Input.is_key_pressed(KEY_E):
		_mouse_roll = clampf(_mouse_roll - _mouse_accum.x * sensitivity * 0.85, -1.45, 1.45)

	var vel_x := -_mouse_accum.y / safe_dt * 0.015
	var vel_y := -_mouse_accum.x / safe_dt * 0.015
	var fake_gyro := Vector3(vel_x, vel_y, 0.0)

	var q := Quaternion.from_euler(Vector3(_mouse_pitch, _mouse_yaw, _mouse_roll))
	s.fusion.apply_external_orientation(q, safe_dt, fake_gyro, Vector3.ZERO)

	# Keyboard left/right/forward step for mouse player
	var mx := 0.0
	var my := 0.0
	if Input.is_key_pressed(KEY_D):
		mx += 1.0
	if Input.is_key_pressed(KEY_A):
		mx -= 1.0
	if Input.is_key_pressed(KEY_S):
		my += 1.0
	if Input.is_key_pressed(KEY_W):
		my -= 1.0
	s.move_axis = Vector2(mx, my).limit_length(1.0)

	s.begin_frame(guard, strike, recenter)
	if s.just_strike_pressed:
		s.fusion.just_swung = true
		s.fusion.last_slash_power = 0.95
		s.fusion.last_swing_source = "Clic Ratón"
		var cut_ang := s.fusion.quantize_4_angles(s.fusion.get_snapped_blade_roll_rad()) - PI * 0.5
		s.fusion.last_slash_dir = Vector2(cos(cut_ang), sin(cut_ang)).normalized()


func trigger_rumble(slot_idx: int, strength: float = 0.65, duration: float = 0.12) -> void:
	if slot_idx < 0 or slot_idx >= slots.size():
		return
	var s := slots[slot_idx]
	if s.source_type == SourceType.GAMEPAD and s.device_id >= 0:
		Input.start_joy_vibration(s.device_id, strength * 0.7, strength, duration)
	elif s.source_type == SourceType.MOBILE and s.device_id >= 0:
		mobile_server.send_rumble(s.device_id, int(duration * 1000.0))


func recenter_slot(slot_idx: int) -> void:
	if slot_idx < 0 or slot_idx >= slots.size():
		return
	var s := slots[slot_idx]
	if s.source_type == SourceType.MOUSE:
		_mouse_pitch = 0.0
		_mouse_yaw = 0.0
		_mouse_roll = 0.0
	s.fusion.recenter()


func recenter_yaw_slot(slot_idx: int) -> void:
	if slot_idx < 0 or slot_idx >= slots.size():
		return
	var s := slots[slot_idx]
	if s.source_type == SourceType.MOUSE:
		_mouse_yaw = 0.0
	s.fusion.recenter_yaw()


func calibrate_bias_slot(slot_idx: int) -> void:
	if slot_idx < 0 or slot_idx >= slots.size():
		return
	slots[slot_idx].fusion.start_bias_calibration(35)
