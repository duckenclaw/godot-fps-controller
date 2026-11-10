class_name Hand
extends Node3D

## A hand socket on the first-person arms rig.
##
## In player.tscn each Hand is a BoneAttachment3D bound to the rig's `weapon.R` /
## `weapon.L` bone, so whatever is parented here follows the animated hand.
## Socket convention: +Y runs along the blade (out of the thumb side of the fist)
## and -Z is the direction the knuckles face. Any model whose blade/length points
## +Y drops straight in. Ranged models are authored pointing -Z and are levelled
## with the camera automatically. A model can override its hold by containing a
## Node3D named "Grip" (placed where the palm goes) and, for ranged weapons, a
## Node3D named "Muzzle" (where projectiles spawn).
##
## Both hands are equal and independent: each has its own AnimationPlayer over
## its half of the rig (see Hands) and runs its own combat state machine
## (draw/sheath, slashes, thrust, block, parry, shoot, reload). The left hand
## plays the same clips mirrored, so every clip name, sweep and camera kick below
## is written for the right hand and flipped automatically for the left.

signal hit_landed(target: Node, damage: float)
## The blade struck world geometry during a swing.
signal staggered()
signal attack_started(attack: StringName)
signal blocked(source: Node, damage_taken: float)
signal parried(source: Node)

enum HandState { EMPTY, DRAW, IDLE, ATTACK, BLOCK, PARRY, SHOOT, RELOAD, SHEATH, STUN }

@export var is_right_hand: bool = true
## Prefix of the animation set played for the held weapon ("oh_" = one-handed).
@export var anim_set: String = "oh_"
## Animation looped while this hand holds nothing.
@export var unarmed_idle: StringName = &"relax"
## Attacks chained while standing still (no movement input). With movement
## input the direction picks the attack instead: forward / backward = thrust,
## left = slash to the left, right = slash to the right.
@export var combo: Array[StringName] = [&"slash_left", &"slash_right", &"slash_down"]
## Stick / key deflection needed before movement picks the attack.
@export var direction_threshold: float = 0.3

## Per-attack tuning. Times are seconds into the clip at speed 1.
##  hit    - window in which the blade can connect
##  cancel - earliest time the next attack / a block may interrupt the recovery
##  yaw, pitch - view-space sweep of the hit test across the window (degrees,
##           +yaw = left, +pitch = up), matching the path of the blade
##  damage - multiplier on the weapon's damage
##  reach  - multiplier on the weapon's range
##  punch  - camera kick on impact (pitch, yaw, roll degrees)
##  lunge  - forward speed added to the player when the attack starts
const ATTACKS: Dictionary = {
	&"slash_left": {"hit": Vector2(0.19, 0.35), "cancel": 0.42, "yaw": Vector2(-40, 40),
		"pitch": Vector2(14, -14), "damage": 1.0, "reach": 1.0, "punch": Vector3(-0.8, 2.4, -2.0)},
	&"slash_right": {"hit": Vector2(0.19, 0.35), "cancel": 0.42, "yaw": Vector2(40, -40),
		"pitch": Vector2(14, -14), "damage": 1.0, "reach": 1.0, "punch": Vector3(-0.8, -2.4, 2.0)},
	&"slash_down": {"hit": Vector2(0.24, 0.39), "cancel": 0.46, "yaw": Vector2(-8, 6),
		"pitch": Vector2(38, -32), "damage": 1.3, "reach": 1.0, "punch": Vector3(-3.0, 0.4, -0.5)},
	&"thrust": {"hit": Vector2(0.23, 0.36), "cancel": 0.48, "yaw": Vector2(0, 0),
		"pitch": Vector2(0, 0), "damage": 1.5, "reach": 1.2, "punch": Vector3(0.8, 0.6, 0.0), "lunge": 5.0},
}

