class_name NoiseWFCSolver extends Node
## Noise-based wave function collapse (WFC) solver.
# TODO: Document me.
# TODO: Confirm all constructs and enumerations are used.
# TODO: Place sufficient debugging information
# TODO: Ensure sufficient protection checks

## A signal for when a tile is placed.
signal tile_placed(coords : Vector2i, source_id : int, atlas_coords : Vector2i)

## A signal for when a tile is removed.
signal tile_removed(coords : Vector2i)

## A signal for when tile possibilities are updated.
signal tile_possibilities_updated(coords : Vector2i, count : int, entropy : float)

## A signal for when the grid is reset. 
signal grid_reset()

## The debug message severity.
enum DebugSeverity {
	INFORMATION, ## An informational message.
	WARNING, ## A warning message.
	ERROR ## An error message.
}

## The direction used for tile comparison.
enum ComparisonDirection {
	LEFT_TO_RIGHT, ## A left-to-right tile comparison.
	TOP_TO_BOTTOM, ## A top-to-bottom tile comparison.
	RIGHT_TO_LEFT, ## A right-to-left tile comparison.
	BOTTOM_TO_TOP ## A bottom-to-top tile comparison.
}

const MIN_SIZE : int = 6 ## The minimum size of the output grid in each dimension.

## The [CellNeighbors] for the terrain layout, starting in the upper-left and
## going clockwise around the border.
const TERRAIN_LAYOUT_ORDER : Array[TileSet.CellNeighbor] = [
	TileSet.CELL_NEIGHBOR_TOP_LEFT_CORNER,
	TileSet.CELL_NEIGHBOR_TOP_SIDE,
	TileSet.CELL_NEIGHBOR_TOP_RIGHT_CORNER,
	TileSet.CELL_NEIGHBOR_RIGHT_SIDE,
	TileSet.CELL_NEIGHBOR_BOTTOM_RIGHT_CORNER,
	TileSet.CELL_NEIGHBOR_BOTTOM_SIDE,
	TileSet.CELL_NEIGHBOR_BOTTOM_LEFT_CORNER,
	TileSet.CELL_NEIGHBOR_LEFT_SIDE
]

var _debug_mode : bool = false ## Output debug messages and information.
var _debug_delay : float = 0.0 ## Delay between tile placements and other major actions.
var _seed : int = 0 ## The seed used in the pseudorandom number generator (PRNG).
var _dimensions : Vector2i = Vector2i(MIN_SIZE, MIN_SIZE) ## The dimensions of the output grid.
var _max_retries : int = 100 ## The maximum number of retry attempts.
var _max_local_resets : int = 100 ## The maximum number of local resets.
var _tile_set : TileSet ## The tileset.
var _noise : Noise ## The noise generator.
# TODO: Consider adding noise parameters
# TODO: Make sure all the below are used somewhere
var _tiles : Dictionary[Vector3i, Array] = {} ## A collection of tile-layout mappings. The key is the tile (source ID and atlas coords) and the value is the terrain layout.
var _tile_weights : Dictionary[Vector3i, float] = {} ## A collection of tile probability weights for each tile (source ID and atlas coords).
var _terrain_tiles : Dictionary[int, Array] = {} ## A collection of tiles organized by terrain index. The key is the terrain index and the value is an [Array] of tiles (source ID and atlas coords).
var _terrain_layouts : Array[Array] = [] ## A collection of terrain layouts.
var _layout_tiles : Dictionary[int, Array] = {} ## A collection of tiles organized by layout. The key is the terrain layout index and the value is an [Array] of tiles (source ID and atlas coords).
var _layout_neighbors : Dictionary[int, Dictionary] = {} ## A collection of layouts considered to be valid neighbors to another layout. The key is the terrain layout index and the value is collection (indexed by ComparisonDirection) of arrays of valid neighbor layout indices.
var _terrain_edges : Array[Vector2i] = [] ## The edges between terrains.
var _terrain_sequence : Array[int] = [] ## The most efficient sequence to go over all terrains to ensure all edges are represented.
var _terrain_distribution : Array[Array] = [] ## The distribution of probabilities for terrains, respecting sequencing. X is domain end and Y is terrain index.
# TODO: Determine what terrains border each other

