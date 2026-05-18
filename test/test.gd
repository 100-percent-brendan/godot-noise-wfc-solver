extends Node2D
## A simple test of the [NoiseWFCSolver].
##
## This uses a tester configurable seed to aid in debugging the solver, as well as
## demonstration.

const GRID_WIDTH : int = 30 ## The grid width in tiles.
const GRID_HEIGHT : int = 20 ## The grid height in tiles.
const RENDER_LABEL_TEXT : bool = false ## Whether or not to render label text. Enable this to see too much information.

@onready var tile_map_layer : TileMapLayer = $TileMapLayer ## A [TileMapLayer] to place tiles within.
@onready var labels : Node2D = $Labels ## Labels used to render tiles remaining and entropy.
@onready var seed_input = $CanvasLayer/PanelContainer/VBoxContainer/SeedContainer/SeedInput
@onready var run_button = $CanvasLayer/PanelContainer/VBoxContainer/RunContainer/RunButton

var _is_running : bool = false ## Double run protection.

var label_map : Dictionary[Vector2i, Label] ## Map of which label applies to which cell.

## Run the solver when the test scene is ready.
func _ready() -> void:
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
	
	# Bind the run button
	run_button.pressed.connect(_run_solver)

## Start and run the solver.
func _run_solver() -> void:
	# Safety to prevent double run
	if _is_running:
		return
	
	# Clear tiles between runs
	_clear_grid()
	
	# Enable double run protection and cache variables locally
	_is_running = true
	var solver_seed = seed_input.value
	
	# Initialize the probability configuration
	var prob_config := WFCProbabilityConfiguration.new()
	prob_config.set_terrain_frequency(0, 1.2) # Set the frequency for grass (terrain 0)
	prob_config.set_terrain_frequency(2, 0.4) # Set the frequency for water (terrain 2)
	prob_config.set_terrain_edge_weight(1.0 / 60.0)
	
	# Initialize the solver, along with the noise that powers it
	var noise : FastNoiseLite = load("res://test/assets/noise.tres").duplicate()
	noise.seed = solver_seed
	var solver : NoiseWFCSolver ## The solver used for debugging.
	solver = NoiseWFCSolver.new(load("res://test/assets/terrain.tres"), noise, prob_config)
	solver.set_seed(solver_seed)
	solver.set_debug_mode(true)
	solver.set_debug_delay(0.0)
	solver.set_dimensions(GRID_WIDTH, GRID_HEIGHT)
	
	# Bind rendering signals
	solver.tile_placed.connect(_on_tile_placed)
	solver.tile_removed.connect(_on_tile_removed)
	solver.cell_possibilities_updated.connect(_on_cell_possibilities_updated)
	solver.grid_cleared.connect(_clear_grid)
	
	# Run the solver
	var _grid := await solver.run()
	
	# Disconnect signals
	solver.tile_placed.disconnect(_on_tile_placed)
	solver.tile_removed.disconnect(_on_tile_removed)
	solver.cell_possibilities_updated.disconnect(_on_cell_possibilities_updated)
	solver.grid_cleared.disconnect(_clear_grid)
	
	_is_running = false

## When a tile is placed in the solver, place it on the test [TileMapLayer].
func _on_tile_placed(coords : Vector2i, source_id : int, atlas_coords : Vector2i) -> void:
	tile_map_layer.set_cell(coords, source_id, atlas_coords)

## When a tile is removed in the solver, remove it from the test [TileMapLayer].
func _on_tile_removed(coords : Vector2i) -> void:
	tile_map_layer.set_cell(coords)

## When the possibilities for a tile are updated in the solver, update the
## floating numbers above the [TileMapLayer].
func _on_cell_possibilities_updated(coords : Vector2i, count : int, entropy : float) -> void:
	if RENDER_LABEL_TEXT:
		if label_map.has(coords):
			label_map[Vector2i(coords)].text = "%d|%0.2f" % [count, entropy]

## Clear the grid.
func _clear_grid() -> void:
	tile_map_layer.clear()
	
	# Clear the labels
	for x in GRID_WIDTH:
		for y in GRID_HEIGHT:
			if label_map.has(Vector2i(x, y)):
				label_map[Vector2i(x, y)].text = ""
