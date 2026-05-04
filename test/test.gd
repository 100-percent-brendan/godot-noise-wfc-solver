extends Node2D
## A simple test of the [NoiseWFCSolver].
##
## This uses an incrementing seed to aid in debugging the solver, as well as
## demonstration.
# TODO: Confirm what is still valid below

const GRID_WIDTH : int = 30 ## The grid width in tiles.
const GRID_HEIGHT : int = 20 ## The grid height in tiles.
const RENDER_LABEL_TEXT : bool = false ## Whether or not to render label text. Enable this to see too much information.

@onready var tile_map_layer : TileMapLayer = $TileMapLayer ## A TileMapLayer to place tiles within.
@onready var labels : Node2D = $Labels ## Labels used to render tiles remaining and entropy.

var solver : NoiseWFCSolver ## The solver used for debugging.
var label_map : Dictionary[Vector2i, Label]

## Run the solver when the test scene is ready.
func _ready() -> void:
	# TODO: Remove temporary test
	var graph : Dictionary[int, Dictionary] = {
		1: {2: 5, 3: 10},
		2: {1: 5, 3: 2},
		3: {1: 10, 2: 2, 4: 1},
		4: {5: 1, 3: 1},
		5: {4: 1}
	}
	var route_solver : RouteInspectionSolver = RouteInspectionSolver.new(graph)
	print(RouteInspectionSolver.find_shortest_paths(graph, 4))
	return
	
	# Add labels that can be used to display tiles remaining and entropy
	for x in GRID_WIDTH:
		for y in GRID_HEIGHT:
			var coords := Vector2i(x, y)
			var label := Label.new()
			label.text = ""
			label.position = tile_map_layer.map_to_local(coords) - Vector2(6, 0)
			label.add_theme_font_size_override("font_size", 4)
			labels.add_child(label)
			label_map[coords] = label
	
	# Iterate over 100 instances of the WFC generation process
	for i in range(100):
		solver = NoiseWFCSolver.new(load("res://test/assets/terrain.tres"))
		solver.set_seed(i)
		solver.set_debug_mode(true)
		solver.set_debug_delay(0.002)
		solver.set_dimensions(GRID_WIDTH, GRID_HEIGHT)
		solver.tile_placed.connect(_on_tile_placed)
		solver.tile_removed.connect(_on_tile_removed)
		solver.tile_possibilities_updated.connect(_on_tile_possibilities_updated)
		solver.grid_reset.connect(_on_grid_reset)
		
		# var _grid := await solver.run() # TODO: Add this
		
		# Wait 3 seconds after success
		await get_tree().create_timer(3.0).timeout
		
		# Clear tiles between runs
		_clear_grid()
		
		# Disconnect previous signals
		solver.tile_placed.disconnect(_on_tile_placed)
		solver.tile_removed.disconnect(_on_tile_removed)
		solver.tile_possibilities_updated.disconnect(_on_tile_possibilities_updated)
		solver.grid_reset.disconnect(_on_grid_reset)

## When a tile is placed in the solver, place it on the test [TileMapLayer].
func _on_tile_placed(coords : Vector2i, source_id : int, atlas_coords : Vector2i) -> void:
	tile_map_layer.set_cell(coords, source_id, atlas_coords)

## When a tile is removed in the solver, remove it from the test [TileMapLayer].
func _on_tile_removed(coords : Vector2i) -> void:
	tile_map_layer.set_cell(coords)

## When the possibilities for a tile are updated in the solver, update the
## floating numbers above the [TileMapLayer].
func _on_tile_possibilities_updated(coords : Vector2i, count : int, entropy : float) -> void:
	if RENDER_LABEL_TEXT:
		if label_map.has(coords):
			label_map[Vector2i(coords)].text = "%d|%0.2f" % [count, entropy]
			

## When the grid is reset in the solver, clear the [TileMapLayer].
func _on_grid_reset() -> void:
	_clear_grid()

## Clear the grid.
func _clear_grid() -> void:
	tile_map_layer.clear()
	
	# Clear the labels
	for x in GRID_WIDTH:
		for y in GRID_HEIGHT:
			if label_map.has(Vector2i(x, y)):
				label_map[Vector2i(x, y)].text = ""