const BOLT_SCENE: PackedScene = preload("res://addons/fps_controller/weapons/bolt_projectile.tscn")
## Visual layer the hands viewport camera renders (1 << 1).
const HANDS_RENDER_LAYER: int = 2
## Maximum projectile deviation (radians) at accuracy 0.0.
const MAX_SPREAD_RAD: float = deg_to_rad(20.0)
## Off-hand ranged weapons (no animation) reload this long after emptying.
const RELOAD_DELAY: float = 1.0
const SWEEP_RADIUS: float = 0.22
const COMBO_RESET: float = 0.7      ## idle time after which the combo restarts
const INPUT_BUFFER: float = 0.3     ## how long an early attack press is remembered
const SWING_BUFFER: float = 1.5     ## a press mid-swing stays queued this long
const SWAP_SPEED: float = 1.6       ## sheath/draw speed while switching weapons
const PARRY_SPAM_GUARD: float = 0.35  ## re-blocking sooner than this cannot parry
const KNOCKBACK: float = 4.0
const RIGID_IMPULSE: float = 3.0
## Ranged models without a "Grip" node are held this far from their rear end.
const RANGED_GRIP_FROM_REAR: float = 0.2

# Injected by Hands. `player` is untyped: the player script has no class_name.
var player
var hands
var inventory: Inventory
var anim_player: AnimationPlayer
var trail: WeaponTrail
## Socket orientation (in Hands space) during the idle pose; used to level
## ranged weapons with the camera.
var idle_socket_basis: Basis = Basis.IDENTITY

var current_item_resource: ItemResource
## The instantiated weapon model (a child of this socket).
var equipped_item: Node3D = null
var state: HandState = HandState.EMPTY

var _pending_item: ItemResource
var _pending_swap: bool = false

# Melee state.
var _attack_name: StringName = &""
var _attack: Dictionary = {}
var _prev_t: float = 0.0
var _hit_bodies: Array = []
var _world_hit: bool = false
var _swing_fx_done: bool = false
var _combo_index: int = 0
var _last_attack_end: float = -10.0
var _buffer_until: float = 0.0
var _riposte_until: float = 0.0
var _riposte_active: bool = false
var _hitstop: float = 0.0
var _cast: ShapeCast3D
var _blade_base: Vector3 = Vector3(0.0, 0.3, 0.0)
var _blade_tip: Vector3 = Vector3(0.0, 1.0, 0.0)

# Block state.
var _block_held: bool = false
var _block_started: float = -10.0
var _block_ended: float = -10.0
var _can_parry: bool = false
var _stun_left: float = 0.0

# Ranged state.
var _clip: int = 0
var _reload_loaded: bool = false

# -- Setup --------------------------------------------------------------------

## Called by Hands once the arms rig is ready, with this hand's own
## AnimationPlayer (its half of the rig) and blade trail.
func bind_arms(p_hands, p_anim: AnimationPlayer, p_trail: WeaponTrail, p_idle_basis: Basis) -> void:
	hands = p_hands
	anim_player = p_anim
	trail = p_trail
	idle_socket_basis = p_idle_basis
	if anim_player:
		anim_player.animation_finished.connect(_on_animation_finished)
		_begin_draw()

## Called by Hands.setup() with the player and its inventory.
func setup(p_player, p_inventory: Inventory) -> void:
	player = p_player
	inventory = p_inventory
	if not _is_primary() or _cast != null or player == null:
		return
	_cast = ShapeCast3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = SWEEP_RADIUS
	_cast.shape = sphere
	_cast.enabled = false
	_cast.collide_with_areas = true
	_cast.collision_mask = 0xFFFFFFFF
	_cast.max_results = 8
	player.camera_3d.add_child(_cast)
	_cast.add_exception(player)

func _is_primary() -> bool:
	return anim_player != null

func _now() -> float:
	return Time.get_ticks_msec() / 1000.0

# -- Equip / unequip ----------------------------------------------------------

## Equip an item resource. The primary hand sheathes what it holds, swaps the
## model while it is off-screen and draws the new one.
func equip_resource(item_res: ItemResource) -> void:
	_end_action()
	current_item_resource = item_res
	_clip = 0
	if item_res and item_res.is_ranged():
		_load_clip()
	if not _is_primary():
		_swap_model(item_res)
		return
	if state == HandState.SHEATH:
		_pending_item = item_res
	elif equipped_item != null and state != HandState.EMPTY:
		_pending_item = item_res
		_pending_swap = true
		state = HandState.SHEATH
		_play(&"sheath", 0.06, SWAP_SPEED)
	else:
		_swap_model(item_res)
		_begin_draw()

