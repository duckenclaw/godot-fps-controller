extends State

## Sliding state - player slides in facing direction with momentum

var slide_direction: Vector3

func enter() -> void:
	# Set slide height
	player.set_slide_height()

	# Disable manual camera tilting during slide
	player.camera.disable_manual_tilt()

	# Get horizontal velocity direction
	var horizontal_velocity = Vector3(player.velocity.x, 0, player.velocity.z)

	# If player has momentum, use it; otherwise use camera forward
	if horizontal_velocity.length() > 0.1:
		slide_direction = horizontal_velocity.normalized()
	else:
		var forward = -player.camera_pivot.global_transform.basis.z
		slide_direction = Vector3(forward.x, 0, forward.z).normalized()

	# Start with current speed or minimum slide speed
	var current_horizontal_speed = horizontal_velocity.length()
	var slide_speed = max(current_horizontal_speed, player.config.slide_speed)
	player.velocity.x = slide_direction.x * slide_speed
	player.velocity.z = slide_direction.z * slide_speed

func update(delta: float) -> String:
	# Check if falling
	if not player.is_on_floor():
		return "FallingState"

	# Get current horizontal speed
	var horizontal_velocity = Vector3(player.velocity.x, 0, player.velocity.z)
	var current_speed = horizontal_velocity.length()

	# Exit slide when speed reaches zero (momentum depleted)
	if current_speed <= 0.1:
		# Check if crouch is still toggled on
		if player.is_crouch_toggled:
			var input_dir = player.get_input_direction()
			if input_dir.length() > 0:
				return "MovingState"  # Will handle crouch movement
			else:
				return "CrouchingState"  # Stay crouched in place
		else:
			# Crouch was toggled off during slide
			var input_dir = player.get_input_direction()
			if input_dir.length() > 0:
				return "MovingState"
			else:
				return "IdleState"
	elif not player.is_crouch_toggled:
		var input_dir = player.get_input_direction()
		if input_dir.length() > 0:
			return "MovingState"
		else:
			return "IdleState"

	# Apply friction to slow down
	var new_speed = max(0, current_speed - player.config.friction * 0.25 * delta)
	player.velocity.x = slide_direction.x * new_speed
	player.velocity.z = slide_direction.z * new_speed

	# Apply gravity
#	player.velocity.y -= player.config.gravity * delta

	player.move_and_slide()

	return ""

func exit() -> void:
	# Re-enable manual camera tilting
	player.camera.enable_manual_tilt()

	# Don't restore height here - let the next state handle it
