@tool
extends Node3D

const FLOAT_MAX = 1.79769e308;

@export var showBoundary := true:
	set(value):
		boundaryMesh.visible = value;
		showBoundary = value;
@export_range(1, 3, .5) var voxelSize := 2.0
@export_range(1, 8) var octreeDepth := 3
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
		
@export_category("Visuals For Debuggin")

@export var CreateNavMeshVisual := false:
	set(value):
		createNavMeshVisual();
		
@export var DeleteNavMeshVisual := false:
	set(value):
		deleteNavMeshVisual();
		
@export var CreateOctreeVisual := false:
	set(value):
		createOctreeVisual();
		
@export var DeleteOctreeVisual := false:
	set(value):
		deleteOctreeVisual();
		
@export var probeDebugButton := false:
	set(value):
		var start = $"../NavPathStart";
		var end = $"../NavPathEnd";
		var path = shortestPath(start.position, end.position);
		drawShortestPath(path);
		
var navMeshMaterial = preload("res://Dev/Nav/M_NavMesh_01.tres");
var octreeVisualMaterial = preload("res://Dev/Nav/M_NavBoundary_01.tres");

var probeAmount := Vector3.ZERO;
var boundsMin := Vector3.ZERO;
var boundsMax := Vector3.ZERO;
var navMesh;
var currentStep := 0;
var currentOctStep = [];
var numOcts = 0;
var numProbes = 0;
var currentCompletedOcts = 0;
var currentCompletedProbes = 0;
var creatingNavMesh := false;

var probeList;

var mainOct;

var navPathStart = null;
var navPathStartPosition = Vector3.ZERO;
var navPathEnd = null;
var navPathEndPosition = Vector3.ZERO;

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
	else:
		navPathStart = get_node_or_null("../NavPathStart");
		navPathEnd = get_node_or_null("../NavPathEnd");

func createNavMesh():
	
	match(currentStep):
		0:
			print();
			print("************");
			print("Creating nav mesh...");
			print("Checking for and deleting previous nav mesh...");
			currentStep += 1;
		1:
			deleteNavMesh();
			currentStep += 1;
		2:
			print("--------------");
			print("Creating probes...");
			currentStep += 1;
		3:
			boundsMax = position + Vector3(scale.x * 25, scale.y * 25, scale.z * 25);
			boundsMin = position + Vector3(scale.x * -25, scale.y * -25, scale.z * -25);
			probeAmount = Vector3(abs(boundsMax - boundsMin)/voxelSize);
			
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
						createProbe(space, query, probe, pos, x, y, z, collided, result, directions);
				
			currentStep += 1;
			numProbes = probeList.size();
			print(str(numProbes) + " probes created");
		5:
			print("Creating temporary octree...");
			currentStep += 1;
		6:
			createOctree();
			currentStep += 1;
		7:
			print("Linking probe neighbors...")
			currentCompletedProbes = 0;
			currentStep += 1;
		8:
			for probe in probeList:
				for x in range(-1, 2):
					for y in range(-1, 2):
						for z in range(-1, 2):
							if(x == 0 and y == 0 and z == 0):
								continue;
							var neighbor = getPossibleProbeAtPoint(probe.position + (Vector3(x, y, z) * voxelSize));
							if(neighbor != -1):
								probe.neighbors.push_back(neighbor);
			currentStep += 1;
		9:
			for probe in probeList:
				#check if this is at the top of a wall and should be a VAULT type probe
				if(probe.probeType == PROBETYPE.WALL):
					for neighborIndex in probe.neighbors:
						var neighbor = probeList[neighborIndex];
						if(neighbor.probeType == PROBETYPE.GROUND or neighbor.probeType == PROBETYPE.CLIMBSTART):
							if(probe.position.y < neighbor.position.y):
								var dist1 = (probe.collisions[0].position).distance_squared_to(neighbor.collisions[0].position)
								var dist2 = (probe.collisions[0].position + (probe.collisions[0].normal * .2)).distance_squared_to(neighbor.collisions[0].position + (neighbor.collisions[0].normal * .2))
								if(dist1 < dist2):
									probe.probeType = PROBETYPE.VAULT;
									break;
			currentStep += 1;
		10:
			print("Shrinkwrapping probes and creating final octree...");
			for probe in probeList:
				probe.position = lerp(probe.position, probe.collisions[0].position, .5)
			currentStep += 1;
		11:
			createOctree();
			#for empty leaf octs (octs at the end of a brand who have no more children),
			#find the closest probe to them so if we try to find a probe in this empty oct
			#we can just get this closest probe as an approximation
			for child in mainOct.children:
				setClosestProbeToEmptyOcts(child);
			currentStep += 1;
		12:
			print("Finalizing mesh...");
			currentStep += 1;
		13:
			createNavMeshVisual();
			currentStep += 1;
		_:
			print("~~~~~~~~~~~~~~");
			print("Nav mesh created!")
			creatingNavMesh = false;
			currentStep += 1;
	
	
