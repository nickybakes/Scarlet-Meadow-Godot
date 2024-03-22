@tool
extends Node3D

@export var showBoundary := true:
	set(value):
		boundaryMesh.visible = value;
		showBoundary = value;
@export_range(1, 3, .5) var voxelSize := 2.0
@export_range(1, 8) var octTreeDepth := 3
@export var createNavOnPlay := false;
@onready var boundaryMesh = $BoundaryMesh;

@export_category("Commands")
@export var CreateNavMesh: bool:
	set(value):
		currentStep = 0;
		creatingNavMesh = true;
		
@export var DeleteNavMesh: bool:
	set(value):
		deleteNavMesh();
		
@export var showOctTree := false:
	set(value):
		showOctTree = createOctTreeVisual();
		
		
var probeScene = preload("res://Dev/Nav/Probe.tscn");
var octVisualScene = preload("res://Dev/Nav/OctVisual.tscn");

var probeAmount := Vector3.ZERO;
var boundsMin := Vector3.ZERO;
var boundsMax := Vector3.ZERO;
var navMesh;
var currentStep := 0;
var currentOctStep = [];
var numOcts = 0;
var currentCompletedOcts = 0;
var creatingNavMesh := false;

var octTreeVisualStep := 0;
var creatingOctTreeVisual := false;

var probeList;

var mainOct;

#midPoint, childOcts, numberOfProbes, closestOctWithProbes

func _get_property_list():
	var properties = []
	
	properties.append({
	"name": "probeList",
	"type": TYPE_ARRAY,
	"usage": PROPERTY_USAGE_STORAGE,
	})
	
	properties.append({
		"name": "mainOct",
		"type": TYPE_DICTIONARY,
		"usage": PROPERTY_USAGE_STORAGE,
	})

	return properties


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
			print();
			print("--------------");
			print("Creating Nav Mesh...");
			print("Checking for and deleting previous probes...");
			currentStep += 1;
		1:
			deleteNavMesh();
			currentStep += 1;
		2:
			print("--------------");
			print("Detecting probes...");
			currentStep += 1;
		3:
			boundsMax = position + Vector3(scale.x * 25, scale.y * 25, scale.z * 25);
			boundsMin = position + Vector3(scale.x * -25, scale.y * -25, scale.z * -25);
			probeAmount = Vector3(abs(boundsMax - boundsMin)/voxelSize);
	
			navMesh = Node3D.new()
			navMesh.set_name("NavMesh")
			get_tree().edited_scene_root.add_child(navMesh, true);
			navMesh.owner = get_tree().edited_scene_root;
			
			probeList = [];
			
			currentStep += 1;
		4:
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
						detectProbe(space, query, probe, pos, x, y, z, collided, result, directions);
				
			currentStep += 1;
			print(str(probeList.size()) + " probes detected");
		5:
			print("--------------");
			print("Splitting octants...");
			currentStep += 1;
		6:
			currentCompletedOcts = 0;
			mainOct = {};
			#midPoint, childOcts, probes, depth, closestOctWithProbes
			mainOct = createOct(position, boundsMin, boundsMax, 0);
			for probe in probeList:
				putProbeInOct(probe, mainOct)
			
			numOcts = 0;
			countOcts(mainOct);
			print(str(numOcts) + " octants created");
			currentStep += 1;
		7:
			print("--------------");
			print("Spawning octants and probes...");
			currentCompletedOcts = 0;
			currentOctStep = [0];
			currentStep += 1;
		8:
			var currentOct = mainOct;
			for i in currentOctStep.size():
				currentOct = currentOct.children[currentOctStep[i]];
			
			while currentOct.children.size() > 1:
				currentOctStep.push_back(0);
				currentOct = currentOct.children[0];
				
				
			for pro in currentOct.probes:
				var probe = probeScene.instantiate();
				navMesh.add_child(probe, true, Node.INTERNAL_MODE_BACK);
				probe.owner = get_tree().edited_scene_root
				probe.position = pro.pos;
				probe.setMat(pro.probeType, pro.collisions);
				
			currentCompletedOcts += 1;			
			
			if(currentCompletedOcts == round(numOcts * .25)):
				print("25% complete");
			if(currentCompletedOcts == round(numOcts * .5)):
				print("50% complete");
			if(currentCompletedOcts == round(numOcts * .75)):
				print("75% complete");
			
			currentOctStep[currentOctStep.size() - 1] += 1;			
			while(currentOctStep.size() > 1 and currentOctStep[currentOctStep.size() - 1] > 7):
				currentOctStep.resize(currentOctStep.size() - 1);
				currentOctStep[currentOctStep.size() - 1] += 1;
			
			if(currentOctStep == [8]):
				currentStep += 1;
		9:
			print("--------------");			
			print("Nav Mesh created!")			
			creatingNavMesh = false;
			currentStep += 1;
	

