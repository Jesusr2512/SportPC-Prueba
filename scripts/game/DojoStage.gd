class_name DojoStage
extends RefCounted

const SUN_ISLAND_RADIUS := 3.55
const VOLCANIC_BRIDGE_HALF_X := 1.45
const VOLCANIC_BRIDGE_HALF_Z := 4.40
const SKY_SANCTUARY_RADIUS := 3.45


static func build_stage(root: Node3D, stage_type: int = GameConfig.ArenaStage.SUN_ISLAND, compact_radius: float = -1.0) -> Dictionary:
	for ch in root.get_children():
		ch.free()

	var is_volcanic := stage_type == GameConfig.ArenaStage.VOLCANIC_BRIDGE
	var is_sky := stage_type == GameConfig.ArenaStage.SKY_SANCTUARY

	# Animated water / lava / cloud sea plane
	var water := MeshInstance3D.new()
	var wm := PlaneMesh.new()
	wm.size = Vector2(180.0, 180.0)
	wm.subdivide_width = 36
	wm.subdivide_depth = 36
	water.mesh = wm

	var shader := Shader.new()
	var deep_c := "vec3(0.18, 0.04, 0.02)" if is_volcanic else ("vec3(0.42, 0.72, 0.96)" if is_sky else "vec3(0.03, 0.36, 0.66)")
	var shallow_c := "vec3(0.98, 0.36, 0.06)" if is_volcanic else ("vec3(0.86, 0.95, 1.00)" if is_sky else "vec3(0.12, 0.68, 0.92)")
	var emissive_str := "0.65" if is_volcanic else "0.10"
	shader.code = """
shader_type spatial;
render_mode specular_schlick_ggx;
uniform float u_time = 0.0;
void vertex() {
	float w = sin(VERTEX.x * 0.75 + u_time * 1.9) * 0.07 + cos(VERTEX.z * 0.65 - u_time * 1.4) * 0.07;
	VERTEX.y += w;
}
void fragment() {
	float rip = sin(UV.x * 46.0 + u_time * 2.2) * cos(UV.y * 46.0 - u_time * 1.7);
	vec3 col = mix(%s, %s, 0.5 + rip * 0.38);
	ALBEDO = col;
	EMISSION = col * %s;
	ROUGHNESS = 0.16;
	METALLIC = 0.08;
}
""" % [deep_c, shallow_c, emissive_str]
	var water_mat := ShaderMaterial.new()
	water_mat.shader = shader
	water.material_override = water_mat
	water.position = Vector3(0.0, -1.45, 0.0)
	root.add_child(water)

	var rim_mat := StandardMaterial3D.new()
	rim_mat.albedo_color = Color(0.98, 0.42, 0.22) if is_volcanic else Color(0.16, 0.78, 0.96)
	rim_mat.emission_enabled = true
	rim_mat.emission = rim_mat.albedo_color * 0.45

	var platform_pivot := Node3D.new()
	platform_pivot.name = "PlatformPivot"
	root.add_child(platform_pivot)

	var ripple_ring: MeshInstance3D = null
	var rim_mesh: MeshInstance3D = null

	if is_volcanic:
		# Narrow stone & obsidian bridge
		var bridge_len := VOLCANIC_BRIDGE_HALF_Z * 2.0
		var bridge_w := VOLCANIC_BRIDGE_HALF_X * 2.0
		var under := MeshInstance3D.new()
		var um := BoxMesh.new()
		um.size = Vector3(bridge_w + 0.18, 1.35, bridge_len + 0.18)
		under.mesh = um
		var umat := StandardMaterial3D.new()
		umat.albedo_color = Color(0.18, 0.16, 0.20)
		umat.roughness = 0.85
		under.material_override = umat
		under.position = Vector3(0.0, -0.76, 0.0)
		platform_pivot.add_child(under)

		var deck := MeshInstance3D.new()
		var dm := BoxMesh.new()
		dm.size = Vector3(bridge_w, 0.16, bridge_len)
		deck.mesh = dm
		var dmat := StandardMaterial3D.new()
		dmat.albedo_color = Color(0.32, 0.27, 0.25)
		dmat.roughness = 0.58
		deck.material_override = dmat
		deck.position = Vector3(0.0, -0.07, 0.0)
		platform_pivot.add_child(deck)

		# Glowing edge trim bars along left/right bridge edges
		for sx in [-1.0, 1.0]:
			var bar := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = Vector3(0.12, 0.04, bridge_len)
			bar.mesh = bm
			bar.material_override = rim_mat
			bar.position = Vector3(sx * (VOLCANIC_BRIDGE_HALF_X - 0.06), 0.02, 0.0)
			platform_pivot.add_child(bar)

		var c_line := MeshInstance3D.new()
		var clm := BoxMesh.new()
		clm.size = Vector3(bridge_w - 0.1, 0.025, 0.14)
		c_line.mesh = clm
		var clmat := StandardMaterial3D.new()
		clmat.albedo_color = Color(1.0, 0.65, 0.22)
		clmat.emission_enabled = true
		clmat.emission = clmat.albedo_color * 0.7
		c_line.material_override = clmat
		c_line.position = Vector3(0.0, 0.015, 0.0)
		platform_pivot.add_child(c_line)
	else:
		var rad := compact_radius if compact_radius > 0.5 else (SKY_SANCTUARY_RADIUS if is_sky else SUN_ISLAND_RADIUS)

		ripple_ring = MeshInstance3D.new()
		var wrm := TorusMesh.new()
		wrm.inner_radius = rad + 0.18
		wrm.outer_radius = rad + 0.48
		wrm.rings = 48
		ripple_ring.mesh = wrm
		var wrmat := StandardMaterial3D.new()
		wrmat.albedo_color = Color(0.78, 0.96, 1.0, 0.44)
		wrmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		ripple_ring.material_override = wrmat
		ripple_ring.rotation_degrees = Vector3(90, 0, 0)
		ripple_ring.scale = Vector3(1.0, 1.0, 0.12)
		ripple_ring.position = Vector3(0.0, -1.42, 0.0)
		root.add_child(ripple_ring)

		var base := MeshInstance3D.new()
		var bm := CylinderMesh.new()
		bm.top_radius = rad + 0.12
		bm.bottom_radius = rad * (0.62 if is_sky else 0.86)
		bm.height = 1.45
		bm.radial_segments = 48
		base.mesh = bm
		var bmat := StandardMaterial3D.new()
		bmat.albedo_color = Color(0.76, 0.82, 0.90) if is_sky else Color(0.32, 0.36, 0.44)
		bmat.roughness = 0.78
		base.material_override = bmat
		base.position = Vector3(0.0, -0.78, 0.0)
		platform_pivot.add_child(base)

		var plat := MeshInstance3D.new()
		var pm := CylinderMesh.new()
		pm.top_radius = rad
		pm.bottom_radius = rad
		pm.height = 0.14
		pm.radial_segments = 48
		plat.mesh = pm
		var pmat := StandardMaterial3D.new()
		pmat.albedo_color = Color(0.92, 0.94, 0.98) if is_sky else Color(0.89, 0.78, 0.60)
		pmat.roughness = 0.48
		plat.material_override = pmat
		plat.position = Vector3(0.0, -0.07, 0.0)
		platform_pivot.add_child(plat)

		rim_mesh = MeshInstance3D.new()
		var rm := TorusMesh.new()
		rm.inner_radius = rad - 0.28
		rm.outer_radius = rad
		rm.rings = 48
		rim_mesh.mesh = rm
		rim_mesh.material_override = rim_mat
		rim_mesh.rotation_degrees = Vector3(90, 0, 0)
		rim_mesh.scale = Vector3(1.0, 1.0, 0.18)
		rim_mesh.position = Vector3(0.0, 0.012, 0.0)
		platform_pivot.add_child(rim_mesh)

		var center_ring := MeshInstance3D.new()
		var cm := TorusMesh.new()
		cm.inner_radius = 1.32
		cm.outer_radius = 1.42
		cm.rings = 48
		center_ring.mesh = cm
		var cmat := StandardMaterial3D.new()
		cmat.albedo_color = Color(0.18, 0.82, 0.98) if is_sky else Color(0.12, 0.74, 0.92)
		cmat.emission_enabled = true
		cmat.emission = cmat.albedo_color * 0.35
		center_ring.material_override = cmat
		center_ring.rotation_degrees = Vector3(90, 0, 0)
		center_ring.scale = Vector3(1.0, 1.0, 0.15)
		center_ring.position = Vector3(0.0, 0.016, 0.0)
		platform_pivot.add_child(center_ring)

	# 4 Decorative corner lanterns
	var pillar_mat := StandardMaterial3D.new()
	pillar_mat.albedo_color = Color(0.22, 0.24, 0.30)
	var lantern_mat := StandardMaterial3D.new()
	lantern_mat.albedo_color = Color(1.0, 0.75, 0.35) if is_volcanic else Color(1.0, 0.92, 0.58)
	lantern_mat.emission_enabled = true
	lantern_mat.emission = lantern_mat.albedo_color * 1.45

	for k in 4:
		var ang := PI * 0.25 + k * PI * 0.5
		var dist := 5.2
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
		root.add_child(post)

		var lamp := MeshInstance3D.new()
		var lm := BoxMesh.new()
		lm.size = Vector3(0.32, 0.38, 0.32)
		lamp.mesh = lm
		lamp.material_override = lantern_mat
		lamp.position = Vector3(px, 1.0, pz)
		root.add_child(lamp)

	# Distant landscape silhouettes
	var island_mat := StandardMaterial3D.new()
	island_mat.albedo_color = Color(0.26, 0.16, 0.14) if is_volcanic else (Color(0.84, 0.92, 1.0) if is_sky else Color(0.24, 0.52, 0.44))
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
		root.add_child(isl)

	return {
		"water_mat": water_mat,
		"ripple_ring": ripple_ring,
		"platform_pivot": platform_pivot,
		"rim_mat": rim_mat,
		"rim_mesh": rim_mesh
	}


