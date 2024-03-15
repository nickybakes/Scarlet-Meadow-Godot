# Run.gd
extends PlayerState

var initialVelocity : Vector3
var wallNormal : Vector3
var climbingInput : Vector2
var timeClimbing : float

func _init():
	gravity_enabled = false
	
func enter(previousState : Enums.STATE, _msg := {}):
	timeClimbing = 0;
	player.grounded = false;
	player.fake_grounded = true;
	wallNormal = _msg["wallNormal"]
	initialVelocity = player.velocity;
	if(initialVelocity.y < 0):
		initialVelocity *= .5;
	else:
		initialVelocity = Vector3.ZERO;
		
	#stick player to wall
	player.velocity = wallNormal * -2;
	for n in 4:
		player.move_and_slide();
		
	player.velocity = initialVelocity;
	pass
	
func exit():
	player.time_in_air = 0.0;
	player.fake_grounded = false;

func update(delta: float) -> void:
	var player_input = player.get_requested_move_direction()	
	var initialMoveSpeed = initialVelocity.length();
	if(initialMoveSpeed > .2):
		var decelAmount = 40
		var currentVelDirection : Vector3 = initialVelocity/initialMoveSpeed
		initialMoveSpeed = move_toward(initialMoveSpeed, 0, decelAmount * delta)
		initialVelocity = currentVelDirection * initialMoveSpeed
		player.velocity = initialVelocity;
		print("aaa")
	else:	
		player.velocity = Vector3.ZERO;
		player.requested_move_direction = player_input
		
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