func createOctTreeVisual() -> bool:
	var octtree = get_node_or_null("../OctTreeVisual");
	if(!creatingOctTreeVisual):
		if(octtree != null):
			octtree.free();
			return false;
		if(mainOct == {}):
			return false;
		octtree = Node3D.new()
		octtree.set_name("OctTreeVisual")
		get_tree().edited_scene_root.add_child(octtree, true);
		octtree.owner = get_tree().edited_scene_root;
		creatingOctTreeVisual = true;
	else:
		creatingOctTreeVisual = false;
		for oct in mainOct.children:
			spawnOctVisual(octtree, oct);
	return true;
	
func spawnOctVisual(octtree, oct):
	for oct2 in oct.children:
		spawnOctVisual(octtree, oct2);
	var octVisual = octVisualScene.instantiate();
	octtree.add_child(octVisual, true, Node.INTERNAL_MODE_BACK);
	octVisual.owner = get_tree().edited_scene_root
	octVisual.position = oct.center;
	octVisual.scale = abs(oct.boundsMax - oct.boundsMin);

func countOcts(currentOct):
	for oct in currentOct.children:
		countOcts(oct)
	numOcts += 1;

func putProbeInOct(probe, currentOct) -> bool:
	if(isPointWithinBounds(probe.pos, currentOct.boundsMin, currentOct.boundsMax)):
		while(currentOct.children.size() == 0 and currentOct.depth < octTreeDepth):
			subdivide(currentOct);
		if currentOct.depth < octTreeDepth:
			for oct in currentOct.children:
				if(putProbeInOct(probe, oct)):
					return true;
		else:
			currentOct.probes.push_back(probe);
			return true;
	return false;
			
func subdivide(parentOct):
	var size = abs(parentOct.boundsMax - parentOct.boundsMin);
	var halfSize = size/2.0;
	var quartSize = size/4.0;
	for i in 2:
		for j in 2:
			for k in 2:
				var mult = Vector3.ONE;
				if(i % 2 == 1):
					mult *= Vector3(-1, 1, 1);
				if(j % 2 == 1):
					mult *= Vector3(1, -1, 1);
				if(k % 2 == 1):
					mult *= Vector3(1, 1, -1);
				parentOct.children.push_back(createOctSize(parentOct.center + (quartSize * mult), quartSize, parentOct.depth + 1));

func createOctSize(center : Vector3, size : Vector3, depth : int) -> Dictionary:
	var bMin = center - size;
	var bMax = center + size;
	return createOct(center, bMin, bMax, depth);

func createOct(center : Vector3, bMin : Vector3, bMax : Vector3, depth : int) -> Dictionary:
	return {"center": center, "boundsMin": bMin, "boundsMax": bMax, "children": [], "probes": [], "depth": depth, "closestOctWithProbes": null}

func isPointWithinBounds(point : Vector3, bMin : Vector3, bMax : Vector3) -> bool:
	if(point.x < bMin.x or point.x > bMax.x):
		return false;
	if(point.y < bMin.y or point.y > bMax.y):
		return false;
	if(point.z < bMin.z or point.z > bMax.z):
		return false;
	return true;

enum PROBETYPE {
	GROUND,
	WALL,
	VAULT,
	CLIMBSTART,
	NONE
}

func detectProbe(space, query, probe, pos, x, y, z, collided, result, directions):
	var probeType = PROBETYPE.NONE;
	pos = boundsMin + (Vector3(x, y, z) * voxelSize);
	collided = [];
	result = null;
	query.from = pos;
	query.to = pos + Vector3.DOWN * voxelSize;
	result = space.intersect_ray(query)
	if(result and result.normal == Vector3.ZERO):
		return;
		
	if(result):
		probeType = PROBETYPE.GROUND;
		collided.push_back(result);
		
	for i in range(1, directions.size()):
		query.to = pos + directions[i] * voxelSize;
		result = space.intersect_ray(query)
		if(result):
			if(probeType == PROBETYPE.GROUND):
				probeType = PROBETYPE.CLIMBSTART;
			else:
				probeType = PROBETYPE.WALL;
			collided.push_back(result);
		if(collided.size() > 1):
			break;
	
	if(collided.size() > 0):
		probeList.push_back({"pos": pos, "collisions": collided, "probeType": probeType});

func deleteNavMesh():
	var navMesh = get_node_or_null("../NavMesh");
	if(navMesh == null):
		print("No NavMesh to delete!");
		return;
	print("Deleting NavMesh...");
	mainOct = {};
	navMesh.free();
	print("NavMesh deleted!");
	pass

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	if(creatingNavMesh):
		createNavMesh();
	if(creatingOctTreeVisual):
		createOctTreeVisual();
	pass
