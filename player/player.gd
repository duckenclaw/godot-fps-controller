extends CharacterBody3D


@export var config: PlayerConfig

# Player stats
@export_group("Stats")
@export var max_health: float = 100.0
@export var max_mana: float = 100.0
@export var max_stamina: float = 100.0

var health: float = 100.0
var mana: float = 100.0
var stamina: float = 100.0

@onready var collision_shape: CollisionShape3D = $CollisionShape3D
@onready var camera_pivot: CameraController = $CameraPivot
@onready var camera: CameraController = $CameraPivot
@onready var camera_3d: Camera3D = $CameraPivot/Camera3D
@onready var interact_raycast: RayCast3D = $CameraPivot/Camera3D/InteractRayCast
@onready var hands: Hands = $CameraPivot/Camera3D/Hands
@onready var hold_point: Node3D = $CameraPivot/Camera3D/HoldPoint
@onready var grab_controller: GrabController = $GrabController
@onready var state_machine: StateMachine = $StateMachine
@onready var inventory: Inventory = $Inventory

# UI references
@onready var hud: Control = $CanvasLayer/HUD if has_node("CanvasLayer/HUD") else null
@onready var pause_menu: Control = $CanvasLayer/PauseMenu if has_node("CanvasLayer/PauseMenu") else null
@onready var inventory_screen: InventoryScreen = $CanvasLayer/InventoryScreen if has_node("CanvasLayer/InventoryScreen") else null

# Currently equipped items (ItemResource references)
var equipped_left_item: ItemResource
var equipped_right_item: ItemResource

# Inventory open flag — gates input / physics the same way is_paused does.
var is_inventory_open: bool = false

# Input flags (set during input handling, used by states)
var jump_pressed: bool = false
var dash_pressed: bool = false
var crouch_pressed: bool = false

# Interact tap-vs-hold tracking: a quick tap picks an item up into the inventory,
# while holding the button grabs a "movable" object (see _physics_process).
const INTERACT_HOLD_TIME: float = 0.25
var _interact_pressed: bool = false   # button is down and being tracked
var _interact_time: float = 0.0       # how long it has been held this press
var _interact_consumed: bool = false  # this press already grabbed/dropped — no tap pickup

# Crouch toggle state
var is_crouch_toggled: bool = false

# Track if currently falling from a jump (for coyote time)
var is_falling_from_jump: bool = false

# Game state
var is_paused: bool = false

# Physics frames to ignore discrete action presses for, set when a menu closes.
# Stops the button that closed the menu (e.g. B, which is also dash) from leaking
# a dash/jump/crouch into gameplay on the resume frame.
var _suppress_action_frames: int = 0

# Stable key used by SaveManager so the player persists across scenes/saves.
var save_id: String = "player"

# Wallrun detection
@onready var wallrun_raycast_right: RayCast3D = RayCast3D.new()
@onready var wallrun_raycast_left: RayCast3D = RayCast3D.new()

# Height settings
const NORMAL_HEIGHT: float = 2.0
const CROUCH_HEIGHT: float = 1.25
const SLIDE_HEIGHT: float = 1.0
const CAMERA_OFFSET: float = 0.1
const HEIGHT_TRANSITION_SPEED: float = 10.0
var current_height: float = NORMAL_HEIGHT
var target_height: float = NORMAL_HEIGHT

