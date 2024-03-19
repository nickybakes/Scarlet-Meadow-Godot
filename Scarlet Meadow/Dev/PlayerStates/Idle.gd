# Idle.gd
extends PlayerState

func _init():
	speed_multiplier = 1

# Upon entering the state, we set the Player node's velocity to zero.
func enter(previousState: Enums.STATE, _msg := {}) -> void:
	player.requested_move_direction = Vector3.ZERO
	# We must declare all the properties we access through `owner` in the `Player.gd` script.
	# player.velocity = Vector3.ZERO


func update(delta: float) -> void:
	# If you have platforms that break when standing on them, you need that check for 
	# the character to fall.
	if player.get_requested_move_direction():
		state_machine.transition_to(Enums.STATE.Run)
		
	if(player.input_buffer.is_action_just_pressed(Enums.INPUT.Jump)):
		player.do_jump()
		state_machine.transition_to(Enums.STATE.JumpFall)
		return
		
	if not player.grounded:
		state_machine.transition_to(Enums.STATE.JumpFall)
		return
		
	var wall_interact = player.request_wall_interactions()
	if wall_interact[0][0] and player.time_grounded > .2:
		state_machine.transition_to(Enums.STATE.ClimbFromGround, {"wallNormal": wall_interact[0][1]})
		return
	
	if wall_interact[1][0] and player.time_grounded > .2:
		state_machine.transition_to(Enums.STATE.Vault, {"direction": wall_interact[1][1]})
		return
#	if not player.is_on_floor():
#		state_machine.transition_to("Air")
#		return
#
#	if Input.is_action_just_pressed("move_up"):
#		# As we'll only have one air state for both jump and fall, we use the `msg` dictionary 
#		# to tell the next state that we want to jump.
#		state_machine.transition_to("Air", {do_jump = true})
#	elif Input.is_action_pressed("move_left") or Input.is_action_pressed("move_right"):
#		state_machine.transition_to("Run")