## Initialize the wave function collapse solver.
##
## It is expected that within the [param tile_set] all tiles will be
## one-tile-by-one-tile in size. Only tiles with terrain mappings will be
## used. Only the first terrain set encountered will be used.
##
## The [param noise] can be set to any [Noise], but should have smooth transitions
## and go through the full range, for best effect.
func _init(tile_set : TileSet, noise : Noise) -> void:
	_tile_set = tile_set
	_noise = noise
	
	if !_noise:
		_print_debug_message("A valid noise generator must be provided.", DebugSeverity.ERROR)
	
	# Load the tile and terrain data
	_load_tile_data()
	
	# Build a set of probability weights for each tile
	_build_tile_weights()
	
	# Build an index of valid neighbors for each layout.
	_index_terrain_layout_neighbors()
	
	# Find the optimal terrain sequence
	_find_terrain_sequence()
	
	# Build a probability distribution from the terrain sequence
	_build_terrain_distribution()

## Load the tiles and terrain data from the tile set.
##
## This also verifies that the tile set is valid.
func _load_tile_data() -> void:
	if !_tile_set:
		_print_debug_message("No tile set found.", DebugSeverity.ERROR)
		return
	
	# Extract and index terrain data by tile
	for i in range(_tile_set.get_source_count()):
		var source_id : int = _tile_set.get_source_id(i)
		var source: TileSetSource = _tile_set.get_source(source_id)

		if source is TileSetAtlasSource:
			for j in range(source.get_tiles_count()):
				var atlas_coords = source.get_tile_id(j)
				# TODO: Add message this does not support alternate tiles
				var tile_data: TileData = source.get_tile_data(atlas_coords, 0)
				var layout : Array[int] = _get_terrain_layout(tile_data)
				var tile : Vector3i = Vector3i(source_id, atlas_coords[0], atlas_coords[1])
				_index_tile(tile, layout)

## Extract terrain layout from the tile set.
##
## The terrain layout based on the [TERRAIN_LAYOUT_ORDER].
##
## Returns an empty array on data missing.
func _get_terrain_layout(tile_data : TileData) -> Array[int]:
	# TODO: Consider adding the center tile to the return
	var layout : Array[int] = []
	
	# Ensure this is part of the correct terrain set
	# Only the first set is used
	if tile_data.terrain_set != 0:
		return []
	
	# Iterate through all terrain tile segments on edge
	# If any are not valid, return an empty array
	# Otherwise, return the terrain data
	for cell_neighbor : TileSet.CellNeighbor in TERRAIN_LAYOUT_ORDER:
		if tile_data.is_valid_terrain_peering_bit(cell_neighbor):
			var terrain : int = tile_data.get_terrain_peering_bit(cell_neighbor)
			if terrain >= 0:
				layout.push_back(terrain)
			else:
				return []
		else:
			return []
	
	return layout

## Adds the tile to relevant indices.
##
## Provide the [param tile] (source ID and atlas coords) and the [param layout].
func _index_tile(tile : Vector3i, layout : Array) -> void:
	if !_tiles.has(tile) && layout.size() > 0:
		# Add to the collection of all tiles
		_tiles[tile] = layout
		
		# Organize tiles by terrain
		var 	unique_terrains = []
		# TODO: Add check here to omit or include desired terrain types
		for terrain in layout:
			# Create terrain array if it does not exist
			if !_terrain_tiles.has(terrain):
				_terrain_tiles[terrain] = []
			
			# Put the tile into the array
			if !_terrain_tiles[terrain].has(tile):
				_terrain_tiles[terrain].push_back(tile)
			
			# Extract unique terrains
			if !unique_terrains.has(terrain):
				unique_terrains.push_back(terrain)
		
		# Index the terrain edges
		unique_terrains.sort()
		for i in unique_terrains:
			for j in unique_terrains:
				# Check to make sure they are not equal and j is always larger than i for uniqueness
				if i < j:
					var edge : Vector2i = Vector2i(i, j)
					if !_terrain_edges.has(edge):
						_terrain_edges.push_back(edge)
		
		# Build a collection of terrain layouts
		# The key forms the basis of the layout groupings below
		if !_terrain_layouts.has(layout):
			_terrain_layouts.push_back(layout)
		
		# Organize tiles into layout groupings
		var key = _terrain_layouts.find(layout)
		if !_layout_tiles.has(key):
			_layout_tiles[key] = []
		_layout_tiles[key].push_back(tile)

