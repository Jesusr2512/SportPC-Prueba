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
	var just_dodge_pressed: bool = false
	var just_thrust_pressed: bool = false
	var move_axis: Vector2 = Vector2.ZERO

	# Buffered strike & fighter combat feedback mirrored back to mobile phone
	var buffered_strike_timer: float = 0.0
	var buffered_strike_dir: Vector2 = Vector2.RIGHT
	var buffered_strike_power: float = 1.0
	var buffered_strike_type: int = MotionFusion.SlashType.CUT
	var hud_guard_meter: float = 100.0
	var hud_spirit: float = 0.0

	var _prev_guard: bool = false
	var _prev_strike: bool = false
	var _prev_recenter: bool = false
	var _prev_dodge: bool = false
	var _prev_thrust: bool = false
	var _joy_flick_latch: bool = false
	var _skip_next_begin_recenter: bool = false

	func clear_edge_states() -> void:
		_prev_guard = false
		_prev_strike = false
		_prev_recenter = false
		_prev_dodge = false
		_prev_thrust = false
		just_guard_pressed = false
		just_strike_pressed = false
		just_recenter_pressed = false
		just_dodge_pressed = false
		just_thrust_pressed = false
		buffered_strike_timer = 0.0

	func begin_frame(guard_now: bool, strike_now: bool, recenter_now: bool, dodge_now: bool = false, thrust_now: bool = false) -> void:
		is_guarding = guard_now
		just_guard_pressed = guard_now and not _prev_guard
		just_strike_pressed = strike_now and not _prev_strike
		just_recenter_pressed = recenter_now and not _prev_recenter
		just_dodge_pressed = dodge_now and not _prev_dodge
		just_thrust_pressed = thrust_now and not _prev_thrust
		_prev_guard = guard_now
		_prev_strike = strike_now
		_prev_recenter = recenter_now
		_prev_dodge = dodge_now
		_prev_thrust = thrust_now
		if just_recenter_pressed and not _skip_next_begin_recenter:
			fusion.recenter()
		_skip_next_begin_recenter = false


var slots: Array[PlayerSlot] = []
var mobile_server: MobileBridgeServer
var mouse_combat_enabled: bool = true

var _mobile_queues: Dictionary = {}
var _mobile_latest_state: Dictionary = {}
var _mobile_last_seq: Dictionary = {}
var _mobile_last_rx_msec: Dictionary = {}
var _mobile_client_ids: Dictionary = {}
var _mobile_has_sensors: Dictionary = {}
var _cid_preferred_slot: Dictionary = {}
var _manually_unassigned_peers: Dictionary = {}
var _mouse_accum: Vector2 = Vector2.ZERO
var _mouse_pitch: float = 0.0
var _mouse_yaw: float = 0.0
var _mouse_roll: float = 0.0
var _last_ticks_usec: int = 0
var _feedback_accum_time: float = 0.0


func _ready() -> void:
	_last_ticks_usec = Time.get_ticks_usec()
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
				s.clear_edge_states()
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


func _clear_slot_fields(s: PlayerSlot) -> void:
	s.source_type = SourceType.NONE
	s.device_id = -1
	s.device_name = "Sin asignar"
	s.has_motion_sensors = false
	s.clear_edge_states()
	s.fusion.reset_pose()


func _set_mouse_fields(s: PlayerSlot) -> void:
	s.source_type = SourceType.MOUSE
	s.device_id = -1
	s.device_name = "Ratón + Teclado (Respaldo)"
	s.has_motion_sensors = false
	s.clear_edge_states()
	s.fusion.reset_pose()


func _notify_mobile_slot(peer_id: int, slot_idx: int) -> void:
	if peer_id >= 0 and mobile_server:
		mobile_server.send_feedback(peer_id, {"as": slot_idx})


func _evict_slot_mobile_if_needed(s: PlayerSlot, except_peer_id: int = -1, mark_manual: bool = true) -> void:
	if s.source_type == SourceType.MOBILE and s.device_id >= 0 and s.device_id != except_peer_id:
		var old_id := s.device_id
		if mark_manual:
			_manually_unassigned_peers[old_id] = true
			var cid := str(_mobile_client_ids.get(old_id, ""))
			if not cid.is_empty():
				_cid_preferred_slot.erase(cid)
		_notify_mobile_slot(old_id, -1)