## Legacy entry point: accepts a pre-instantiated Node3D (no weapon stats).
func equip_item(item: Node3D) -> void:
	_end_action()
	_free_model()
	current_item_resource = null
	_pending_swap = false
	if item == null:
		return
	equipped_item = item
	_attach_model()
	if _is_primary():
		state = HandState.IDLE
		_play(&"idle", 0.15)

func unequip_item() -> void:
	_end_action()
	current_item_resource = null
	_clip = 0
	if not _is_primary():
		_free_model()
		return
	if state == HandState.SHEATH:
		_pending_item = null
	elif equipped_item != null and state != HandState.EMPTY:
		_pending_item = null
		_pending_swap = true
		state = HandState.SHEATH
		_play(&"sheath", 0.06, SWAP_SPEED)
	else:
		_free_model()
		_begin_draw()

func has_item() -> bool:
	return current_item_resource != null or equipped_item != null

func get_equipped_item() -> Node3D:
	return equipped_item

func _free_model() -> void:
	if equipped_item:
		if equipped_item.get_parent() == self:
			remove_child(equipped_item)
		equipped_item.queue_free()
		equipped_item = null

func _swap_model(item_res: ItemResource) -> void:
	_free_model()
	_pending_swap = false
	if item_res == null or item_res.model == null:
		return
	var inst: Node = item_res.model.instantiate()
	if inst is Node3D:
		equipped_item = inst
		_attach_model()
	else:
		inst.free()

## Parent the model to the socket and work out how it is held.
func _attach_model() -> void:
	add_child(equipped_item)
	equipped_item.transform = Transform3D.IDENTITY
	var item: ItemResource = current_item_resource
	var ranged: bool = item != null and item.is_ranged()
	if ranged:
		# Point the weapon where the camera looks while the hand idles.
		equipped_item.basis = idle_socket_basis.inverse()
	var grip := equipped_item.find_child("Grip", true, false) as Node3D
	if grip:
		var rel: Transform3D = equipped_item.global_transform.affine_inverse() * grip.global_transform
		equipped_item.transform = equipped_item.transform * rel.affine_inverse()
	elif ranged:
		# No Grip marker: assume the hand holds the weapon near its rear end.
		var box: AABB = _model_aabb(equipped_item.global_transform)
		if box.size.z > RANGED_GRIP_FROM_REAR:
			equipped_item.position -= equipped_item.basis * Vector3(0.0, 0.0, box.end.z - RANGED_GRIP_FROM_REAR)
	_prepare_visuals(equipped_item)
	# Blade extent along the socket's +Y, for the swing trail.
	var top: float = _model_aabb(global_transform).end.y
	if top <= 0.05:
		top = 0.8
	_blade_base = Vector3(0.0, top * 0.3, 0.0)
	_blade_tip = Vector3(0.0, top, 0.0)

## Bounds of the held model's meshes, expressed in the space of `frame`.
func _model_aabb(frame: Transform3D) -> AABB:
	var box := AABB()
	var first: bool = true
	var inv: Transform3D = frame.affine_inverse()
	for mi in equipped_item.find_children("*", "MeshInstance3D", true, false):
		var b: AABB = (inv * (mi as Node3D).global_transform) * (mi as MeshInstance3D).get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box

## Mark every visual under `node` as hands-layer so only the overlay hands
## camera draws it (keeps it on top of world geometry), and stop it casting
## shadows into the world.
func _prepare_visuals(node: Node) -> void:
	if node is VisualInstance3D:
		node.layers = HANDS_RENDER_LAYER
	if node is GeometryInstance3D:
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for child in node.get_children():
		_prepare_visuals(child)

func _begin_draw() -> void:
	if current_item_resource == null and equipped_item == null:
		state = HandState.EMPTY
		if anim_player and anim_player.has_animation(unarmed_idle):
			anim_player.play(unarmed_idle, 0.2)
		return
	state = HandState.DRAW
	_play(&"draw", 0.05, SWAP_SPEED, true)
	if hands:
		hands.fx_draw()

# -- Animation helpers --------------------------------------------------------