## Build a set of tile probability weights.
##
## For each tile the weight will be calculated so:
## - Multi-terrain (edge) tiles have lower probability than single terrain tiles.
## - All tiles with the same layout have their probabilities divided by the amount of tiles in their layout group.
## - Include weight from terrain set
func _build_tile_weights() -> void:
	# TODO: Consider include weight bias for different types of terrains, based on input to class
	var weights : Dictionary[Vector3i, float] = {}
	for i : int in _terrain_layouts.size():
		var layout : Array = _terrain_layouts[i]
		var is_edge : bool = false
		for j : int in range(layout.size() - 1):
			if layout[j] != layout [j + 1]:
				is_edge = true
		
		# Extract the weights of the matching tiles from the tile set
		var tile_set_weights : Dictionary[Vector3i, float]
		var total_tile_set_weight : float = 0.0
		for tile : Vector3i in _layout_tiles[i]:
			var source_id : int = _tile_set.get_source_id(tile.x)
			var source: TileSetSource = _tile_set.get_source(source_id)
			if source is TileSetAtlasSource:
				var tile_data : TileData = source.get_tile_data(Vector2i(tile.y, tile.z), 0)
				tile_set_weights[tile] = tile_data.probability
				total_tile_set_weight += tile_data.probability
		
		var base_weight : float = 1.0
		if is_edge:
			base_weight = 1.0 / 40.0 # Edge pieces should be much less frequent, otherwise they dominate
		
		# Make sure each layout only take up a single tiles' worth of probability
		for tile : Vector3i in _layout_tiles[i]:
			var weight = base_weight * tile_set_weights[tile] / total_tile_set_weight
			weights[tile] = weight
	
	_tile_weights = weights

## Compare terrain layouts to see if they can neighbor each other.
##
## This compares where layouts touch to see if they can be neighbors.
func _can_terrain_layouts_neighbor(a : Array, b : Array, dir : ComparisonDirection) -> bool:
	if a.size() != 8 || b.size() != 8:
		return false
	
	# The TERRAIN_LAYOUT_ORDER is guaranteed to start in the top-left and go
	# in a clockwise order. The windowing method below relies on that.
	var base_offset = 0 # The offset of layout A
	
	match dir:
		ComparisonDirection.BOTTOM_TO_TOP:
			base_offset = 0
		ComparisonDirection.LEFT_TO_RIGHT:
			base_offset = 2
		ComparisonDirection.TOP_TO_BOTTOM:
			base_offset = 4
		ComparisonDirection.RIGHT_TO_LEFT:
			base_offset = 6
		_:
			return false
	
	# Get the row corresponding to the edge of layout A
	# The follows the edge from the corner
	var cells_a : Array = []
	for i in 3:
		cells_a.push_back(a[(base_offset + i) % 8])
	
	# Use an offset of 4 to get the opposing edge of layout B
	# Then reverse it for easy comparison
	var cells_b : Array = []
	for i in 3:
		cells_b.push_back(b[(base_offset + 4 + i) % 8])
	cells_b.reverse()
	
	# Make sure the edges match (or don't not match)
	for i in 3:
		if cells_a[i] != cells_b[i]:
			return false
	
	# If edges match, they can be neighbors
	return true

