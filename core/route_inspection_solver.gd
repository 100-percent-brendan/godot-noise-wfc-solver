class_name RouteInspectionSolver extends Node
## Solver for the route inspection (Chinese postman) problem.
##
## Intended to find the most efficient path that includes all edges in a
## connected, undirected graph.
##
## See the initializer for the expected graph format.

var _graph : Dictionary[int, Dictionary] # The graph to search for a solution in.

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
		
		# Relax the edges; update routing if a path is shorter
		for v in graph[u].keys():
			var weight = graph[u][v]
			var alt = dist[u] + weight
			
			# Alternative path is shorter; replace previous hop and weight
			if alt < dist[v]:
				dist[v] = alt
				prev[v] = u
				q.push_back({"v": v, "dist": alt})
		
	return [dist, prev]

## Initialize the solver.
##
## The [param graph] that is passed in must be a [Dictionary] indexed by
## vertex ID (integer) containing other [Dictionary] objects indexed with a list
## of vertex IDs (neighbors) with each value set to a weight. The [param graph]
## must be connected, undirected, and contain at least one vertex.
##
## For example:
## [code]
## {
##   1: {2: 5, 3: 10},
##   2: {1: 5, 3: 4, 5: 1},
##   3: {1: 10, 2: 4, 4: 1},
##   4: {5: 1, 3: 1},
##   5: {4: 1, 6: 2, 2: 1},
##   6: {5: 2, 7: 3},
##   7: {6: 3}
## }
## [/code]
func _init(graph : Dictionary[int, Dictionary]):
	if !graph && graph.size() > 0:
		push_error("A graph must be supplied.")
		return
	
	for u in graph:
		for v in graph[u]:
			if v is not int || graph[u][v] is not int:
				push_error("Both the key and the value in the neighbor dictionary must be integers.")
				return
			
			if graph[u][v] < 0:
				push_error("All weights must be positive or zero.")
				return
	
	for u in graph:
		for v in graph[u]:
			if !graph.has(v) || !graph[v].has(u) || graph[u][v] != graph[v][u]:
				push_error("The graph must be undirected, with weights symmetric in both directions.")
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
## Returns a 2D data structure composed of [Dictionary] objects, where the
## contained value is an array composed of the distance between two vertices and
## the path.
func _find_shortest_odd_pair_paths(odd_verts : Array[int]) -> Dictionary:
	var m : Dictionary = {}
	
	# For each odd vertex pairing, compose a distance and path array
	for u : int in odd_verts:
		var shortest_paths := find_shortest_paths(_graph, u)
		var dist : Dictionary = shortest_paths[0]
		var prev : Dictionary = shortest_paths[1]
		
		m[u] = {}
		for v in odd_verts:
			if u != v:
				m[u][v] = []
				m[u][v].push_back(dist[v])
				
				var path = []
				var pv = v # The current path vertex
				while pv != null:
					path.push_front(pv)
					pv = prev[pv]
				
				m[u][v].push_back(path)
	
	return m

## Perform minimum weight perfect matching.
##
## This finds the path between the odd pairs that is optimal (minimum weight).
## This function is recursive.
##
## Returns the odd vertex pairings with the lowest path cost.
func _find_min_weight_pairs(odd_verts : Array[int], odd_pair_paths : Dictionary) -> Array:
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
		var result : Array = _find_min_weight_pairs(rem, odd_pair_paths)
		var cost : int = odd_pair_paths[u][v][0]
		for j in result:
			cost += odd_pair_paths[j[0]][j[1]][0]
		
		if cost < lowest_cost:
			lowest_cost = cost
			best_match = [[u, v]] + result
	
	return best_match

## Get an edge collection built from the graph.
##
## Returns an array that contains edge endpoints as [Vector2i] (lowest index will be first).
func _get_edges() -> Array[Vector2i]:
	var edges : Array[Vector2i] = []
	var visited : Array[Vector2i] = []
	
	for u : int in _graph:
		for v : int in _graph[u]:
			var edge : Vector2i = Vector2i(u, v)
			if u < v && !visited.has(edge):
				visited.push_back(edge)
				edges.push_back(edge)
	
	return edges

## Find the Eulerian circuit.
##
## Use Hierholzer’s Algorithm to find the Eulerian circuit.
##
## Returns a list of vertices representing the circuit.
func _find_eulerian_circuit(edges : Array[Vector2i]) -> Array[int]:
	if !edges:
		return []
	
	var circuit : Array[int] = []
	var stack : Array[int] = [edges[0][0]]
	
	# Build an adjacency index
	var adj :  = {}
	for edge in edges:
		var u : int = edge[0]
		var v : int = edge[1]
		
		if !adj.has(u):
			adj[u] = []
		if !adj.has(v):
			adj[v] = []
		
		adj[u].push_back(v)
		adj[v].push_back(u)
	
	# Explore the first vertex in the stack
	# Find all neighbors to the vertex at that point point
	# Once all neighbor are on the stack (and the current vertex has no neighbors), put that vertex in the circuit
	# Continue in this way on the next vertex and so forth, so that it draws loops
	# Once the vertices are depleted, the pattern formed shall be an Eulerian circuit
	while stack.size() > 0:
		var v : int = stack[-1]
		
		if adj[v].size() > 0:
			var u : int = adj[v].pop_back()
			adj[u].erase(v)
			stack.push_back(u)
		else:
			circuit.push_back(stack.pop_back())
	
	return circuit

## Run the solver to generate a Eulerian circuit from the graph.
##
## Internally, this solves the route inspection (Chinese postman)
## problem.
##
## Returns a list of vertices representing the circuit.
func run() -> Array[int]:
	if !_graph:
		push_error("A valid graph is required.")
		return []
	
	# Find the odd vertices
	var odd_verts : Array[int] = _get_odd_vertices()
	
	# Find the paths between the odd pairs
	var odd_pair_paths : Dictionary = _find_shortest_odd_pair_paths(odd_verts)
	
	# Find the pairs that have the paths between them with the lowest cost (minimum weight)
	var min_weight_pairs : Array = _find_min_weight_pairs(odd_verts, odd_pair_paths)
	
	# Duplicate edges along the matched shortest paths
	var edges : Array[Vector2i] = _get_edges()
	for pair : Array in min_weight_pairs:
		var path : Array = odd_pair_paths[pair[0]][pair[1]][1]
		for i in range(path.size() - 1):
			var edge : Vector2i
			if path[i] < path[i + 1]:
				edge = Vector2i(path[i], path[i + 1])
			else:
				edge = Vector2i(path[i + 1], path[i])
			edges.push_back(edge)
	
	# Find and return the Eulerian
	return _find_eulerian_circuit(edges)
