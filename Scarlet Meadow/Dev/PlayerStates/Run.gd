# Run.gd
extends PlayerState

var skid_cooldown := 0.0
var accel_time := 0.0
	
func enter(previousState : Enums.STATE, _msg := {}):
	accel_time = 0.0
	if previousState == Enums.STATE.JumpFall or previousState == Enums.STATE.Skid:
		accel_time = 0.6
	pass

func physics_update(delta: float) -> void:
	accel_time += delta
	speed_multiplier = lerp(0, 1, clamp((accel_time + skid_cooldown)/.6, 0, 1))
	var player_input = player.get_requested_move_direction()
	
	skid_cooldown = move_toward(skid_cooldown, 0, delta)
	
	if not player_input:
		state_machine.transition_to(Enums.STATE.Idle)
		return
		
	if(player.input_buffer.is_action_just_pressed(Enums.INPUT.Jump)):
		player.do_jump()
		state_machine.transition_to(Enums.STATE.JumpFall)
		return
		
	if not player.grounded:
		state_machine.transition_to(Enums.STATE.JumpFall)
		return
		
	if player_input.dot(player.get_horizontal_velocity().normalized()) < -.4 and skid_cooldown <= 0:
		skid_cooldown = .5
		state_machine.transition_to(Enums.STATE.Skid, {"direction": player_input})
		return

	player.requested_move_direction = player_input
