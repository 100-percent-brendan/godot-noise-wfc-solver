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
			
			if !visited[v]:
				visited[v] = true
				queue.push_back(v)
	
	# Check to see if all vertices have been visited, if not this graph is not connected
	for v in visited.keys():
		if !visited[v]:
			return false
	
	return true

## Initialize the solver.
##
## The [param graph] that is passed in must be a [Dictionary] indexed by
## vertex ID (integer) containing other [Dictionary] objects indexed with a list
## of neighboring vertex IDs with each value set to a weight. The [param graph]
## must be connected, directed, and contain at least one vertex.
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