func _ready() -> void:
	# Create default config if none exists
	if not config:
		config = PlayerConfig.new()

	# Load settings from GameSettings singleton
	config.mouse_sensitivity = GameSettings.mouse_sensitivity
	config.invert_camera_x = GameSettings.invert_camera_x
	config.invert_camera_y = GameSettings.invert_camera_y
	config.difficulty = GameSettings.difficulty

	# Register for the save system (see save_data/load_data below).
	add_to_group("saveable")

	# Setup wallrun raycasts
	setup_wallrun_raycasts()

	# Pass config to camera
	if camera:
		camera.config = config

	# Initialize stats
	health = max_health
	mana = max_mana
	stamina = max_stamina

	# Connect to pause menu
	if pause_menu:
		pause_menu.player = self

	# Let hands aim with the camera and consume ammo from the inventory
	if hands:
		hands.setup(self, inventory)

	# Let the grab controller manipulate "movable" objects in front of the camera
	if grab_controller:
		grab_controller.setup(camera_3d, hold_point, hands)

	# Wire inventory UI
	if inventory_screen:
		inventory_screen.bind(self)
	if inventory:
		inventory.changed.connect(_refresh_quick_hud)
		inventory.quick_changed.connect(_refresh_quick_hud)
		inventory.pickup_failed.connect(_on_inventory_pickup_failed)

	# Update HUD
	update_hud()
	_refresh_quick_hud()

	# Set initial height
	set_player_height(NORMAL_HEIGHT)

func _input(event: InputEvent) -> void:
	# Handle pause (Esc / Options button). Deliberately NOT ui_cancel: B is bound to
	# both ui_cancel and dash, so opening pause on ui_cancel made dashing pop the menu.
	if event.is_action_pressed("pause"):
		if is_inventory_open and inventory_screen:
			inventory_screen.close()
			return
		toggle_pause()
		return

	# Quick save / load (work even while paused above is handled separately).
	if event.is_action_pressed("quicksave"):
		SaveManager.save_game(0)
		if hud and hud.has_method("show_toast"):
			hud.show_toast("Game saved")
		return
	if event.is_action_pressed("quickload"):
		if SaveManager.has_save(0):
			SaveManager.load_game(0)
		return

	# Don't process other inputs when paused
	if is_paused:
		return

	# Toggle inventory
	if event.is_action_pressed("inventory"):
		if inventory_screen:
			inventory_screen.toggle()
		return

	# While inventory is open, only allow UI — block gameplay actions.
	if is_inventory_open:
		return

	# Interact: tap = pick item into inventory; hold = grab a movable object.
	# While already holding a movable object, a press drops it.
	if event.is_action_pressed("interact"):
		if grab_controller.is_holding():
			grab_controller.drop()
			_interact_consumed = true
		_interact_pressed = true
		_interact_time = 0.0
	elif event.is_action_released("interact"):
		# A quick release that didn't grab/drop counts as a tap → pick up.
		if _interact_pressed and not _interact_consumed and not grab_controller.is_holding():
			try_pickup()
		_interact_pressed = false
		_interact_consumed = false

	# Handle hand actions — while holding, the hands instead drop/throw the object.
	if event.is_action_pressed("left_hand"):
		if grab_controller.is_holding():
			grab_controller.drop()
		else:
			hands.use_left_hand()

	if event.is_action_pressed("right_hand"):
		if grab_controller.is_holding():
			grab_controller.throw()
		else:
			hands.use_right_hand()

	# Reload the right hand's ranged weapon
	if event.is_action_pressed("reload"):
		hands.reload_right_hand()

	# Quick-equip
	for i in 8:
		if event.is_action_pressed("equip_%d" % (i + 1)):
			equip_from_quick(i)
			return

func _physics_process(delta: float) -> void:
	# Don't process physics when paused or inventory is open
	if is_paused or is_inventory_open:
		return

	# Smoothly interpolate height
	update_height_smooth(delta)

	# Once interact has been held long enough, grab the movable object in view.
	if _interact_pressed and not Input.is_action_pressed("interact"):
		# Release was swallowed (e.g. inventory opened mid-press) — reset tracking.
		_interact_pressed = false
		_interact_consumed = false
	elif _interact_pressed and not _interact_consumed and not grab_controller.is_holding():
		_interact_time += delta
		if _interact_time >= INTERACT_HOLD_TIME:
			var movable: Node3D = get_movable_in_view()
			if movable:
				grab_controller.grab(movable)
				_interact_consumed = true

	# Update input flags for states to use. Skip for a couple of frames right after a
	# menu closes so the closing button press doesn't leak into gameplay.
	if _suppress_action_frames > 0:
		_suppress_action_frames -= 1
		jump_pressed = false
		dash_pressed = false
		crouch_pressed = false
	else:
		jump_pressed = Input.is_action_just_pressed("jump")
		dash_pressed = Input.is_action_just_pressed("dash")
		crouch_pressed = Input.is_action_just_pressed("crouch")

	# Toggle crouch state when crouch is pressed
	if crouch_pressed:
		is_crouch_toggled = not is_crouch_toggled

