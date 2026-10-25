class_name PlayerConfig
extends Resource

## Player configuration resource containing all movement and camera settings

# Mechanics toggles — turn individual abilities on/off to tailor the controller
# to a genre. Disabling one also makes it safe to delete that ability's state node
# from the player's StateMachine (see player.gd can_* helpers). The "core" abilities
# (walk/run movement, jumping, crouching, interacting) have no flags; they always run.
@export_group("Mechanics")
@export var enable_sprint: bool = true          ## Hold-to-sprint (faster while holding "sprint").
@export var enable_crouch: bool = true          ## Crouch toggle (needs a CrouchingState node).
@export var enable_walk_run_toggle: bool = true ## Capslock toggles base speed walk<->run.
@export var enable_dash: bool = true            ## Dash in camera direction (needs a DashingState node).
@export var enable_slide: bool = true           ## Slide when crouching at sprint speed (needs a SlidingState node).
@export var enable_wallrun: bool = true         ## Wallrun along walls (needs a WallrunningState node).
@export var enable_grab: bool = true            ## Hold interact to grab/throw "movable" physics objects.
@export_group("")

# Movement speeds
@export var walk_speed: float = 3.0     ## Base speed in "walk" mode (walk/run toggle off).
@export var run_speed: float = 5.0      ## Base speed in "run" mode (default; walk/run toggle on).
@export var sprint_speed: float = 8.0   ## Speed while holding "sprint" (overrides walk/run).
@export var crouch_speed: float = 2.5
@export var slide_speed: float = 10.0
@export var wallrun_speed: float = 6.0

# Jump settings
@export var jump_velocity: float = 6.0
@export var min_jump_velocity: float = 3.0
@export var coyote_time: float = 10.15

# Dash settings
@export var dash_speed: float = 15.0
@export var dash_duration: float = 0.3

# Wallrun settings
@export var wallrun_gravity: float = 2.0
@export var wallrun_jump_velocity: float = 8.0
@export var wallrun_jump_horizontal_velocity: float = 5.0
@export var wallrun_jump_forward_boost: float = 3.0  # Forward momentum when jumping off wall
@export var wallrun_speed_decay: float = 2.0  # Speed decrease per second
@export var wallrun_gravity_increase: float = 3.0  # Gravity increase per second
@export var wallrun_min_speed: float = 1.0  # Minimum wallrun speed before falling

# Physics
@export var gravity: float = 20.0
@export var acceleration: float = 50.0
@export var friction: float = 50.0
@export var air_acceleration: float = 15.0

# Camera settings
@export var mouse_sensitivity: float = 0.002
@export var invert_camera_x: bool = false
@export var invert_camera_y: bool = false

# Controller / right-stick look
@export var controller_look_sensitivity: float = 3.0
@export var controller_deadzone: float = 0.2
@export var invert_controller_y: bool = false
@export var tilt_angle: float = 10.0
@export var tilt_speed: float = 5.0
@export var tilt_shift: float = 1.0  # Horizontal camera shift when tilting
@export var base_fov: float = 80.0
@export var max_fov: float = 120.0
@export var fov_speed_threshold: float = 8.0

# Head bobbing
@export var bob_frequency: float = 2.0
@export var bob_amplitude: float = 0.08

# Interaction
@export var interact_distance: float = 3.0

# Gameplay settings
@export var difficulty: String = "Normal"