func assign_gamepad(slot_idx: int, device: int) -> void:
	if slot_idx < 0 or slot_idx >= slots.size():
		return
	var target := slots[slot_idx]
	_evict_slot_mobile_if_needed(target)
	for other in slots:
		if other.index != slot_idx and other.source_type == SourceType.GAMEPAD and other.device_id == device:
			_clear_slot_fields(other)
	target.source_type = SourceType.GAMEPAD
	target.device_id = device
	target.device_name = Input.get_joy_name(device)
	target.has_motion_sensors = Input.has_joy_motion_sensors(device)
	if target.has_motion_sensors:
		Input.set_joy_motion_sensors_enabled(device, true)
	target.clear_edge_states()
	target.fusion.reset_pose()
	target.fusion.start_bias_calibration(20)
	if slots[0].source_type == SourceType.NONE:
		_set_mouse_fields(slots[0])
	slots_changed.emit()


func assign_mouse(slot_idx: int) -> void:
	if slot_idx < 0 or slot_idx >= slots.size():
		return
	var target := slots[slot_idx]
	_evict_slot_mobile_if_needed(target)
	for other in slots:
		if other.index != slot_idx and other.source_type == SourceType.MOUSE:
			_clear_slot_fields(other)
	_set_mouse_fields(target)
	slots_changed.emit()


func assign_mobile(slot_idx: int, peer_id: int) -> void:
	if slot_idx < 0 or slot_idx >= slots.size():
		return
	_manually_unassigned_peers.erase(peer_id)
	var target := slots[slot_idx]
	var already_same := (target.source_type == SourceType.MOBILE and target.device_id == peer_id)
	_evict_slot_mobile_if_needed(target, peer_id)
	for other in slots:
		if other.index != slot_idx and other.source_type == SourceType.MOBILE and other.device_id == peer_id:
			_clear_slot_fields(other)
			if other.index == 0:
				_set_mouse_fields(slots[0])
	target.source_type = SourceType.MOBILE
	target.device_id = peer_id
	target.device_name = "Móvil Wi-Fi #%d" % peer_id
	target.has_motion_sensors = bool(_mobile_has_sensors.get(peer_id, true))
	if not already_same:
		target.clear_edge_states()
		target.fusion.reset_pose()
		target.fusion.start_bias_calibration(20)
	var cid := str(_mobile_client_ids.get(peer_id, ""))
	if not cid.is_empty():
		_cid_preferred_slot[cid] = slot_idx
	_notify_mobile_slot(peer_id, slot_idx)
	slots_changed.emit()


func unassign_slot(slot_idx: int) -> void:
	if slot_idx < 0 or slot_idx >= slots.size():
		return
	var target := slots[slot_idx]
	_evict_slot_mobile_if_needed(target)
	_clear_slot_fields(target)
	slots_changed.emit()


func calibrate_bias_slot(slot_idx: int) -> void:
	if slot_idx < 0 or slot_idx >= slots.size():
		return
	slots[slot_idx].fusion.start_bias_calibration(20)


func get_available_gamepads() -> Array[Dictionary]:
	var list: Array[Dictionary] = []
	for joy_id in Input.get_connected_joypads():
		list.append({
			"id": joy_id,
			"name": Input.get_joy_name(joy_id),
			"motion": Input.has_joy_motion_sensors(joy_id)
		})
	return list


func get_connected_mobile_peers() -> Array[int]:
	var seen: Dictionary = {}
	for k in _mobile_latest_state.keys():
		seen[int(k)] = true
	for k in _mobile_last_rx_msec.keys():
		seen[int(k)] = true
	for s in slots:
		if s.source_type == SourceType.MOBILE and s.device_id >= 0:
			seen[s.device_id] = true
	var peers: Array[int] = []
	for k in seen.keys():
		peers.append(int(k))
	peers.sort()
	return peers


func get_mobile_peer_info(peer_id: int) -> Dictionary:
	return {
		"peer_id": peer_id,
		"sensors": bool(_mobile_has_sensors.get(peer_id, true)),
		"slot": _find_slot_by_mobile_peer(peer_id),
		"idle": _is_mobile_peer_idle(peer_id, 1800)
	}


