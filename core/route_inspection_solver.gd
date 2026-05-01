class_name RouteInspectionSolver extends Node
## Solver for the route inspection problem.
##
## Intended to find the most efficient path that includes all edges.
# TODO: Review and update comments for accuracy

var _graph : Dictionary[int, Dictionary]

## Check if a graph is fully connected.
##
## This is a prerequisite of using the solver.
static func is_fully_connected(graph : Dictionary[int, Dictionary]) -> bool:
	# An empty graph is not 
	if graph.size() == 0:
		return true
	
	# Choose the first vertice
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
			
			if !visited.has(v):
				visited[v] = true
				queue.append(v)
	
	# Check to see if all vertices have been visited, if not this graph is not fully connected
	for v in graph.keys():
		if !visited.has(v):
			return false
	
	return true

## Initialize the solver.
##
## The [param graph] that is passed in must be a [Dictionary] indexed by
## vertex ID (integer) containing other [Dictionary] objects indexed with a list
## of neighboring vertex IDs, containing a weight (cost to transit).
##
## [code]
## {
##   1: [2: 5, 3: 1],
##   2: [1: 5, 3: 2],
##   3: [1: 1, 2: 2]
## }
## [/code]
func _init(graph : Dictionary[int, Dictionary]):
	if !graph:
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
	
	_graph = graph

## Get an array of vertices from the graph with odd degree.
func _get_odd_vertices() -> Array[int]:
	var verts = []
	
	for v in _graph.keys():
		if _graph[v].size() % 2 != 0:
			verts.append(v)
	
	return verts

## An implementation of Dijkstra's algorithm to ---
## TODO: Find shortest paths between every pair of odd vertices

## TODO: Minimum weight perfect matching

## TODO: Duplicate edges along the matched shortest paths

## TODO Find the Eulerian circuit
