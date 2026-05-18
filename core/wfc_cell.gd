class_name WFCCell extends Node
## A grid cell within a [WFCGrid].
##
## Each cell stores part of a solution state, such as the Shannon entropy,
## if the cell has been populated, etc.

## The status of this cell.
enum Status {
	OPEN, ## The cell is open for placing a tile in.
	CLOSED, ## The cell has a tile in it.
	INVALID ## The cell has a tile in it, and that tile has been marked invalid.
}

var _tile : Vector3i = Vector3i() ## The source ID followed by the atlas coordinates within the source.
var _status : Status = Status.OPEN ## The status of this cell.
var _entropy : float = 0.0 ## The Shannon entropy.
var _possibility_count : int = 0 ## The total number of possible options.

## Set the Shannon entropy and count of possible tiles.
func set_entropy(entropy : float, count : int) -> void:
	_entropy = entropy
	_possibility_count = count

## Set cell to contain a tile.
##
## The [param tile] is a source ID and atlas coordinates.
func place_tile(tile : Vector3i) -> void:
	_tile = tile
	_status = Status.CLOSED
	_entropy = 0.0
	_possibility_count = 0

## Get the tile.
##
## Be sure to check status to see if a tile exists here first.
func get_tile() -> Vector3i:
	return _tile

## Reset cell to open.
func reset() -> void:
	_tile = Vector3i()
	_status = Status.OPEN
	_entropy = 0.0
	_possibility_count = 0

## Get the status.
func get_status() -> Status:
	return _status

## Get the entropy of the cell.
##
## This is the Shannon entropy of all tiles that could occupy the cell.
func get_entropy() -> float:
	return _entropy

## Get the total number of possible tiles.
func get_possibility_count() -> int:
	return _possibility_count

## Mark the cell as invalid.
func mark_invalid() -> void:
	_status = Status.INVALID