func _is_mobile_peer_idle(peer_id: int, max_idle_ms: int = 1800) -> bool:
	if peer_id < 0 or not _mobile_last_rx_msec.has(peer_id):
		return true
	return (Time.get_ticks_msec() - int(_mobile_last_rx_msec[peer_id])) > max_idle_ms


func _on_mobile_telemetry(peer_id: int, data: Dictionary) -> void:
	var act := str(data.get("act", ""))
	var cid := str(data.get("cid", "")).strip_edges()
	var is_first_rx := not _mobile_last_rx_msec.has(peer_id)
	_mobile_last_rx_msec[peer_id] = Time.get_ticks_msec()
	if not cid.is_empty():
		_mobile_client_ids[peer_id] = cid
	if data.has("sens"):
		var sens_flag := int(data.get("sens", 1)) != 0
		_mobile_has_sensors[peer_id] = sens_flag
		var cur_slot := _find_slot_by_mobile_peer(peer_id)
		if cur_slot != -1 and slots[cur_slot].has_motion_sensors != sens_flag:
			slots[cur_slot].has_motion_sensors = sens_flag
			slots_changed.emit()

	var requested_slot := clampi(int(data.get("s", 0)), 0, 1)
	var owner_slot := _find_slot_by_mobile_peer(peer_id)

	if act == "claim":
		_manually_unassigned_peers.erase(peer_id)
		if owner_slot != requested_slot:
			var target := slots[requested_slot]
			var occupied_by_fresh_mobile := (
				target.source_type == SourceType.MOBILE
				and target.device_id != peer_id
				and not _is_mobile_peer_idle(target.device_id, 1800)
			)
			if not occupied_by_fresh_mobile:
				assign_mobile(requested_slot, peer_id)
			else:
				_notify_mobile_slot(peer_id, owner_slot)
	elif act == "hello" or (owner_slot == -1 and is_first_rx and not _manually_unassigned_peers.has(peer_id)):
		if owner_slot == -1:
			var desired := requested_slot
			if not cid.is_empty() and _cid_preferred_slot.has(cid):
				desired = clampi(int(_cid_preferred_slot[cid]), 0, 1)
			var target := slots[desired]
			var alt := slots[1 - desired]
			var can_take_desired := (
				target.source_type == SourceType.NONE
				or target.source_type == SourceType.MOUSE
				or (target.source_type == SourceType.MOBILE and _is_mobile_peer_idle(target.device_id, 1800))
			)
			var can_take_alt := (
				alt.source_type == SourceType.NONE
				or alt.source_type == SourceType.MOUSE
				or (alt.source_type == SourceType.MOBILE and _is_mobile_peer_idle(alt.device_id, 1800))
			)
			if can_take_desired:
				assign_mobile(desired, peer_id)
			elif can_take_alt:
				assign_mobile(1 - desired, peer_id)
			else:
				_notify_mobile_slot(peer_id, -1)
		else:
			_notify_mobile_slot(peer_id, owner_slot)

	owner_slot = _find_slot_by_mobile_peer(peer_id)
	if owner_slot != -1 and act == "recenter":
		recenter_slot(owner_slot)

	_mobile_latest_state[peer_id] = data
	var has_motion_payload := data.has("g") or data.has("a") or data.has("b")
	if not has_motion_payload:
		return

	var seq := int(data.get("q", -1))
	var prev_seq := int(_mobile_last_seq.get(peer_id, -1))
	if seq >= 0 and seq == prev_seq:
		return
	if seq >= 0:
		_mobile_last_seq[peer_id] = seq

	var queue: Array = _mobile_queues.get(peer_id, [])
	queue.append(data)
	if queue.size() > 14:
		queue.remove_at(0)
	_mobile_queues[peer_id] = queue


func _find_slot_by_mobile_peer(peer_id: int) -> int:
	for s in slots:
		if s.source_type == SourceType.MOBILE and s.device_id == peer_id:
			return s.index
	return -1


