# Run.gd
extends PlayerState

var direction : Vector3

func _init():
	gravity_enabled = false
	
func enter(previousState : Enums.STATE, _msg := {}):
	direction = _msg["direction"]
	player.requested_move_direction = -direction
	player.velocity = (-direction + Vector3(0, 8, 0)) * player.current_speed()
	player.do_jump()
	pass

func update(delta: float) -> void:
	
	if(state_machine.time_in_state > .3):
		if(!player.grounded):
			state_machine.transition_to(Enums.STATE.JumpFall)
			return

		if(player.grounded):
			state_machine.transition_to(Enums.STATE.Run)
			return
