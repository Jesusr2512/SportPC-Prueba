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

	print("ALL SMOKE TESTS PASSED SUCCESSFULLY!")
	tree.quit(0)