func _on_mobile_disconnected(peer_id: int) -> void:
	_mobile_queues.erase(peer_id)
	_mobile_latest_state.erase(peer_id)
	_mobile_last_seq.erase(peer_id)
	_mobile_last_rx_msec.erase(peer_id)
	_mobile_client_ids.erase(peer_id)
	_mobile_has_sensors.erase(peer_id)
	_manually_unassigned_peers.erase(peer_id)
	for s in slots:
		if s.source_type == SourceType.MOBILE and s.device_id == peer_id:
			_clear_slot_fields(s)
	if slots[0].source_type == SourceType.NONE:
		assign_mouse(0)
	slots_changed.emit()


func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_mouse_accum += event.relative


func _process(_delta: float) -> void:
	# Unscaled real elapsed time so IMU integration & swing capture remain 1:1 even during Slow-Mo!
	var now_usec := Time.get_ticks_usec()
	var real_dt := clampf(float(now_usec - _last_ticks_usec) / 1000000.0, 0.002, 0.05)
	_last_ticks_usec = now_usec

	for s in slots:
		s.buffered_strike_timer = maxf(0.0, s.buffered_strike_timer - real_dt)
		match s.source_type:
			SourceType.GAMEPAD:
				_update_gamepad_slot(s, real_dt)
			SourceType.MOBILE:
				_update_mobile_slot(s, real_dt)
			SourceType.MOUSE:
				_update_mouse_slot(s, real_dt)
			SourceType.NONE:
				s.begin_frame(false, false, false, false, false)

		# Buffer genuine strikes briefly (150ms) so fast hits during hitstop or swing end are never lost
		if s.fusion.just_swung:
			s.buffered_strike_timer = 0.15
			s.buffered_strike_dir = s.fusion.last_slash_dir
			s.buffered_strike_power = s.fusion.last_slash_power
			s.buffered_strike_type = s.fusion.last_slash_type

	_mouse_accum = Vector2.ZERO

	_feedback_accum_time += real_dt
	if _feedback_accum_time >= 0.05:
		_feedback_accum_time = 0.0
		_push_mobile_hud_feedback()


func _push_mobile_hud_feedback() -> void:
	for s in slots:
		if s.source_type == SourceType.MOBILE and s.device_id >= 0 and mobile_server:
			mobile_server.send_feedback(s.device_id, {
				"as": s.index,
				"roll": snappedf(s.fusion.get_blade_angle_deg(), 0.5),
				"aim": [snappedf(s.fusion.aim_dir.x, 0.01), snappedf(s.fusion.aim_dir.y, 0.01)],
				"pose": s.fusion.get_aim_label(),
				"spd": snappedf(s.fusion.tip_speed, 0.1),
				"hit": 1 if s.buffered_strike_timer > 0.0 else 0,
				"guard": int(roundf(s.hud_guard_meter)),
				"spirit": int(roundf(s.hud_spirit))
			})


