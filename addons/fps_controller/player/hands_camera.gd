extends Camera3D

## Overlay camera living in the hands SubViewport. Renders only the hands
## render layer (cull_mask = 2) and mirrors the main camera's transform and
## FOV every frame so head bob, tilt, and FOV kicks stay in sync.

@export var source_camera_path: NodePath

var _source: Camera3D

func _ready() -> void:
	_source = get_node_or_null(source_camera_path) as Camera3D
	# Run after the camera controller so we copy this frame's final transform.
	process_priority = 100

func _process(_delta: float) -> void:
	if _source:
		global_transform = _source.global_transform
		fov = _source.fov
