# Run.gd
extends PlayerState

var initialWallDragDirection : Vector2
var initialWallDragSpeed : float
var wallNormal : Vector3
var altWallNormal: Vector3;
var horizontalMoveAxis : Vector3
var verticalMoveAxis : Vector3
var climbingInput : Vector2
var climbingDirection : Vector3
var timeClimbing : float

func _init():
	gravity_enabled = false
	rotation_mode = Enums.ROTATION_MODE.Chosen_Direction
	movement_mode = Enums.MOVEMENT_MODE.None
	
func enter(previousState : Enums.STATE, _msg := {}):
	timeClimbing = 0;
	player.grounded = false;
	player.fake_grounded = true;
	
	if(player.velocity == Vector3.ZERO):
		player.velocity = Vector3(0, -.1, 0);
		
	setWall(_msg["wallNormal"])
	altWallNormal = wallNormal;
	calculateMovementAxis();
	calculateInitialWallSlide();
		
	#stick player to wall
	player.velocity = wallNormal * -2;
	for n in 4:
		player.move_and_slide();
		
	moveAlongWall(initialWallDragDirection, initialWallDragSpeed);
	pass
	
func exit():
	player.time_in_air = 0.0;
	player.fake_grounded = false;
	
func calculateInitialWallSlide():
	var dot = player.velocity.normalized().dot(horizontalMoveAxis);
	initialWallDragDirection = Vector2(dot, 1 - abs(dot));
	initialWallDragSpeed = (player.velocity * .5).length();
	
func setWall(normal: Vector3):
	wallNormal = normal;
	updateRotation(wallNormal)
	calculateMovementAxis()
	
func updateRotation(normal: Vector3):
	player.chosen_rotation_direction = Vector2(-normal.x, -normal.z);
	
func calculateMovementAxis():
	horizontalMoveAxis = Vector3(wallNormal.z, 0, -wallNormal.x).normalized();
	verticalMoveAxis = horizontalMoveAxis.cross(wallNormal);
	
func moveAlongWall(direction: Vector2, speed: float):
	climbingInput = direction;
	climbingDirection = (direction.x * horizontalMoveAxis + direction.y * verticalMoveAxis).normalized();
	player.velocity = climbingDirection * speed;	

func update(delta: float) -> void:
	var player_input = player.get_basic_input_dir();
	if(initialWallDragSpeed > 0):
		initialWallDragSpeed = initialWallDragSpeed - (delta * 40);
		moveAlongWall(initialWallDragDirection, initialWallDragSpeed);
	else:
		player.velocity = Vector3.ZERO;
		moveAlongWall(player_input, 6);
		
	if(player.grounded and player_input):
		state_machine.transition_to(Enums.STATE.Run)
		return
		
	if(player.grounded and not player_input):
		state_machine.transition_to(Enums.STATE.Idle)
		return
	
func physics_update(delta: float) -> void:
	timeClimbing += delta;
	if player.input_buffer.is_action_just_pressed(Enums.INPUT.Interact) and timeClimbing > .5:
		state_machine.transition_to(Enums.STATE.JumpFall);
		return
		
	var wall_check = player.raycast_climb(climbingDirection, wallNormal);
	
	var outset = wall_check[0]
	var inset = wall_check[1]
	var origin = wall_check[2]
	
	if outset:
		var dist = origin.distance_squared_to(outset.position)
		if(wallNormal != outset.normal):
			altWallNormal = outset.normal;
		updateRotation(lerp(wallNormal, altWallNormal, .5).normalized())
		if dist > 2.3:
			setWall(outset.normal)
			return
			
	if inset:
		var dist = origin.distance_squared_to(outset.position)
		if(wallNormal != outset.normal):
			altWallNormal = outset.normal;
		updateRotation(lerp(wallNormal, altWallNormal, .5).normalized())
		if dist > 2.3:
			setWall(outset.normal)
			return
			
	if(player.velocity.y > 0 and !outset):
		state_machine.transition_to(Enums.STATE.Vault, {"direction": wallNormal})
		return
		

