extends Node

func _ready() -> void:
	call_deferred("_run_checks")


func _run_checks() -> void:
	var tree := get_tree()
	await tree.process_frame

	# 1. Check Autoloads
	var hub = tree.root.get_node_or_null("MotionHub")
	assert(hub != null, "MotionHub autoload missing")
	var sfx = tree.root.get_node_or_null("SoundFX")
	assert(sfx != null, "SoundFX autoload missing")
	assert(hub.mobile_server.is_running, "MobileBridgeServer failed to listen")
	print("OK MobileBridgeServer running on port %d (%s)" % [hub.mobile_server.active_port, hub.mobile_server.get_primary_url()])

	# 2. MotionFusion tilted-gravity recenter & anti-cross-coupling checks
	var mf := MotionFusion.new()
	var tilted_grav := Vector3(0.0, -7.0, 6.8)
	for i in 10:
		mf.update(0.016, Vector3(0.01, -0.01, 0.0), tilted_grav, tilted_grav)
	assert(not mf.just_swung, "Should not swing while stationary")
	mf.recenter()
	assert(absf(mf.pitch_rad) < 0.001 and absf(mf.yaw_rad) < 0.001 and absf(mf.blade_roll_rad) < 0.001, "Recenter must zero tilted angles")
	assert(mf.orientation.is_equal_approx(Quaternion.IDENTITY), "Recenter must reset orientation")

	# Turning horizontally (yaw) while tilted must NOT couple into blade_roll_rad
	for i in 12:
		mf.update(0.016, Vector3(0.0, -2.5, 0.0), tilted_grav, tilted_grav)
	assert(absf(mf.blade_roll_rad) < 0.05, "Yaw turn on tilted grip must not leak into roll")

	# Swing detection check
	var swung := false
	for i in 8:
		mf.update(0.016, Vector3(0.0, -9.5, 0.0), Vector3(0, -9.81, 0), Vector3(0, -9.81, 0))
		if mf.just_swung:
			swung = true
	assert(swung, "Should detect horizontal swing")
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
	assert(aligned_swung, "Should detect forward pitch cut when holding blade horizontal")
	assert(absf(mf.last_slash_dir.x) > 0.85, "Horizontal blade pitch swing must execute horizontally, got %s" % str(mf.last_slash_dir))
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
	assert(lunge_swung, "Forward thrust must trigger attack even if device linear_accel fallback relies on accel magnitude/jerk")
	assert(mf.last_swing_source == "Empuje frontal", "Expected forward thrust source, got %s" % mf.last_swing_source)
	mf.recenter()
	print("OK MotionFusion tilted recenter / blade-aligned slash / forward lunge")

	# 3. MainMenu scene load & step
	var menu_scene: PackedScene = load("res://scenes/MainMenu.tscn")
	var menu := menu_scene.instantiate()
	tree.root.add_child(menu)
	await tree.process_frame
	menu.queue_free()
	await tree.process_frame
	print("OK MainMenu instantiated")

	# 4. CalibrationRoom animated coach & live diag step check
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
	print("OK CalibrationRoom animated coach instantiated and stepped")

	# 5. ChambaraArena 1P entry calibration, active parry, auto-guard, and guard break checks
	GameConfig.match_mode = "1p"
	var arena_scene: PackedScene = load("res://scenes/ChambaraArena.tscn")
	var arena = arena_scene.instantiate()
	tree.root.add_child(arena)
	await tree.process_frame

	# Verify entry calibration auto-completes on steady controller
	arena.begin_entry_calibration(true)
	assert(arena.phase == arena.MatchPhase.CALIBRATE_ENTRY, "Should enter CALIBRATE_ENTRY phase")
	hub.slots[0].fusion.angular_speed = 0.05
	for i in 35:
		arena._process(0.02)
	assert(arena.phase == arena.MatchPhase.INTRO, "Steady hold should finish entry calibration into INTRO")
	print("OK Chambara entry calibration auto-center")

	# Setup fighting state for 1P duel
	arena.phase = arena.MatchPhase.FIGHTING
	arena.f1.position = Vector3(0.0, 0.0, 0.9)
	arena.f2.position = Vector3(0.0, 0.0, -0.9)

	# Test A: 1P Perpendicular parry (active guard) stuns 1.65s & charges defender
	arena.f2.state = AvatarFighter.State.NORMAL
	arena.f2.is_guarding = true
	arena.f2.is_charged = false
	arena.f2.blade_roll_rad = 0.0
	arena.f1.state = AvatarFighter.State.NORMAL
	arena.f1.trigger_slash(Vector2(1.0, 0.0), 1.0)
	assert(arena.f1.state == AvatarFighter.State.STUNNED, "Perpendicular active parry should stun attacker")
	assert(arena.f1.stun_timer > 1.2, "Perpendicular parry must stun for Switch Sports duration (~1.65s)")
	assert(arena.f2.is_charged, "Perpendicular parry must charge defender for next counter-strike")
	print("OK Chambara perpendicular active parry & charge")

	# Test B: 1P Diagonal visual cross parry (AI f2 slashes (0.7,0.7) -> visually '/'; f1 blocks '-' diagonal (-PI/4) -> visually '\')
	arena.f1.reset_for_round(Vector3(0.0, 0.0, 0.76), Vector2(0.0, -1.0))
	arena.f2.reset_for_round(Vector3(0.0, 0.0, -0.76), Vector2(0.0, 1.0))
	arena.f1.is_guarding = true
	arena.f1.blade_roll_rad = -PI * 0.25
	arena.f2.trigger_slash(Vector2(0.7, 0.7), 1.0)
	assert(arena.f2.state == AvatarFighter.State.STUNNED, "Visual diagonal X cross must parry opposing AI slash")
	print("OK Chambara 1P diagonal visual-cross parry")

	# Test C: Zero-button Passive Auto-Guard when holding blade steady at perpendicular angle
	arena.f1.reset_for_round(Vector3(0.0, 0.0, 0.76), Vector2(0.0, -1.0))
	arena.f2.reset_for_round(Vector3(0.0, 0.0, -0.76), Vector2(0.0, 1.0))
	arena.f1.is_guarding = false
	arena.f1.state = AvatarFighter.State.NORMAL
	arena.f1.blade_roll_rad = 0.0
	hub.slots[0].fusion.is_steady = true
	arena.f2.trigger_slash(Vector2(1.0, 0.0), 1.0)
	assert(arena.f2.state == AvatarFighter.State.STUNNED, "Zero-button steady perpendicular posture should auto-parry")
	print("OK Chambara zero-button auto-guard parry")

	# Test D: Parallel guard overcome (pushes defender without self-stun stars)
	arena.f1.reset_for_round(Vector3(0.0, 0.0, 0.76), Vector2(0.0, -1.0))
	arena.f2.reset_for_round(Vector3(0.0, 0.0, -0.76), Vector2(0.0, 1.0))
	arena.f2.is_guarding = true
	arena.f2.blade_roll_rad = PI * 0.5
	arena.f1.trigger_slash(Vector2(1.0, 0.0), 1.0)
	assert(arena.f2.guard_break_timer > 0.0, "Parallel slash should trigger guard_break_timer")
	assert(arena.f2.state == AvatarFighter.State.NORMAL, "Parallel guard overcome must not freeze defender in stun stars")
	assert(arena.f2.velocity_xz.y < -1.5, "Guard overcome should knock defender backward along -Z")
	print("OK Chambara parallel guard overcome")

	# Test E: Stun multi-hit combo & charged strike
	arena.f1.reset_for_round(Vector3(0.0, 0.0, 0.76), Vector2(0.0, -1.0))
	arena.f2.reset_for_round(Vector3(0.0, 0.0, -0.76), Vector2(0.0, 1.0))
	arena.f1.is_charged = true
	arena.f2.apply_stun(1.65)
	arena.f1.trigger_slash(Vector2(1.0, 0.0), 1.0)
	assert(not arena.f1.is_charged, "Charged strike must consume is_charged")
	assert(arena.f2.state == AvatarFighter.State.STUNNED, "Hit 1 during stun must allow fast combo follow-up")
	assert(arena.f2.stun_timer > 1.0 and arena.f2.stun_timer < 1.3, "Hit 1 should shave 0.45s off 1.65s stun, got %f" % arena.f2.stun_timer)
	assert(arena.f2.velocity_xz.y < -6.0, "Charged hit should deal heavy 1.65x knockback along -Z")
	arena.f1.state = AvatarFighter.State.NORMAL
	arena.f1.trigger_slash(Vector2(0.0, 1.0), 1.0)
	assert(arena.f2.state == AvatarFighter.State.STUNNED and arena.f2.stun_timer < 0.85, "Hit 2 should continue stun combo")
	print("OK Chambara stun combo & charged strike")

	# Test F: Sword Clash (simultaneous swing / late windup)
	arena.f1.reset_for_round(Vector3(0.0, 0.0, 0.76), Vector2(0.0, -1.0))
	arena.f2.reset_for_round(Vector3(0.0, 0.0, -0.76), Vector2(0.0, 1.0))
	arena.f2.start_windup(Vector2(1.0, 0.0), 0.15)
	arena.f1.trigger_slash(Vector2(0.0, 1.0), 1.0)
	assert(arena.f1.state == AvatarFighter.State.NORMAL and arena.f2.state == AvatarFighter.State.NORMAL, "Sword clash must cancel both attacks")
	assert(arena.f1.velocity_xz.y > 0.5 and arena.f2.velocity_xz.y < -0.5, "Sword clash must push both fighters slightly apart")
	print("OK Chambara sword clash")

	arena.queue_free()
	await tree.process_frame
	print("ALL SMOKE TESTS PASSED SUCCESSFULLY!")
	tree.quit(0)
