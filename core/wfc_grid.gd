class_name WFCGrid extends Node
## A grid used when solving, storing and returning data from a wave function collapse solver.
##
## Each cell in the grid represents a slot where a square tile can be placed.
## Where a solution is found, this can be used to populate a [TileMapLayer]
## or other construct.

## The status of a grid.
enum Status {
	UNINITIALIZED, ## The grid is uninitialized and unsafe to used.
	UNSOLVED, ## The solution is not yet solved.
	FAILED, ## A solution could not be found or an error has occured.
	SOLVED ## A solution has been found.
}

## The cause of a failure.
enum FailureCause {
	NONE, ## There was no failure, or the cause was not known.
	ERROR, ## An unexpected error has occured.
	NO_SOLUTION ## A solution could not be found.
}

var _width : int = 0 ## The width of the grid.
var _height : int = 0 ## The height of the grid.
var _grid : Array[WFCCell] = [] ## The raw grid. This will wrap around based on width.
var _status : Status = Status.UNINITIALIZED ## The status of the grid.
var _failure_cause : FailureCause = FailureCause.NONE ## The cause of a failure.

## Initialize the grid.
func _init(width : int, height : int) -> void:
	_init_grid(width, height)
	_status = Status.UNSOLVED

## Initialize the grid.
func _init_grid(width : int, height : int):
	_width = maxi(width, 0)
	_height = maxi(height, 0)
	for w in range(_width):
		for h in range(_height):
			_grid.push_back(WFCCell.new())

## Get the width and height of the grid.
func get_dimensions() -> Vector2i:
	return Vector2i(_width, _height)

## Get the status of the grid.
func get_status() -> Status:
	return _status

## Get the cause of a failure.
func get_failure_cause() -> FailureCause:
	return _failure_cause

## Where a failure occurs, this may be called to invalidate the grid.
func set_failed(failure_cause : FailureCause) -> void:
	_width = 0
	_height = 0
	_grid.clear()
	_status = Status.FAILED
	_failure_cause = failure_cause

## Where a solution is found, this may be called to declare success.
func set_solved() -> void:
	if _status != Status.UNSOLVED:
		return
	
	_status = Status.SOLVED

## Get a cell at a specific position from the grid.
##
## The cell may then be updated.
func get_cell(x : int, y : int) -> WFCCell:
	if x >= _width || y >= _height || x < 0 || y < 0:
		return null
	
	return _grid[x + y * _width]