func drawShortestPath(path : Array):
	var oldMesh = get_node_or_null("../ShortestPathVisualizer");
	if(oldMesh != null):
		oldMesh.free();
		
	var st = SurfaceTool.new();
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var size = .2;
	for i in path.size() - 1:
		var pA = path[i].position;
		var pB = path[i + 1].position;
		addQuadColor(st, [pA + (Vector3(0, 0, 1) * size), pA + (Vector3(0, 0, -1) * size), pB + (Vector3(0, 0, -1) * size), pB + (Vector3(0, 0, 1) * size)], Color.BLACK);
		addQuadColor(st, [pA + (Vector3(1, 0, 0) * size), pA + (Vector3(-1, 0, 0) * size), pB + (Vector3(-1, 0, 0) * size), pB + (Vector3(1, 0, 0) * size)], Color.BLACK);
		addQuadColor(st, [pA + (Vector3(0, 1, 0) * size), pA + (Vector3(0, -1, 0) * size), pB + (Vector3(0, -1, 0) * size), pB + (Vector3(0, 1, 0) * size)], Color.BLACK);


	var arrayMesh = st.commit();
	var visualMesh = MeshInstance3D.new()
	visualMesh.set_name("ShortestPathVisualizer")
	visualMesh.mesh = arrayMesh;
	visualMesh.set_surface_override_material(0, navMeshMaterial);
	visualMesh.set_cast_shadows_setting(GeometryInstance3D.SHADOW_CASTING_SETTING_OFF);
	get_tree().edited_scene_root.add_child(visualMesh, true);
	visualMesh.owner = get_tree().edited_scene_root;

func getCleanProbe(probe : Dictionary) -> Dictionary:
	return {"index": probe.index, "position": probe.position, "probeType": probe.probeType};
	
func shortestPath(start : Vector3, end : Vector3) -> Array:
	var startProbe = getProbeClosestToPoint(start);
	var endProbe = getProbeClosestToPoint(end);
	var visited = {startProbe.index: true};
	var startProbeClean = getCleanProbe(startProbe);
	var endProbeClean = getCleanProbe(endProbe);
	var finalPath = [startProbeClean];
	var currentProbe = startProbe;
	while currentProbe.position != endProbe.position:
		var closestDistanceSquared = FLOAT_MAX;
		var bestNeighbor = {};
		for neighborIndex in currentProbe.neighbors:
			if(visited.has(neighborIndex)):
				continue;
			var neighbor = probeList[neighborIndex];
			var dist = neighbor.position.distance_squared_to(endProbe.position);
			if(dist < closestDistanceSquared):
				closestDistanceSquared = dist;
				bestNeighbor = neighbor;
		if(bestNeighbor == {}):
			if(finalPath.size() == 1):
				print("Could not find a path!");
				return finalPath;
			finalPath.resize(finalPath.size() - 1);
		else:
			finalPath.push_back(getCleanProbe(bestNeighbor));
			visited[bestNeighbor.index] = true;
		currentProbe = probeList[finalPath[finalPath.size() - 1].index];
			
	
	finalPath.push_back(endProbeClean);
	return finalPath;