func _update_gamepad_slot(s: PlayerSlot, delta: float) -> void:
	var id := s.device_id
	if not Input.get_connected_joypads().has(id):
		s.begin_frame(false, false, false, false, false)
		return

	var guard := (
		Input.is_joy_button_pressed(id, JOY_BUTTON_LEFT_SHOULDER)
		or Input.is_joy_button_pressed(id, JOY_BUTTON_RIGHT_SHOULDER)
		or Input.is_joy_button_pressed(id, JOY_BUTTON_B)
		or Input.get_joy_axis(id, JOY_AXIS_TRIGGER_LEFT) > 0.35
		or Input.get_joy_axis(id, JOY_AXIS_TRIGGER_RIGHT) > 0.35
	)
	var strike := Input.is_joy_button_pressed(id, JOY_BUTTON_A)
	var stick_x := Input.get_joy_axis(id, JOY_AXIS_LEFT_X)
	if absf(stick_x) < 0.30:
		s._joy_flick_latch = false
	var stick_flick_dodge := false
	if not s._joy_flick_latch and absf(stick_x) >= 0.65:
		stick_flick_dodge = true
		s._joy_flick_latch = true
	var dodge := Input.is_joy_button_pressed(id, JOY_BUTTON_X) or stick_flick_dodge
	var thrust := Input.is_joy_button_pressed(id, JOY_BUTTON_Y)
	var recenter := (
		Input.is_joy_button_pressed(id, JOY_BUTTON_START)
		or Input.is_joy_button_pressed(id, JOY_BUTTON_BACK)
		or Input.is_joy_button_pressed(id, JOY_BUTTON_MISC1)
	)

	# Switch Sports duel: lateral dodge direction only (zero free walking / stick drift!)
	s.move_axis = Vector2(signf(stick_x) if absf(stick_x) >= 0.45 else 0.0, 0.0)

	if s.has_motion_sensors:
		var raw_g := Input.get_joy_gyroscope(id)
		var raw_a := Input.get_joy_accelerometer(id)
		var raw_grav := Input.get_joy_gravity(id)
		# Align Godot joypad axes uniformly to Sword frame (+X right, +Y up, -Z forward)
		var mapped_gyro := Vector3(raw_g.x, raw_g.y, -raw_g.z)
		var mapped_accel := Vector3(-raw_a.x, -raw_a.y, raw_a.z)
		var mapped_gravity := raw_grav
		if raw_grav.length() > 1.0:
			# Ensure gravity points roughly same direction as -reaction accel at rest
			var alt_pos := Vector3(raw_grav.x, raw_grav.y, -raw_grav.z)
			var alt_neg := Vector3(-raw_grav.x, -raw_grav.y, raw_grav.z)
			mapped_gravity = alt_pos if alt_pos.dot(mapped_accel) >= alt_neg.dot(mapped_accel) else alt_neg
		s.fusion.update(delta, mapped_gyro, mapped_accel, mapped_gravity)
	else:
		# Non-gyro controllers (Xbox etc.) adjust blade angle smoothly using Right Stick
		var rx := Input.get_joy_axis(id, JOY_AXIS_RIGHT_X)
		var ry := Input.get_joy_axis(id, JOY_AXIS_RIGHT_Y)
		var rs := Vector2(rx, ry)
		if rs.length() > 0.25:
			var target_roll := clampf(atan2(rs.x, -rs.y), -PI * 0.5, PI * 0.5)
			var roll_delta := (target_roll - s.fusion.blade_roll_rad)
			var fake_gyro := Vector3(0.0, 0.0, roll_delta / maxf(delta, 0.01) * 0.25)
			var q := Quaternion.from_euler(Vector3(0.0, 0.0, -target_roll))
			s.fusion.apply_external_orientation(q, delta, fake_gyro, Vector3.ZERO)
		else:
			s.fusion.apply_external_orientation(s.fusion.orientation, delta, Vector3.ZERO, Vector3.ZERO)

	s.begin_frame(guard, strike, recenter, dodge, thrust)
	_apply_manual_attack_buttons(s, thrust)