func _anim(clip: StringName) -> StringName:
	return StringName(anim_set + String(clip))

func _play(clip: StringName, blend: float = 0.08, speed: float = 1.0, restart: bool = false) -> bool:
	if anim_player == null:
		return false
	var full: StringName = _anim(clip)
	if not anim_player.has_animation(full):
		return false
	if restart and anim_player.current_animation == full:
		# Replaying the clip that is already running: cross-fade into its twin
		# ("<name>_b", the same animation) so the restart blends instead of popping.
		var twin := StringName(String(full) + "_b")
		if anim_player.has_animation(twin):
			full = twin
		else:
			anim_player.stop(true)
	anim_player.play(full, blend, speed)
	return true

## Name of the clip this hand is playing, without the set prefix / twin suffix.
func current_clip() -> StringName:
	if anim_player == null:
		return &""
	return StringName(String(anim_player.current_animation).trim_prefix(anim_set).trim_suffix("_b"))

func _clip_time() -> float:
	return anim_player.current_animation_position if anim_player else 0.0

func _to_idle() -> void:
	state = HandState.IDLE
	_play(&"idle", 0.12)
	if _block_held and can_block():
		_enter_block()

func _on_animation_finished(anim_name: StringName) -> void:
	var clip: String = String(anim_name).trim_prefix(anim_set).trim_suffix("_b")
	match clip:
		"draw":
			if state == HandState.DRAW:
				_to_idle()
		"sheath":
			if state == HandState.SHEATH:
				_swap_model(_pending_item)
				_begin_draw()
		"block":
			if state == HandState.BLOCK:
				_play(&"block_loop", 0.1)
		"parry":
			if state == HandState.PARRY:
				if _block_held:
					state = HandState.BLOCK
					_play(&"block_loop", 0.1)
				else:
					_leave_block()
		"unblock":
			if state == HandState.IDLE:
				_play(&"idle", 0.1)
		"shoot":
			if state == HandState.SHOOT:
				_to_idle()
				if _clip <= 0:
					_start_reload()
		"reload":
			if state == HandState.RELOAD:
				_to_idle()
		_:
			if state == HandState.ATTACK and StringName(clip) == _attack_name:
				_finish_attack()
				_to_idle()

# -- Per-frame ----------------------------------------------------------------

func _process(delta: float) -> void:
	if not _is_primary():
		return
	# Hit-stop: the swing freezes for a few frames when the blade connects.
	if _hitstop > 0.0:
		_hitstop -= delta / maxf(Engine.time_scale, 0.01)
		if _hitstop <= 0.0:
			anim_player.speed_scale = 1.0
	if _stun_left > 0.0:
		_stun_left -= delta
		if _stun_left <= 0.0 and state == HandState.STUN:
			_to_idle()
	if state == HandState.ATTACK and trail and hands:
		var t: float = _clip_time()
		var h: Vector2 = _attack["hit"]
		if t >= h.x - 0.04 and t <= h.y + 0.05:
			trail.push(hands.to_local(global_transform * _blade_base),
					hands.to_local(global_transform * _blade_tip))

func _physics_process(_delta: float) -> void:
	if not _is_primary():
		return
	match state:
		HandState.ATTACK:
			_update_attack()
		HandState.RELOAD:
			if not _reload_loaded and anim_player.current_animation_length > 0.0 \
					and _clip_time() >= anim_player.current_animation_length * 0.5:
				_reload_loaded = true
				_load_clip()
		HandState.IDLE:
			if _buffer_until > _now():
				_buffer_until = 0.0
				attack()
		_:
			pass

# -- Attack -------------------------------------------------------------------

## Use the held item: swing a melee weapon or fire a ranged one.
func attack() -> void:
	var item: ItemResource = current_item_resource
	if item == null:
		if equipped_item and equipped_item.has_method("attack"):
			equipped_item.attack()
		return
	if item.is_melee():
		_request_melee()
	elif item.is_ranged():
		_request_shot()

func is_attacking() -> bool:
	return state == HandState.ATTACK or state == HandState.SHOOT

