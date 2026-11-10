class_name TrainingDummy
extends StaticBody3D

## A stand-in enemy for trying out melee combat. It takes damage through a Health
## component, flashes and rocks when struck, and (optionally) swings back with a
## clearly telegraphed blow so blocking and parrying can be practised:
## the club rises and the dummy glows, then the hit lands.

@export var attacks: bool = true
@export var attack_damage: float = 15.0
@export var attack_range: float = 2.6
@export var attack_interval: float = 2.2
@export var windup_time: float = 0.6
@export var respawn_time: float = 3.0

const BASE_COLOR: Color = Color(0.72, 0.6, 0.42)
const HIT_COLOR: Color = Color(1.0, 0.25, 0.2)
const STUN_COLOR: Color = Color(0.35, 0.6, 1.0)
const WARN_COLOR: Color = Color(1.0, 0.75, 0.2)

@onready var health: Health = $Health
@onready var body: MeshInstance3D = $Body
@onready var arm: Node3D = $ArmPivot
@onready var shape: CollisionShape3D = $CollisionShape3D

var _mat: StandardMaterial3D
var _flash: float = 0.0
var _flash_color: Color = HIT_COLOR
var _rock: Vector3 = Vector3.ZERO
var _cooldown: float = 1.5
var _windup: float = -1.0
var _stun: float = 0.0
var _swing: float = 0.0
var _dead: bool = false
var _time: float = 0.0

func _ready() -> void:
	add_to_group(&"enemy")
	_mat = StandardMaterial3D.new()
	_mat.albedo_color = BASE_COLOR
	body.material_override = _mat
	health.died.connect(_on_died)

func take_damage(amount: float, source: Node = null) -> void:
	if _dead:
		return
	_flash = 1.0
	_flash_color = HIT_COLOR
	health.take_damage(amount, source)

## Shove from a weapon hit: the dummy rocks away from the blow.
func apply_knockback(impulse: Vector3) -> void:
	_rock += Vector3(impulse.z, 0.0, -impulse.x) * 0.05

## The player deflected our blow: stagger and leave an opening.
func on_parried(_by: Node) -> void:
	_stun = 1.6
	_windup = -1.0
	_flash = 1.0
	_flash_color = STUN_COLOR
	_rock += global_basis.x * 0.5

func _physics_process(delta: float) -> void:
	_time += delta
	# Rocking and colour feedback.
	_rock = _rock.lerp(Vector3.ZERO, 1.0 - exp(-5.0 * delta))
	var wobble: float = sin(_time * 22.0)
	body.rotation = Vector3(_rock.x, 0.0, _rock.z) * wobble
	_flash = maxf(0.0, _flash - delta * 4.0)
	var warn: float = clampf(_windup / windup_time, 0.0, 1.0) if _windup >= 0.0 else 0.0
	_mat.albedo_color = BASE_COLOR.lerp(WARN_COLOR, warn * 0.8).lerp(_flash_color, _flash)
	_swing = maxf(0.0, _swing - delta * 3.0)
	arm.rotation.x = lerpf(0.0, -2.3, warn) + _swing * 1.2
	if _dead or not attacks:
		return

	var player: Node3D = get_tree().get_first_node_in_group(&"player") as Node3D
	if player == null:
		return
	var to_player: Vector3 = player.global_position - global_position
	to_player.y = 0.0
	if to_player.length() > 0.1:
		rotation.y = lerp_angle(rotation.y, atan2(-to_player.x, -to_player.z), 1.0 - exp(-6.0 * delta))
	if _stun > 0.0:
		_stun -= delta
		return
	var in_range: bool = to_player.length() <= attack_range
	if _windup >= 0.0:
		_windup += delta
		if _windup >= windup_time:
			_windup = -1.0
			_swing = 1.0
			_cooldown = attack_interval
			if in_range and player.has_method("take_damage"):
				player.take_damage(attack_damage, self)
	else:
		_cooldown -= delta
		if _cooldown <= 0.0 and in_range:
			_windup = 0.0

func _on_died() -> void:
	_dead = true
	_windup = -1.0
	visible = false
	shape.set_deferred("disabled", true)
	get_tree().create_timer(respawn_time).timeout.connect(_respawn)

func _respawn() -> void:
	health.revive()
	_dead = false
	_cooldown = 1.5
	visible = true
	shape.set_deferred("disabled", false)
