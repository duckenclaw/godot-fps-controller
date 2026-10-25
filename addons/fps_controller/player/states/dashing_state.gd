extends State

## Dashing state - moves player in camera direction including vertically

var dash_timer: float = 0.0
var dash_direction: Vector3

func enter() -> void:
	dash_timer = player.config.dash_duration
	player.is_crouch_toggled = false
	player.set_normal_height()

	# Get dash direction from camera (including vertical component)
	dash_direction = -player.camera_3d.global_transform.basis.z

	# Set dash velocity
	player.velocity = dash_direction * player.config.dash_speed

	# Play jump sound
	if player.camera:
		player.camera.play_jump_sound()

func update(delta: float) -> String:
	dash_timer -= delta

	# End dash when timer expires
	if dash_timer <= 0:
		if player.is_on_floor():
			var input_dir = player.get_input_direction()
			if input_dir.length() > 0:
				return "MovingState"
			else:
				return "IdleState"
		else:
			return "FallingState"

	# Maintain dash velocity
	player.velocity = dash_direction * player.config.dash_speed

	player.move_and_slide()

	return ""

func exit() -> void:
	dash_timer = 0.0
