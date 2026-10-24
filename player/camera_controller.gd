class_name CameraController
extends Node3D

## Camera controller - handles camera movement, rotation, tilting, head bobbing, and FOV

@onready var camera: Camera3D = $Camera3D
@onready var player: CharacterBody3D = owner

var config: PlayerConfig

# Camera rotation
var rotation_x: float = 0.0
var rotation_y: float = 0.0

# Head tilt
var current_tilt: float = 0.0
var target_tilt: float = 0.0
var tilt_override_active: bool = false
var tilt_override_angle: float = 0.0
var manual_tilt_enabled: bool = true

# Head bobbing
var bob_time: float = 0.0
var last_bob_phase: float = 0.0
var was_moving: bool = false

# Footsteps
var footsteps_player: AudioStreamPlayer3D = null
var step_sounds: Array[AudioStream] = []
var jump_sound: AudioStream = null
const STEP_PITCH_MIN: float = 0.9
const STEP_PITCH_MAX: float = 1.1

# FOV
var current_fov: float = 75.0

# Screen shake (applied via the camera's frustum offset so it never fights the
# rotation/bob/tilt logic above). add_shake() accumulates strength; it decays.
var shake_strength: float = 0.0
const SHAKE_DECAY: float = 5.0
const SHAKE_MAX_OFFSET: float = 0.25

func _ready() -> void:
	# Capture mouse
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	# Get config from player
	if player:
		config = player.config
		if config:
			# Load FOV from GameSettings (overrides config base_fov)
			current_fov = GameSettings.field_of_view
			config.base_fov = current_fov  # Update config to match
			camera.fov = current_fov

	# Get footsteps player reference
	if player and player.has_node("FootstepsPlayer"):
		footsteps_player = player.get_node("FootstepsPlayer")

	# Load multiple step sounds
	step_sounds = [
		load("res://assets/sounds/steps/step0.wav"),
		load("res://assets/sounds/steps/step1.wav"),
		load("res://assets/sounds/steps/step2.wav")
	]

	# Load jump sound
	jump_sound = load("res://assets/sounds/jump.wav")

func _input(event: InputEvent) -> void:
	if not config:
		return

	# Don't process input when paused
	if player and player.is_paused:
		return

	# Handle mouse movement
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_camera(event.relative)

func _process(delta: float) -> void:
	if not config:
		return

	# Don't process when paused
	if player and player.is_paused:
		return

	# Gamepad right-stick look (mouse look is handled in _input)
	update_gamepad_look(delta)

	# Update tilt
	update_tilt(delta)

	# Update FOV based on speed
	update_fov(delta)

	# Update screen shake
	update_shake(delta)

## Rotate camera based on mouse movement
func rotate_camera(relative: Vector2) -> void:
	# Apply invert settings, scale by mouse sensitivity, then hand to the shared core.
	var horizontal_input = relative.x * (-1 if config.invert_camera_x else 1)
	var vertical_input = relative.y * (-1 if config.invert_camera_y else 1)
	apply_look(horizontal_input * config.mouse_sensitivity, vertical_input * config.mouse_sensitivity)

## Apply an already-scaled look delta (radians) to body yaw and camera pitch.
## Shared by the mouse and gamepad look paths.
func apply_look(yaw_delta: float, pitch_delta: float) -> void:
	# Horizontal rotation (Y axis) - rotate the player body
	rotation_y -= yaw_delta
	player.rotation.y = rotation_y

	# Vertical rotation (X axis) - rotate the camera
	rotation_x -= pitch_delta
	rotation_x = clamp(rotation_x, -PI/2, PI/2)
	camera.rotation.x = rotation_x

## Poll the right analog stick and rotate the camera (frame-rate independent).
func update_gamepad_look(delta: float) -> void:
	var look := Vector2(
		Input.get_joy_axis(0, JOY_AXIS_RIGHT_X),
		Input.get_joy_axis(0, JOY_AXIS_RIGHT_Y))

	# Radial deadzone so stick drift never nudges the camera.
	var magnitude := look.length()
	if magnitude < config.controller_deadzone:
		return

	# Rescale past the deadzone to 0..1 and square for finer control near center.
	var scaled := (magnitude - config.controller_deadzone) / (1.0 - config.controller_deadzone)
	scaled = clamp(scaled, 0.0, 1.0)
	look = look.normalized() * scaled * scaled

	# Apply invert settings (X follows the mouse invert; Y has its own controller toggle).
	var horizontal_input = look.x * (-1 if config.invert_camera_x else 1)
	var vertical_input = look.y * (-1 if config.invert_controller_y else 1)

	var speed := config.controller_look_sensitivity * delta
	apply_look(horizontal_input * speed, vertical_input * speed)

## Update head tilt based on input
func update_tilt(delta: float) -> void:
	# Check if tilt is being overridden by a state
	if tilt_override_active:
		target_tilt = tilt_override_angle
		# Calculate horizontal offset based on override angle
		var tilt_input = tilt_override_angle / deg_to_rad(config.tilt_angle)
		var target_x_offset = -tilt_input * config.tilt_shift
		camera.position.x = lerp(camera.position.x, target_x_offset, config.tilt_speed * delta)
	elif manual_tilt_enabled:
		# Get tilt input only if manual tilting is enabled
		var tilt_input = 0.0
		if Input.is_action_pressed("tilt_left"):
			tilt_input = 1.0
		elif Input.is_action_pressed("tilt_right"):
			tilt_input = -1.0

		# Update target tilt
		target_tilt = tilt_input * deg_to_rad(config.tilt_angle)

		# Move camera horizontally based on tilt (left tilt = shift left, right tilt = shift right)
		var target_x_offset = -tilt_input * config.tilt_shift
		camera.position.x = lerp(camera.position.x, target_x_offset, config.tilt_speed * delta)
	else:
		# Manual tilt disabled, return to neutral
		target_tilt = 0.0
		camera.position.x = lerp(camera.position.x, 0.0, config.tilt_speed * delta)

	# Smoothly interpolate to target tilt
	current_tilt = lerp(current_tilt, target_tilt, config.tilt_speed * delta)
	camera.rotation.z = current_tilt

