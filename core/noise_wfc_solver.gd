class_name NoiseWFCSolver extends Node
## Noise-based wave function collapse (WFC) solver.
##
## The initialization routine of the solver will extract terrain tile data from
## a [TileSet], and use this to build relevant data structures and probabilities.
## There are several expectations for the supplied tileset:
## 1. Tile shape shall be square.
## 2. A terrain set shall be supplied at index 0, with at least one valid terrain.
## 3. The terrain mode shall be set to match corners and sides.
## 4. Tiles shall contain terrain data on all edge points.
## 5. Each tile shall be 1x1 in terms of unit size.
## 6. There must be edge pieces between bordering terrains allowing placement
##    in all cardinal directions. A very simple subset of the Wang set may be
##    used.
## 7. Terrains must logically flow such that no terrain is orphaned from the
##    set. For example, water flows to mud flows to grass, but lava should not
##    be on its own.
##
## Internally, a route inspection (Chinese postman) problem solver is used.
## This forms a way to map noise to terrains in a way that only allows edges
## that can touch.
##
## Any valid [Noise] object may be supplied to inform tile placement. As not all
## noise algorithms are equal, experimentation is recommended when mixing noise
## with any given tile set. To start, it was discovered that using the
## fractal type "ping-pong" with value cubic or cellular noise has low-cost,
## visually-consistent results.
##
## To further tune probabilities, an optional [WFCProbabilityConfiguration]
## may be supplied.
##
## To learn what happens when you run the solver, see the documentation for the
## [code]run()[/code] method.
# TODO: Add safety to return to defer to core loop to prevent program freezing

## A signal for when a tile is placed.
signal tile_placed(coords : Vector2i, source_id : int, atlas_coords : Vector2i)

## A signal for when a tile is removed.
signal tile_removed(coords : Vector2i)

## A signal for when tile possibilities are updated.
signal cell_possibilities_updated(coords : Vector2i, count : int, entropy : float)

## A signal for when the grid is cleared.
signal grid_cleared()

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
var _last_defer : float = 0.0 ## Total time since last defer.
var _seed : int = 0 ## The seed used in the pseudorandom number generator (PRNG).
var _dimensions : Vector2i = Vector2i(MIN_SIZE, MIN_SIZE) ## The dimensions of the output grid.
var _max_local_resets : int = 1000 ## The maximum number of local resets.
var _tile_set : TileSet ## The tileset.
var _noise : Noise ## The noise generator.
var _prob_config : WFCProbabilityConfiguration ## The probability configuration.
var _tiles : Dictionary[Vector3i, Array] = {} ## A collection of tile-layout mappings. The key is the tile (source ID and atlas coords) and the value is the terrain layout.
var _tile_weights : Dictionary[Vector3i, float] = {} ## A collection of tile probability weights for each tile (source ID and atlas coords).
var _terrain_tiles : Dictionary[int, Array] = {} ## A collection of tiles organized by terrain index. The key is the terrain index and the value is an [Array] of tiles (source ID and atlas coords).
var _terrain_layouts : Array[Array] = [] ## A collection of terrain layouts.
var _layout_tiles : Dictionary[int, Array] = {} ## A collection of tiles organized by layout. The key is the terrain layout index and the value is an [Array] of tiles (source ID and atlas coords).
var _layout_neighbors : Dictionary[int, Dictionary] = {} ## A collection of layouts considered to be valid neighbors to another layout. The key is the terrain layout index and the value is collection (indexed by ComparisonDirection) of arrays of valid neighbor layout indices.
var _terrain_edges : Array[Vector2i] = [] ## The edges between terrains.
var _terrain_sequence : Array[int] = [] ## The most efficient sequence to go over all terrains to ensure all edges are represented.
var _terrain_distribution : Array[Array] = [] ## The distribution of probabilities for terrains, respecting sequencing. X is domain end and Y is terrain index.