func getProbeClosestToPoint(point : Vector3) -> Dictionary:
	var oct = getOctFromPoint(point);
	if(oct.probes.size() == 0):
		return probeList[oct.closestProbeIfEmpty];
	var closestProbe = probeList[oct.probes[0]];
	var closestDistanceSquared = FLOAT_MAX;
	if(oct.probes.size() > 1):
		for probe in oct.probes:
			var dist = probeList[probe].position.distance_squared_to(point);
			if(dist < closestDistanceSquared):
				closestDistanceSquared = dist;
				closestProbe = probeList[probe];
	return closestProbe;
	
func createNavMeshVisual():
	if(mainOct == {} or probeList == []):
		print("No nav mesh made yet! Create a nav mesh first!")
		return;
	
	var oldMesh = get_node_or_null("../NavMeshVisualizer");
	if(oldMesh != null):
		oldMesh.free();
		
	var st = SurfaceTool.new();
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var size = .3;
	for probe in probeList:
		addQuadColor(st, [probe.position + (Vector3(0, -1, 0) * size), probe.position + (Vector3(1, 0, 0) * size), probe.position + (Vector3(0, 1, 0) * size), probe.position + (Vector3(-1, 0, 0) * size)], getVertexColor(probe.probeType));
		addQuadColor(st, [probe.position + (Vector3(0, 0, -1) * size), probe.position + (Vector3(0, -1, 0) * size), probe.position + (Vector3(0, 0, 1) * size), probe.position + (Vector3(0, 1, 0) * size)], getVertexColor(probe.probeType));
		addQuadColor(st, [probe.position + (Vector3(-1, 0, 0) * size), probe.position + (Vector3(0, 0, -1) * size), probe.position + (Vector3(1, 0, 0) * size), probe.position + (Vector3(0, 0, 1) * size)], getVertexColor(probe.probeType));

	var arrayMesh = st.commit();
	var visualMesh = MeshInstance3D.new()
	visualMesh.set_name("NavMeshVisualizer")
	visualMesh.mesh = arrayMesh;
	visualMesh.set_surface_override_material(0, navMeshMaterial);
	visualMesh.set_cast_shadows_setting(GeometryInstance3D.SHADOW_CASTING_SETTING_OFF);
	get_tree().edited_scene_root.add_child(visualMesh, true);
	visualMesh.owner = get_tree().edited_scene_root;
		
	return;

func deleteNavMeshVisual():
	var oldMesh = get_node_or_null("../NavMeshVisualizer");
	if(oldMesh != null):
		oldMesh.free();
		print("Nav mesh visual deleted!");
	else:
		print("No nav mesh visual to delete!");

func getVertexColor(probeType : PROBETYPE) -> Color:
	var color = Color(0, 0, 0);
	match(probeType):
		PROBETYPE.GROUND:
			color = Color(0, 0.4, 0);
		PROBETYPE.WALL:
			color = Color(0, 0.0, 1);
		PROBETYPE.VAULT:
			color = Color(1, 0.8, 0);
		PROBETYPE.CLIMBSTART:
			color = Color(1, 0.0, 0);
	return color;

func getNeighborClosestToOrientation(probe: Dictionary, axis : Vector3, usedNeighbors : Array) -> int:
	var result = -1;
	var highestDot = -1;
	for neighborIndex in probe.neighbors:
		var neighbor = probeList[neighborIndex];
		var dot = axis.dot((neighbor.position - probe.position).normalized());
		if(dot > .6):
			if(dot > highestDot and !usedNeighbors.has(neighborIndex)):
				result = neighborIndex
				highestDot = dot;
	return result;

func getOrientatedNeighbors(probe: Dictionary, rightAxis : Vector3, downAxis : Vector3):
	var usedNeighbors = [];
	if(probe.rightNeighbor == -1):
		probe.rightNeighbor = getNeighborClosestToOrientation(probe, rightAxis, usedNeighbors);
		usedNeighbors.push_back(probe.rightNeighbor);
	
	if(probe.downNeighbor == -1):
		probe.downNeighbor = getNeighborClosestToOrientation(probe, downAxis, usedNeighbors);
		usedNeighbors.push_back(probe.downNeighbor);
	
	if(probe.leftNeighbor == -1):
		probe.leftNeighbor = getNeighborClosestToOrientation(probe, -rightAxis, usedNeighbors);
		usedNeighbors.push_back(probe.leftNeighbor);
	
	if(probe.upNeighbor == -1):
		probe.upNeighbor = getNeighborClosestToOrientation(probe, -downAxis, usedNeighbors);

