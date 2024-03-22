@tool
extends Node3D

enum PROBETYPE {
	GROUND,
	WALL,
	VAULT,
	CLIMBSTART,
	NONE
}

@onready var displayMesh = $DisplayMesh;

var mat1 = preload("res://Dev/Debug/M_DebugOnTop_01.tres");
var mat2 = preload("res://Dev/Debug/M_DebugOnTop_02.tres");
var mat3 = preload("res://Dev/Debug/M_DebugOnTop_03.tres");
var mat4 = preload("res://Dev/Debug/M_DebugOnTop_04.tres");

var collisions;

# Called when the node enters the scene tree for the first time.
func _ready():
	if not Engine.is_editor_hint():
		displayMesh.visible = false


func setMat(probeType, col):
	var mesh = $DisplayMesh;
	match(probeType):
		PROBETYPE.GROUND:
			mesh.set_surface_override_material(0, mat4);
		PROBETYPE.WALL:
			mesh.set_surface_override_material(0, mat2);
		PROBETYPE.CLIMBSTART:
			mesh.set_surface_override_material(0, mat1);
	pass

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	pass