## Initialize the wave function collapse solver.
##
## It is expected that within the [param tile_set] all tiles will be
## one-tile-by-one-tile in size. Only tiles with terrain mappings will be
## used. Only the first terrain set encountered (terrain 0) will be used.
##
## The [param noise] can be set to any [Noise], but should have smooth transitions
## and go through the full range, for best effect. This will inform the terrain
## distributions.
##
## An optional [param prob_config] may be supplied to alter default probability
## distributions.
func _init(
	tile_set : TileSet, noise : Noise, prob_config : WFCProbabilityConfiguration = null
) -> void:
	_tile_set = tile_set
	_noise = noise
	
	if !_noise:
		_print_debug_message("A valid noise generator must be provided.", DebugSeverity.ERROR)
	
	# Ensure there is always a probability configuration.
	if prob_config:
		_prob_config = prob_config
	else:
		_prob_config = WFCProbabilityConfiguration.new()
	
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
			base_weight = _prob_config.get_terrain_edge_weight()
		
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
		# Skip over terrains that have 0.0 frequency
		if _prob_config.get_terrain_frequency(u) == 0.0 || _prob_config.get_terrain_frequency(v) == 0.0:
			continue
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
## This applies terrain frequencies from the [WFCProbabilityConfiguration].
##
## X is the domain end (the highest) and Y is the terrain.
func _build_terrain_distribution() -> void:
	var terrain_weights : Dictionary[int, float] = {}
	var counts : Dictionary[int, int] = {}
	for terrain : int in _terrain_sequence:
		if !counts.has(terrain):
			counts[terrain] = 0
		counts[terrain] += 1
		terrain_weights[terrain] = _prob_config.get_terrain_frequency(terrain)
	
	var total_weight : float = 0.0
	for terrain : int in terrain_weights:
		total_weight += terrain_weights[terrain]
	
	var end : float = 0.0 # Current domain end
	var distribution : Array[Array] = []
	for terrain : int in _terrain_sequence:
		# Adjust frequencies so terrains that appear more in the sequence are evened out
		var weight : float = terrain_weights[terrain] / total_weight / counts[terrain]
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

## Apply a debug delay when in debug mode.
##
## This will also defer processing to the main loop, if this is not in debug
## mode.
func _wait_on_debug_delay():
	if _debug_mode && _debug_delay > 0.0:
		await Engine.get_main_loop().create_timer(_debug_delay).timeout
	else:
		# Defer to the main loop every physics tick to prevent hanging
		if (Time.get_ticks_msec() - _last_defer) > (1000.0 / Engine.physics_ticks_per_second):
			_last_defer = Time.get_ticks_msec()
			await Engine.get_main_loop().process_frame

## Get the terrain index from the probability distribution belonging to x.
##
## The [param x] parameters expects a value between 0 and 1.
##
## Returns the terrain index or -1 on none found.
func _get_terrain_by_distribution(x : float) -> int:
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
	if !_noise:
		return -1
	
	var val : float = (_noise.get_noise_2d(coords.x, coords.y) / 2.0 + 0.5)
	return _get_terrain_by_distribution(clampf(val, 0.0, 1.0))

## Place tile in grid cell.
##
## This does not check if a placement is valid.
func _place_tile(grid : WFCGrid, coords : Vector2i, tile : Vector3i) -> void:
	var cell = grid.get_cell(coords.x, coords.y)
	cell.place_tile(tile)
	tile_placed.emit(coords, tile.x, Vector2i(tile.y, tile.z))

## Remove tile and reset grid cell.
func _remove_tile(grid : WFCGrid, coords : Vector2i) -> void:
	var cell = grid.get_cell(coords.x, coords.y)
	cell.reset()
	tile_removed.emit(coords)

## Get random tile from array of tiles.
##
## This takes into account weights.
##
## Returns the tile as source ID and atlas coords, or [code]Vector3i(-1, -1, -1)[/code] on error.
func _get_random_tile(rng : RandomNumberGenerator, tiles : Array) -> Vector3i:
	var total_weight : float = 0.0
	
	for tile in tiles:
		total_weight += _tile_weights[tile]
	
	if total_weight <= 0:
		return Vector3i(-1, -1, -1)
	
	var roll : float = rng.randf() * total_weight
	for tile : Vector3i in tiles:
		var weight = _tile_weights[tile]
		if roll <= weight:
			return tile
		roll -= weight
	
	return Vector3i(-1, -1, -1)

