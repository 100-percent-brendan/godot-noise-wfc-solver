class_name RouteInspectionSolver extends Node
## Solver for the route inspection problem.
##
## Intended to find the most efficient path that includes all edges.
# TODO: Review and update comments for accuracy

var _graph : Dictionary[int, Dictionary]

## Check if a graph is connected.
##
## This is a prerequisite of using the solver.
static func is_graph_connected(graph : Dictionary[int, Dictionary]) -> bool:
	# An empty graph is connected
	if graph.size() == 0:
		return true
	
	# Choose the first vertex
	var start : int = graph.keys()[0]
	
	# Perform a simple breadth first search
	# Start at one vertex, then explore each edge for new vertices until all
	# connected vertices are explored
	var visited : Dictionary[int, bool] = {}
	for v in graph.keys():
		visited[v] = false
	
	var queue : Array[int] = [start]
	visited[start] = true
	
	while queue.size() > 0:
		var u = queue.pop_front()
		for v in graph[u].keys():
			# Extra check to make sure vertex actually exists
			if !graph.has(v):
				return false
			
			if !visited[v]:
				visited[v] = true
				queue.push_back(v)
	
	# Check to see if all vertices have been visited, if not this graph is not connected
	for v in visited.keys():
		if !visited[v]:
			return false
	
	return true

## Find the shortest path to all vertices in the graph.
##
## Internally, this uses Dijkstra's algorithm.
##
## Returns an [Array] where index 0 is a [Dictionary] that contains distances from
## the source to a vertex, and index 1 is a [Dictionary] that contains the vertex indexed for
## a previous hop towards the source. On no path found distance is INF and prev is null.
static func find_shortest_paths(graph : Dictionary[int, Dictionary], source : int) -> Array:
	if !graph.has(source):
		push_error("Source must exist in graph.")
		return [{}, {}]
	
	var dist : Dictionary = {}
	var prev : Dictionary = {}
	var visited : Dictionary = {}
	
	for v in graph:
		dist[v] = INF
		prev[v] = null
		visited[v] = false
	
	dist[source] = 0
	
	# This is driven by a priority queue
	# Initialize the queue with the source
	var q : Array = []
	q.push_back({"v": source, "dist": 0})
	
	while q.size() > 0:
		# Get the item with minimum distance in the queue
		q.sort_custom(func(a, b):
			return a["dist"] < b["dist"]
		)
		var current = q.pop_front()
		var u = current["v"]
		
		if visited[u]:
			continue
		visited[u] = true
		
		# Relax the edges (Update routing if a path is shorter)
		for v in graph[u].keys():
			var weight = graph[u][v]
			var alt = dist[u] + weight
			
			# Alternative path is shorter
			if alt < dist[v]:
				dist[v] = alt
				prev[v] = u
				q.push_back({"v": v, "dist": alt})
		
	return [dist, prev]

## Initialize the solver.
##
## The [param graph] that is passed in must be a [Dictionary] indexed by
## vertex ID (integer) containing other [Dictionary] objects indexed with a list
## of neighboring vertex IDs with each value set to a weight. The [param graph]
## must be connected, undirected, and contain at least one vertex.
##
## For example:
## [code]
## {
##   1: {2: 5, 3: 1},
##   2: {1: 5, 3: 2},
##   3: {1: 1, 2: 2}
## }
## [/code]
func _init(graph : Dictionary[int, Dictionary]):
	if !graph && graph.size() > 0:
		push_error("A graph must be supplied.")
		return
	
	for i in graph:
		for j in graph[i]:
			if j is not int || graph[i][j] is not int:
				push_error("Both the key and the value in the neighbor dictionary must be integers.")
				return
			
			if graph[i][j] < 0:
				push_error("All weights must be positive or zero.")
				return
	
	if !is_graph_connected(graph):
		push_error("Graph must be connected.")
		return
	
	_graph = graph

## Get an array of vertices from the graph with odd degree.
func _get_odd_vertices() -> Array[int]:
	var verts : Array[int] = []
	
	for v in _graph.keys():
		if _graph[v].size() % 2 != 0:
			verts.append(v)
	
	return verts

## Find shortest paths between every pair of odd vertices.
##
## Returns a 2D matrix implemeneted using [Dictionary] objects, where the
## contained value is distance between two vertices.
func _find_shortest_odd_pair_matrix(odd_verts : Array[int]) -> Dictionary:
	# TODO: Add safety somewhere to prevent directed graphs from being processed (uneven weight)
	var m : Dictionary = {}
	
	# For each odd vertex pairing, create a matrix item representing distance
	for u : int in odd_verts:
		var dist : Dictionary = find_shortest_paths(_graph, u)[0]
		m[u] = {}
		for v in odd_verts:
			if u != v:
				m[u][v] = dist[v]
	
	return m

## Perform minimum weight perfect matching.
##
## This finds the path between the odd pairs that is optimal (minimum weight).
## This function is recursive.
##
## Returns the odd vertex pairings with the lowest path cost.
func _find_min_weight_pairs(odd_verts : Array[int], odd_pair_dist : Dictionary) -> Array:
	if odd_verts.size() == 0:
		return []
	
	var u : int = odd_verts[0]
	var lowest_cost = INF
	var best_match = [] # A pair of vertices
	
	# Skip over 0 because that's where we start
	for i in range(1, odd_verts.size()):
		var v : int = odd_verts[i]
		var rem = odd_verts.duplicate() # Remaining vertices to search
		rem.erase(u)
		rem.erase(v)
		
		# Recursively search for lowest cost pairings
		var result : Array = _find_min_weight_pairs(rem, odd_pair_dist)
		var cost : int = odd_pair_dist[u][v]
		for j in result:
			cost += odd_pair_dist[j[0]][j[1]]
		
		if cost < lowest_cost:
			lowest_cost = cost
			best_match = [[u, v]] + result
	
	return best_match

## TODO: Duplicate edges along the matched shortest paths

## TODO Find the Eulerian circuit
