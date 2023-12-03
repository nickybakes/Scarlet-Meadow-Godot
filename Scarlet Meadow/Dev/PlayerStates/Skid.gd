# Run.gd
extends PlayerState

var direction : Vector3
	
func enter(previousState : Enums.STATE, _msg := {}):
	direction = _msg["direction"]
	speed_multiplier = 0;

func physics_update(delta: float) -> void:
	
	if(player.input_buffer.is_action_just_pressed(Enums.INPUT.Jump)):
		state_machine.transition_to(Enums.STATE.SideFlip, {"direction": direction})
		return
	
	if(player.time_grounded < .3 or state_machine.time_in_state > .2):
		state_machine.transition_to(Enums.STATE.Run)
		return