## Get a list of valid tiles for a cell.
##
## Inquires the cell's neighbors to see what tiles are valid for a cell.
func _get_valid_tiles(grid : WFCGrid, coords : Vector2i) -> Array[Vector3i]:
	# The directions are reversed here, as the comparison happens from the other cell
	var neighbors : Dictionary[ComparisonDirection, WFCCell] = {}
	neighbors[ComparisonDirection.LEFT_TO_RIGHT] = grid.get_cell(coords.x - 1, coords.y)
	neighbors[ComparisonDirection.BOTTOM_TO_TOP] = grid.get_cell(coords.x, coords.y + 1)
	neighbors[ComparisonDirection.RIGHT_TO_LEFT] = grid.get_cell(coords.x + 1, coords.y)
	neighbors[ComparisonDirection.TOP_TO_BOTTOM] = grid.get_cell(coords.x, coords.y - 1)
	
	var tiles : Array[Vector3i] = _tiles.keys().duplicate()
	
	for dir : ComparisonDirection in neighbors:
		var cell : WFCCell = neighbors[dir]
		
		# No neighbor cell means it is outside the grid
		if !cell:
			continue
		
		# No tile, means all tiles are possible
		if cell.get_status() == WFCCell.Status.OPEN:
			continue
		
		# Get the layout for the neighboring tile and load the array of layouts which can neighbor it
		var neighbor_tile : Vector3i = cell.get_tile()
		var neighbor_layout : Array = _tiles[neighbor_tile]
		var neighbor_layout_id : int = _terrain_layouts.find(neighbor_layout)
		var valid_layouts : Array = _layout_neighbors[neighbor_layout_id][dir]
		
		# Remove tiles found to be invalid
		var valid_tiles : Array = []
		for layout in valid_layouts:
			valid_tiles += _layout_tiles[layout]
		tiles = tiles.filter(func(tile):
			return valid_tiles.has(tile)
		)
	
	return tiles

## If the tile is valid for a cell.
##
## Compares the tile to the current cell's neighbors to see if the tile can be
## placed there. This also works to identify if a cell already in a tile is
## valid.
func _is_tile_placement_valid(grid : WFCGrid, coords : Vector2i, tile : Vector3i) -> bool:
	# If this cell is open or invalid, skip checking as it is unnecessary
	var status := grid.get_cell(coords.x, coords.y).get_status()
	if status == WFCCell.Status.INVALID:
		return false
	if status == WFCCell.Status.OPEN:
		return true
	
	# The directions are reversed here, as the comparison happens from the other cell
	var neighbors : Dictionary[ComparisonDirection, WFCCell] = {}
	neighbors[ComparisonDirection.LEFT_TO_RIGHT] = grid.get_cell(coords.x - 1, coords.y)
	neighbors[ComparisonDirection.BOTTOM_TO_TOP] = grid.get_cell(coords.x, coords.y + 1)
	neighbors[ComparisonDirection.RIGHT_TO_LEFT] = grid.get_cell(coords.x + 1, coords.y)
	neighbors[ComparisonDirection.TOP_TO_BOTTOM] = grid.get_cell(coords.x, coords.y - 1)
	
	# The main tile layout
	var layout : Array = _tiles[tile]
	var layout_id : int = _terrain_layouts.find(layout)
	
	for dir : ComparisonDirection in neighbors:
		var cell : WFCCell = neighbors[dir]
		
		# No neighbor cell means it is outside the grid
		if !cell:
			continue
		
		# No tile, means all tiles are possible
		if cell.get_status() == WFCCell.Status.OPEN:
			continue
		
		# Get the layout for the neighboring tile and load the array of layouts which can neighbor it
		var neighbor_tile : Vector3i = cell.get_tile()
		var neighbor_layout : Array = _tiles[neighbor_tile]
		var neighbor_layout_id : int = _terrain_layouts.find(neighbor_layout)
		var valid_layouts : Array = _layout_neighbors[neighbor_layout_id][dir]
		
		# If the layout for the tile is not found, then it is invalid
		if valid_layouts.find(layout_id) == -1:
			return false
	
	return true