## Update head bobbing when moving
func update_movement(speed: float, delta: float) -> void:
	var is_moving = speed > 0.1 and player.is_on_floor()

	if is_moving:
		var previous_bob_time = bob_time
		bob_time += delta * config.bob_frequency * speed
		var bob_offset = sin(bob_time) * config.bob_amplitude
		camera.position.y = bob_offset

		# Detect footsteps - trigger when sine wave crosses from negative to positive (bottom of bob)
		var current_phase = fmod(bob_time, TAU)
		var previous_phase = fmod(previous_bob_time, TAU)

		# Check if we crossed PI (bottom of the step cycle)
		if (previous_phase < PI and current_phase >= PI) or (previous_phase < TAU and current_phase >= TAU):
			play_footstep(speed)

		was_moving = true
	else:
		# Play stop sound when transitioning from moving to stopped
		if was_moving and player.is_on_floor():
			play_footstep(0.0)
			was_moving = false

		# Return to center
		bob_time = 0
		camera.position.y = lerp(camera.position.y, 0.0, 10.0 * delta)

## Update FOV based on player speed
func update_fov(delta: float) -> void:
	var horizontal_velocity = Vector3(player.velocity.x, 0, player.velocity.z)
	var speed = horizontal_velocity.length()

	# Increase FOV when moving fast
	var target_fov = config.base_fov
	if speed > config.fov_speed_threshold:
		var fov_increase = (speed - config.fov_speed_threshold) / config.fov_speed_threshold
		fov_increase = clamp(fov_increase, 0.0, 1.0)
		target_fov = lerp(config.base_fov, config.max_fov, fov_increase)

	# Smoothly interpolate FOV
	current_fov = lerp(current_fov, target_fov, 5.0 * delta)
	camera.fov = current_fov

## Set tilt override (used by states like wallrunning)
func set_tilt_override(angle_degrees: float) -> void:
	tilt_override_active = true
	tilt_override_angle = deg_to_rad(angle_degrees)

## Clear tilt override and return to normal behavior
func clear_tilt_override() -> void:
	tilt_override_active = false
	tilt_override_angle = 0.0

## Enable manual tilting (default)
func enable_manual_tilt() -> void:
	manual_tilt_enabled = true

## Disable manual tilting
func disable_manual_tilt() -> void:
	manual_tilt_enabled = false

## Play footstep sound with pitch variation based on speed
func play_footstep(speed: float) -> void:
	if not footsteps_player or step_sounds.is_empty():
		return

	# Don't play if already playing (prevent overlap)
	if footsteps_player.playing:
		return

	# Randomly select a step sound
	var random_index = randi() % step_sounds.size()
	footsteps_player.stream = step_sounds[random_index]

	# Vary pitch based on speed (faster = higher pitch)
	var speed_factor = clamp(speed / 10.0, 0.5, 1.5)
	var pitch = lerp(STEP_PITCH_MIN, STEP_PITCH_MAX, speed_factor)
	footsteps_player.pitch_scale = pitch

	# Play the sound
	footsteps_player.play()

## Play landing sound (called from player states)
func play_landing_sound(impact_velocity: float = 0.0) -> void:
	if not footsteps_player or step_sounds.is_empty():
		return

	# Randomly select a step sound
	var random_index = randi() % step_sounds.size()
	footsteps_player.stream = step_sounds[random_index]

	# Vary pitch based on impact velocity (harder landing = lower pitch)
	var impact_factor = clamp(abs(impact_velocity) / 15.0, 0.0, 1.0)
	var pitch = lerp(1.0, 0.7, impact_factor)
	footsteps_player.pitch_scale = pitch

	# Play the sound with slightly higher volume for landing
	footsteps_player.play()

## Play jump sound (called from player states)
func play_jump_sound() -> void:
	if not footsteps_player or not jump_sound:
		return

	# Set jump sound as the stream
	footsteps_player.stream = jump_sound

	# Slight pitch variation for variety
	footsteps_player.pitch_scale = randf_range(0.95, 1.05)

	# Play the sound
	footsteps_player.play()

## Add screen shake. `amount` is roughly 0..1; calls stack and decay over time.
func add_shake(amount: float) -> void:
	shake_strength = min(shake_strength + amount, 1.0)

## Backwards-compatible alias (older states may call shake()).
func shake(intensity: float, _duration: float = 0.0) -> void:
	add_shake(intensity)

## Apply and decay the current shake via the camera's frustum offset.
func update_shake(delta: float) -> void:
	if shake_strength <= 0.0:
		camera.h_offset = 0.0
		camera.v_offset = 0.0
		return
	shake_strength = max(shake_strength - SHAKE_DECAY * delta, 0.0)
	var s := shake_strength * shake_strength  # ease out
	camera.h_offset = randf_range(-1.0, 1.0) * SHAKE_MAX_OFFSET * s
	camera.v_offset = randf_range(-1.0, 1.0) * SHAKE_MAX_OFFSET * s