func _update_mobile_slot(s: PlayerSlot, delta: float) -> void:
	var queue: Array = _mobile_queues.get(s.device_id, [])
	if queue.is_empty():
		var cached: Dictionary = _mobile_latest_state.get(s.device_id, {})
		if cached.is_empty():
			s.move_axis = Vector2.ZERO
			s.begin_frame(false, false, false, false, false)
			return
		var btns_c := int(cached.get("b", 0))
		var dodge_c := ((btns_c & 8) != 0) or ((btns_c & 32) != 0)
		var d_c := float(cached.get("d", 1.0 if (btns_c & 32) != 0 else (-1.0 if (btns_c & 8) != 0 else 0.0)))
		s.move_axis = Vector2(clampf(d_c, -1.0, 1.0), 0.0) if dodge_c else Vector2.ZERO
		s.fusion.just_swung = false
		s.begin_frame((btns_c & 1) != 0, (btns_c & 2) != 0, (btns_c & 4) != 0, dodge_c, (btns_c & 16) != 0)
		return

	var any_swung := false
	var swung_dir := s.fusion.last_slash_dir
	var swung_power := 0.0
	var swung_type := s.fusion.last_slash_type
	var swung_source := s.fusion.last_swing_source

	var any_guard := false
	var last_guard := false
	var strike := false
	var recenter := false
	var inline_recentered := false
	var prev_pkt_recenter := s._prev_recenter
	var dodge := false
	var dodge_dir := 0.0
	var thrust := false

	for pkt in queue:
		var btns := int(pkt.get("b", 0))
		var pkt_guard := (btns & 1) != 0
		any_guard = any_guard or pkt_guard
		last_guard = pkt_guard
		strike = strike or ((btns & 2) != 0)
		var pkt_recenter := (btns & 4) != 0
		recenter = recenter or pkt_recenter
		if pkt_recenter and not prev_pkt_recenter:
			s.fusion.recenter()
			inline_recentered = true
		prev_pkt_recenter = pkt_recenter
		var pkt_dodge := ((btns & 8) != 0) or ((btns & 32) != 0)
		if pkt_dodge:
			dodge = true
			if pkt.has("d"):
				dodge_dir = float(pkt.get("d", 0.0))
			elif (btns & 32) != 0:
				dodge_dir = 1.0
			else:
				dodge_dir = -1.0
		elif pkt.has("d") and absf(float(pkt.get("d", 0.0))) > 0.25:
			dodge = true
			dodge_dir = float(pkt.get("d", 0.0))
		thrust = thrust or ((btns & 16) != 0)

		if dodge_dir == 0.0:
			var m_arr: Array = pkt.get("m", [0.0, 0.0])
			if m_arr.size() >= 1 and dodge:
				dodge_dir = clampf(float(m_arr[0]), -1.0, 1.0)

		var pkt_dt := clampf(float(pkt.get("dt", delta)), 0.003, 0.08)
		var g_arr: Array = pkt.get("g", [0.0, 0.0, 0.0])
		var pg_arr: Array = pkt.get("pg", g_arr)
		var a_arr: Array = pkt.get("a", [0.0, 0.0, 9.81])
		var l_arr: Array = pkt.get("l", [0.0, 0.0, 0.0])
		var la_arr: Array = pkt.get("la", l_arr)
		var has_lin := int(pkt.get("hl", 1)) != 0

		# Exact right-handed transformation: Phone (+X right, +Y blade top, +Z screen normal) -> Sword Frame
		var raw_gyro := Vector3(float(g_arr[0]), float(g_arr[1]), float(g_arr[2]))
		var peak_gyro := Vector3(float(pg_arr[0]), float(pg_arr[1]), float(pg_arr[2]))
		var raw_accel := Vector3(-float(a_arr[0]), -float(a_arr[2]), float(a_arr[1]))
		var raw_linear_now := Vector3(float(la_arr[0]), float(la_arr[2]), -float(la_arr[1]))
		var raw_linear_peak := Vector3(float(l_arr[0]), float(l_arr[2]), -float(l_arr[1]))
		var gravity_est := (raw_accel + raw_linear_now) if has_lin else Vector3.ZERO

		s.fusion.update(pkt_dt, raw_gyro, raw_accel, gravity_est, peak_gyro, raw_linear_peak)
		if s.fusion.just_swung:
			if not any_swung or s.fusion.last_slash_power >= swung_power:
				swung_dir = s.fusion.last_slash_dir
				swung_power = s.fusion.last_slash_power
				swung_type = s.fusion.last_slash_type
				swung_source = s.fusion.last_swing_source
			any_swung = true

	queue.clear()
	_mobile_queues[s.device_id] = queue

	if any_swung:
		s.fusion.just_swung = true
		s.fusion.last_slash_dir = swung_dir
		s.fusion.last_slash_power = swung_power
		s.fusion.last_slash_type = swung_type
		s.fusion.last_swing_source = swung_source

	var guard := last_guard or (any_guard and not s.is_guarding)
	s._skip_next_begin_recenter = inline_recentered
	s.move_axis = Vector2(clampf(dodge_dir, -1.0, 1.0), 0.0) if dodge else Vector2.ZERO
	s.begin_frame(guard, strike, recenter, dodge, thrust)
	_apply_manual_attack_buttons(s, thrust)


