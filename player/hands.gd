class_name Hands
extends Node3D

## Hands manager. Owns the first-person arms rig (the `Arms` child: a skinned
## mesh with an AnimationPlayer), the two Hand sockets attached to its weapon
## bones, and everything that makes the viewmodel feel alive: sway behind the
## camera, movement bob, recoil springs, the camera motion baked into the arm
## animations, the blade trails, impact particles and combat sounds.
##
## The two arms are fully independent. The rig's clips are authored on the right
## arm; at load each one is split into a right-arm clip and a mirrored left-arm
## clip, played by two AnimationPlayers that drive disjoint halves of the same
## skeleton. Either hand can therefore hold any weapon and run its own
## draw / attack / block / reload while the other does something else.
##
## This node sits at the camera origin; the rig is offset so its `camera` bone
## coincides with the real camera, i.e. the arms appear exactly as authored.

## Visual layer the hands viewport camera renders (1 << 1).
const HANDS_RENDER_LAYER: int = 2

# Sway tuning: how strongly camera rotation deflects the hands, the maximum
# deflection, how fast the hands settle back, and positional follow amount.
const SWAY_RESPONSE: float = 0.5
const SWAY_MAX: float = deg_to_rad(4.0)
const SWAY_RECOVER_SPEED: float = 9.0
const SWAY_POSITION_FACTOR: float = 0.04

# Recoil spring (critically damped-ish) for impacts, blocks and shots.
const KICK_STIFFNESS: float = 190.0
const KICK_DAMPING: float = 22.0

const LOOPING: Array[StringName] = [&"oh_idle", &"oh_block_loop", &"relax", &"guard_idle", &"knife_idle"]

## Optional replacements for the synthesised placeholder sounds.
@export_group("Sounds")
@export var sfx_swing: AudioStream
@export var sfx_hit: AudioStream
@export var sfx_clang: AudioStream
@export var sfx_parry: AudioStream
@export var sfx_shoot: AudioStream
@export var sfx_draw: AudioStream
@export_group("")

@onready var right_hand: Hand = $RightHand
@onready var left_hand: Hand = $LeftHand
@onready var arms: Node3D = get_node_or_null("Arms")

var skeleton: Skeleton3D
## The right arm's player (the rig's own AnimationPlayer) and the left arm's.
var anim_player: AnimationPlayer
var anim_player_left: AnimationPlayer

var _player
var _camera_controller
var _base_position: Vector3
var _last_cam_quat: Quaternion
var _sway: Vector2 = Vector2.ZERO  # x = pitch offset, y = yaw offset
var _bob: Vector3 = Vector3.ZERO
var _kick_pos: Vector3 = Vector3.ZERO
var _kick_pos_vel: Vector3 = Vector3.ZERO
var _kick_rot: Vector3 = Vector3.ZERO
var _kick_rot_vel: Vector3 = Vector3.ZERO
var _stamina_used_at: float = -10.0

# Camera bone of the rig: the rotation keyed on it in whatever clip each hand is
# playing is replayed on the real camera (mirrored for the left hand).
var _cam_bone: int = -1
var _cam_rest_inv: Basis = Basis.IDENTITY
var _cam_parent_basis: Basis = Basis.IDENTITY
var _skel_basis: Basis = Basis.IDENTITY
var _cam_tracks: Dictionary = {}  # clip name -> [source Animation, camera rotation track]
var _cam_kick: Vector3 = Vector3.ZERO

func _ready() -> void:
	# Run after the AnimationPlayer has posed the skeleton this frame.
	process_priority = 50
	_base_position = position
	var cam: Node3D = get_parent() as Node3D
	if cam:
		_last_cam_quat = cam.global_basis.get_rotation_quaternion()

	if arms:
		skeleton = arms.find_child("Skeleton3D", true, false) as Skeleton3D
		anim_player = arms.find_child("AnimationPlayer", true, false) as AnimationPlayer
		_prepare_visuals(arms)
	if skeleton:
		_skel_basis = (global_transform.affine_inverse() * skeleton.global_transform).basis.orthonormalized()
		_cam_bone = skeleton.find_bone("camera")
		if _cam_bone >= 0:
			_cam_rest_inv = skeleton.get_bone_global_rest(_cam_bone).basis.orthonormalized().inverse()
			var parent: int = skeleton.get_bone_parent(_cam_bone)
			if parent >= 0:
				_cam_parent_basis = skeleton.get_bone_global_rest(parent).basis.orthonormalized()
	if skeleton and anim_player:
		_split_arm_animations()

	for hand in [right_hand, left_hand]:
		if hand == null:
			continue
		var player_for: AnimationPlayer = anim_player if hand.is_right_hand else anim_player_left
		var hand_trail := WeaponTrail.new()
		hand_trail.name = "WeaponTrailR" if hand.is_right_hand else "WeaponTrailL"
		hand_trail.layers = HANDS_RENDER_LAYER
		add_child(hand_trail)
		hand.bind_arms(self, player_for, hand_trail, _sample_idle_socket_basis(hand, player_for))