## Get 2D input direction.
## Uses Input.get_vector so the analog stick gets proper circular deadzone handling
## and graduated magnitude; keyboard still yields full-length cardinals/diagonals.
func get_input_direction() -> Vector2:
	return Input.get_vector("left", "right", "backward", "forward")

## Get 3D movement direction relative to camera
func get_move_direction() -> Vector3:
	var input_dir = get_input_direction()

	# Get camera forward and right vectors (flattened to XZ plane)
	var forward = -camera_pivot.global_transform.basis.z
	forward.y = 0
	forward = forward.normalized()

	var right = camera_pivot.global_transform.basis.x
	right.y = 0
	right = right.normalized()

	# Calculate movement direction
	return (forward * input_dir.y + right * input_dir.x).normalized()

## Tap interact: trigger the object's interact() (e.g. pick a Pickup into inventory).
func try_pickup() -> void:
	if interact_raycast.is_colliding():
		var collider = interact_raycast.get_collider()
		if collider and collider.has_method("interact"):
			collider.interact()

## Return the "movable" object currently under the interact ray, if any.
func get_movable_in_view() -> Node3D:
	if interact_raycast.is_colliding():
		var collider = interact_raycast.get_collider()
		if collider and collider.is_in_group(&"movable"):
			return collider
	return null

## Setup wallrun detection raycasts
func setup_wallrun_raycasts() -> void:
	# Right raycast
	wallrun_raycast_right.target_position = Vector3(1.0, 0, 0)
	wallrun_raycast_right.enabled = true
	add_child(wallrun_raycast_right)

	# Left raycast
	wallrun_raycast_left.target_position = Vector3(-1.0, 0, 0)
	wallrun_raycast_left.enabled = true
	add_child(wallrun_raycast_left)

## Check if player can wallrun
func can_wallrun() -> bool:
	# Must be in the air
	if is_on_floor():
		return false

	# Must be moving
	var input_dir = get_input_direction()
	if input_dir.length() < 0.1:
		return false

	# Check if either side has a wall
	var has_wall = wallrun_raycast_right.is_colliding() or wallrun_raycast_left.is_colliding()
	if not has_wall:
		return false

	# Get wall normal
	var wall_normal = get_wallrun_normal()

	# Don't wallrun if facing the wall directly
	var forward = -camera_pivot.global_transform.basis.z
	var dot = forward.dot(wall_normal)

	# If dot product is positive, player is facing away from wall (good for wallrun)
	# If negative, player is facing the wall (don't wallrun)
	return dot > -0.3

## Get the normal vector of the wall player is next to (for wallrunning)
func get_wallrun_normal() -> Vector3:
	if wallrun_raycast_right.is_colliding():
		return wallrun_raycast_right.get_collision_normal()
	elif wallrun_raycast_left.is_colliding():
		return wallrun_raycast_left.get_collision_normal()
	return Vector3.ZERO

# ====================
# Height Management
# ====================

## Set target player height (will interpolate smoothly)
func set_player_height(height: float) -> void:
	target_height = height

## Update height with smooth interpolation
func update_height_smooth(delta: float) -> void:
	if abs(current_height - target_height) > 0.01:
		current_height = lerp(current_height, target_height, HEIGHT_TRANSITION_SPEED * delta)

		# Update collision shape
		if collision_shape and collision_shape.shape is CapsuleShape3D:
			var capsule: CapsuleShape3D = collision_shape.shape
			capsule.height = current_height

			# Position collision shape so bottom stays at ground (y = 0)
			# Capsule center should be at height / 2
			collision_shape.position.y = current_height / 2.0

		# Update camera position (height - offset from top)
		if camera_pivot:
			camera_pivot.position.y = current_height - CAMERA_OFFSET

