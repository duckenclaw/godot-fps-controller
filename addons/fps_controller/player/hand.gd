class_name Hand
extends Node3D

## Hand controller. Holds an item and performs attacks with it:
## - Melee: plays the weapon's attack animation on this hand's AnimationPlayer
##   (e.g. "right_slash") and enables the MeleeHitboxArea3D for the duration
##   of the swing, damaging anything in the "enemy"/"destructible" groups.
## - Ranged: plays the weapon's attack animation (e.g. "shoot") and fires a
##   projectile tilted off-aim according to the weapon's accuracy.
##
## Note: only the RightHand has authored animations and a melee hitbox in
## player.tscn. Left-hand melee attacks are inert; left-hand ranged weapons
## fire without an animation.

signal hit_landed(target: Node, damage: float)
signal staggered()

@export var is_right_hand: bool = true

const BOLT_SCENE: PackedScene = preload("res://addons/fps_controller/weapons/bolt_projectile.tscn")
const IDLE_ANIM: StringName = &"idle"
## Visual layer the hands viewport camera renders (1 << 1).
const HANDS_RENDER_LAYER: int = 2
## Maximum projectile deviation (radians) at accuracy 0.0.
const MAX_SPREAD_RAD: float = deg_to_rad(20.0)
const RELOAD_DELAY: float = 1.0

# Injected by Hands so ranged weapons can consume ammo and aim with the camera.
# Untyped: the player script has no class_name, and we access its camera_3d.
var player
var inventory: Inventory

var current_item_resource: ItemResource

# The instantiated weapon model (a child of this hand, so it follows the
# hand's attack animations — the animation tracks target the hand node itself).
var equipped_item: Node3D = null

@onready var anim_player: AnimationPlayer = get_node_or_null(
	"RightHandAnimationPlayer" if is_right_hand else "LeftHandAnimationPlayer")
@onready var melee_hitbox: Area3D = get_node_or_null("MeleeHitboxArea3D")

# Per-swing state.
var _attacking: bool = false
var _hit_bodies: Array = []

# Ranged state.
var _clip: int = 0

func _ready() -> void:
	if melee_hitbox:
		melee_hitbox.monitoring = false
		melee_hitbox.monitorable = false
		melee_hitbox.collision_layer = 0
		melee_hitbox.collision_mask = 0xFFFFFFFF
		melee_hitbox.body_entered.connect(_on_body_entered)
		melee_hitbox.area_entered.connect(_on_area_entered)
	if anim_player:
		anim_player.animation_finished.connect(_on_animation_finished)

# -- Equip / unequip ----------------------------------------------------------

## Equip an item resource. Spawns the model as a child of this hand.
func equip_resource(item_res: ItemResource) -> void:
	unequip_item()
	current_item_resource = item_res
	if item_res == null:
		return
	if item_res.model:
		var inst: Node = item_res.model.instantiate()
		if inst is Node3D:
			equipped_item = inst
			add_child(equipped_item)
			equipped_item.position = Vector3.ZERO
			equipped_item.rotation = Vector3.ZERO
			_set_render_layer_recursive(equipped_item, HANDS_RENDER_LAYER)
	if item_res.is_melee():
		_resize_hitbox(item_res.range)
	elif item_res.is_ranged():
		_clip = 0
		reload()

## Legacy entry point — accepts a pre-instantiated Node3D (no weapon stats).
func equip_item(item: Node3D) -> void:
	unequip_item()
	current_item_resource = null
	if item == null:
		return
	equipped_item = item
	add_child(equipped_item)
	equipped_item.position = Vector3.ZERO
	equipped_item.rotation = Vector3.ZERO
	_set_render_layer_recursive(equipped_item, HANDS_RENDER_LAYER)

func unequip_item() -> void:
	_end_attack()
	if equipped_item:
		if equipped_item.get_parent() == self:
			remove_child(equipped_item)
		equipped_item.queue_free()
		equipped_item = null
	current_item_resource = null
	_clip = 0

func has_item() -> bool:
	return equipped_item != null

func get_equipped_item() -> Node3D:
	return equipped_item

## Mark every visual under `node` as hands-layer so only the overlay
## hands camera draws it (keeps it on top of world geometry).
func _set_render_layer_recursive(node: Node, layer: int) -> void:
	if node is VisualInstance3D:
		node.layers = layer
	for child in node.get_children():
		_set_render_layer_recursive(child, layer)

## Stretch the melee hitbox (and its debug mesh) to the weapon's reach.
func _resize_hitbox(reach: float) -> void:
	if melee_hitbox == null:
		return
	var col: CollisionShape3D = melee_hitbox.get_node_or_null("CollisionShape3D")
	if col and col.shape is BoxShape3D:
		col.shape.size.y = reach
		col.position.y = reach / 2.0
	var mesh_inst: MeshInstance3D = melee_hitbox.get_node_or_null("MeshInstance3D")
	if mesh_inst:
		mesh_inst.position.y = reach / 2.0
		if mesh_inst.mesh is BoxMesh:
			mesh_inst.mesh.size.y = reach

