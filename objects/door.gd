class_name Door
extends RigidBody3D

## A hinge-mounted door that uses the player's grab mechanic. It is in group
## "movable" and implements the grab interface so the GrabController drives it
## through its HingeJoint3D instead of the default "hold in front of camera"
## behavior:
##   - on_hold: a soft spring pulls the door's handle toward the camera hold
##     point, so walking into the held door slowly swings it open on the hinge.
##   - on_throw ("right_hand"): a strong impulse at the handle slams it open.

## How heavy the door is. Affects how far a throw swings it (heavier = less);
## the held follow-speed stays responsive regardless (see on_hold).
@export var weight: float = 6.0
## Maximum swing each way from closed, in degrees. The door cannot rotate past
## ±max_open_angle (applied to the child HingeJoint3D and enforced hard in code).
@export_range(0.0, 180.0) var max_open_angle: float = 90.0

@export_group("Grab Tuning")
## Spring stiffness pulling the handle toward the camera hold point while held.
@export var spring_strength: float = 18.0
## Velocity damping while held (keeps the swing from oscillating).
@export var grab_damp: float = 5.0
## Impulse applied at the handle when the door is thrown open.
@export var throw_impulse: float = 10.0
## Local position of the grab handle, near the door's outer (free) edge.
@export var handle_offset: Vector3 = Vector3(1.55, 1.0, 0.0)

# The door's closed-pose orientation, captured at spawn so the swing can be
# clamped relative to however the scene was placed (any yaw).
var _rest_basis: Basis

func _ready() -> void:
	mass = weight
	_rest_basis = global_transform.basis
	_apply_swing_limit()

## Push the configured swing range onto the child hinge joint (limits are in
## degrees). The joint limit is "soft" (it can be crept past under sustained
## force), so it only provides bounce/feel — the hard stop is in _integrate_forces.
func _apply_swing_limit() -> void:
	var hinge: HingeJoint3D = get_node_or_null("HingeJoint3D") as HingeJoint3D
	if hinge:
		hinge.set("angular_limit/enable", true)
		hinge.set("angular_limit/lower", -max_open_angle)
		hinge.set("angular_limit/upper", max_open_angle)

## Hard-clamp the swing. The door only rotates about its vertical hinge, so the
## open angle is the Y rotation relative to the closed pose (_rest_basis). We
## clamp it to ±max_open_angle and kill any angular velocity still pushing past
## the stop, so the door stops regardless of how hard on_hold/on_throw push it.
func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	var limit: float = deg_to_rad(max_open_angle)
	var angle: float = (_rest_basis.inverse() * state.transform.basis).get_euler().y
	if angle > limit or angle < -limit:
		var clamped: float = clampf(angle, -limit, limit)
		var xform: Transform3D = state.transform
		xform.basis = _rest_basis * Basis.from_euler(Vector3(0.0, clamped, 0.0))
		state.transform = xform
		var av: Vector3 = state.angular_velocity
		if (angle > limit and av.y > 0.0) or (angle < -limit and av.y < 0.0):
			av.y = 0.0
			state.angular_velocity = av

func on_grab(_controller: Node) -> void:
	sleeping = false

func on_hold(controller: Node, _delta: float) -> void:
	var handle: Vector3 = to_global(handle_offset)
	var to_target: Vector3 = controller.get_hold_point() - handle
	# Velocity at the handle = linear + angular cross radius.
	var radius: Vector3 = handle - global_position
	var handle_velocity: Vector3 = linear_velocity + angular_velocity.cross(radius)
	# Scale by mass so the door follows the hand at a weight-independent rate
	# (force = mass * acceleration), keeping a heavy door from feeling sluggish.
	var accel: Vector3 = to_target * spring_strength - handle_velocity * grab_damp
	apply_force(accel * mass, radius)

func on_throw(controller: Node) -> void:
	# Absolute impulse (not mass-scaled): heavier doors swing open less.
	var handle: Vector3 = to_global(handle_offset)
	apply_impulse(controller.get_camera_forward() * throw_impulse, handle - global_position)

func on_release(_controller: Node) -> void:
	pass