## Rebuild the rig's clips as two independent sets: the right-arm tracks of each
## clip stay on the rig's AnimationPlayer, and a mirrored copy retargeted to the
## left-arm bones goes to a second player. Both sets keep the original clip
## names, so a Hand plays e.g. "oh_slash_left" on its own player without caring
## which side it is. Every clip is also registered as "<name>_b" so it can
## cross-fade into itself when the same attack is repeated.
func _split_arm_animations() -> void:
	var prefixes: Array[String] = []
	var extra: Array[StringName] = []
	for hand in [right_hand, left_hand]:
		if hand:
			if not prefixes.has(hand.anim_set):
				prefixes.append(hand.anim_set)
			extra.append(hand.unarmed_idle)
	var right_lib := AnimationLibrary.new()
	var left_lib := AnimationLibrary.new()
	var mirror := Transform3D(Basis.from_scale(Vector3(-1.0, 1.0, 1.0)), Vector3.ZERO)
	var corrections: Dictionary = {}  # left bone name -> [Transform3D, valid]
	for clip_name in anim_player.get_animation_list():
		var wanted: bool = extra.has(clip_name)
		for prefix in prefixes:
			wanted = wanted or String(clip_name).begins_with(prefix)
		if not wanted:
			continue
		var src: Animation = anim_player.get_animation(clip_name)
		var right := Animation.new()
		var left := Animation.new()
		for anim in [right, left]:
			anim.length = src.length
			anim.loop_mode = Animation.LOOP_LINEAR if LOOPING.has(clip_name) else Animation.LOOP_NONE
		for t in src.get_track_count():
			var path: NodePath = src.track_get_path(t)
			var bone: String = String(path.get_concatenated_subnames())
			var type: int = src.track_get_type(t)
			if bone == "camera" and type == Animation.TYPE_ROTATION_3D:
				_cam_tracks[clip_name] = [src, t]
			if not bone.ends_with(".R"):
				continue
			var left_bone: String = bone.trim_suffix(".R") + ".L"
			if not corrections.has(left_bone):
				corrections[left_bone] = _mirror_correction(bone, left_bone, mirror)
			_copy_track(src, t, right, path, false, Transform3D.IDENTITY)
			if corrections[left_bone][1]:
				_copy_track(src, t, left, NodePath(String(path.get_concatenated_names()) + ":" + left_bone),
						true, corrections[left_bone][0])
		for suffix in ["", "_b"]:
			right_lib.add_animation(StringName(String(clip_name) + suffix), right)
			left_lib.add_animation(StringName(String(clip_name) + suffix), left)

	anim_player_left = AnimationPlayer.new()
	anim_player_left.name = "AnimationPlayerLeft"
	anim_player.get_parent().add_child(anim_player_left)
	anim_player_left.root_node = anim_player.root_node
	anim_player_left.add_animation_library(&"", left_lib)
	for lib_name in anim_player.get_animation_library_list():
		anim_player.remove_animation_library(lib_name)
	anim_player.add_animation_library(&"", right_lib)

## Transform that carries a right bone's local pose to its left twin:
## local_L = C * local_R * mirror, with C = parent_L_rest^-1 * mirror * parent_R_rest.
func _mirror_correction(right_bone: String, left_bone: String, mirror: Transform3D) -> Array:
	var ri: int = skeleton.find_bone(right_bone)
	var li: int = skeleton.find_bone(left_bone)
	if ri < 0 or li < 0:
		return [Transform3D.IDENTITY, false]
	var rp: int = skeleton.get_bone_parent(ri)
	var lp: int = skeleton.get_bone_parent(li)
	var r_parent: Transform3D = skeleton.get_bone_global_rest(rp) if rp >= 0 else Transform3D.IDENTITY
	var l_parent: Transform3D = skeleton.get_bone_global_rest(lp) if lp >= 0 else Transform3D.IDENTITY
	return [l_parent.affine_inverse() * mirror * r_parent, true]

