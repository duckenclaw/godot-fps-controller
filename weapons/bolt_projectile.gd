class_name BoltProjectile
extends Node3D

## Crossbow bolt. Flies in a straight line (raycast-stepped to avoid
## tunneling), damages "enemy"/"destructible" targets on impact, then sticks
## in place. Old bolts are culled when too many exist or when too far away.

const MAX_PROJECTILES: int = 24
const MAX_DISTANCE: float = 100.0

var damage: float = 0.0
var speed: float = 40.0

var _velocity: Vector3 = Vector3.ZERO
var _origin: Vector3 = Vector3.ZERO
var _stuck: bool = false
var _shooter: Node3D = null

func _ready() -> void:
	add_to_group(&"projectiles")
	_cull_oldest()

## Place the bolt at `origin` flying along `direction`. `shooter` is excluded
## from collision and used as the reference point for far-away cleanup.
func launch(origin: Vector3, direction: Vector3, shooter: Node3D = null) -> void:
	global_position = origin
	_origin = origin
	_shooter = shooter
	var dir: Vector3 = direction.normalized()
	_velocity = dir * speed
	var up: Vector3 = Vector3.UP if absf(dir.dot(Vector3.UP)) < 0.99 else Vector3.RIGHT
	look_at(origin + dir, up)

func _physics_process(delta: float) -> void:
	if _stuck:
		# Stuck bolts linger; free them once the shooter is far away.
		if _shooter and is_instance_valid(_shooter) \
				and global_position.distance_to(_shooter.global_position) > MAX_DISTANCE:
			queue_free()
		return

	if global_position.distance_to(_origin) > MAX_DISTANCE:
		queue_free()
		return

	var next: Vector3 = global_position + _velocity * delta
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(global_position, next)
	query.collide_with_areas = false
	if _shooter is CollisionObject3D:
		query.exclude = [_shooter.get_rid()]
	var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		global_position = next
		return

	var collider: Node = hit.get("collider")
	if collider and (collider.is_in_group(&"enemy") or collider.is_in_group(&"destructible")):
		if collider.has_method("take_damage"):
			collider.take_damage(damage, _shooter)
	global_position = hit.get("position")
	_stuck = true

func _cull_oldest() -> void:
	var projectiles: Array[Node] = get_tree().get_nodes_in_group(&"projectiles")
	var excess: int = projectiles.size() - MAX_PROJECTILES
	for i in maxi(0, excess):
		if projectiles[i] != self:
			projectiles[i].queue_free()