# -- Attack -------------------------------------------------------------------

func attack() -> void:
	if current_item_resource:
		if current_item_resource.is_melee():
			_begin_melee_attack()
		elif current_item_resource.is_ranged():
			_begin_ranged_attack()
	elif equipped_item and equipped_item.has_method("attack"):
		equipped_item.attack()

func _begin_melee_attack() -> void:
	if _attacking:
		return
	# Left hand has no authored attack animations or hitbox.
	if anim_player == null or melee_hitbox == null:
		return
	var anim: StringName = current_item_resource.attack_animation
	if anim == &"" or not anim_player.has_animation(anim):
		return
	_attacking = true
	_hit_bodies.clear()
	anim_player.speed_scale = maxf(0.1, current_item_resource.speed)
	melee_hitbox.monitoring = true
	anim_player.play(anim)

func _begin_ranged_attack() -> void:
	if _attacking:
		return
	if _clip <= 0:
		reload()
		if _clip <= 0:
			return  # no ammo — dry fire
	_clip -= 1
	_spawn_projectile()
	var anim: StringName = current_item_resource.attack_animation
	if anim_player and anim != &"" and anim_player.has_animation(anim):
		_attacking = true
		anim_player.speed_scale = maxf(0.1, current_item_resource.speed)
		anim_player.play(anim)
	if _clip <= 0:
		_schedule_reload()

func _on_animation_finished(anim_name: StringName) -> void:
	if anim_name == IDLE_ANIM:
		return
	_end_attack()

## Reset swing state and return to the idle loop.
func _end_attack() -> void:
	_attacking = false
	_hit_bodies.clear()
	if melee_hitbox:
		melee_hitbox.monitoring = false
	if anim_player:
		anim_player.speed_scale = 1.0
		if anim_player.has_animation(IDLE_ANIM):
			anim_player.play(IDLE_ANIM)
		else:
			anim_player.stop()

# -- Melee hit detection --------------------------------------------------------

func _on_body_entered(body: Node) -> void:
	_handle_hit(body)

func _on_area_entered(area: Area3D) -> void:
	_handle_hit(area)

func _handle_hit(target: Node) -> void:
	if not _attacking or target == null or target in _hit_bodies:
		return
	if target.is_in_group(&"player"):
		return
	_hit_bodies.append(target)

	var dmg: float = current_item_resource.damage if current_item_resource else 0.0
	if target.is_in_group(&"enemy") or target.is_in_group(&"destructible"):
		if target.has_method("take_damage"):
			target.take_damage(dmg, owner)
		hit_landed.emit(target, dmg)
	else:
		# Hit world geometry: end the swing early.
		_end_attack()
		staggered.emit()

# -- Ranged -------------------------------------------------------------------

## Refill the clip from the inventory's ammo stock.
func reload() -> void:
	var item: ItemResource = current_item_resource
	if item == null or not item.is_ranged() or inventory == null:
		return
	var needed: int = item.clip_size - _clip
	if needed <= 0:
		return
	_clip += inventory.consume_item(item.ammo_type, needed)

func _schedule_reload() -> void:
	var item: ItemResource = current_item_resource
	get_tree().create_timer(RELOAD_DELAY).timeout.connect(
		func() -> void:
			if current_item_resource == item:
				reload())

func _spawn_projectile() -> void:
	var item: ItemResource = current_item_resource
	var dir: Vector3 = -global_basis.z
	var cam: Camera3D = player.camera_3d if player else null
	if cam:
		dir = -cam.global_basis.z
	dir = _apply_spread(dir.normalized(), item.accuracy)
	var origin: Vector3 = equipped_item.global_position if equipped_item else global_position
	var bolt: BoltProjectile = BOLT_SCENE.instantiate()
	bolt.damage = item.damage
	get_tree().current_scene.add_child(bolt)
	bolt.launch(origin, dir, player)

## Tilt `dir` by a random angle within the accuracy cone
## (accuracy 1.0 = dead-on, lower = wider cone).
func _apply_spread(dir: Vector3, accuracy: float) -> Vector3:
	var max_angle: float = (1.0 - clampf(accuracy, 0.0, 1.0)) * MAX_SPREAD_RAD
	if max_angle <= 0.0:
		return dir
	var angle: float = max_angle * sqrt(randf())
	var ortho: Vector3 = dir.cross(Vector3.UP)
	if ortho.length_squared() < 0.001:
		ortho = dir.cross(Vector3.RIGHT)
	var tilt_axis: Vector3 = ortho.normalized().rotated(dir, randf() * TAU)
	return dir.rotated(tilt_axis, angle).normalized()