func _copy_track(src: Animation, t: int, dst: Animation, path: NodePath, flip: bool, c: Transform3D) -> void:
	var type: int = src.track_get_type(t)
	if type != Animation.TYPE_POSITION_3D and type != Animation.TYPE_ROTATION_3D and type != Animation.TYPE_SCALE_3D:
		return
	var d: int = dst.add_track(type)
	dst.track_set_path(d, path)
	dst.track_set_interpolation_type(d, src.track_get_interpolation_type(t))
	var flip_basis := Basis.from_scale(Vector3(-1.0, 1.0, 1.0))
	for k in src.track_get_key_count(t):
		var time: float = src.track_get_key_time(t, k)
		var value: Variant = src.track_get_key_value(t, k)
		match type:
			Animation.TYPE_POSITION_3D:
				dst.position_track_insert_key(d, time, c * (value as Vector3) if flip else value)
			Animation.TYPE_ROTATION_3D:
				if flip:
					value = (c.basis * Basis(value as Quaternion) * flip_basis).orthonormalized().get_rotation_quaternion()
				dst.rotation_track_insert_key(d, time, value)
			Animation.TYPE_SCALE_3D:
				dst.scale_track_insert_key(d, time, value)

## Orientation of a hand's weapon socket, in this node's space, while idling
## (used to level ranged weapons with the camera).
func _sample_idle_socket_basis(hand: Hand, player_for: AnimationPlayer) -> Basis:
	if skeleton == null or player_for == null:
		return Basis.IDENTITY
	var bone: int = skeleton.find_bone("weapon.R" if hand.is_right_hand else "weapon.L")
	var idle: StringName = StringName(hand.anim_set + "idle")
	if bone < 0 or not player_for.has_animation(idle):
		return Basis.IDENTITY
	player_for.play(idle)
	player_for.advance(0.0)
	var pose: Basis = skeleton.get_bone_global_pose(bone).basis.orthonormalized()
	player_for.stop()
	return (_skel_basis * pose).orthonormalized()

func _prepare_visuals(node: Node) -> void:
	if node is VisualInstance3D:
		node.layers = HANDS_RENDER_LAYER
	if node is GeometryInstance3D:
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for child in node.get_children():
		_prepare_visuals(child)

## Inject player/inventory references so hands can aim, hit and consume ammo.
func setup(player: Node3D, inventory: Inventory) -> void:
	_player = player
	_camera_controller = player.get("camera") if player else null
	for hand in [right_hand, left_hand]:
		if hand:
			hand.setup(player, inventory)

# -- Procedural motion --------------------------------------------------------

func _process(delta: float) -> void:
	_update_sway(delta)
	_update_bob(delta)
	_update_kick(delta)

	# Camera motion authored on the rig's `camera` bone: rotate the real camera
	# by it and counter-rotate the arms, so the arms stay put in the world while
	# the view kicks - exactly what the animation looks like in Blender.
	_cam_kick = _cam_kick.lerp(_sample_camera_kick(), 1.0 - exp(-40.0 * delta))
	var cam_kick: Basis = Basis.from_euler(_cam_kick)
	if _camera_controller:
		_camera_controller.anim_kick = _cam_kick
		_camera_controller.apply_view_offsets()

	basis = Basis.from_euler(Vector3(_sway.x, _sway.y, 0.0) + _kick_rot) * cam_kick.inverse()
	position = _base_position + Vector3(-_sway.y, _sway.x, 0.0) * SWAY_POSITION_FACTOR + _bob + _kick_pos

	_regen_stamina(delta)

## Hands are parented to the camera, so a zero offset means perfectly locked.
## Track the camera's per-frame rotation and deflect the opposite way, then
## ease back - this makes the hands follow the camera with a slight delay.
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

## Step bob while walking, plus a lift/dip while rising or falling.
func _update_bob(delta: float) -> void:
	var target: Vector3 = Vector3.ZERO
	if _player:
		var speed: float = Vector2(_player.velocity.x, _player.velocity.z).length()
		if _player.is_on_floor():
			if speed > 0.5 and _camera_controller:
				var k: float = clampf(speed / 8.0, 0.25, 1.0)
				var phase: float = _camera_controller.bob_time
				target = Vector3(sin(phase * 0.5) * 0.009, sin(phase + 0.7) * 0.006, 0.0) * k
		else:
			target.y = clampf(-_player.velocity.y * 0.004, -0.035, 0.035)
	_bob = _bob.lerp(target, 1.0 - exp(-12.0 * delta))