## Set to normal standing height
func set_normal_height() -> void:
	set_player_height(NORMAL_HEIGHT)

## Set to crouching height
func set_crouch_height() -> void:
	set_player_height(CROUCH_HEIGHT)

## Set to sliding height
func set_slide_height() -> void:
	set_player_height(SLIDE_HEIGHT)

# ====================
# Stat Management
# ====================

## Update health value and clamp it
func set_health(value: float) -> void:
	health = clamp(value, 0, max_health)
	update_hud()
	if health <= 0:
		die()

## Update mana value and clamp it
func set_mana(value: float) -> void:
	mana = clamp(value, 0, max_mana)
	update_hud()

## Update stamina value and clamp it
func set_stamina(value: float) -> void:
	stamina = clamp(value, 0, max_stamina)
	update_hud()

## Take damage. `source` is whoever dealt it (optional). Scales with difficulty,
## announces on the EventBus, and triggers screen shake + a HUD damage flash.
func take_damage(amount: float, source: Node = null) -> void:
	if amount <= 0.0:
		return
	amount *= _difficulty_damage_multiplier()
	set_health(health - amount)

	EventBus.damage_dealt.emit(self, amount, source)

	# Feedback: shake intensity scales with the hit, clamped to a sane range.
	if camera and camera.has_method("add_shake"):
		camera.add_shake(clampf(amount / 25.0, 0.15, 1.0))
	if hud and hud.has_method("flash_damage"):
		hud.flash_damage()

## Incoming-damage multiplier from the difficulty setting (Easy 0.5x, Hard 1.5x).
func _difficulty_damage_multiplier() -> float:
	match GameSettings.difficulty:
		"Easy": return 0.5
		"Hard": return 1.5
		_: return 1.0

## Heal player
func heal(amount: float) -> void:
	set_health(health + amount)

## Use mana
func use_mana(amount: float) -> bool:
	if mana >= amount:
		set_mana(mana - amount)
		return true
	return false

## Restore mana
func restore_mana(amount: float) -> void:
	set_mana(mana + amount)

## Use stamina
func use_stamina(amount: float) -> bool:
	if stamina >= amount:
		set_stamina(stamina - amount)
		return true
	return false

## Restore stamina
func restore_stamina(amount: float) -> void:
	set_stamina(stamina + amount)

## Update HUD display
func update_hud() -> void:
	if hud and hud.has_method("update_bar"):
		hud.update_bar("health", health, max_health)
		hud.update_bar("mana", mana, max_mana)
		hud.update_bar("stamina", stamina, max_stamina)

## Called when player dies. Announces on the EventBus, then respawns by reloading
## the most recent save if one exists, otherwise restarts the current level.
func die() -> void:
	EventBus.entity_died.emit(self)
	if SaveManager.has_save(0):
		SaveManager.load_game(0)
	else:
		SceneManager.reload_current_scene()

# ====================
# Save / Load (SaveManager "saveable" contract)
# ====================

## Serialise player state to a JSON-friendly dictionary.
func save_data() -> Dictionary:
	var items: Array = []
	if inventory:
		for anchor in inventory.all_anchors():
			var slot = inventory.get_slot_at_anchor(anchor)
			if slot and not slot.is_empty() and slot.item:
				items.append({"id": String(slot.item.id), "count": slot.count})
	return {
		"pos": [global_position.x, global_position.y, global_position.z],
		"yaw": rotation.y,
		"health": health,
		"mana": mana,
		"stamina": stamina,
		"items": items,
	}

