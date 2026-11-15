extends Node

var _failed: bool = false

func _check(cond: bool, msg: String) -> void:
	if not cond:
		push_error("ASSERT FAILED: " + msg)
		print("FAIL: " + msg)
		_failed = true
		get_tree().quit(1)


func _step_combat(arena: Node, frames: int = 5, step_dt: float = 0.02) -> void:
	for _i in frames:
		arena._process(step_dt)


func _ready() -> void:
	call_deferred("_run_checks")


func _run_checks() -> void:
	var tree := get_tree()
	await tree.process_frame

	# 1. Check Autoloads
	var hub = tree.root.get_node_or_null("MotionHub")
	_check(hub != null, "MotionHub autoload missing")
	var sfx = tree.root.get_node_or_null("SoundFX")
	_check(sfx != null, "SoundFX autoload missing")
	_check(hub.mobile_server.is_running, "MobileBridgeServer failed to listen")
	if _failed: return
	print("OK MobileBridgeServer running on port %d (%s)" % [hub.mobile_server.active_port, hub.mobile_server.get_primary_url()])

	# 2. MotionFusion tilted-gravity recenter, pure twist immunity, combo reversal, & thrust checks
	var mf := MotionFusion.new()
	var tilted_grav := Vector3(0.0, -7.0, 6.8)
	for i in 10:
		mf.update(0.016, Vector3(0.01, -0.01, 0.0), tilted_grav, tilted_grav)
	_check(not mf.just_swung, "Should not swing while stationary")
	mf.recenter()
	_check(absf(mf.pitch_rad) < 0.001 and absf(mf.yaw_rad) < 0.001 and absf(mf.blade_roll_rad) < 0.001, "Recenter must zero tilted angles")
	_check(mf.orientation.is_equal_approx(Quaternion.IDENTITY), "Recenter must reset orientation")

	# Turning horizontally (yaw) while tilted must NOT couple into blade_roll_rad
	for i in 12:
		mf.update(0.016, Vector3(0.0, -2.5, 0.0), tilted_grav, tilted_grav)
	_check(absf(mf.blade_roll_rad) < 0.05, "Yaw turn on tilted grip must not leak into roll")

	# Pure wrist roll twist along blade axis must produce ZERO false swing
	mf.recenter()
	var twist_swung := false
	for i in 15:
		var g := mf.orientation.inverse() * Vector3(0.0, -9.81, 0.0)
		mf.update(0.016, Vector3(0.0, 0.0, 5.8), g, g)
		if mf.just_swung:
			twist_swung = true
	_check(not twist_swung, "Fast pure forearm roll twist must NOT trigger false strike")
	mf.recenter()

	# Horizontal swing detection check
	var swung := false
	for i in 8:
		mf.update(0.016, Vector3(0.0, -9.5, 0.0), Vector3(0, -9.81, 0), Vector3(0, -9.81, 0))
		if mf.just_swung:
			swung = true
	_check(swung, "Should detect horizontal swing")

	# Reverse back-and-forth combo without waiting for full stop!
	for i in 8:
		mf.update(0.016, Vector3(0.0, -0.5, 0.0), Vector3(0, -9.81, 0), Vector3(0, -9.81, 0))
	var combo_swung := false
	for i in 10:
		mf.update(0.016, Vector3(0.0, 7.5, 0.0), Vector3(0, -9.81, 0), Vector3(0, -9.81, 0))
		if mf.just_swung:
			combo_swung = true
	_check(combo_swung, "Directional reversal whip must trigger rapid combo without deadlock")
	mf.recenter()

	# Blade-aligned slash check: holding horizontal (PI/2) + downward pitch must cut horizontally
	for i in 66:
		var g := mf.orientation.inverse() * Vector3(0.0, -9.81, 0.0)
		mf.update(0.016, Vector3(0.0, 0.0, 1.5), g, g)
	for i in 14:
		var g := mf.orientation.inverse() * Vector3(0.0, -9.81, 0.0)
		mf.update(0.016, Vector3.ZERO, g, g)
	var aligned_swung := false
	for i in 8:
		var g := mf.orientation.inverse() * Vector3(0.0, -9.81, 0.0)
		mf.update(0.016, Vector3(-7.0, 0.0, 0.0), g, g)
		if mf.just_swung:
			aligned_swung = true
	_check(aligned_swung, "Should detect forward pitch cut when holding blade horizontal")
	_check(absf(mf.last_slash_dir.x) > 0.85, "Horizontal blade pitch swing must execute horizontally, got %s" % str(mf.last_slash_dir))
	mf.recenter()

	# Forward arm thrust check even when browser linear_accel (raw_accel - raw_gravity) is missing
	for i in 14:
		mf.update(0.016, Vector3.ZERO, Vector3(0.0, -9.81, 0.0), Vector3(0.0, -9.81, 0.0))
	var lunge_swung := false
	for i in 6:
		var punch_accel := Vector3(0.0, -9.81, 6.8)
		mf.update(0.016, Vector3(-0.9, 0.0, 0.0), punch_accel, punch_accel)
		if mf.just_swung:
			lunge_swung = true
	_check(lunge_swung, "Forward thrust must trigger attack")
	_check(mf.last_swing_source == "Empuje frontal", "Expected forward thrust source, got %s" % mf.last_swing_source)
	_check(mf.last_slash_type == MotionFusion.SlashType.THRUST, "Expected SlashType.THRUST")
	mf.recenter()
	if _failed: return
	print("OK MotionFusion real-speed / twist-immune / combo / thrust checks")

	# 3. MainMenu scene load, stage selector & style selector
	var menu_scene: PackedScene = load("res://scenes/MainMenu.tscn")
	var menu := menu_scene.instantiate()
	tree.root.add_child(menu)
	await tree.process_frame
	menu._on_stage_select_item_selected(1)
	_check(GameConfig.arena_stage == GameConfig.ArenaStage.VOLCANIC_BRIDGE, "Stage select should update arena_stage")
	menu._on_style_select_item_selected(1)
	_check(GameConfig.combat_style == GameConfig.CombatStyle.TWIN_BLADES, "Style select should update combat_style")
	menu._on_stage_select_item_selected(0)
	menu._on_style_select_item_selected(0)
	menu.queue_free()
	await tree.process_frame
	if _failed: return
	print("OK MainMenu instantiated & stage/style toggles verified")

	# 4. CalibrationRoom animated coach, live dojo & sparring dummy check
	var cal_scene: PackedScene = load("res://scenes/CalibrationRoom.tscn")
	var cal := cal_scene.instantiate()
	tree.root.add_child(cal)
	await tree.process_frame
	cal._on_step_3_pressed()
	for i in 55:
		cal._process(0.02)
	cal._on_step_4_pressed()
	for i in 20:
		cal._process(0.02)
	cal.queue_free()
	await tree.process_frame
	print("OK CalibrationRoom animated coach & sparring dummy instantiated and stepped")

	# 5. ChambaraArena 1P full combat pipeline tests
	GameConfig.match_mode = "1p"
	GameConfig.arena_stage = GameConfig.ArenaStage.SUN_ISLAND
	GameConfig.combat_style = GameConfig.CombatStyle.CLASSIC
	var arena_scene: PackedScene = load("res://scenes/ChambaraArena.tscn")
	var arena = arena_scene.instantiate()
	tree.root.add_child(arena)
	await tree.process_frame

	# Verify entry calibration auto-completes on steady controller
	arena.begin_entry_calibration(true)
	_check(arena.phase == arena.MatchPhase.CALIBRATE_ENTRY, "Should enter CALIBRATE_ENTRY phase")
	hub.slots[0].fusion.angular_speed = 0.05
	for i in 35:
		arena._process(0.02)
	_check(arena.phase == arena.MatchPhase.INTRO, "Steady hold should finish entry calibration into INTRO")
	if _failed:
		arena.queue_free()
		return
	print("OK Chambara entry calibration auto-center")

	# Setup deterministic combat physics tests (A..H) before 2P integration check
	arena.phase = arena.MatchPhase.FIGHTING
	arena.script_ai_and_input_enabled = false
	arena.f1.reset_for_round(Vector3(0.0, 0.0, 0.90), Vector2(0.0, -1.0))
	arena.f2.reset_for_round(Vector3(0.0, 0.0, -0.90), Vector2(0.0, 1.0))

	# Test A: Timed Perfect Parry at perpendicular angle stuns attacker 1.65s, charges defender, & recovers Slow-Mo
	arena.f2.is_guarding = true
	arena.f2.is_charged = false
	arena.f2.blade_roll_rad = 0.0
	arena.f1.trigger_slash(Vector2(1.0, 0.0), 1.0)
	_step_combat(arena, 5, 0.02)
	_check(arena.f1.state == AvatarFighter.State.STUNNED, "Perpendicular timed parry must stun attacker")
	_check(arena.f1.stun_timer > 1.2, "Perpendicular parry must stun for Switch Sports duration (~1.65s)")
	_check(arena.f2.is_charged, "Perpendicular parry must charge defender")
	for i in 22:
		arena._process(0.015)
	_check(Engine.time_scale > 0.9, "Slow-motion must cleanly recover back to 1.0")
	if _failed:
		arena.queue_free()
		return
	print("OK Chambara timed Perfect Parry, Slow-Mo recovery & charge")

	# Test B: Diagonal X visual cross Perfect Parry
	arena.f1.reset_for_round(Vector3(0.0, 0.0, 0.76), Vector2(0.0, -1.0))
	arena.f2.reset_for_round(Vector3(0.0, 0.0, -0.76), Vector2(0.0, 1.0))
	arena.f1.is_guarding = true
	arena.f1.blade_roll_rad = -PI * 0.25
	arena.f2.trigger_slash(Vector2(0.7, 0.7), 1.0)
	_step_combat(arena, 5, 0.02)
	_check(arena.f2.state == AvatarFighter.State.STUNNED, "Visual diagonal X cross must parry opposing AI slash")
	for i in 22:
		arena._process(0.015)
	Engine.time_scale = 1.0
	if _failed:
		arena.queue_free()
		return
	print("OK Chambara 1P diagonal visual-cross parry")

	# Test B2: Early held Solid Block blocks knockback safely without granting free 1.65s stun
	arena.f1.reset_for_round(Vector3(0.0, 0.0, 0.76), Vector2(0.0, -1.0))
	arena.f2.reset_for_round(Vector3(0.0, 0.0, -0.76), Vector2(0.0, 1.0))
	arena.f1.is_guarding = true
	arena.f1.blade_roll_rad = 0.0
	for i in 15:
		arena.f1.step_fighter(0.02, Vector2.ZERO, arena.f2.position, true)
	_check(arena.f1.guard_held_time > 0.22, "Held guard should exit Perfect Parry window")
	arena.f2.trigger_slash(Vector2(1.0, 0.0), 1.0)
	_step_combat(arena, 5, 0.02)
	_check(arena.f2.state != AvatarFighter.State.STUNNED, "Held block recoils attacker safely without free stun")
	_check(arena.f1.guard_meter < 100.0, "Solid block should consume a sliver of guard meter")
	if _failed:
		arena.queue_free()
		return
	print("OK Chambara held-early Solid Guard block")

	# Test C: Zero-button Passive Glancing Deflect (reduced knockback, NO free 1.65s stun)
	arena.f1.reset_for_round(Vector3(0.0, 0.0, 0.76), Vector2(0.0, -1.0))
	arena.f2.reset_for_round(Vector3(0.0, 0.0, -0.76), Vector2(0.0, 1.0))
	arena.f1.is_guarding = false
	arena.f1.blade_roll_rad = 0.0
	hub.slots[0].fusion.is_steady = true
	arena.f2.trigger_slash(Vector2(1.0, 0.0), 1.0)
	_step_combat(arena, 5, 0.02)
	_check(arena.f2.state != AvatarFighter.State.STUNNED, "Zero-button passive deflect must not award free stun")
	_check(arena.f1.velocity_xz.y < 2.2, "Passive deflect must soften knockback below direct hit")
	if _failed:
		arena.queue_free()
		return
	print("OK Chambara zero-button Glancing Passive Deflect")

	# Test D: Parallel guard overcome -> Guard Meter drain -> Total Stance Break
	arena.f1.reset_for_round(Vector3(0.0, 0.0, 0.76), Vector2(0.0, -1.0))
	arena.f2.reset_for_round(Vector3(0.0, 0.0, -0.76), Vector2(0.0, 1.0))
	arena.f2.is_guarding = true
	arena.f2.blade_roll_rad = PI * 0.5
	arena.f1.trigger_slash(Vector2(1.0, 0.0), 1.0)
	_step_combat(arena, 5, 0.02)
	_check(arena.f2.guard_break_timer > 0.0, "Parallel slash should trigger guard_break_timer")
	_check(arena.f2.guard_meter < 65.0, "Parallel slash should drain guard_meter")
	_check(arena.f2.velocity_xz.y < -1.5, "Guard overcome should knock defender backward along -Z")
	arena.f2.guard_meter = 15.0
	arena.f2.guard_break_timer = 0.0
	arena.f1.state = AvatarFighter.State.NORMAL
	arena.f2.is_guarding = true
	arena.f1.trigger_slash(Vector2(1.0, 0.0), 1.0)
	_step_combat(arena, 5, 0.02)
	_check(arena.f2.state == AvatarFighter.State.STUNNED, "Depleting guard_meter to 0 must trigger Stance Break STUNNED")
	if _failed:
		arena.queue_free()
		return
	print("OK Chambara parallel guard overcome & Stance Break")

	# Test E: Stun multi-hit combo & charged strike
	arena.f1.reset_for_round(Vector3(0.0, 0.0, 0.76), Vector2(0.0, -1.0))
	arena.f2.reset_for_round(Vector3(0.0, 0.0, -0.76), Vector2(0.0, 1.0))
	arena.f1.is_charged = true
	arena.f2.apply_stun(1.65)
	arena.f1.trigger_slash(Vector2(1.0, 0.0), 1.0)
	_step_combat(arena, 4, 0.02)
	_check(not arena.f1.is_charged, "Charged strike must consume is_charged")
	_check(arena.f2.state == AvatarFighter.State.STUNNED, "Hit 1 during stun must allow combo follow-up")
	_check(arena.f2.stun_timer > 1.0 and arena.f2.stun_timer < 1.3, "Hit 1 should shave 0.45s off stun, got %f" % arena.f2.stun_timer)
	_check(arena.f2.velocity_xz.y < -6.0, "Charged hit should deal heavy 1.65x knockback along -Z, got %f" % arena.f2.velocity_xz.y)
	arena.f1.state = AvatarFighter.State.NORMAL
	arena.f1.trigger_slash(Vector2(0.0, 1.0), 1.0)
	_step_combat(arena, 6, 0.02)
	_check(arena.f2.state == AvatarFighter.State.STUNNED and arena.f2.stun_timer < 0.85, "Hit 2 should continue stun combo, state=%d stun=%f" % [arena.f2.state, arena.f2.stun_timer])
	if _failed:
		arena.queue_free()
		return
	print("OK Chambara stun combo & charged strike")

	# Test F: Sword Clash (simultaneous swing / late windup)
	arena._hitstop_timer = 0.0
	arena.f1.reset_for_round(Vector3(0.0, 0.0, 0.76), Vector2(0.0, -1.0))
	arena.f2.reset_for_round(Vector3(0.0, 0.0, -0.76), Vector2(0.0, 1.0))
	arena.f2.start_windup(Vector2(1.0, 0.0), 0.15)
	arena.f1.trigger_slash(Vector2(0.0, 1.0), 1.0)
	_step_combat(arena, 4, 0.02)
	_check(arena.f1.state == AvatarFighter.State.NORMAL and arena.f2.state == AvatarFighter.State.NORMAL, "Sword clash must cancel both attacks")
	_check(arena.f1.velocity_xz.y > 0.5 and arena.f2.velocity_xz.y < -0.5, "Sword clash must push both fighters apart")
	if _failed:
		arena.queue_free()
		return
	print("OK Chambara sword clash")

	# Test G: Estocada pierces passive/held guard & Sidestep Dodge evades cleanly via i-frames
	arena._hitstop_timer = 0.0
	arena.f1.reset_for_round(Vector3(0.0, 0.0, 0.80), Vector2(0.0, -1.0))
	arena.f2.reset_for_round(Vector3(0.0, 0.0, -0.80), Vector2(0.0, 1.0))
	arena.f2.is_guarding = true
	arena.f2.blade_roll_rad = 0.0
	for i in 15:
		arena.f2.step_fighter(0.02, Vector2.ZERO, arena.f1.position, true)
	arena.f1.trigger_slash(Vector2(0.0, -1.0), 1.0, AvatarFighter.AttackType.THRUST)
	_step_combat(arena, 5, 0.02)
	_check(arena.f2.guard_break_timer > 0.0 and arena.f2.velocity_xz.y < -2.0, "Estocada must pierce early held block, got vel_y=%f" % arena.f2.velocity_xz.y)

	arena.f1.reset_for_round(Vector3(0.0, 0.0, 0.80), Vector2(0.0, -1.0))
	arena.f2.reset_for_round(Vector3(0.0, 0.0, -0.80), Vector2(0.0, 1.0))
	_check(arena.f1.trigger_dodge(Vector2(1.0, 0.0)), "Sidestep dodge should trigger")
	arena.f2.trigger_slash(Vector2(1.0, 0.0), 1.0)
	_step_combat(arena, 5, 0.02)
	_check(arena.f1.spirit > 15.0, "Evading slash with dodge i-frames should grant Spirit reward")
	if _failed:
		arena.queue_free()
		return
	print("OK Chambara Estocada pierce & Sidestep Dodge i-frames")

	# Test H: 100% Spirit Crescent Wave hits beyond melee range
	arena._hitstop_timer = 0.0
	arena.f1.reset_for_round(Vector3(0.0, 0.0, 1.65), Vector2(0.0, -1.0))
	arena.f2.reset_for_round(Vector3(0.0, 0.0, -1.65), Vector2(0.0, 1.0))
	arena.f1.spirit = 100.0
	arena.f1.trigger_slash(Vector2(1.0, 0.0), 1.2)
	_check(arena.f1.spirit == 0.0, "Swinging at 100% spirit must consume Spirit and fire Crescent Wave")
	var min_z_vel := 0.0
	for i in 18:
		arena._process(0.02)
		min_z_vel = minf(min_z_vel, arena.f2.velocity_xz.y)
	_check(min_z_vel < -4.0 and arena.f2.position.z < -1.9, "Crescent Energy Wave must strike opponent from 3.3m range, min_v=%f pos_z=%f" % [min_z_vel, arena.f2.position.z])
	if _failed:
		arena.queue_free()
		return
	print("OK Chambara 100% Spirit Crescent Wave")

	arena.queue_free()
	await tree.process_frame

	# Test I: 2P Split-Screen + Puente Volcánico + Espadas Gemelas instantiation
	GameConfig.match_mode = "2p"
	GameConfig.arena_stage = GameConfig.ArenaStage.VOLCANIC_BRIDGE
	GameConfig.combat_style = GameConfig.CombatStyle.TWIN_BLADES
	var arena_2p = arena_scene.instantiate()
	tree.root.add_child(arena_2p)
	await tree.process_frame
	arena_2p._complete_entry_calibration()
	_step_combat(arena_2p, 10, 0.02)
	_check(arena_2p._split_root != null, "2P mode must mount SplitScreenRoot")
	arena_2p.queue_free()
	await tree.process_frame
	GameConfig.match_mode = "1p"
	GameConfig.arena_stage = GameConfig.ArenaStage.SUN_ISLAND
	GameConfig.combat_style = GameConfig.CombatStyle.CLASSIC
	if _failed: return
	print("OK Chambara 2P Split-Screen + Puente Volcánico + Espadas Gemelas")

	# Test J: 3D Poses (Frente, Arriba, Abajo, Izq, Der), Overhead Chop & Brisk Linear Whip
	var f_up := MotionFusion.new()
	f_up.reset_pose()
	f_up.apply_external_orientation(Quaternion(Vector3.RIGHT, 1.05), 0.016, Vector3.ZERO, Vector3.ZERO)
	_check(f_up.get_aim_label() == "ARRIBA", "Up pitch must report ARRIBA, got %s" % f_up.get_aim_label())
	# Chop downward from vertical overhead hold (angular pitch -X)
	f_up.apply_external_orientation(Quaternion(Vector3.RIGHT, 0.85), 0.016, Vector3(-4.2, 0.0, 0.0), Vector3.ZERO)
	_check(f_up.just_swung and f_up.last_slash_type == MotionFusion.SlashType.CUT, "Downward chop from ARRIBA must trigger CUT")

	var f_poses := MotionFusion.new()
	f_poses.reset_pose()
	_check(f_poses.get_aim_label() == "AL FRENTE", "Identity must report AL FRENTE")
	f_poses.apply_external_orientation(Quaternion(Vector3.RIGHT, -0.95), 0.016, Vector3.ZERO, Vector3.ZERO)
	_check(f_poses.get_aim_label() == "ABAJO", "Down pitch must report ABAJO, got %s" % f_poses.get_aim_label())
	f_poses.apply_external_orientation(Quaternion(Vector3.UP, 0.90), 0.016, Vector3.ZERO, Vector3.ZERO)
	_check(f_poses.get_aim_label() == "IZQUIERDA", "Left yaw must report IZQUIERDA, got %s" % f_poses.get_aim_label())
	f_poses.apply_external_orientation(Quaternion(Vector3.UP, -0.90), 0.016, Vector3.ZERO, Vector3.ZERO)
	_check(f_poses.get_aim_label() == "DERECHA", "Right yaw must report DERECHA, got %s" % f_poses.get_aim_label())

	var f_brisk := MotionFusion.new()
	f_brisk.reset_pose()
	# Pure wrist roll should still stay 0 swings, while brisk lateral linear whip + slight wrist impulse triggers CUT
	for k in 6:
		var g_rot := f_brisk.orientation.inverse() * Vector3(0.0, -9.81, 0.0)
		f_brisk.update(0.016, Vector3(0.0, 0.0, 5.0), g_rot, g_rot, Vector3(0.0, 0.0, 5.0))
		_check(not f_brisk.just_swung, "Pure wrist twist must NEVER trigger false slash")
	f_brisk.recenter()
	f_brisk.update(0.016, Vector3(0.0, -1.2, 0.0), Vector3(-11.5, -9.81, 0.0), Vector3(0.0, -9.81, 0.0))
	_check(f_brisk.just_swung and f_brisk.last_slash_type == MotionFusion.SlashType.CUT, "Brisk linear arm whip + impulse must trigger CUT cleanly")
	if _failed: return
	print("OK 3D Poses, Overhead Chop & Brisk Linear Whip")

	# Test K: Zero Free-Walk / No Backward Drift + True 3D Sword Aim Tracking in Fighter
	var arena_k = arena_scene.instantiate()
	tree.root.add_child(arena_k)
	await tree.process_frame
	arena_k._complete_entry_calibration()
	arena_k.f1.reset_for_round(Vector3(0.0, 0.0, 0.85), Vector2(0.0, -1.0))
	arena_k.f2.reset_for_round(Vector3(0.0, 0.0, -0.85), Vector2(0.0, 1.0))
	var start_z: float = arena_k.f1.position.z
	for i in 12:
		arena_k.f1.step_fighter(0.02, Vector2(0.0, 1.0), arena_k.f2.position, true)
	_check(absf(arena_k.f1.position.z - start_z) < 0.001, "Fighter must NEVER walk backward from move_input (got z=%f vs %f)" % [arena_k.f1.position.z, start_z])

	# Verify 3D blade tip responds to UP, DOWN, LEFT, RIGHT orientation without Euler clamp lock
	arena_k.f1.blade_orientation = Quaternion(Vector3.RIGHT, 1.04)
	for i in 18: arena_k.f1.step_fighter(0.02, Vector2.ZERO, arena_k.f2.position, true)
	await tree.process_frame
	var seg_up: Array[Vector3] = arena_k.f1.get_blade_segment_world()
	var dir_up: Vector3 = (seg_up[1] - seg_up[0]).normalized()
	_check(dir_up.y > 0.82, "3D ARRIBA pose must point sword high UP (dir_up.y=%f)" % dir_up.y)

	arena_k.f1.blade_orientation = Quaternion(Vector3.RIGHT, -1.04)
	for i in 18: arena_k.f1.step_fighter(0.02, Vector2.ZERO, arena_k.f2.position, true)
	await tree.process_frame
	var seg_dn: Array[Vector3] = arena_k.f1.get_blade_segment_world()
	var dir_dn: Vector3 = (seg_dn[1] - seg_dn[0]).normalized()
	_check(dir_dn.y < -0.45, "3D ABAJO pose must point sword DOWN (dir_dn.y=%f)" % dir_dn.y)

	arena_k.f1.blade_orientation = Quaternion(Vector3.UP, 1.0)
	for i in 18: arena_k.f1.step_fighter(0.02, Vector2.ZERO, arena_k.f2.position, true)
	await tree.process_frame
	var seg_lf: Array[Vector3] = arena_k.f1.get_blade_segment_world()
	var dir_lf: Vector3 = (seg_lf[1] - seg_lf[0]).normalized()
	_check(dir_lf.x < -0.50, "3D IZQUIERDA pose must aim blade toward -X world left (dir_lf.x=%f)" % dir_lf.x)

	arena_k.f1.blade_orientation = Quaternion(Vector3.UP, -1.0)
	for i in 18: arena_k.f1.step_fighter(0.02, Vector2.ZERO, arena_k.f2.position, true)
	await tree.process_frame
	var seg_rt: Array[Vector3] = arena_k.f1.get_blade_segment_world()
	var dir_rt: Vector3 = (seg_rt[1] - seg_rt[0]).normalized()
	_check(dir_rt.x > 0.50, "3D DERECHA pose must aim blade toward +X world right (dir_rt.x=%f)" % dir_rt.x)

	arena_k.queue_free()
	await tree.process_frame
	if _failed: return
	print("OK Zero Backward Walk & 3D Sword Aim Tracking (Up/Down/Left/Right)")

	# Test L: End-to-end Android Chrome WebSocket payload -> MotionHub -> Fusion (Thrust / Dodge / Idle Zero Walk)
	hub._on_mobile_telemetry(999, {"s": 0, "q": 1, "dt": 0.016, "g": [0.0, 0.0, 0.0], "pg": [0.0, 0.0, 0.0], "a": [0.0, 0.0, 9.81], "l": [0.0, 0.0, 0.0], "hl": 1, "d": 0, "m": [0.0, 0.0], "b": 4})
	hub._process(0.016)
	_check(hub.slots[0].source_type == MotionHub.SourceType.MOBILE, "Telemetry must bind mobile peer to Slot 0")
	_check(hub.slots[0].move_axis == Vector2.ZERO, "Mobile idle must keep move_axis == ZERO")

	# Simulated Android forward phone thrust (+Y_phone linear accel = +10.0)
	hub._on_mobile_telemetry(999, {"s": 0, "q": 2, "dt": 0.016, "g": [0.0, 0.0, 0.0], "pg": [0.0, 0.0, 0.0], "a": [0.0, 10.0, 9.81], "l": [0.0, 10.0, 0.0], "hl": 1, "d": 0, "m": [0.0, 0.0], "b": 0})
	hub._process(0.016)
	_check(hub.slots[0].fusion.just_swung and hub.slots[0].fusion.last_slash_type == MotionFusion.SlashType.THRUST, "Android Chrome +Y forward accel must trigger THRUST, got %d" % hub.slots[0].fusion.last_slash_type)

	# Simulated lateral sidestep dodge pulse Left (b=8, d=-1) then idle clear
	hub._on_mobile_telemetry(999, {"s": 0, "q": 3, "dt": 0.016, "g": [0.0, 0.0, 0.0], "pg": [0.0, 0.0, 0.0], "a": [0.0, 0.0, 9.81], "l": [0.0, 0.0, 0.0], "hl": 1, "d": -1, "m": [0.0, 0.0], "b": 8})
	hub._process(0.016)
	_check(hub.slots[0].just_dodge_pressed and hub.slots[0].move_axis.x < -0.5, "Mobile dodgeLeft must trigger dodge with -X direction")
	hub._on_mobile_telemetry(999, {"s": 0, "q": 4, "dt": 0.016, "g": [0.0, 0.0, 0.0], "pg": [0.0, 0.0, 0.0], "a": [0.0, 0.0, 9.81], "l": [0.0, 0.0, 0.0], "hl": 1, "d": 0, "m": [0.0, 0.0], "b": 0})
	hub._process(0.016)
	_check(hub.slots[0].move_axis == Vector2.ZERO, "Mobile move_axis must reset to ZERO immediately after dodge")

	# Verify mobile rotation (gz = r.beta) spins blade roll without attacking, gy = r.gamma slashes horizontally, and gx = r.alpha slashes vertically
	hub.slots[0].fusion.recenter()
	for q_i in range(5, 10):
		hub._on_mobile_telemetry(999, {"s": 0, "q": q_i, "dt": 0.016, "g": [1.8, 1.5, 8.5], "pg": [1.8, 1.5, 8.5], "a": [0.0, 0.0, 9.81], "l": [0.0, 0.0, 0.0], "hl": 1, "d": 0, "m": [0.0, 0.0], "b": 0})
		hub._process(0.016)
		_check(not hub.slots[0].fusion.just_swung, "Mobile rotation (gz = r.beta) must NEVER trigger attack")
	hub.slots[0].fusion.recenter()
	hub._on_mobile_telemetry(999, {"s": 0, "q": 10, "dt": 0.016, "g": [0.0, -5.8, 0.0], "pg": [0.0, -5.8, 0.0], "a": [0.0, 0.0, 9.81], "l": [0.0, 0.0, 0.0], "hl": 1, "d": 0, "m": [0.0, 0.0], "b": 0})
	hub._process(0.016)
	_check(hub.slots[0].fusion.just_swung and hub.slots[0].fusion.last_slash_dir.x > 0.7, "Mobile horizontal swing (gy = r.gamma) must trigger left-to-right slash")
	hub.slots[0].fusion.recenter()
	hub._on_mobile_telemetry(999, {"s": 0, "q": 11, "dt": 0.016, "g": [-5.8, 0.0, 0.0], "pg": [-5.8, 0.0, 0.0], "a": [0.0, 0.0, 9.81], "l": [0.0, 0.0, 0.0], "hl": 1, "d": 0, "m": [0.0, 0.0], "b": 0})
	hub._process(0.016)
	_check(hub.slots[0].fusion.just_swung and hub.slots[0].fusion.last_slash_dir.y > 0.7, "Mobile vertical swing (gx = r.alpha) must trigger up-to-down slash")
	hub._on_mobile_disconnected(999)
	if _failed: return
	print("OK End-to-End Android Mobile Telemetry (Thrust / Lateral Dodge / Idle Zero Walk)")

	# Test M: Pommel/Hilt ("pomo") Axial Flip Twist Immunity + Braking Lag vs Real Directional Swings
	var f_pomo := MotionFusion.new()
	f_pomo.reset_pose()
	var flip_false_hit := false
	for i in 12:
		var g_dir := f_pomo.orientation.inverse() * Vector3(0.0, -9.81, 0.0)
		var g_lag := g_dir + Vector3(-10.5, 0.0, 9.0)
		f_pomo.update(0.016, Vector3(2.4, 2.2, 9.5), g_lag, g_dir, Vector3(2.4, 2.2, 9.5))
		if f_pomo.just_swung:
			flip_false_hit = true
	for i in 6:
		var g_dir := f_pomo.orientation.inverse() * Vector3(0.0, -9.81, 0.0)
		var g_lag := g_dir + Vector3(-7.5, 0.0, 7.0)
		f_pomo.update(0.016, Vector3(2.6, 0.4, 0.2), g_lag, g_dir, Vector3(2.6, 0.4, 0.2))
		if f_pomo.just_swung:
			flip_false_hit = true
	_check(not flip_false_hit, "Axial phone flip + wrist wobble + gravity-lag must NEVER trigger strike")

	for i in 12:
		var g_dir := f_pomo.orientation.inverse() * Vector3(0.0, -9.81, 0.0)
		f_pomo.update(0.016, Vector3.ZERO, g_dir, g_dir)
	f_pomo.recenter()
	f_pomo.update(0.016, Vector3(-4.8, 0.0, 0.0), Vector3(0.0, -9.81, 0.0), Vector3(0.0, -9.81, 0.0))
	_check(f_pomo.just_swung and f_pomo.last_slash_dir.y > 0.8, "Pitch chop up->down must trigger vertical slash")
	f_pomo.recenter()
	f_pomo.update(0.016, Vector3(0.0, -4.8, 0.0), Vector3(0.0, -9.81, 0.0), Vector3(0.0, -9.81, 0.0))
	_check(f_pomo.just_swung and f_pomo.last_slash_dir.x > 0.8, "Yaw sweep left->right must trigger horizontal slash")
	if _failed: return
	print("OK Pommel Axial Twist Immunity + Braking Lag vs Real Directional Swings")

	# Test N: SimpleQR, Persistent Mobile Client Pairing, Slot Ownership & Bias Calibration
	var qr_script = preload("res://scripts/ui/SimpleQR.gd")
	var qr_tex: ImageTexture = qr_script.make_texture("https://192.168.1.100:8443", 4, 2)
	_check(qr_tex != null and qr_tex.get_width() == 132, "SimpleQR V3-L texture must build crisp 132x132 image")

	hub.assign_mouse(0)
	hub.unassign_slot(1)
	hub._on_mobile_telemetry(201, {"act": "hello", "cid": "tab1", "s": 0, "sens": 0})
	_check(hub.slots[0].source_type == MotionHub.SourceType.MOBILE and hub.slots[0].device_id == 201, "Mobile hello must claim Slot 0 (Jugador 1), got id=%d" % hub.slots[0].device_id)
	hub.assign_mobile(1, 201)
	_check(hub.slots[1].device_id == 201 and hub.slots[0].source_type == MotionHub.SourceType.MOUSE, "Moving peer to P2 must keep P1 usable as Mouse")
	hub._on_mobile_telemetry(201, {"s": 0, "q": 10, "dt": 0.016, "g": [0, 0, 0], "pg": [0, 0, 0], "a": [0, 0, 9.81], "l": [0, 0, 0], "hl": 1, "b": 0})
	_check(hub.slots[1].device_id == 201 and hub.slots[0].source_type == MotionHub.SourceType.MOUSE, "Passive telemetry must NOT steal P1 back when PC set peer to P2")
	hub._on_mobile_telemetry(201, {"act": "claim", "cid": "tab1", "s": 0, "sens": 1})
	_check(hub.slots[0].device_id == 201, "Explicit mobile claim must allow reclaiming P1")
	# Simulate reconnect with same cid -> peer 202 takes over preferred slot without bouncing to P2
	hub._on_mobile_disconnected(201)
	hub._on_mobile_telemetry(202, {"act": "hello", "cid": "tab1", "s": 0, "sens": 1})
	_check(hub.slots[0].source_type == MotionHub.SourceType.MOBILE and hub.slots[0].device_id == 202, "Reconnect with same cid must restore Slot 0 (J1)")
	# Simulate idle peer (>1.8s silent) replaced cleanly by fresh mobile peer 203
	hub._mobile_last_rx_msec[202] = Time.get_ticks_msec() - 2500
	hub._on_mobile_telemetry(203, {"act": "hello", "cid": "tab2", "s": 0, "sens": 0})
	_check(hub.slots[0].device_id == 203, "Fresh mobile must replace idle stale peer in Slot 0")
	hub.calibrate_bias_slot(0)
	_check(hub.slots[0].fusion._bias_samples_left == 20, "calibrate_bias_slot(0) must initialize IMU bias samples safely")

	var main_menu_scene := load("res://scenes/MainMenu.tscn") as PackedScene
	var menu_inst = main_menu_scene.instantiate()
	tree.root.add_child(menu_inst)
	await tree.process_frame
	var p1_sel: OptionButton = menu_inst.device_picker_p1
	_check(p1_sel.get_item_id(p1_sel.selected) == 1000 + 203, "MainMenu P1 picker must select connected mobile peer #203, got %d" % p1_sel.get_item_id(p1_sel.selected))
	menu_inst.queue_free()
	await tree.process_frame
	hub._on_mobile_disconnected(202)
	hub._on_mobile_disconnected(203)
	hub.assign_mouse(0)
	hub.unassign_slot(1)
	if _failed: return
	print("OK SimpleQR, Persistent Mobile Pairing, PC<->Mobile Sync & MainMenu Picker")

	# Test O: AI World-Space Diagonal Guard/Attack Math, Thrust Stun, No Stun-Hold Parry Exploit & Rematch Reset
	var arena_o = arena_scene.instantiate()
	tree.root.add_child(arena_o)
	await tree.process_frame
	arena_o._complete_entry_calibration()
	arena_o.phase = arena_o.MatchPhase.FIGHTING
	arena_o.script_ai_and_input_enabled = false
	arena_o.f1.reset_for_round(Vector3(0.0, 0.0, 0.78), Vector2(0.0, -1.0))
	arena_o.f2.reset_for_round(Vector3(0.0, 0.0, -0.78), Vector2(0.0, 1.0))
	arena_o.f1.is_guarding = true
	arena_o.f1.blade_roll_rad = PI * 0.25
	var ai_brk_dir: Vector2 = arena_o._ai_slash_dir_for_world_axis(arena_o.f1.get_world_blade_axis())
	_check(absf(arena_o.f2.get_world_slash_axis(ai_brk_dir).dot(arena_o.f1.get_world_blade_axis())) > 0.95, "AI parallel guard-break slash must align in world space on diagonals")
	var diag_slash_w: Vector3 = arena_o.f1.get_world_slash_axis(Vector2(0.707, 0.707))
	var ai_blk_roll: float = arena_o._ai_roll_for_world_axis(diag_slash_w, PI * 0.5)
	_check(absf(arena_o.f2.get_world_blade_axis(ai_blk_roll).dot(diag_slash_w)) < 0.05, "AI perpendicular diagonal block roll must be orthogonal in world space")

	# Early windup counter-hit (must hit, NOT force Clash)
	arena_o.f2.start_windup(Vector2(1.0, 0.0), 0.30)
	arena_o.f2.windup_timer = 0.25
	arena_o.f1.trigger_slash(Vector2(0.0, 1.0), 1.0)
	_step_combat(arena_o, 5, 0.02)
	_check(arena_o.f2.velocity_xz.y < -2.0, "Hitting early during windup must land counter-hit instead of forcing clash")

	# Thrust depleting guard_meter to 0 must stun defender (held static guard past parry window)
	arena_o._hitstop_timer = 0.0
	arena_o.f1.reset_for_round(Vector3(0.0, 0.0, 0.78), Vector2(0.0, -1.0))
	arena_o.f2.reset_for_round(Vector3(0.0, 0.0, -0.78), Vector2(0.0, 1.0))
	arena_o.f2.is_guarding = true
	arena_o.f2.guard_meter = 20.0
	for _j in 15:
		arena_o.f2.step_fighter(0.02, Vector2.ZERO, arena_o.f1.position, true)
	arena_o.f1.trigger_slash(Vector2(0.0, -1.0), 1.0, AvatarFighter.AttackType.THRUST)
	_step_combat(arena_o, 5, 0.02)
	_check(arena_o.f2.guard_meter == 0.0 and arena_o.f2.state == AvatarFighter.State.STUNNED, "Thrust breaking remaining guard_meter must stun defender (meter=%f state=%d)" % [arena_o.f2.guard_meter, arena_o.f2.state])
	if _failed:
		arena_o.queue_free()
		return

	# Holding guard continuously through stun must NOT yield free Perfect Parry upon stun expiry
	arena_o._hitstop_timer = 0.0
	arena_o.f2.reset_for_round(Vector3(0.0, 0.0, -0.78), Vector2(0.0, 1.0))
	arena_o.f2.apply_stun(0.03)
	arena_o.f2.is_guarding = true
	arena_o.f2.step_fighter(0.02, Vector2.ZERO, arena_o.f1.position, true)
	arena_o.f2.is_guarding = true
	arena_o.f2.step_fighter(0.02, Vector2.ZERO, arena_o.f1.position, true)
	_check(arena_o.f2.state == AvatarFighter.State.NORMAL and arena_o.f2.guard_held_time > 50.0, "Holding guard without releasing after stun must not trigger frame-0 Perfect Parry")
	# Releasing then re-pressing guard cleanly arms Perfect Parry window
	arena_o.f2.is_guarding = false
	arena_o.f2.step_fighter(0.02, Vector2.ZERO, arena_o.f1.position, true)
	arena_o.f2.is_guarding = true
	arena_o.f2.step_fighter(0.02, Vector2.ZERO, arena_o.f1.position, true)
	_check(arena_o.f2.guard_held_time < 0.05, "Re-pressing guard after release must arm fresh Perfect Parry timing")
	if _failed:
		arena_o.queue_free()
		return
	arena_o.queue_free()
	await tree.process_frame
	if _failed: return
	print("OK AI World-Space Geometry, Early Windup Counter-Hit, Thrust Stun & Parry Exploits")

	print("ALL SMOKE TESTS PASSED SUCCESSFULLY!")
	tree.quit(0)