## Index the terrain layout neighbors.
##
## Identify what layouts can border each other.
func _index_terrain_layout_neighbors() -> void:
	var neighbors : Dictionary[int, Dictionary] = {}
	
	# Compare each layout edge to each other edge, and add layouts to the indices where they can neighbor
	for i : int in _terrain_layouts.size():
		neighbors[i] = {}
		var a : Array = _terrain_layouts[i]
		for dir : ComparisonDirection in ComparisonDirection.values():
			neighbors[i][dir] = []
			for j : int in _terrain_layouts.size():
				var b : Array = _terrain_layouts[j]
				if _can_terrain_layouts_neighbor(a, b, dir):
					neighbors[i][dir].push_back(j)
	
	_layout_neighbors = neighbors

## Find an optimally-efficient path through terrain types.
##
## This acts as a solver to the route inspection problem (Chinese postman problem.)
func _find_terrain_sequence() -> void:
	var graph : Dictionary[int, Dictionary] = {}
	for edge : Vector2i in _terrain_edges:
		var u : int = edge[0]
		var v : int = edge[1]
		if !graph.has(u):
			graph[u] = {}
		if !graph.has(v):
			graph[v] = {}
		graph[u][v] = 1
		graph[v][u] = 1
	
	_terrain_sequence =  RouteInspectionSolver.new(graph).run()

## Build the terrain probability distribution, respecting sequencing.
##
## This is normalized between 0 and 1.
## If a terrain appears multiple times, it will be adjusted to match the frequency of other terrains.
##
## X is the domain end (the highest) and Y is the terrain.
func _build_terrain_distribution() -> void:
	# TODO Consider applying per-terrain frequencies; e.g. some terrains are more likely than others
	var counts : Dictionary[int, int] = {}
	for terrain : int in _terrain_sequence:
		if !counts.has(terrain):
			counts[terrain] = 0
		counts[terrain] += 1
	
	var end : float = 0.0 # Current domain end
	var distribution : Array[Array] = []
	for terrain : int in _terrain_sequence:
		# Adjust frequencies so terrains that appear more in the sequence are evened out
		var weight : float = 1.0 / counts.size() / counts[terrain]
		end += weight
		distribution.push_back([end,terrain])
	
	# Set end of all domains to 1.0, to account for possible floating point errors
	if distribution.size() > 0:
		distribution[-1][0] = 1.0
	
	_terrain_distribution = distribution

## Conditionally output a debug message at a given severity level.
func _print_debug_message(message: String, severity : DebugSeverity) -> void:
	if _debug_mode:
		match severity:
			DebugSeverity.ERROR:
				push_error(message)
			DebugSeverity.WARNING:
				push_error(message)
			_:
				print(message)

## Set if the solver will output debug messages and information.
func set_debug_mode(debug_mode : bool) -> void:
	_debug_mode = debug_mode

## Set the amount of time between major actions, such as tile placements, when debugging.
##
## The delay will likely sync to the nearest physics cycle above it in time.
func set_debug_delay(delay : float) -> void:
	_debug_delay = max(delay, 0.0)

## Set the seed for the pseudorandom number generator (PRNG).
func set_seed(prng_seed : int) -> void:
	_seed = prng_seed

## Set the dimensions of the output grid.
##
## Each cell represents a tile unit. Must be larger than the minimum size in
## each dimension.
func set_dimensions(width : int, height : int) -> void:
	_dimensions = Vector2i(maxi(width, MIN_SIZE), maxi(height, MIN_SIZE))

## Set the maximum number of retry attempts before the solver gives up.
##
## This must be a positive integer.
func set_max_retries(max_retries : int) -> void:
	_max_retries = maxi(max_retries, 1)

## Set the maximum number of local retries before the solver gives up.
##
## This must be zero or above.
func set_max_local_resets(max_local_resets : int) -> void:
	_max_local_resets = maxi(max_local_resets, 1)