func _update_mouse_slot(s: PlayerSlot, delta: float) -> void:
	var safe_dt := maxf(delta, 0.004)
	var gui_hovered := get_viewport().gui_get_hovered_control()
	var clicking_ui := gui_hovered != null and (
		gui_hovered is BaseButton
		or gui_hovered is OptionButton
		or gui_hovered is Slider
		or gui_hovered is ScrollBar
	)
	var guard := Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)
	var strike := Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and mouse_combat_enabled and not clicking_ui
	var dodge_left := Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT)
	var dodge_right := Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT)
	var dodge := Input.is_key_pressed(KEY_SPACE) or Input.is_key_pressed(KEY_SHIFT) or dodge_left or dodge_right
	var thrust := Input.is_key_pressed(KEY_F)
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

	if mouse_combat_enabled or Input.is_key_pressed(KEY_Q) or Input.is_key_pressed(KEY_E):
		_mouse_yaw = clampf(_mouse_yaw - _mouse_accum.x * sensitivity, -1.25, 1.25)
		_mouse_pitch = clampf(_mouse_pitch - _mouse_accum.y * sensitivity, -1.1, 1.1)
		if not Input.is_key_pressed(KEY_Q) and not Input.is_key_pressed(KEY_E):
			_mouse_roll = clampf(_mouse_roll - _mouse_accum.x * sensitivity * 0.85, -1.45, 1.45)

	var fake_gyro := Vector3.ZERO

	var q := Quaternion.from_euler(Vector3(_mouse_pitch, _mouse_yaw, _mouse_roll))
	s.fusion.apply_external_orientation(q, safe_dt, fake_gyro, Vector3.ZERO)

	var dodge_dx := 0.0
	if dodge_right:
		dodge_dx += 1.0
	if dodge_left:
		dodge_dx -= 1.0
	s.move_axis = Vector2(dodge_dx, 0.0)

	s.begin_frame(guard, strike, recenter, dodge, thrust)
	if mouse_combat_enabled:
		_apply_manual_attack_buttons(s, thrust)


func _apply_manual_attack_buttons(s: PlayerSlot, is_thrust_btn: bool) -> void:
	if (s.just_strike_pressed or s.just_thrust_pressed) and s.fusion.swing_cooldown_timer <= 0.0:
		s.fusion.swing_cooldown_timer = 0.22
		s.fusion.just_swung = true
		s.fusion.last_slash_power = 0.95
		s.fusion.last_slash_type = MotionFusion.SlashType.THRUST if (is_thrust_btn or s.just_thrust_pressed) else MotionFusion.SlashType.CUT
		s.fusion.last_swing_source = "Estocada" if s.fusion.last_slash_type == MotionFusion.SlashType.THRUST else "Botón"
		var cut_ang := s.fusion.quantize_4_angles(s.fusion.get_snapped_blade_roll_rad()) - PI * 0.5
		s.fusion.last_slash_dir = Vector2(cos(cut_ang), sin(cut_ang)).normalized()


func trigger_rumble(slot_idx: int, strength: float = 0.65, duration: float = 0.12) -> void:
	if slot_idx < 0 or slot_idx >= slots.size():
		return
	var s := slots[slot_idx]
	if s.source_type == SourceType.GAMEPAD and s.device_id >= 0:
		Input.start_joy_vibration(s.device_id, strength * 0.7, strength, duration)
	elif s.source_type == SourceType.MOBILE and s.device_id >= 0:
		mobile_server.send_rumble(s.device_id, int(clampf(duration * 1000.0, 20.0, 220.0)))


func trigger_haptic_pattern(slot_idx: int, pattern: Array) -> void:
	if slot_idx < 0 or slot_idx >= slots.size():
		return
	var s := slots[slot_idx]
	if s.source_type == SourceType.GAMEPAD and s.device_id >= 0:
		Input.start_joy_vibration(s.device_id, 0.8, 1.0, 0.16)
	elif s.source_type == SourceType.MOBILE and s.device_id >= 0:
		mobile_server.send_feedback(s.device_id, {"v": pattern})


func recenter_slot(slot_idx: int) -> void:
	if slot_idx < 0 or slot_idx >= slots.size():
		return
	var s := slots[slot_idx]
	if s.source_type == SourceType.MOUSE:
		_mouse_pitch = 0.0
		_mouse_yaw = 0.0
		_mouse_roll = 0.0
		s.fusion.apply_external_orientation(Quaternion.IDENTITY, 0.016, Vector3.ZERO, Vector3.ZERO)
	s.fusion.recenter()
