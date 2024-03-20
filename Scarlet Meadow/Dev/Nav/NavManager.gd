@tool
extends Node3D

@export var showBoundary := true:
	set(value):
		boundaryMesh.visible = value;
		showBoundary = value;
@export_range(1, 3, .5) var voxelSize := 2.0
@export var createNavOnPlay := false;
@onready var boundaryMesh = $BoundaryMesh;

@export_category("Commands")
@export var CreateNavMesh: bool:
	set(value):
		currentStep = 0;
		creatingNavMesh = true;
		
@export var DeleteProbes: bool:
	set(value):
		deleteProbes();
		
var probeScene = preload("res://Dev/Nav/Probe.tscn");

var currentStep := 0;
var creatingNavMesh := false;


# Called when the node enters the scene tree for the first time.
func _ready():
	if not Engine.is_editor_hint():
		boundaryMesh.visible = false
		if(createNavOnPlay):
			currentStep = 0;
			creatingNavMesh = true;

func createNavMesh():
	
	match(currentStep):
		0:
			print("Creating Nav Mesh...");
			print("Checking for and deleting previous probes...");
		1:
			deleteProbes();
		2:
			print("Spawning probes...");
		3:
			var boundsMax = position + Vector3(scale.x * 25, scale.y * 25, scale.z * 25);
			var boundsMin = position + Vector3(scale.x * -25, scale.y * -25, scale.z * -25);
			var probeAmount = Vector3(abs(boundsMax - boundsMin)/voxelSize);
	
			var probeHolder = Node3D.new()
			probeHolder.set_name("Probes")
			get_tree().edited_scene_root.add_child(probeHolder, true);
			probeHolder.owner = get_tree().edited_scene_root;
			var space = get_world_3d().direct_space_state;
			var query = PhysicsRayQueryParameters3D.create(Vector3.ZERO, Vector3.DOWN, 0b0011)
			query.collide_with_areas = false
			query.hit_back_faces = false
			query.hit_from_inside = true
			var probe;
			var pos;
			var collided = [];
			var result = null;
			var directions = [Vector3.DOWN, Vector3.FORWARD, Vector3.BACK, Vector3.RIGHT, Vector3.LEFT];
			for x in probeAmount.x:
				for y in probeAmount.y:
					for z in probeAmount.z:
						pos = boundsMin + (Vector3(x, y, z) * voxelSize);
						collided = [];
						result = null;
						query.from = pos;
						query.to = pos + Vector3.DOWN * voxelSize;
						result = space.intersect_ray(query)
						if(result and result.normal == Vector3.ZERO):
							continue;
							
						if(result):
							collided.push_back(result);
							
						for i in range(1, directions.size()):
							query.to = pos + directions[i] * voxelSize;
							result = space.intersect_ray(query)
							if(result):
								collided.push_back(result);
							if(collided.size() > 1):
								break;
						
						if(collided.size() > 0):
							probe = probeScene.instantiate();
							probeHolder.add_child(probe, true, Node.INTERNAL_MODE_BACK);
							probe.owner = get_tree().edited_scene_root
							probe.position = pos;
				
			print("Nav Mesh created!")
			creatingNavMesh = false;
	
func deleteProbes():
	var probeHolder = get_node_or_null("../Probes");
	if(probeHolder == null):
		print("No probs to delete!");
		return;
	print("Deleting probes...");
	probeHolder.free();
	print("Probes deleted!");
	pass

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	if(creatingNavMesh):
		createNavMesh();
		currentStep += 1;
	pass