## Get the terrain index from the probability distribution belonging to x.
##
## The [param x] parameters expects a value between 0 and 1.
##
## Returns the terrain index or -1 on none found.
func _get_terrain_by_distribution(x : float) -> int:
	# TODO: Move into private section
	for i : int in _terrain_distribution.size():
		var bottom : float = 0.0 # The floor
		if i > 0:
			bottom = _terrain_distribution[i - 1][0]
		var top : float = _terrain_distribution[i][0]
		if x >= bottom && x <= top:
			return _terrain_distribution[i][1]
	
	return -1

## Get the default terrain by position.
##
## The terrain is determined by the noise function.
##
## Returns the terrain index or -1 on none found.
func _get_default_terrain(coords : Vector2i) -> int:
	# TODO: Move into private section
	if !_noise:
		return -1
	
	var val : float = (_noise.get_noise_2d(coords.x, coords.y) / 2.0 + 0.5)
	return _get_terrain_by_distribution(clampf(val, 0.0, 1.0))

## Place tile in grid cell.
##
## This does not check if a placement is valid.
func _place_tile(grid : WFCGrid, coords : Vector2i, tile : Vector3i) -> void:
	# TODO: Move into private section
	var cell = grid.get_cell(coords.x, coords.y)
	cell.place_tile(tile)
	tile_placed.emit(coords, tile.x, Vector2i(tile.y, tile.z))

## Get random tile from array of tiles.
##
## This takes into account weights.
##
## Returns the tile as source ID and atlas coords, or [code]Vector3i(-1, -1, -1)[/code] on error.
func _get_random_tile(rand : RandomNumberGenerator, tiles : Array) -> Vector3i:
	var total_weight : float = 0.0
	
	for tile in tiles:
		total_weight += _tile_weights[tile]
	
	if total_weight <= 0:
		return Vector3i(-1, -1, -1)
	
	var roll : float = rand.randf() * total_weight
	for tile : Vector3i in tiles:
		var weight = _tile_weights[tile]
		if roll <= weight:
			return tile
		roll -= weight
	
	return Vector3i(-1, -1, -1)

# TODO: Add function to place tile then calculate neighbor entropy

# TODO: Add function to calculate all open cell entropy

# TODO: Create function to find possibilities for cell based on neighboring cells.

# TODO: Create function for identify if cell contains invalid state.

# TODO: Create function for calculating entropy for open cell

# TODO: Phase 1: Set grid cells to solid terrain tiles based on noise
## Place tiles in grid cells based on noise.
##
## This is intended to place cells, many of which will be invalid and will later be removed.
func _place_default_tiles(rand : RandomNumberGenerator, grid : WFCGrid) -> void:
	var dims : Vector2i = grid.get_dimensions()
	for x : int in dims.x:
		for y : int in dims.y:
			var terrain : int = _get_default_terrain(Vector2i(x, y))
			if terrain == -1:
				continue
			
			# Find the terrain layout whose border is entirely the terrain
			var layout : Array[int]
			layout.resize(8)
			layout.fill(terrain)
			
			# Locate the tiles that have that layout
			var index = _terrain_layouts.find(layout)
			if index == -1:
				continue
			var tiles : Array = _layout_tiles[index]
			if tiles.size() == 0:
				continue
			
			# Get a random tile to use as the default
			var tile = _get_random_tile(rand, tiles)
			if tile == Vector3i(-1, -1, -1):
				continue
			
			_place_tile(grid, Vector2i(x, y), tile)

# TODO: Phase 2: Invalidate then reset all cells that border tiles which they should not neighbor. Calculate entropy.

# TODO: Phase 3: Run wave function collapse, with area resets, until a full grid is found.

# TODO: Execute process from start to finish in run function

# TODO: Document me
# TODO: Add return
func run() -> void:
	var rand : RandomNumberGenerator = RandomNumberGenerator.new()
	rand.seed = _seed
	var grid : WFCGrid = WFCGrid.new(_dimensions.x, _dimensions.y)
	
	_place_default_tiles(rand, grid)