## Calculate entropy for cell.
##
## This calculates the Shannon entropy for a possibility space, saving it to the cell.
func _calc_cell_entropy(grid : WFCGrid, coords : Vector2i) -> void:
	var cell : WFCCell = grid.get_cell(coords.x, coords.y)
	if !cell:
		return
	
	# If cell is already filled (whether valid or not), the entropy is 0.0
	var status = cell.get_status()
	if status == WFCCell.Status.CLOSED || status == WFCCell.Status.INVALID:
		cell.set_entropy(0.0, 0)
		cell_possibilities_updated.emit(coords, 0, 0.0)
		return
	
	# Load the possibility space (valid tiles) and calculate the total entropy based on weights
	var total_weight : float = 0.0
	var entropy : float = 0.0
	var valid_tiles : Array[Vector3i] = _get_valid_tiles(grid, coords)
	for tile : Vector3i in valid_tiles:
		total_weight += _tile_weights[tile]
	
	for tile : Vector3i in valid_tiles:
		var prob : float = _tile_weights[tile] / total_weight
		entropy -= (prob * log(prob) / log(2))
	
	cell.set_entropy(entropy, valid_tiles.size())
	cell_possibilities_updated.emit(coords, valid_tiles.size(), entropy)

## Calculate entropy for cell and its neighbors.
##
## This calculates the Shannon entropy for a possibility space, for the cell
## and the neighbors touching it above, below, to the right, and left.
func _calc_cell_neighborhood_entropy(grid : WFCGrid, coords : Vector2i):
	_calc_cell_entropy(grid, coords)
	_calc_cell_entropy(grid, Vector2i(coords.x - 1, coords.y))
	_calc_cell_entropy(grid, Vector2i(coords.x + 1, coords.y))
	_calc_cell_entropy(grid, Vector2i(coords.x, coords.y - 1))
	_calc_cell_entropy(grid, Vector2i(coords.x, coords.y + 1))

## Place tiles in grid cells based on noise.
##
## This is intended to place cells, many of which will be invalid and will later be removed.
func _place_default_tiles(rng : RandomNumberGenerator, grid : WFCGrid) -> void:
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
			var tile = _get_random_tile(rng, tiles)
			if tile == Vector3i(-1, -1, -1):
				continue
			
			_place_tile(grid, Vector2i(x, y), tile)

## Invalidate any cells that should be.
##
## Goes through all cells in the grid and marks any that should be invalid.
func _mark_invalid_cells(grid : WFCGrid):
	var dims : Vector2i = grid.get_dimensions()
	for x : int in dims.x:
		for y : int in dims.y:
			var cell : WFCCell = grid.get_cell(x, y)
			if cell.get_status() == WFCCell.Status.CLOSED:
				if !_is_tile_placement_valid(grid, Vector2i(x, y), cell.get_tile()):
					cell.mark_invalid()

## Reset any invalid cells.
##
## Goes through all cells in the grid and resets any marked invalid.
func _reset_invalid_cells(grid : WFCGrid):
	var dims : Vector2i = grid.get_dimensions()
	for x : int in dims.x:
		for y : int in dims.y:
			var cell : WFCCell = grid.get_cell(x, y)
			if cell.get_status() == WFCCell.Status.INVALID:
				_remove_tile(grid, Vector2i(x, y))

## Remove tiles from cells around a point.
##
## Does not remove at the center.
##
## Returns any cells, indexed by coordinates, that had tile removed.
func _remove_tiles_around(grid : WFCGrid, coords : Vector2i, radius : int) -> Dictionary[Vector2i, WFCCell]:
	var cells_reset : Dictionary[Vector2i, WFCCell] = {}
	radius = max(radius, 1)
	
	for x_offset : int in range(-radius, radius + 1):
		for y_offset : int in range(-radius, radius + 1):
			# Step over central tile
			if x_offset == 0 && y_offset == 0:
				continue
			
			var x = coords.x + x_offset
			var y = coords.y + y_offset
			
			var cell = grid.get_cell(x, y)
			
			# If the coordinates are outside the grid, step over
			if !cell:
				continue
			
			# Step over any cells that are open
			if cell.get_status() == WFCCell.Status.OPEN:
				continue
			
			# Remove the tile and calculate entropy
			var target : Vector2i = Vector2i(x, y)
			_remove_tile(grid, target)
			_calc_cell_neighborhood_entropy(grid, target)
			cells_reset[target] = cell
	
	return cells_reset

