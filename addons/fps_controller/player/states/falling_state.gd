extends State

## Falling state - player is in the air and falling

var coyote_timer: float = 0.0

func enter() -> void:
	# Only apply coyote time if not falling from a jump
	if player.is_falling_from_jump:
		coyote_timer = 0.0
		player.is_falling_from_jump = false
	else:
		coyote_timer = player.config.coyote_time
	player.set_normal_height()

func update(delta: float) -> String:
	# Update coyote timer
	coyote_timer -= delta

	# Check for coyote jump
	if player.jump_pressed and coyote_timer > 0:
		return "JumpingState"

	# Check for dash
	if player.dash_pressed:
		return "DashingState"

	# Check for wallrun
	if player.can_wallrun():
		return "WallrunningState"

	# Check if landed
	if player.is_on_floor():
		# Play landing sound based on impact velocity
		if player.camera:
			player.camera.play_landing_sound(player.velocity.y)

		var input_dir = player.get_input_direction()
		if input_dir.length() > 0:
			return "MovingState"
		else:
			return "IdleState"

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
	coyote_timer = 0.0
