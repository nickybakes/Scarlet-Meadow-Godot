# Run.gd
extends PlayerState

var direction : Vector3

func _init():
	jump_multiplier = 1.5
	speed_multiplier = .8
	#control_rotation = false
	
func enter(previousState : Enums.STATE, _msg := {}):
	direction = _msg["direction"]
	player.requested_move_direction = direction
	player.velocity = direction * player.current_speed()
	player.do_jump()
	player.grounded = false
	pass

func update(delta: float) -> void:
	
	if(state_machine.time_in_state > .3):
		if(!player.grounded):
			state_machine.transition_to(Enums.STATE.JumpFall)
			return

		if(player.grounded):
			state_machine.transition_to(Enums.STATE.Run)
			return