static func is_out_of_bounds(pos_xz: Vector2, stage_type: int, radius_override: float = -1.0) -> bool:
	if stage_type == GameConfig.ArenaStage.VOLCANIC_BRIDGE:
		return absf(pos_xz.x) > VOLCANIC_BRIDGE_HALF_X or absf(pos_xz.y) > VOLCANIC_BRIDGE_HALF_Z
	var rad := radius_override if radius_override > 0.5 else (SKY_SANCTUARY_RADIUS if stage_type == GameConfig.ArenaStage.SKY_SANCTUARY else SUN_ISLAND_RADIUS)
	return pos_xz.length() > rad


static func get_edge_ratio(pos_xz: Vector2, stage_type: int, radius_override: float = -1.0) -> float:
	if stage_type == GameConfig.ArenaStage.VOLCANIC_BRIDGE:
		return clampf(maxf(absf(pos_xz.x) / VOLCANIC_BRIDGE_HALF_X, absf(pos_xz.y) / VOLCANIC_BRIDGE_HALF_Z), 0.0, 1.0)
	var rad := radius_override if radius_override > 0.5 else (SKY_SANCTUARY_RADIUS if stage_type == GameConfig.ArenaStage.SKY_SANCTUARY else SUN_ISLAND_RADIUS)
	return clampf(pos_xz.length() / rad, 0.0, 1.0)