func _update_kick(delta: float) -> void:
	# Fixed small steps keep the springs stable through frame hitches.
	var left: float = minf(delta, 0.1)
	while left > 0.0:
		var dt: float = minf(left, 1.0 / 120.0)
		left -= dt
		_kick_pos_vel += (-KICK_STIFFNESS * _kick_pos - KICK_DAMPING * _kick_pos_vel) * dt
		_kick_pos += _kick_pos_vel * dt
		_kick_rot_vel += (-KICK_STIFFNESS * _kick_rot - KICK_DAMPING * _kick_rot_vel) * dt
		_kick_rot += _kick_rot_vel * dt

## Knock the arms away from their pose; they spring back. `offset` is the peak
## displacement in metres (camera space, +Z = toward the player), `rot_deg` the
## peak rotation in degrees.
func kick(offset: Vector3, rot_deg: Vector3 = Vector3.ZERO) -> void:
	var gain: float = sqrt(KICK_STIFFNESS) * 2.72
	_kick_pos_vel += offset * gain
	_kick_rot_vel += Vector3(deg_to_rad(rot_deg.x), deg_to_rad(rot_deg.y), deg_to_rad(rot_deg.z)) * gain

## Camera rotation (pitch, yaw, roll) authored in the clips the two hands are
## playing right now. The left hand's contribution is mirrored.
func _sample_camera_kick() -> Vector3:
	var total := Vector3.ZERO
	if _cam_bone < 0:
		return total
	for hand in [right_hand, left_hand]:
		if hand == null or hand.anim_player == null:
			continue
		var clip := StringName(String(hand.anim_player.current_animation).trim_suffix("_b"))
		if not _cam_tracks.has(clip):
			continue
		var src: Animation = _cam_tracks[clip][0]
		var q: Quaternion = src.rotation_track_interpolate(_cam_tracks[clip][1],
				minf(hand.anim_player.current_animation_position, src.length))
		var pose: Basis = _cam_parent_basis * Basis(q)
		var e: Vector3 = (_skel_basis * (pose * _cam_rest_inv) * _skel_basis.inverse()).orthonormalized().get_euler()
		total += e if hand.is_right_hand else Vector3(e.x, -e.y, -e.z)
	return total

func _regen_stamina(delta: float) -> void:
	if _player == null or _player.config == null:
		return
	var cfg: PlayerConfig = _player.config
	if _player.stamina < _player.max_stamina \
			and Time.get_ticks_msec() / 1000.0 - _stamina_used_at > cfg.stamina_regen_delay:
		_player.set_stamina(_player.stamina + cfg.stamina_regen * delta)

func note_stamina_used() -> void:
	_stamina_used_at = Time.get_ticks_msec() / 1000.0

# -- Input-level API ----------------------------------------------------------

## Each hand button uses that hand: it attacks with the weapon held there. A
## button whose hand holds no weapon raises the guard with the other hand's
## melee weapon instead (hold to block, press just before a hit to parry).
func use_left_hand() -> void:
	_use_hand(left_hand, right_hand)

func use_right_hand() -> void:
	_use_hand(right_hand, left_hand)

func release_left_hand() -> void:
	_release_hand(left_hand, right_hand)

func release_right_hand() -> void:
	_release_hand(right_hand, left_hand)

func _use_hand(hand: Hand, other: Hand) -> void:
	if hand == null:
		return
	if not hand.wields_weapon() and other and other.can_block():
		other.start_block()
	else:
		hand.attack()

func _release_hand(hand: Hand, other: Hand) -> void:
	if hand and not hand.wields_weapon() and other:
		other.stop_block()

func is_blocking() -> bool:
	return (right_hand != null and right_hand.is_blocking()) \
			or (left_hand != null and left_hand.is_blocking())

## Run incoming damage through the guard; returns what still gets through.
func absorb_hit(amount: float, source: Node) -> float:
	for hand in [right_hand, left_hand]:
		if hand and hand.is_blocking():
			return hand.absorb_hit(amount, source)
	return amount

## Reload whichever hands hold a ranged weapon.
func reload_right_hand() -> void:
	for hand in [right_hand, left_hand]:
		if hand:
			hand.reload()

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

# -- Feedback -----------------------------------------------------------------