## Place a random tile into a cell.
##
## This will choose a random tile from the valid possibilities and place it.
func _place_rand_tile(rng : RandomNumberGenerator, grid : WFCGrid, coords : Vector2i):
	var tiles : Array[Vector3i] = _get_valid_tiles(grid, coords)
	var tile : Vector3i = _get_random_tile(rng, tiles)
	_place_tile(grid, coords, tile)
	_calc_cell_neighborhood_entropy(grid, coords)

## Calculate entropy for the entire grid.
##
## This calculates the Shannon entropy for every cell in the grid.
func _calc_grid_entropy(grid : WFCGrid):
	var dims : Vector2i = grid.get_dimensions()
	for x : int in dims.x:
		for y : int in dims.y:
			_calc_cell_entropy(grid, Vector2i(x, y))

## Create the wave function collapse (WFC) queue.
##
## Load all open cells into a queue, organized as coordinate-cell pairs.
func _create_wfc_queue(grid : WFCGrid) -> Array:
	var dims : Vector2i = grid.get_dimensions()
	var queue : Array = []
	for x : int in dims.x:
		for y : int in dims.y:
			var cell : WFCCell = grid.get_cell(x, y)
			if cell.get_status() == WFCCell.Status.OPEN:
				queue.push_back([Vector2i(x, y), cell])
	
	return queue

## Sort the wave function collapse (WFC) queue.
##
## The queue items will be sorted by entropy then distance from center.
func _sort_wfc_queue(queue : Array) -> void:
	queue.sort_custom(func (a, b):
		if a[1].get_entropy() == b[1].get_entropy():
			return a[0].distance_to(_dimensions/2.0) < b[0].distance_to(_dimensions/2.0)
		return a[1].get_entropy() < b[1].get_entropy()
	)

## Use wave function collapse (WFC) to resolve the grid.
##
## Run through wave function collapse trying to solve for a valid state where
## all tiles are occupied. Apply local resets up until the limit.
##
## All cells in the grid are expected to either be be opened or closed.
## Invalid cells should be processed in advance.
##
## Returns true if a solution is found, false if not.
func _run_wfc_loop(rng : RandomNumberGenerator, grid : WFCGrid, local_resets : int) -> bool:
	# Load all open cells into a queue, organized as coordinate-cell pairs
	var queue : Array = _create_wfc_queue(grid)
	
	var resets_remaining : int = local_resets
	
	while queue.size() > 0:
		await _wait_on_debug_delay()
		
		_sort_wfc_queue(queue)
		var next : Array = queue.pop_front()
		var coords : Vector2i = next[0]
		var cell : WFCCell = next[1]
		
		if cell.get_possibility_count() > 0:
			_place_rand_tile(rng, grid, coords)
			
			# If there are no tiles left, this is successful
			if queue.size() == 0:
				grid.set_solved()
				_print_debug_message(
					String(
						"A solution has been found with " + str(resets_remaining) +\
						" of " + str(local_resets) + " local resets remaining."
					),
					DebugSeverity.INFORMATION
				)
				return true
		else:
			if resets_remaining > 0:
				# Try a local reset if there are any available
				resets_remaining -= 1
				var tile_removal_radius : int = 1
				
				# To prevent this from getting stuck in loops
				# Alternate how many tiles to remove
				# By default, remove a radius of 1
				# Increase to 2 and 3 on the 15th and 18th iterations
				# Assuming this starts at a multiple of 20
				if (resets_remaining % 10) == 5:
					tile_removal_radius = 2
				if (resets_remaining % 10) == 2:
					tile_removal_radius = 3
				
				var cells_updated : Dictionary[Vector2i, WFCCell] = _remove_tiles_around(grid, coords, tile_removal_radius)
				queue.push_back([coords, cell])
				for neighbor_coords : Vector2i in cells_updated:
					var neighbor_cell : WFCCell = cells_updated[neighbor_coords]
					queue.push_back([neighbor_coords, neighbor_cell])
			else:
				# No resets means failure
				grid.set_failed(WFCGrid.FailureCause.NO_SOLUTION)
				grid_cleared.emit()
				_print_debug_message(
					String("No solution could be found."),
					DebugSeverity.INFORMATION
				)
				
				return false
	
	return false

