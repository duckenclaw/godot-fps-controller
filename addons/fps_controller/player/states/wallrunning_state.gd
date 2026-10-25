extends State

## Wallrunning state - player runs along walls

var wall_normal: Vector3
var wallrun_direction: Vector3
var current_wallrun_speed: float
var current_gravity: float
var step_timer: float = 0.0
const WALLRUN_STEP_INTERVAL: float = 0.1  # Time between steps while wallrunning

func enter() -> void:
	player.set_normal_height()

	# Get wall normal from raycast
	wall_normal = player.get_wallrun_normal()

	# Calculate wallrun direction (perpendicular to wall normal)
	var forward = -player.camera_pivot.global_transform.basis.z
	wallrun_direction = forward - wall_normal * forward.dot(wall_normal)
	wallrun_direction = wallrun_direction.normalized()

	# Initialize wallrun parameters
	current_wallrun_speed = player.config.wallrun_speed
	current_gravity = player.config.wallrun_gravity

	# Set initial wallrun velocity
	player.velocity = wallrun_direction * current_wallrun_speed
	player.velocity.y = 0

	# Reset step timer
	step_timer = 0.0

	# Play initial footstep sound when starting wallrun
	if player.camera:
		player.camera.play_footstep(current_wallrun_speed)

	# Set camera tilt based on which side the wall is on
	update_camera_tilt()

func update(delta: float) -> String:
	# Check for jump off wall
	if player.jump_pressed:
		# Jump away from wall while preserving forward momentum
		# Blend wall normal (away) with wallrun direction (forward)
		var away_from_wall = wall_normal * player.config.wallrun_jump_horizontal_velocity
		var forward_momentum = wallrun_direction * player.config.wallrun_jump_forward_boost

		# Combine directions for diagonal jump
		var jump_direction = (away_from_wall + forward_momentum).normalized()
		var total_horizontal_speed = player.config.wallrun_jump_horizontal_velocity + player.config.wallrun_jump_forward_boost

		player.velocity = jump_direction * total_horizontal_speed
		player.velocity.y = player.config.wallrun_jump_velocity

		# Play jump sound
		if player.camera:
			player.camera.play_jump_sound()

		return "JumpingState"

	# Decrease horizontal speed over time
	current_wallrun_speed -= player.config.wallrun_speed_decay * delta
	current_wallrun_speed = max(current_wallrun_speed, player.config.wallrun_min_speed)

	# Increase gravity over time (fall faster as wallrun continues)
	current_gravity += player.config.wallrun_gravity_increase * delta
	current_gravity = min(current_gravity, player.config.gravity)  # Cap at normal gravity

	# Check if speed is too low to continue wallrunning
	if current_wallrun_speed <= player.config.wallrun_min_speed:
		return "FallingState"

	# Check if no longer touching wall
	if not player.can_wallrun():
		return "FallingState"

	# Update wall normal and direction
	wall_normal = player.get_wallrun_normal()
	var forward = -player.camera_pivot.global_transform.basis.z
	wallrun_direction = forward - wall_normal * forward.dot(wall_normal)
	wallrun_direction = wallrun_direction.normalized()

	# Update camera tilt
	update_camera_tilt()

	# Move along wall with decreasing speed
	player.velocity.x = wallrun_direction.x * current_wallrun_speed
	player.velocity.z = wallrun_direction.z * current_wallrun_speed

	# Apply increasing gravity (slide down faster over time)
	player.velocity.y -= current_gravity * delta

	# Update step timer and play footsteps
	step_timer += delta
	if step_timer >= WALLRUN_STEP_INTERVAL:
		step_timer = 0.0
		if player.camera:
			player.camera.play_footstep(current_wallrun_speed)

	player.move_and_slide()

	return ""

func exit() -> void:
	# Clear camera tilt override when exiting wallrun
	player.camera.clear_tilt_override()

## Update camera tilt based on which side the wall is on
func update_camera_tilt() -> void:
	# Determine which side the wall is on
	if player.wallrun_raycast_right.is_colliding():
		# Wall is on the right, tilt left (away from wall)
		player.camera.set_tilt_override(player.config.tilt_angle)
	elif player.wallrun_raycast_left.is_colliding():
		# Wall is on the left, tilt right (away from wall)
		player.camera.set_tilt_override(-player.config.tilt_angle)
