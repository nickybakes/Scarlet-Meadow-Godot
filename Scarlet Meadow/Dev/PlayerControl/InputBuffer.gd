class_name InputBuffer
extends Node

var inputs_pressed := [1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0]
var inputs_released := [1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0]
var inputs_held := [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
var maxInputBufferTime := .2
var inputs := ["jump", "strike", "grab", "interact", "dodge", "block", "lasso"]


# Called when the node enters the scene tree for the first time.
func _ready():
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	for n in inputs.size():
		inputs_pressed[n] += delta
		inputs_released[n] += delta
		if(Input.is_action_just_pressed(inputs[n])):
			inputs_pressed[n] = 0.0
			inputs_held[n] = 0.0
		if(Input.is_action_pressed(inputs[n])):
			inputs_held[n] += delta
		if(Input.is_action_just_released(inputs[n])):
			inputs_held[n] = 0.0
			inputs_released[n] = 0.0
			
func is_action_just_pressed(input : Enums.INPUT) -> bool:
	return inputs_pressed[input] < maxInputBufferTime
	
func is_action_just_released(input : Enums.INPUT) -> bool:
	return inputs_released[input] < maxInputBufferTime
	
func is_action_pressed(input : Enums.INPUT) -> bool:
	return inputs_held[input] > 0.0
	
func action_held_time(input : Enums.INPUT) -> float:
	return inputs_held[input]