## Use wave function collapse (WFC) to resolve the grid.
##
## Run through wave function collapse trying to solve for a valid state where
## all tiles are occupied. Apply local resets up until the limit.
##
## All cells in the grid are expected to either be be opened or closed.
## Invalid cells should be processed in advance.
func _solve_wfc(rng : RandomNumberGenerator, grid : WFCGrid):
	_print_debug_message(
		String("Starting wave function loop."),
		DebugSeverity.INFORMATION
	)
	
	# Abort if loop fails
	if !(await _run_wfc_loop(rng, grid, _max_local_resets)):
		return

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

## Set the maximum number of local retries before the solver gives up.
##
## This must be zero or above.
func set_max_local_resets(max_local_resets : int) -> void:
	_max_local_resets = maxi(max_local_resets, 0)

## Run the noise-based wave function collapse (WFC) solver.
##
## This consists of several phases including:
## 1. Using noise to set the initial tile state of the grid to solid-edged terrain
##    tiles, based on the terrain distribution. This will result in invalid tile
##    placements; this is intentional.
## 2. Remove all tiles with invalid neighbor relationships. For example, a mud
##    tile edge touching a grass tile edge.
## 3. Calculate the entropy and possible tile counts for the open grid cells.
## 4. Run the wave function collapse solver until the grid has a fully-solved
##    grid, or runs out of attempts. Internally, this will reset groups of cells
##    if there are no valid tiles for a space.
##
## Returns a [WFCGrid] with tiles placed in valid positions. Be sure to check
## the status of the [WFCGrid] to make sure the solver was successful.
func run() -> WFCGrid:
	var start_time : int = Time.get_ticks_msec() ## When the process started
	var rng : RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = _seed
	var grid : WFCGrid = WFCGrid.new(_dimensions.x, _dimensions.y)
	
	_print_debug_message(
		"The solver has started with seed " + str(_seed) + ".",
		DebugSeverity.INFORMATION
	)
	
	# Phase 1: Set grid cells to solid terrain tiles based on noise
	_print_debug_message(
		"Phase 1: Placing default tiles along generated noise.",
		DebugSeverity.INFORMATION
	)
	_place_default_tiles(rng, grid)
	await _wait_on_debug_delay()
	
	# Phase 2: Invalidate then reset all cells that border tiles which they should not neighbor.
	_print_debug_message(
		"Phase 2: Removing all tiles with invalid neighbor relationships.",
		DebugSeverity.INFORMATION
	)
	_mark_invalid_cells(grid)
	await _wait_on_debug_delay()
	_reset_invalid_cells(grid)
	
	# Phase 3: Calculate initial entropy scores and possible tiles for each open cells.
	_print_debug_message(
		"Phase 3: Calculate entropy and possible tiles for open cells.",
		DebugSeverity.INFORMATION
	)
	_calc_grid_entropy(grid)
	await _wait_on_debug_delay()
	
	# Phase 4: Run wave function collapse, with local resets, until a full grid is found
	_print_debug_message(
		"Phase 4: Running wave function collapse process.",
		DebugSeverity.INFORMATION
	)
	await _solve_wfc(rng, grid)
	
	var end_time : int = Time.get_ticks_msec() ## When the process ended
	
	_print_debug_message(
		String("The solver has finished and has taken " + str(end_time - start_time) + "ms to run."),
		DebugSeverity.INFORMATION
	)
	
	return grid
