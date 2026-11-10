class_name CombatFX
extends RefCounted

## One-shot impact particles (sparks / blood puffs). CPU particles, so they work
## on every renderer including GL Compatibility.

static func burst(parent: Node, pos: Vector3, normal: Vector3, color: Color,
		amount: int = 14, speed: float = 5.0, size: float = 0.035) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	var p := CPUParticles3D.new()
	p.emitting = false
	p.one_shot = true
	p.explosiveness = 1.0
	p.amount = amount
	p.lifetime = 0.4
	p.direction = normal if normal.length_squared() > 0.001 else Vector3.UP
	p.spread = 60.0
	p.initial_velocity_min = speed * 0.35
	p.initial_velocity_max = speed
	p.gravity = Vector3(0.0, -12.0, 0.0)
	p.scale_amount_min = 0.4
	p.scale_amount_max = 1.0
	var ramp := Gradient.new()
	ramp.set_color(0, color)
	ramp.set_color(1, Color(color.r, color.g, color.b, 0.0))
	p.color_ramp = ramp
	var quad := QuadMesh.new()
	quad.size = Vector2(size, size)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.vertex_color_use_as_albedo = true
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.billboard_keep_scale = true
	quad.material = mat
	p.mesh = quad
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(p)
	p.global_position = pos
	p.finished.connect(p.queue_free)
	p.emitting = true