func _request_melee() -> void:
	if not _is_primary():
		return
	match state:
		HandState.IDLE, HandState.BLOCK, HandState.PARRY:
			_start_attack(_pick_attack())
		HandState.ATTACK:
			if _clip_time() >= float(_attack["cancel"]):
				_start_attack(_pick_attack())
			else:
				# Any press during a swing queues the next one for its cancel point.
				_buffer_until = _now() + SWING_BUFFER
		HandState.DRAW:
			_buffer_until = _now() + INPUT_BUFFER
		_:
			pass

## Decide which attack the next press performs.
func _pick_attack() -> StringName:
	var item: ItemResource = current_item_resource
	# A weapon can force a single attack through its `attack_animation`.
	if ATTACKS.has(item.attack_animation):
		return item.attack_animation
	# Movement input chooses the attack. Slash clips are authored for the right
	# hand; the left hand plays them mirrored, so it swaps left and right.
	var move: Vector2 = player.get_input_direction() if player else Vector2.ZERO
	if absf(move.y) > direction_threshold and absf(move.y) >= absf(move.x):
		return &"thrust"
	if absf(move.x) > direction_threshold:
		var to_left: bool = move.x < 0.0
		return &"slash_left" if to_left == is_right_hand else &"slash_right"
	return _next_in_combo()

func _next_in_combo() -> StringName:
	if combo.is_empty():
		return &"slash_left"
	if state != HandState.ATTACK and _now() - _last_attack_end > COMBO_RESET:
		_combo_index = 0
	var pick: StringName = combo[_combo_index % combo.size()]
	_combo_index += 1
	return pick if ATTACKS.has(pick) else &"slash_left"

func _start_attack(attack_name: StringName) -> void:
	_attack_name = attack_name
	_attack = ATTACKS[attack_name]
	if not is_right_hand:
		# Mirrored clip: the blade path and the camera kick flip sideways.
		_attack = _attack.duplicate()
		_attack["yaw"] = -(_attack["yaw"] as Vector2)
		var punch: Vector3 = _attack["punch"]
		_attack["punch"] = Vector3(punch.x, -punch.y, -punch.z)
	state = HandState.ATTACK
	_hit_bodies.clear()
	_world_hit = false
	_swing_fx_done = false
	_prev_t = 0.0
	_buffer_until = 0.0
	_riposte_active = _now() < _riposte_until
	_riposte_until = 0.0
	_play(attack_name, 0.07, maxf(0.1, current_item_resource.speed), true)
	if _attack.has("lunge") and player and player.get_input_direction().y > direction_threshold:
		var fwd: Vector3 = -player.global_basis.z
		player.velocity += Vector3(fwd.x, 0.0, fwd.z).normalized() * float(_attack["lunge"])
	attack_started.emit(attack_name)

func _update_attack() -> void:
	var t: float = _clip_time()
	var h: Vector2 = _attack["hit"]
	if t >= h.x and _prev_t < h.y:
		if not _swing_fx_done:
			_swing_fx_done = true
			if hands:
				hands.fx_swing(_attack_name)
		_sweep(inverse_lerp(h.x, h.y, maxf(_prev_t, h.x)), inverse_lerp(h.x, h.y, minf(t, h.y)))
	_prev_t = t
	if t >= float(_attack["cancel"]):
		if _buffer_until > _now():
			_start_attack(_pick_attack())
		elif _block_held and can_block():
			_finish_attack()
			_enter_block()

func _finish_attack() -> void:
	_last_attack_end = _now()
	_hit_bodies.clear()
	_riposte_active = false

## Reset any action in flight (used when the weapon changes).
func _end_action() -> void:
	_hit_bodies.clear()
	_buffer_until = 0.0
	_hitstop = 0.0
	_stun_left = 0.0
	if anim_player:
		anim_player.speed_scale = 1.0
	if trail:
		trail.clear()
	if state in [HandState.ATTACK, HandState.BLOCK, HandState.PARRY, HandState.SHOOT, HandState.RELOAD, HandState.STUN]:
		state = HandState.IDLE

# -- Melee hit detection ------------------------------------------------------