func _sfx(sound: StringName, override: AudioStream, pitch: float = 1.0) -> void:
	# Looked up by path so this script also compiles where the core autoloads
	# are not registered yet (tools, headless scripts).
	var audio: Node = get_node_or_null("/root/AudioManager")
	if audio:
		audio.play_sfx(override if override else CombatSfx.stream(sound), pitch)

func _world() -> Node:
	var scene: Node = get_tree().current_scene
	return scene if scene else (_player.get_parent() if _player else null)

func fx_draw() -> void:
	_sfx(&"draw", sfx_draw, randf_range(0.95, 1.1))

func fx_swing(_attack: StringName) -> void:
	_sfx(&"swing", sfx_swing, randf_range(0.9, 1.15))

func fx_enemy_hit(point: Vector3, normal: Vector3, punch_deg: Vector3, heavy: bool) -> void:
	CombatFX.burst(_world(), point, normal, Color(0.8, 0.08, 0.06), 16 if heavy else 10, 3.5, 0.06)
	CombatFX.burst(_world(), point, normal, Color(1.0, 0.95, 0.8), 5, 5.0, 0.03)
	_sfx(&"hit", sfx_hit, randf_range(0.75, 0.85) if heavy else randf_range(0.92, 1.1))
	kick(Vector3(0.0, 0.0, 0.02), Vector3(1.5, 0.0, 0.0))
	if _camera_controller:
		_camera_controller.add_shake(0.4 if heavy else 0.25)
		_camera_controller.add_punch(punch_deg * (1.0 if heavy else 0.6))

func fx_world_hit(point: Vector3, normal: Vector3) -> void:
	CombatFX.burst(_world(), point, normal, Color(1.0, 0.8, 0.35), 12, 6.0, 0.03)
	_sfx(&"clang", sfx_clang, randf_range(1.0, 1.25))
	kick(Vector3(0.0, 0.0, 0.035), Vector3(3.0, 0.0, 0.0))
	if _camera_controller:
		_camera_controller.add_shake(0.2)

func fx_block() -> void:
	_blade_sparks(10)
	_sfx(&"clang", sfx_clang, randf_range(0.78, 0.88))
	kick(Vector3(0.0, -0.012, 0.05), Vector3(4.0, 0.0, -2.0))
	if _camera_controller:
		_camera_controller.add_shake(0.35)
		_camera_controller.add_punch(Vector3(1.6, randf_range(-0.8, 0.8), 0.0))

func fx_parry() -> void:
	_blade_sparks(22)
	_sfx(&"parry", sfx_parry, randf_range(0.97, 1.06))
	kick(Vector3(0.0, 0.0, 0.02), Vector3(1.5, 0.0, 0.0))
	if _camera_controller:
		_camera_controller.add_shake(0.3)
		_camera_controller.add_fov_kick(-5.0)
	# A beat of slow motion sells the deflection and opens the riposte.
	var slow: float = _player.config.parry_slowmo if _player and _player.config else 1.0
	if slow < 1.0:
		Engine.time_scale = slow
		get_tree().create_timer(0.14, true, false, true).timeout.connect(
			func() -> void: Engine.time_scale = 1.0)

func fx_guard_break() -> void:
	_blade_sparks(14)
	_sfx(&"clang", sfx_clang, 0.6)
	kick(Vector3(0.03, -0.06, 0.06), Vector3(10.0, 0.0, -8.0))
	if _camera_controller:
		_camera_controller.add_shake(0.6)
		_camera_controller.add_punch(Vector3(3.0, 0.0, 2.5))

func fx_shoot() -> void:
	_sfx(&"shoot", sfx_shoot, randf_range(0.95, 1.08))
	if _camera_controller:
		_camera_controller.add_punch(Vector3(1.6, randf_range(-0.4, 0.4), 0.0))

func fx_dry_fire() -> void:
	kick(Vector3(0.0, -0.004, 0.006), Vector3(0.8, 0.0, 0.0))

## Sparks where the blade meets an incoming blow, just ahead of the camera.
func _blade_sparks(amount: int) -> void:
	var cam: Node3D = get_parent() as Node3D
	if cam == null:
		return
	var at: Vector3 = cam.global_position - cam.global_basis.z * 0.7 + cam.global_basis.y * 0.05
	CombatFX.burst(_world(), at, cam.global_basis.z, Color(1.0, 0.85, 0.45), amount, 5.0, 0.03)
