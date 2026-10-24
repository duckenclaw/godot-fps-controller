class_name GrabController
extends Node

## Physical object manipulation. While the player looks at an object in group
## "movable" and presses "interact", that object is grabbed and held in front of
## the camera (the weapons are hidden for the duration). "interact"/"left_hand"
## drop it; "right_hand" throws it.
##
## Dispatch is duck-typed: objects implementing on_grab/on_hold/on_throw/
## on_release (e.g. the hinged Door) drive their own held behavior. Plain
## RigidBody3D "movable" objects (e.g. a crate) fall back to the default
## "freeze-kinematic + ease toward the hold point" behavior below.

## How quickly a default-held body eases toward the hold point (1 = snap).
const HOLD_FOLLOW_SPEED: float = 18.0
## Forward impulse applied to a default-held body when thrown.
const THROW_FORCE: float = 8.0

var camera_3d: Camera3D
var hold_point: Node3D
var hands: Node3D

var _held: Node3D = null

## Injected from player._ready().
func setup(camera: Camera3D, hold_point_marker: Node3D, hands_node: Node3D) -> void:
	camera_3d = camera
	hold_point = hold_point_marker
	hands = hands_node

func is_holding() -> bool:
	return _held != null

func _physics_process(delta: float) -> void:
	if _held == null:
		return
	if _held.has_method("on_hold"):
		_held.on_hold(self, delta)
	else:
		_default_hold(delta)

# -- Grab / drop / throw ------------------------------------------------------

func grab(obj: Node3D) -> void:
	if obj == null or _held != null:
		return
	_held = obj
	if hands:
		hands.visible = false
	if obj.has_method("on_grab"):
		obj.on_grab(self)
	elif obj is RigidBody3D:
		var body: RigidBody3D = obj
		body.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
		body.freeze = true

func drop() -> void:
	if _held == null:
		return
	var obj: Node3D = _held
	_held = null
	if obj.has_method("on_release"):
		obj.on_release(self)
	elif obj is RigidBody3D:
		(obj as RigidBody3D).freeze = false
	if hands:
		hands.visible = true

func throw() -> void:
	if _held == null:
		return
	var obj: Node3D = _held
	_held = null
	if obj.has_method("on_throw"):
		obj.on_throw(self)
	elif obj is RigidBody3D:
		var body: RigidBody3D = obj
		body.freeze = false
		body.apply_central_impulse(get_camera_forward() * THROW_FORCE * body.mass)
	if hands:
		hands.visible = true

# -- Default crate hold -------------------------------------------------------

## Ease a frozen-kinematic body toward the hold point in front of the camera.
func _default_hold(delta: float) -> void:
	if hold_point == null:
		return
	var t: float = minf(1.0, HOLD_FOLLOW_SPEED * delta)
	_held.global_position = _held.global_position.lerp(hold_point.global_position, t)
	var target_basis: Basis = camera_3d.global_basis if camera_3d else _held.global_basis
	_held.global_basis = _held.global_basis.slerp(target_basis, t).orthonormalized()

# -- Helpers (used by custom grabbables) --------------------------------------

func get_hold_point() -> Vector3:
	return hold_point.global_position if hold_point else Vector3.ZERO

func get_camera_forward() -> Vector3:
	return -camera_3d.global_basis.z if camera_3d else Vector3.FORWARD
