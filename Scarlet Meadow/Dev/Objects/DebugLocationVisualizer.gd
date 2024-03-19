extends Node3D

@onready var player = $"../Player" as PlayerStatus


# Called when the node enters the scene tree for the first time.
func _ready():
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	position = player.debug[0];
	pass
