# Run.gd
extends PlayerState

func _init():
	control_rotation = false
	
func enter(previousState : Enums.STATE, _msg := {}):
	speed_multiplier = 1;

func update(delta: float) -> void:
	
	var player_input = player.get_requested_move_direction()
	
	if(player.grounded and player_input):
		state_machine.transition_to(Enums.STATE.Run)
		return
		
	if(player.grounded and not player_input):
		state_machine.transition_to(Enums.STATE.Idle)
		return
		
	player.requested_move_direction = player_input
	
func physics_update(delta: float) -> void:
	var wall_check = player.check_wall_interactions()
	var bot = wall_check[0]
	var mid = wall_check[1]
	var top = wall_check[2]
	
	var normal_to_use : Vector3
	
	var amount = 0
	if(bot):
		amount += 1
		normal_to_use = bot.normal
		
	if(top):
		amount += 1
		normal_to_use = top.normal		
		
	if(mid):
		amount += 1
		normal_to_use = mid.normal
	
	if player.input_buffer.is_action_just_pressed(Enums.INPUT.Interact):
		if top and player.time_in_air > .2:
			print("climb")
			return
	
	if player.input_buffer.is_action_just_pressed(Enums.INPUT.Interact):
		if !top and ((mid and bot) or (!mid and bot) or (mid and !bot)) and player.time_in_air > .2:
			print("vault")
			return
			
	if player.input_buffer.is_action_just_pressed(Enums.INPUT.Jump):
		if(amount >= 2) and player.time_in_air > .25 and player.is_on_wall_only():
			normal_to_use = Vector3(normal_to_use.x, 0, normal_to_use.z).normalized()
			state_machine.transition_to(Enums.STATE.Walljump, {"direction": normal_to_use})
			return
	
	if player.input_buffer.is_action_just_pressed(Enums.INPUT.Jump):
		if (player.road_runner_jump_available && player.time_in_air < player.ROAD_RUNNER_TIME_MAX):
			player.do_jump()
	pass