## Sweep a sphere from the camera along the blade's path for the part of the hit
## window covered since the last physics tick (u0..u1 in 0..1).
func _sweep(u0: float, u1: float) -> void:
	if _cast == null or player == null:
		return
	var reach: float = maxf(0.5, current_item_resource.range * float(_attack["reach"]))
	var yaw: Vector2 = _attack["yaw"]
	var pitch: Vector2 = _attack["pitch"]
	const STEPS: int = 2
	for i in STEPS:
		var u: float = lerpf(u0, u1, float(i + 1) / STEPS)
		var local_dir: Vector3 = Basis(Vector3.UP, deg_to_rad(lerpf(yaw.x, yaw.y, u))) \
				* Basis(Vector3.RIGHT, deg_to_rad(lerpf(pitch.x, pitch.y, u))) * Vector3.FORWARD
		_cast.target_position = local_dir * maxf(0.1, reach - SWEEP_RADIUS)
		_cast.force_shapecast_update()
		var world_dir: Vector3 = _cast.global_basis * local_dir
		for c in _cast.get_collision_count():
			_register_hit(_cast.get_collider(c), _cast.get_collision_point(c),
					_cast.get_collision_normal(c), world_dir)
		if state != HandState.ATTACK:
			return

func _register_hit(collider: Object, point: Vector3, normal: Vector3, dir: Vector3) -> void:
	if collider == null or not (collider is Node):
		return
	var target: Node = _damage_root(collider)
	if target == null:
		# World geometry / props.
		if collider is Area3D:
			return
		if collider is RigidBody3D and not (collider in _hit_bodies):
			_hit_bodies.append(collider)
			collider.apply_impulse(dir * RIGID_IMPULSE, point - collider.global_position)
		if _world_hit:
			return
		_world_hit = true
		if hands:
			hands.fx_world_hit(point, normal)
		staggered.emit()
		return
	if target == player or target in _hit_bodies:
		return
	_hit_bodies.append(target)
	var dmg: float = current_item_resource.damage * float(_attack["damage"])
	if _riposte_active and player and player.config:
		dmg *= player.config.riposte_multiplier
	if target.has_method("take_damage"):
		target.take_damage(dmg, player)
	if target.has_method("apply_knockback"):
		target.apply_knockback(dir * KNOCKBACK * float(_attack["damage"]))
	hit_landed.emit(target, dmg)
	if hands:
		hands.fx_enemy_hit(point, normal, _attack["punch"], _riposte_active)
	var stop: float = player.config.hitstop if player and player.config else 0.07
	if stop > 0.0:
		_hitstop = stop * (1.6 if _riposte_active else 1.0)
		anim_player.speed_scale = 0.05

## The damageable entity a collider belongs to (itself or a near ancestor in the
## "enemy" / "destructible" groups), or null for plain world geometry.
func _damage_root(node: Node) -> Node:
	var n: Node = node
	for i in 4:
		if n == null:
			break
		if n.is_in_group(&"enemy") or n.is_in_group(&"destructible"):
			return n
		n = n.get_parent()
	return null

# -- Block / parry ------------------------------------------------------------

func can_block() -> bool:
	return _is_primary() and current_item_resource != null and current_item_resource.is_melee()

## True if this hand holds something its button attacks with.
func wields_weapon() -> bool:
	var item: ItemResource = current_item_resource
	return item != null and (item.is_melee() or item.is_ranged())

func is_blocking() -> bool:
	return state == HandState.BLOCK or state == HandState.PARRY

## Raise the guard (hold). Pressing it just before a hit lands parries instead.
func start_block() -> void:
	_block_held = true
	if not can_block():
		return
	if state == HandState.IDLE:
		_enter_block()
	elif state == HandState.ATTACK and _clip_time() >= float(_attack["cancel"]):
		_finish_attack()
		_enter_block()

func stop_block() -> void:
	_block_held = false
	if state == HandState.BLOCK:
		_leave_block()

func _enter_block() -> void:
	var now: float = _now()
	_can_parry = now - _block_ended > PARRY_SPAM_GUARD
	_block_started = now
	state = HandState.BLOCK
	_play(&"block", 0.06, 1.3, true)

func _leave_block() -> void:
	_block_ended = _now()
	state = HandState.IDLE
	_play(&"unblock", 0.06, 1.2, true)

