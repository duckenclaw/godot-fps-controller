extends State

## Jumping state - handles jump with variable height and coyote time

var jump_released: bool = false

func enter() -> void:
	jump_released = false
	player.velocity.y = player.config.jump_velocity
	player.is_crouch_toggled = false
	player.set_normal_height()

	# Play jump sound
	if player.camera:
		player.camera.play_jump_sound()

func update(delta: float) -> String:
	# Variable jump height - if jump released early, reduce upward velocity
	if not Input.is_action_pressed("jump") and not jump_released and player.velocity.y > 0:
		player.velocity.y = max(player.velocity.y * 0.5, player.config.min_jump_velocity)
		jump_released = true

	# Check for dash
	if player.dash_pressed:
		return "DashingState"

	# Check for wallrun
#	if player.can_wallrun():
#		return "WallrunningState"

	# Transition to falling when moving downward
	if player.velocity.y < 0:
		player.is_falling_from_jump = true
		return "FallingState"

	# Air movement
	var input_dir = player.get_input_direction()
	if input_dir.length() > 0:
		var direction = player.get_move_direction()
		var target_velocity = direction * player.config.walk_speed
		player.velocity.x = move_toward(player.velocity.x, target_velocity.x, player.config.air_acceleration * delta)
		player.velocity.z = move_toward(player.velocity.z, target_velocity.z, player.config.air_acceleration * delta)

	# Apply gravity
	player.velocity.y -= player.config.gravity * delta

	player.move_and_slide()

	return ""

func exit() -> void:
	jump_released = false
