extends State

## Moving state - handles regular movement, sprint, and crouch movement

var is_sprinting: bool = false
var is_crouching: bool = false

func enter() -> void:
	is_sprinting = false
	is_crouching = player.is_crouch_toggled

	# Set height based on crouch state
	if is_crouching:
		player.set_crouch_height()
	else:
		player.set_normal_height()

func update(delta: float) -> String:
	# Get input direction early for sprint/slide checks
	var input_dir = player.get_input_direction()

	# Update crouch state based on toggle
	var was_crouching = is_crouching

	# Update sprint state (only when moving forward and not crouching)
	# input_dir.y > 0.7 means player is pressing forward (not backward/strafing)
	is_sprinting = Input.is_action_pressed("sprint") and input_dir.y > 0.7 and not is_crouching
	
	# Check for slide (only when sprinting and crouch toggled on)
	if player.crouch_pressed and is_sprinting and not was_crouching:
		return "SlidingState"
	
	is_crouching = player.is_crouch_toggled

	# Check for jump
	if player.jump_pressed and player.is_on_floor():
		return "JumpingState"

	# Check for dash
	if player.dash_pressed:
		return "DashingState"


	# Check if stopped moving
	if input_dir.length() == 0:
		if player.is_on_floor():
			return "IdleState"
		else:
			return "FallingState"

	# Check if falling
	if not player.is_on_floor():
		return "FallingState"

	# Update height based on crouch state
	if is_crouching:
		player.set_crouch_height()
	else:
		player.set_normal_height()

	# Calculate target speed
	var target_speed = player.config.walk_speed
	if is_sprinting:
		target_speed = player.config.sprint_speed
	elif is_crouching:
		target_speed = player.config.crouch_speed

	# Get movement direction in 3D space
	var direction = player.get_move_direction()

	# Apply movement
	var target_velocity = direction * target_speed
	player.velocity.x = move_toward(player.velocity.x, target_velocity.x, player.config.acceleration * delta)
	player.velocity.z = move_toward(player.velocity.z, target_velocity.z, player.config.acceleration * delta)

	# Apply gravity
#	player.velocity.y -= player.config.gravity * delta

	player.move_and_slide()

	# Update camera based on movement
	player.camera.update_movement(player.velocity.length(), delta)

	return ""

func exit() -> void:
	is_sprinting = false
	is_crouching = false