## Filter incoming damage through the guard. Returns the damage that still gets
## through (0 on a parry). Called by the player before health is reduced.
func absorb_hit(amount: float, source: Node) -> float:
	if not is_blocking() or player == null or not _is_frontal(source):
		return amount
	var cfg: PlayerConfig = player.config
	var now: float = _now()
	if _can_parry and now - _block_started <= cfg.parry_window:
		state = HandState.PARRY
		_block_started = now  # a flurry can be parried hit by hit
		_riposte_until = now + cfg.riposte_window
		_play(&"parry", 0.03, 1.0, true)
		if source and source.has_method("on_parried"):
			source.on_parried(player)
		parried.emit(source)
		if hands:
			hands.fx_parry()
		return 0.0
	var taken: float = amount * (1.0 - cfg.block_damage_reduction)
	var cost: float = (amount - taken) * cfg.block_stamina_cost
	if hands:
		hands.note_stamina_used()
	if player.stamina < cost:
		# Guard break: the block collapses and half the blow lands.
		player.set_stamina(0.0)
		_block_ended = now
		state = HandState.STUN
		_stun_left = cfg.guard_break_time
		_play(&"unblock", 0.05, 0.6, true)
		if hands:
			hands.fx_guard_break()
		blocked.emit(source, amount * 0.5)
		return amount * 0.5
	player.use_stamina(cost)
	if hands:
		hands.fx_block()
	blocked.emit(source, taken)
	return taken

func _is_frontal(source: Node) -> bool:
	if not (source is Node3D):
		return false
	var to_src: Vector3 = (source as Node3D).global_position - player.global_position
	to_src.y = 0.0
	if to_src.length_squared() < 0.0001:
		return true
	var fwd: Vector3 = -player.global_basis.z
	return to_src.normalized().dot(Vector3(fwd.x, 0.0, fwd.z).normalized()) > 0.2

# -- Ranged -------------------------------------------------------------------

func _request_shot() -> void:
	if not _is_primary():
		_offhand_shot()
		return
	if state != HandState.IDLE:
		return
	if _clip <= 0:
		if not _start_reload() and hands:
			hands.fx_dry_fire()
		return
	_clip -= 1
	_spawn_projectile()
	state = HandState.SHOOT
	_play(&"shoot", 0.03, maxf(0.1, current_item_resource.speed), true)
	if hands:
		hands.fx_shoot()

func _offhand_shot() -> void:
	if _clip <= 0:
		_load_clip()
		if _clip <= 0:
			return
	_clip -= 1
	_spawn_projectile()
	if _clip <= 0:
		var item: ItemResource = current_item_resource
		get_tree().create_timer(RELOAD_DELAY).timeout.connect(
			func() -> void:
				if current_item_resource == item:
					_load_clip())

## Reload the held ranged weapon (plays the reload animation on the primary hand).
func reload() -> void:
	if _is_primary():
		_start_reload()
	else:
		_load_clip()

func _start_reload() -> bool:
	var item: ItemResource = current_item_resource
	if item == null or not item.is_ranged() or inventory == null or state != HandState.IDLE:
		return false
	if item.clip_size - _clip <= 0 or inventory.count_item(item.ammo_type) <= 0:
		return false
	state = HandState.RELOAD
	_reload_loaded = false
	if not _play(&"reload", 0.08, 1.0, true):
		_load_clip()
		state = HandState.IDLE
	return true

## Refill the clip from the inventory's ammo stock (instant).
func _load_clip() -> void:
	var item: ItemResource = current_item_resource
	if item == null or not item.is_ranged() or inventory == null:
		return
	var needed: int = item.clip_size - _clip
	if needed > 0:
		_clip += inventory.consume_item(item.ammo_type, needed)

func _spawn_projectile() -> void:
	var item: ItemResource = current_item_resource
	var dir: Vector3 = -global_basis.z
	var cam: Camera3D = player.camera_3d if player else null
	if cam:
		dir = -cam.global_basis.z
	dir = _apply_spread(dir.normalized(), item.accuracy)
	var origin: Vector3 = global_position
	if equipped_item:
		var muzzle := equipped_item.find_child("Muzzle", true, false) as Node3D
		origin = muzzle.global_position if muzzle else equipped_item.global_position
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