func setClosestProbeToEmptyOcts(oct : Dictionary):
	if oct.children.size() > 0:
		for child in oct.children:
			setClosestProbeToEmptyOcts(child);
	elif oct.probes.size() == 0:
		var closestDistanceSquared = FLOAT_MAX;
		for probe in probeList:
			var dist = oct.center.distance_squared_to(probe.position);
			if(dist < closestDistanceSquared):
				oct.closestProbeIfEmpty = probe.index;
				closestDistanceSquared = dist;

func getPossibleProbeAtPoint(point : Vector3) -> int:
	var oct = getOctFromPoint(point);
	for probe in oct.probes:
		if(probeList[probe].position == point):
			return probe;
	return -1;

func getOctChildIndexFromPoint(point : Vector3, center : Vector3) -> int:
	var index = 0;
	if(point.x < center.x):
		index += 4;
	if(point.y < center.y):
		index += 2;
	if(point.z < center.z):
		index += 1;
	return index;
		

func getOctFromPoint(point : Vector3) -> Dictionary:
	var currentOct = mainOct;
	var childIndex = 0;
	while(currentOct.children.size() != 0):
		childIndex = getOctChildIndexFromPoint(point, currentOct.center);
		currentOct = currentOct.children[childIndex];
	return currentOct;

func createOctreeVisual():
	if(mainOct == {}):
		print("No octree made yet! Create a nav mesh first!")
		return;
	
	var oldMesh = get_node_or_null("../OctreeVisualizer");
	if(oldMesh != null):
		oldMesh.free();
		
	var st = SurfaceTool.new();
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	
	for oct in mainOct.children:
		addOctreeVisualVertices(st, oct);
	
	var arrayMesh = st.commit();
	var visualMesh = MeshInstance3D.new()
	visualMesh.set_name("OctreeVisualizer")
	visualMesh.mesh = arrayMesh;
	visualMesh.set_surface_override_material(0, octreeVisualMaterial);
	visualMesh.set_cast_shadows_setting(GeometryInstance3D.SHADOW_CASTING_SETTING_OFF);
	get_tree().edited_scene_root.add_child(visualMesh, true);
	visualMesh.owner = get_tree().edited_scene_root;

	
func addOctreeVisualVertices(st : SurfaceTool, oct : Dictionary):
	for child in oct.children:
		addOctreeVisualVertices(st, child);
	var x = oct.boundsMin.x;
	var y = oct.boundsMin.y;
	var z = oct.boundsMin.z;
	var x2 = oct.boundsMax.x;
	var y2 = oct.boundsMax.y;
	var z2 = oct.boundsMax.z;
	
	addQuad(st, [Vector3(x,y,z), Vector3(x2,y,z), Vector3(x2,y2,z), Vector3(x,y2,z)], Vector3.FORWARD);
	addQuad(st, [Vector3(x2,y,z), Vector3(x2,y,z2), Vector3(x2,y2,z2), Vector3(x2,y2,z)], Vector3.RIGHT);
	addQuad(st, [Vector3(x2,y,z2), Vector3(x,y,z2), Vector3(x,y2,z2), Vector3(x2,y2,z2)], Vector3.BACK);
	addQuad(st, [Vector3(x,y,z2), Vector3(x,y,z), Vector3(x,y2,z), Vector3(x,y2,z2)], Vector3.LEFT);
	addQuad(st, [Vector3(x,y2,z), Vector3(x2,y2,z), Vector3(x2,y2,z2), Vector3(x,y2,z2)], Vector3.UP);
	addQuad(st, [Vector3(x2,y,z2), Vector3(x2,y,z), Vector3(x,y,z), Vector3(x,y,z2)], Vector3.DOWN);

