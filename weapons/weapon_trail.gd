class_name WeaponTrail
extends MeshInstance3D

## Fading ribbon drawn behind a swinging blade. Points are stored in the parent's
## local space (the Hands node), so the trail shows the swing itself and does not
## smear when the player turns the camera.

@export var lifetime: float = 0.13
@export var color: Color = Color(1.0, 1.0, 1.0, 0.5)

var _points: Array = []  # each: [age, base, tip]
var _mesh: ImmediateMesh

func _ready() -> void:
	_mesh = ImmediateMesh.new()
	mesh = _mesh
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.vertex_color_use_as_albedo = true
	material_override = mat

## Add a blade sample (base and tip, in the parent's local space).
func push(base: Vector3, tip: Vector3) -> void:
	_points.push_front([0.0, base, tip])

func clear() -> void:
	_points.clear()
	_mesh.clear_surfaces()

func _process(delta: float) -> void:
	if _points.is_empty():
		return
	for p in _points:
		p[0] += delta
	while not _points.is_empty() and _points[-1][0] >= lifetime:
		_points.pop_back()
	_mesh.clear_surfaces()
	if _points.size() < 2:
		return
	_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	for p in _points:
		var fade: float = 1.0 - p[0] / lifetime
		var c := Color(color.r, color.g, color.b, color.a * fade * fade)
		_mesh.surface_set_color(Color(c.r, c.g, c.b, 0.0))
		_mesh.surface_add_vertex(p[1])
		_mesh.surface_set_color(c)
		_mesh.surface_add_vertex(p[2])
	_mesh.surface_end()
