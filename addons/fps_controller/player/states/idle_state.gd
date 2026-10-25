extends State

## Idle state - player is standing still

func enter() -> void:
	# Set height based on crouch toggle
	# (Though if toggled, we'll immediately transition to CrouchingState)
	if player.is_crouch_toggled:
		player.set_crouch_height()
	else:
		player.set_normal_height()

func update(delta: float) -> String:
	# Check for jump
	if player.jump_pressed and player.is_on_floor():
		return "JumpingState"

	# Check for dash
	if player.dash_pressed:
		return "DashingState"

	# Check for crouch toggle
	if player.is_crouch_toggled:
		return "CrouchingState"

	# Check for movement
	var input_dir = player.get_input_direction()
	if input_dir.length() > 0:
		return "MovingState"

	# Check if falling
	if not player.is_on_floor():
		return "FallingState"

	# Apply gravity and friction
#	player.velocity.y -= player.config.gravity * delta
	player.velocity.x = move_toward(player.velocity.x, 0, player.config.friction * delta)
	player.velocity.z = move_toward(player.velocity.z, 0, player.config.friction * delta)

	player.move_and_slide()

	return ""

func exit() -> void:
	pass
