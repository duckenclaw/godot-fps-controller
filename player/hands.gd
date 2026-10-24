class_name Hands
extends Node3D

## Hands manager — manages both left and right hands, exposes resource-aware
## equip helpers used by the player, and applies inertia so the hands trail
## the camera's rotation with a slight delay.

# Sway tuning: how strongly camera rotation deflects the hands, the maximum
# deflection, how fast the hands settle back, and positional follow amount.
const SWAY_RESPONSE: float = 0.5
const SWAY_MAX: float = deg_to_rad(4.0)
const SWAY_RECOVER_SPEED: float = 9.0
const SWAY_POSITION_FACTOR: float = 0.15

@onready var right_hand: Hand = $RightHand
@onready var left_hand: Hand = $LeftHand

var _base_position: Vector3
var _last_cam_quat: Quaternion
var _sway: Vector2 = Vector2.ZERO  # x = pitch offset, y = yaw offset

func _ready() -> void:
	_base_position = position
	var cam: Node3D = get_parent() as Node3D
	if cam:
		_last_cam_quat = cam.global_basis.get_rotation_quaternion()

## Inject player/inventory references so hands can aim and consume ammo.
func setup(player: Node3D, inventory: Inventory) -> void:
	for hand in [right_hand, left_hand]:
		if hand:
			hand.player = player
			hand.inventory = inventory

func _process(delta: float) -> void:
	_update_sway(delta)

## Hands are parented to the camera, so a zero offset means perfectly locked.
## Track the camera's per-frame rotation and deflect the opposite way, then
## ease back — this makes the hands follow the camera with a slight delay.
func _update_sway(delta: float) -> void:
	var cam: Node3D = get_parent() as Node3D
	if cam == null:
		return
	var q: Quaternion = cam.global_basis.get_rotation_quaternion()
	var rel: Vector3 = (_last_cam_quat.inverse() * q).get_euler()
	_last_cam_quat = q

	_sway.x = clampf(_sway.x - rel.x * SWAY_RESPONSE, -SWAY_MAX, SWAY_MAX)
	_sway.y = clampf(_sway.y - rel.y * SWAY_RESPONSE, -SWAY_MAX, SWAY_MAX)
	_sway = _sway.lerp(Vector2.ZERO, minf(1.0, SWAY_RECOVER_SPEED * delta))

	rotation = Vector3(_sway.x, _sway.y, 0.0)
	position = _base_position + Vector3(-_sway.y, _sway.x, 0.0) * SWAY_POSITION_FACTOR

## Trigger an attack with the left hand.
func use_left_hand() -> void:
	if left_hand:
		left_hand.attack()

## Trigger an attack with the right hand.
func use_right_hand() -> void:
	if right_hand:
		right_hand.attack()

## Reload the right hand's ranged weapon (if any).
func reload_right_hand() -> void:
	if right_hand:
		right_hand.reload()

## Equip an ItemResource to the right hand (spawns its model).
func equip_right_hand(item_res: ItemResource) -> void:
	if right_hand:
		right_hand.equip_resource(item_res)

## Equip an ItemResource to the left hand.
func equip_left_hand(item_res: ItemResource) -> void:
	if left_hand:
		left_hand.equip_resource(item_res)

func unequip_right_hand() -> void:
	if right_hand:
		right_hand.unequip_item()

func unequip_left_hand() -> void:
	if left_hand:
		left_hand.unequip_item()

func get_right_hand() -> Hand:
	return right_hand

func get_left_hand() -> Hand:
	return left_hand