func addQuadColor(st : SurfaceTool, vertices : Array, color : Color):
	st.set_color(color);
	st.add_vertex(vertices[0]);
	st.set_color(color);
	st.add_vertex(vertices[1]);
	st.set_color(color);
	st.add_vertex(vertices[3]);
	st.set_color(color);
	st.add_vertex(vertices[3]);
	st.set_color(color);
	st.add_vertex(vertices[1]);
	st.set_color(color);
	st.add_vertex(vertices[2]);
	
func addQuad(st : SurfaceTool, vertices : Array, normal : Vector3):
	st.set_normal(normal);
	st.add_vertex(vertices[0]);
	st.set_normal(normal);
	st.add_vertex(vertices[1]);
	st.set_normal(normal);
	st.add_vertex(vertices[3]);
	st.set_normal(normal);
	st.add_vertex(vertices[3]);
	st.set_normal(normal);
	st.add_vertex(vertices[1]);
	st.set_normal(normal);
	st.add_vertex(vertices[2]);

func deleteOctreeVisual():
	var oldMesh = get_node_or_null("../OctreeVisualizer");
	if(oldMesh != null):
		oldMesh.free();
		print("Octree visual deleted!");
	else:
		print("No octree visual to delete!");

func countOcts(currentOct):
	for oct in currentOct.children:
		countOcts(oct)
	numOcts += 1;

func putProbeInOct(probe, currentOct) -> bool:
	if(isPointWithinBounds(probe.position, currentOct.boundsMin, currentOct.boundsMax)):
		while(currentOct.children.size() == 0 and currentOct.depth < octreeDepth):
			subdivide(currentOct);
		if currentOct.depth < octreeDepth:
			for oct in currentOct.children:
				if(putProbeInOct(probe, oct)):
					return true;
		else:
			currentOct.probes.push_back(probe.index);
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
	return {"center": center, "boundsMin": bMin, "boundsMax": bMax, "children": [], "probes": [], "depth": depth, "closestProbeIfEmpty": -1}

func createOctree():
	currentCompletedOcts = 0;
	mainOct = {};
	mainOct = createOct(position, boundsMin, boundsMax, 0);
	for probe in probeList:
		putProbeInOct(probe, mainOct)
	
	numOcts = 0;
	countOcts(mainOct);
	print(str(numOcts) + " octants created");

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

func createProbe(space, query, probe, pos, x, y, z, collided, result, directions):
	var probeType = PROBETYPE.NONE;
	pos = boundsMin + (Vector3(x, y, z) * voxelSize);
	collided = [];
	result = null;
	query.from = pos;
	query.to = pos + Vector3.DOWN * voxelSize;
	result = space.intersect_ray(query)
	if(result and result.normal == Vector3.ZERO):
		return;
		
	if(result and result.normal.y > .625):
		probeType = PROBETYPE.GROUND;
		collided.push_back(result);
		
	for i in range(1, directions.size()):
		query.to = pos + directions[i] * voxelSize;
		result = space.intersect_ray(query)
		if(result and result.normal.y < .3 and result.normal.y > -.3):
			if(probeType == PROBETYPE.GROUND):
				probeType = PROBETYPE.CLIMBSTART;
			else:
				probeType = PROBETYPE.WALL;
			collided.push_back(result);
		if(collided.size() > 1):
			break;
	
	if(collided.size() > 0):
		probeList.push_back({"index": probeList.size(), "position": pos, "collisions": collided, "probeType": probeType, "neighbors": []});

func deleteNavMesh():
	if(probeList == [] and mainOct == {}):
		print("No nav mesh to delete!");
		return;
	probeList = [];
	mainOct = {};
	var oldMesh = get_node_or_null("../NavMeshVisualizer");
	if(oldMesh != null):
		oldMesh.free();
	print("Nav mesh deleted!");
	pass

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	if(creatingNavMesh):
		createNavMesh();
	else:
		if(navPathStart != null and navPathEnd != null):
			if(navPathStart.position != navPathStartPosition or navPathEnd.position != navPathEndPosition):
				navPathStartPosition = navPathStart.position;
				navPathEndPosition = navPathEnd.position;
				var path = shortestPath(navPathStartPosition, navPathEndPosition);
				drawShortestPath(path);
	pass
