@tool
extends Node3D

const FLOAT_MAX = 1.79769e308;
const WORLD_COLLISION_MASK = 0b0011;

@export var showBoundary := true:
	set(value):
		if(boundaryMesh != null):
			boundaryMesh.visible = value;
			showBoundary = value;
@export_range(1, 3, .5) var voxelSize := 2.0
@export_range(1, 8) var octreeDepth := 3
@export var createNavOnPlay := false;
@onready var boundaryMesh = get_node_or_null("BoundaryMesh");

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
		var path = shortestPathFull(start.position, end.position);
		if(path != []):
			drawShortestPath(path);

@export_range(0, 99) var islandDebug := 0:
	set(value):
		if(value < islandList.size()):
			islandDebug = value;
			createNavMeshVisual();

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
var currentIslandPath;
var currentIslandScore;
var finalIslandPath;
var finalIslandScore;
var islandVisited;
var creatingNavMesh := false;

#nav mesh storage
var probeList;
var mainOct;
var islandList;

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
	
	properties.append({
		"name": "islandList",
		"type": TYPE_ARRAY,
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
			position = snapped(position, Vector3(.5, .5, .5));
			scale = snapped(scale, Vector3(.25, .25, .25));
			boundsMax = position + Vector3(scale.x * 25, scale.y * 25, scale.z * 25);
			boundsMin = position + Vector3(scale.x * -25, scale.y * -25, scale.z * -25);
			probeAmount = Vector3(abs(boundsMax - boundsMin)/voxelSize);
			
			probeList = [];
			
			currentStep += 1;
		4:
			var space = get_world_3d().direct_space_state;
			var query = PhysicsRayQueryParameters3D.create(Vector3.ZERO, Vector3.DOWN, WORLD_COLLISION_MASK)
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
								if(probe.probeType == PROBETYPE.WALL and probeList[neighbor].probeType == PROBETYPE.WALL):
									if(probe.collisions[0].normal.dot(probeList[neighbor].collisions[0].normal) < 0):
										continue;
								probe.neighbors.push_back(neighbor);
			currentStep += 1;
		9:
			print("Shrinkwrapping probes...");
			for probe in probeList:
				probe.position = lerp(probe.position, probe.collisions[0].position, .5)
			currentStep += 1;
		10:
			for probe in probeList:
				#check if this is at the top of a wall and should be a VAULT type probe
				if(probe.probeType == PROBETYPE.WALL):
					var spawnedDropOff = false;
					for neighborIndex in probe.neighbors:
						var neighbor = probeList[neighborIndex];
						if(neighbor.probeType == PROBETYPE.GROUND or neighbor.probeType == PROBETYPE.CLIMBSTART or neighbor.probeType == PROBETYPE.DROPOFF):
							if(probe.position.y < neighbor.position.y):
								var dist1 = (probe.collisions[0].position).distance_squared_to(neighbor.collisions[0].position)
								var dist2 = (probe.collisions[0].position + (probe.collisions[0].normal * .2)).distance_squared_to(neighbor.collisions[0].position + (neighbor.collisions[0].normal * .2))
								if(dist1 < dist2):
									probe.probeType = PROBETYPE.VAULT;
									neighbor.neighbors.erase(probe.index);
									if(!spawnedDropOff):
										var dropOffPoition = Vector3(probe.position.x, neighbor.position.y, probe.position.z);
										probeList.push_back({"index": probeList.size(), "position": dropOffPoition, "collisions": probe.collisions, "probeType": PROBETYPE.DROPOFF, "neighbors": [neighbor.index], "island": -1});
										for neighborIndex2 in neighbor.neighbors:
											if(!probeList[neighborIndex2].neighbors.has(probeList.size() - 1) and probeList[neighborIndex2].position.distance_to(dropOffPoition) < voxelSize):
												probeList[neighborIndex2].neighbors.push_back(probeList.size() - 1);
										neighbor.neighbors.push_back(probeList.size() - 1);
										spawnedDropOff = true;
			currentStep += 1;
		11:
			print("Creating islands...");
			islandList = [];
			currentStep += 1;
		12:
			for probe in probeList:
				if(probe.island != -1):
					continue;
				probe.island = islandList.size();
				islandList.push_back({"index": islandList.size(), "probes": [probe.index], "islandType": getIslandTypeFromProbeType(probe.probeType), "connections": []});
				addNeighborsToIsland(probe);
			
			print(str(islandList.size()) + " islands created");
			currentStep += 1;
		13:
			for probe in probeList:
				if(probe.probeType == PROBETYPE.DROPOFF):
					for island in islandList:
						if(island.index != probe.island):
							var closestProbe = {};
							if(island.islandType == ISLANDTYPE.GROUND):
								closestProbe = getClosestProbeInIslandToPoint(probe.position, island, 0, 1);
							if(island.islandType == ISLANDTYPE.WALL):
								closestProbe = getClosestProbeInIslandToPoint(probe.position, island, 8, -.2);
							if(closestProbe != {}):
								var horDist = Vector2(probe.position.x, probe.position.z).distance_to(Vector2(closestProbe.position.x, closestProbe.position.z));
								var verDist = probe.position.y - closestProbe.position.y;
								var t = horDist/11.0;
								var y = verDist + (17.5*t) - (22.5*(pow(t, 2.0)));
								if(y > 0):
									probe.neighbors.push_back(closestProbe.index);
			currentStep += 1;
		14:
			#finding all direct connections between each island
			for island in islandList:
				for probeIndex in island.probes:
					var probe = probeList[probeIndex];
					for neighborIndex in probe.neighbors:
						var neighbor = probeList[neighborIndex];
						if(neighbor.island != island.index):
							island.connections.push_back({"from": probe.index, "to": neighbor.index, "distance": probeList[probe.index].position.distance_to(probeList[neighbor.index].position)});
			currentStep += 1;
		15:
			print("Creating final octree...");
			createOctree();
			#for empty leaf octs (octs at the end of a brand who have no more children),
			#find the closest probe to them so if we try to find a probe in this empty oct
			#we can just get this closest probe as an approximation
			for child in mainOct.children:
				setClosestProbeToEmptyOcts(child);
			currentStep += 1;
		16:
			print("Finalizing mesh...");
			currentStep += 1;
		17:
			createNavMeshVisual();
			currentStep += 1;
		_:
			print("~~~~~~~~~~~~~~");
			print("Nav mesh created!")
			creatingNavMesh = false;
			currentStep += 1;
	
func islandShortestPath(currentIsland : Dictionary, homeIsland : Dictionary, goalIsland : Dictionary):
	for connectionIndex in currentIsland.connections:
		var connection = currentIsland.connections[connectionIndex];
		if(!islandVisited.has(probeList[connection.to].island)):
			if(probeList[connection.to].island == goalIsland.index):
				if(currentIslandScore < finalIslandScore):
					finalIslandScore = currentIslandScore;
					finalIslandPath = currentIslandPath.duplicate();
			elif(currentIslandScore + connection.score < finalIslandScore):
				islandVisited[probeList[connection.to].island] = true;
				currentIslandPath.push_back(connection);
				currentIslandScore += connection.score;
				islandShortestPath(islandList[probeList[connection.to].island], homeIsland, goalIsland);
				islandVisited.erase(probeList[connection.to].island);
				currentIslandPath.resize(currentIslandPath.size() - 1);
				currentIslandScore -= connection.score;
	
func islandConnectScore(from : Dictionary, to : Dictionary) -> float:
	var score = 0.0;
	if(from.probeType == PROBETYPE.DROPOFF and getIslandTypeFromProbeType(to.probeType) == ISLANDTYPE.GROUND):
		score = .1;
	elif(from.probeType == PROBETYPE.DROPOFF and getIslandTypeFromProbeType(to.probeType) == ISLANDTYPE.WALL):
		score = .2;
	elif(getIslandTypeFromProbeType(from.probeType) == ISLANDTYPE.GROUND and getIslandTypeFromProbeType(to.probeType) == ISLANDTYPE.GROUND):
		score = .25;
	elif(getIslandTypeFromProbeType(from.probeType) == ISLANDTYPE.GROUND and to.probeType == PROBETYPE.VAULT):
		score = .3;
	elif(getIslandTypeFromProbeType(from.probeType) == ISLANDTYPE.GROUND and to.probeType == PROBETYPE.WALL):
		score = .35;
	elif(getIslandTypeFromProbeType(from.probeType) == ISLANDTYPE.WALL and getIslandTypeFromProbeType(to.probeType) == ISLANDTYPE.WALL):
		score = .4;
	return score;
	
func raycast(start : Vector3, end : Vector3) -> Dictionary:
	var space = get_world_3d().direct_space_state;
	var query = PhysicsRayQueryParameters3D.create(start, end, WORLD_COLLISION_MASK)
	query.collide_with_areas = false
	query.hit_back_faces = false
	query.hit_from_inside = true
	var probe;
	var pos;
	var collided = [];
	return space.intersect_ray(query);
	
func getClosestProbeInIslandToPoint(point : Vector3, island : Dictionary, minDistance : float, maxDot : float) -> Dictionary:
	var closestDistanceSquared = FLOAT_MAX;
	var closestProbe = {};
	minDistance = pow(minDistance, 2);
	for probeIndex in island.probes:
		var probe = probeList[probeIndex];
		var dist = probe.position.distance_squared_to(point);
		if(probe.probeType != PROBETYPE.DROPOFF and probe.collisions[0].normal.dot((probe.position - point).normalized()) < maxDot and dist > minDistance and dist < closestDistanceSquared and raycast(point, probe.position) == {}):
			closestDistanceSquared = dist;
			closestProbe = probe;
	return closestProbe;
				
func addNeighborsToIsland(probe : Dictionary):
	for neighborIndex in probe.neighbors:
		var neighbor = probeList[neighborIndex];
		if(neighbor.island != -1):
			continue;
		if((probe.probeType == PROBETYPE.GROUND or probe.probeType == PROBETYPE.CLIMBSTART  or probe.probeType == PROBETYPE.DROPOFF) and (neighbor.probeType == PROBETYPE.GROUND or neighbor.probeType == PROBETYPE.CLIMBSTART or neighbor.probeType == PROBETYPE.DROPOFF)):
			neighbor.island = probe.island;
			islandList[probe.island].probes.push_back(neighbor.index);
			addNeighborsToIsland(neighbor);
		if((probe.probeType == PROBETYPE.WALL or probe.probeType == PROBETYPE.VAULT) and (neighbor.probeType == PROBETYPE.WALL or neighbor.probeType == PROBETYPE.VAULT)):
			if(getBestFitAxis(probe.collisions[0].normal) == getBestFitAxis(neighbor.collisions[0].normal)):
				neighbor.island = probe.island;
				islandList[probe.island].probes.push_back(neighbor.index);
				addNeighborsToIsland(neighbor);

enum ISLANDTYPE{
	GROUND,
	WALL
}

func getIslandTypeFromProbeType(probeType : PROBETYPE) -> ISLANDTYPE:
	if(probeType == PROBETYPE.GROUND or probeType == PROBETYPE.CLIMBSTART or probeType == PROBETYPE.DROPOFF):
		return ISLANDTYPE.GROUND;
	return ISLANDTYPE.WALL;

func getBestFitAxis(normal : Vector3) -> Vector3:
	var axis = [Vector3.FORWARD, Vector3.RIGHT, Vector3.BACK, Vector3.LEFT];
	var highestDot = -1;
	var bestAxis = axis[0];
	for ax in axis:
		var dot = normal.dot(ax);
		if(dot > highestDot):
			highestDot = dot;
			bestAxis = ax;
		
	return bestAxis;
	
	
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

func shortestPathProbe(from : Dictionary, to : Dictionary) -> Array:
	var visited = {from.index: true};
	var finalPath = [];
	var currentProbe = from;
	while currentProbe.index != to.index:
		var closestDistanceSquared = FLOAT_MAX;
		var bestNeighbor = {};
		for neighborIndex in currentProbe.neighbors:
			if(visited.has(neighborIndex) or probeList[neighborIndex].island != to.island):
				continue;
			var neighbor = probeList[neighborIndex];
			var dist = neighbor.position.distance_squared_to(to.position);
			if(dist < closestDistanceSquared):
				closestDistanceSquared = dist;
				bestNeighbor = neighbor;
		if(bestNeighbor == {}):
			if(finalPath.size() == 0):
				print("Could not find a path!");
				return finalPath;
			else:
				finalPath.resize(finalPath.size() - 1);
		else:
			finalPath.push_back(bestNeighbor);
			visited[bestNeighbor.index] = true;
		if(finalPath.size() != 0):
			currentProbe = probeList[finalPath[finalPath.size() - 1].index];
		else:
			currentProbe = from;
	return finalPath;

func shortestPathFull(start : Vector3, end : Vector3) -> Array:
	var startProbe = getProbeClosestToPoint(start);
	var endProbe = getProbeClosestToPoint(end);
	var finalPathDirty = [startProbe];
	
	if(startProbe.island == endProbe.island):
		finalPathDirty.append_array(shortestPathProbe(startProbe, endProbe));
	else:
		var connections = [];
		var currentIsland = islandList[startProbe.island];
		var visited = {currentIsland.index: true};
		while currentIsland.index != endProbe.island:
			var closestDistanceSquared = FLOAT_MAX;
			var bestConnection = {};
			for con in currentIsland.connections:
				if(visited.has(probeList[con.to].island)):
					continue;
				var dist = probeList[con.to].position.distance_squared_to(endProbe.position) + (con.distance*.6);
				if(dist <= closestDistanceSquared):
					closestDistanceSquared = dist;
					bestConnection = con;
			if(bestConnection == {}):
				if(connections.size() == 0):
					print("Could not find a connection!");
					return [];
				else:
					connections.resize(connections.size() - 1);
			else:
				connections.push_back(bestConnection);
				visited[probeList[bestConnection.to].island] = true;
			if(connections.size() != 0):
				currentIsland = islandList[probeList[connections[connections.size() - 1].to].island];
			else:
				currentIsland = islandList[startProbe.island];
		
		if connections.size() == 0:
			return [];
		
		for connection in connections:
			finalPathDirty.append_array(shortestPathProbe(finalPathDirty[finalPathDirty.size() - 1], probeList[connection.from]));
			finalPathDirty.push_back(probeList[connection.to]);
		finalPathDirty.append_array(shortestPathProbe(finalPathDirty[finalPathDirty.size() - 1], endProbe))
		
	var finalPathClean = [];
	for step in finalPathDirty:
		finalPathClean.push_back(getCleanProbe(step));
	return finalPathClean;

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
		var color = getVertexColor(probe.probeType);
		#if(probe.island == islandDebug):
			#color = Color.BLACK;
		addQuadColor(st, [probe.position + (Vector3(0, -1, 0) * size), probe.position + (Vector3(1, 0, 0) * size), probe.position + (Vector3(0, 1, 0) * size), probe.position + (Vector3(-1, 0, 0) * size)], color);
		addQuadColor(st, [probe.position + (Vector3(0, 0, -1) * size), probe.position + (Vector3(0, -1, 0) * size), probe.position + (Vector3(0, 0, 1) * size), probe.position + (Vector3(0, 1, 0) * size)], color);
		addQuadColor(st, [probe.position + (Vector3(-1, 0, 0) * size), probe.position + (Vector3(0, 0, -1) * size), probe.position + (Vector3(1, 0, 0) * size), probe.position + (Vector3(0, 0, 1) * size)], color);

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
		PROBETYPE.DROPOFF:
			color = Color(1, 0.2, 0);
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
	DROPOFF,
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
		probeList.push_back({"index": probeList.size(), "position": pos, "collisions": collided, "probeType": probeType, "neighbors": [], "island": -1});

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
				var path = shortestPathFull(navPathStartPosition, navPathEndPosition);
				#var stProbe = getProbeClosestToPoint(navPathStartPosition);
				#print(stProbe.position);
				#var path = [stProbe];
				#for neighbor in stProbe.neighbors:
					#path.push_back(probeList[neighbor]);
					#path.push_back(stProbe);
				if(path.size() > 1):
					drawShortestPath(path);
	pass
