extends Camera3D

## Overlay camera living in the hands SubViewport. Renders only the hands
## render layer (cull_mask = 2) and mirrors the main camera's transform every
## frame so head bob, tilt and view punch stay in sync.
##
## The viewmodel keeps its own field of view: the arm animations were authored
## for a 75 degree vertical FOV, and locking it stops speed-based FOV kicks and
## the player's FOV setting from stretching or cropping the arms.

@export var source_camera_path: NodePath
## Vertical FOV used for the arms. Set to 0 to follow the main camera instead.
@export var viewmodel_fov: float = 75.0

var _source: Camera3D

func _ready() -> void:
	_source = get_node_or_null(source_camera_path) as Camera3D
	# Run after the camera controller and Hands so we copy this frame's final transform.
	process_priority = 100

func _process(_delta: float) -> void:
	if _source:
		global_transform = _source.global_transform
		fov = viewmodel_fov if viewmodel_fov > 0.0 else _source.fov
