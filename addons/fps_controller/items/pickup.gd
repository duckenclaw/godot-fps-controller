class_name Pickup
extends RigidBody3D

## World representation of a pickupable item. Add to group "interactable".

@export var item: ItemResource
@export var count: int = 1

var _model_instance: Node3D

func _ready() -> void:
	add_to_group(&"interactable")
	_spawn_model()

func _spawn_model() -> void:
	if _model_instance:
		_model_instance.queue_free()
		_model_instance = null
	if item == null or item.model == null:
		return
	var inst: Node = item.model.instantiate()
	if inst is Node3D:
		_model_instance = inst
		add_child(_model_instance)

## Called by the player's try_interact dispatch.
func interact() -> void:
	var player: Node = get_tree().get_first_node_in_group(&"player")
	if player == null or item == null:
		return
	var inv: Inventory = player.get("inventory") if player.has_method("get") else null
	if inv == null and player.has_node("Inventory"):
		inv = player.get_node("Inventory")
	if inv == null:
		return
	var leftover: int = inv.try_pickup(item, count)
	if leftover == count:
		return  # fully blocked; pickup_failed signal already fired
	if leftover > 0:
		count = leftover
		return
	queue_free()

## Spawn a pickup in the world (used when throwing from inventory).
static func spawn(scene: PackedScene, item: ItemResource, count: int, world: Node, global_origin: Vector3, velocity: Vector3) -> Pickup:
	if scene == null or item == null or count <= 0:
		return null
	var p: Pickup = scene.instantiate()
	p.item = item
	p.count = count
	world.add_child(p)
	p.global_position = global_origin
	p.linear_velocity = velocity
	return p
