# Run.gd
extends PlayerState

var wallNormal : Vector3;
var timeInState : float;

func _init():
	rotation_mode = Enums.ROTATION_MODE.None
	
func enter(previousState : Enums.STATE, _msg := {}):
	player.do_jump(true);
	wallNormal = _msg["wallNormal"]
	timeInState = 0.0;
	speed_multiplier = 1;

func update(delta: float) -> void:
	timeInState += delta;
	if(timeInState > .07):
		state_machine.transition_to(Enums.STATE.Climb, {"wallNormal": wallNormal});
	
func physics_update(delta: float) -> void:
	pass
