@tool
extends Node3D

@onready var displayMesh = $DisplayMesh;

# Called when the node enters the scene tree for the first time.
func _ready():
	if not Engine.is_editor_hint():
		displayMesh.visible = false


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	pass