## Restore player state from a dictionary produced by save_data().
func load_data(data: Dictionary) -> void:
	var p = data.get("pos", null)
	if p is Array and p.size() == 3:
		global_position = Vector3(p[0], p[1], p[2])
		velocity = Vector3.ZERO
	if data.has("yaw"):
		rotation.y = float(data["yaw"])
		if camera:
			camera.rotation_y = float(data["yaw"])

	health = float(data.get("health", health))
	mana = float(data.get("mana", mana))
	stamina = float(data.get("stamina", stamina))

	# Rebuild inventory contents from saved item ids (exact grid layout is not
	# preserved — items are re-added via try_pickup).
	if inventory and data.has("items"):
		for anchor in inventory.all_anchors():
			inventory.remove_stack(anchor)
		for entry in data["items"]:
			var item := ItemDB.get_item(StringName(entry.get("id", "")))
			if item:
				inventory.try_pickup(item, int(entry.get("count", 1)))

	update_hud()
	_refresh_quick_hud()

# ====================
# Pause System
# ====================

## Toggle pause state
func toggle_pause() -> void:
	if is_paused:
		resume_game()
	else:
		pause_game()

## Pause the game
func pause_game() -> void:
	is_paused = true
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	if pause_menu:
		pause_menu.visible = true
		pause_menu.show_main_menu()

## Resume the game
func resume_game() -> void:
	is_paused = false
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	suppress_action_input()

	if pause_menu:
		pause_menu.visible = false

## Ignore discrete action presses (jump/dash/crouch) for a few physics frames.
## Called when a menu closes so the closing button doesn't leak into gameplay.
func suppress_action_input(frames: int = 2) -> void:
	_suppress_action_frames = max(_suppress_action_frames, frames)

# ====================
# Inventory / Equip
# ====================

## Equip the item bound to a quick slot. If it's already held, move it to the other hand.
## Two-handed weapons go exclusively to the right hand and force the left hand empty.
func equip_from_quick(quick_idx: int) -> void:
	if inventory == null or hands == null:
		return
	var item: ItemResource = inventory.get_quick_item(quick_idx)
	if item == null:
		return

	# Two-handed weapons: right hand only, left must be empty.
	if item.is_two_handed():
		if item == equipped_right_item:
			_unequip_right()
		else:
			_unequip_left()
			_equip_right(item)
		return

	# Already in one of the hands -> swap to the other.
	if item == equipped_right_item:
		_unequip_right()
		_equip_left(item)
		return
	if item == equipped_left_item:
		_unequip_left()
		# Free up the right hand if a two-handed weapon is currently held.
		if equipped_right_item and equipped_right_item.is_two_handed():
			_unequip_right()
		_equip_right(item)
		return

	# Fresh equip: weapons (ranged or melee) go right, everything else left.
	if item.is_weapon():
		_equip_right(item)
	else:
		_equip_left(item)

func _equip_right(item: ItemResource) -> void:
	if item == null or item.model == null:
		return
	# Right slot is exclusive when occupied by a two-handed weapon.
	_unequip_right()
	hands.equip_right_hand(item)
	equipped_right_item = item
	_refresh_quick_hud()

func _equip_left(item: ItemResource) -> void:
	if item == null or item.model == null:
		return
	# Two-handed weapons cannot be placed in the left hand.
	if item.is_two_handed():
		_equip_right(item)
		return
	_unequip_left()
	hands.equip_left_hand(item)
	equipped_left_item = item
	_refresh_quick_hud()

func _unequip_right() -> void:
	if equipped_right_item == null:
		return
	hands.unequip_right_hand()
	equipped_right_item = null

func _unequip_left() -> void:
	if equipped_left_item == null:
		return
	hands.unequip_left_hand()
	equipped_left_item = null

func _refresh_quick_hud() -> void:
	if hud and hud.has_method("update_quick_bar"):
		hud.update_quick_bar(inventory, equipped_left_item, equipped_right_item)

func _on_inventory_pickup_failed(_item: ItemResource, _leftover: int) -> void:
	if hud and hud.has_method("show_toast"):
		hud.show_toast("Not enough space")
	elif inventory_screen and inventory_screen.visible:
		inventory_screen.show_pickup_failed()
