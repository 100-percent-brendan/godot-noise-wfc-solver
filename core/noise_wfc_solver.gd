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
# TODO: Consider adding noise parameters
var _tile_set : TileSet ## The tileset.
# TODO: Make sure all the below are used somewhere
var _tiles : Dictionary[Vector3i, Array] = {} ## A collection of tile-layout mappings. The key is the tile (source ID and atlas coords) and the value is the terrain layout.
var _terrain_tiles : Dictionary[int, Array] = {} ## A collection of tiles organized by terrain identifier. The key is the terrain identifier and the value is an [Array] of tiles (source ID and atlas coords).
var _terrain_layouts : Array[Array] = [] ## A collection of terrain layouts.
var _layout_tiles : Dictionary[int, Array] = {} ## A collection of tiles organized by layout. The key is the terrain layout index and the value is an [Array] of tiles (source ID and atlas coords).
var _terrain_edges : Array[Vector2i] = [] ## The edges between terrains.
var _terrain_sequence : Array[int] = [] ## The most efficient sequence to go over all terrains to ensure all edges are represented.
var _terrain_probability_distribution : Array = [] ## The distribution of probabilities for terrains, respecting sequencing. X is domain end and Y is terrain.
# TODO: Consider adding terrain weight
# TODO: Determine what terrains border each other
# TODO: Define terrain gradient

## Initialize the wave function collapse solver.
##
## It is expected that within the [param tile_set] all tiles will be
## one-tile-by-one-tile in size. Only tiles with terrain mappings will be
## used. Only the first terrain set encountered will be used.
func _init(tile_set : TileSet) -> void:
	_tile_set = tile_set
	
	# TODO: Confirm the tiles have appropriate terrain mappings
	# TODO: Determine terrain weight based on shape
	
	# Load the tile and terrain data
	_load_tile_data()
	
	# Find the optimal terrain sequence
	_find_terrain_sequence()
	
	# Build a probability distribution from the terrain sequence
	_build_terrain_probability_distribution()

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
func _build_terrain_probability_distribution() -> void:
	# TODO Consider applying per-terrain frequencies; e.g. some terrains are more likely than others
	var counts : Dictionary[int, int] = {}
	for terrain : int in _terrain_sequence:
		if !counts.has(terrain):
			counts[terrain] = 0
		counts[terrain] += 1
	
	var end : float = 0.0 # Current domain end
	var distribution : Array = []
	for terrain : int in _terrain_sequence:
		# Adjust frequencies so terrains that appear more in the sequence are evened out
		var weight : float = 1.0 / counts.size() / counts[terrain]
		end += weight
		distribution.push_back([end,terrain])
	
	# Set end of all domains to 1.0, to account for possible floating point errors
	if distribution.size() > 0:
		distribution[-1][0] = 1.0
	
	_terrain_probability_distribution = distribution

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
