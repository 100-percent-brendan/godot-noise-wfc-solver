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

var _debug_mode : bool = false ## Output debug messages and information.
var _debug_delay : float = 0.0 ## Delay between tile placements and other major actions.
var _seed : int = 0 ## The seed used in the pseudorandom number generator (PRNG).
var _dimensions : Vector2i = Vector2i(MIN_SIZE, MIN_SIZE) ## The dimensions of the output grid.
var _max_retries : int = 100 ## The maximum number of retry attempts.
var _max_local_resets : int = 100 ## The maximum number of local resets.
# TODO: Consider adding noise parameters
var _tile_set : TileSet ## The tileset.
# TODO: Add terrain list
# TODO: Consider adding terrain weight
# TODO: Determine what terrains border each other
# TODO: Define terrain gradient

## Initialize the wave function collapse solver.
##
## It is expected that within the [param tile_set] all tiles will be
## one-tile-by-one-tile in size. Only tiles with terrain mappings will be
## used. Only the first terrain set encountered will be used.
func _init(tile_set : TileSet, input_maps : Array[TileMapLayer]) -> void:
	_tile_set = tile_set
	# TODO: Confirm the tiles have appropriate terrain mappings
	# TODO: Load the tiles and terrain data
	# TODO: Determine terrain weight based on shape

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
func set_dimensions(width : int, height : int):
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
