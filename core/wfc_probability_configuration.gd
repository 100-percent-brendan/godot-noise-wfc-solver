class_name WFCProbabilityConfiguration extends Node
## A configuration class for wave function collapse (WFC) solver probabilities.
##
## This stores weights and modifiers intended to configure the solver.

## The base weight for how likely the edge between two terrains is to appear.
var _terrain_edge_weight : float = 1.0 / 80.0

## A collection of relative frequency for each terrain to appear.
var _terrain_frequencies : Dictionary[int, float] = {}

## Set the weight for how likely the edge between two terrains is to appear.
##
## This is a weight that is applied separately to each tile layout.
## Normal tile layouts each have a weight of 1.0.
## Edge pieces should be much less frequent, otherwise they dominate.
## Cannot be set lower than 1 / 64000.
func set_terrain_edge_weight(weight) -> void:
	_terrain_edge_weight = max(weight, 1.0 / 64000.0)

## Get the weight for how likely the edge between two terrains is to appear.
func get_terrain_edge_weight() -> float:
	return _terrain_edge_weight

## Set the frequency weight for how likely a terrain is to appear.
##
## This determines the relative size of the terrain in the distribution.
## By default, all terrains will be treated as having a probability of 1.0.
## The [param terrain] should match the index position of the terrain in the
## [TileSet].
##
## The [param frequency] will be bounded to a range of 0.1 and 10.0.
func set_terrain_frequency(terrain : int, frequency : float) -> void:
	_terrain_frequencies[terrain] = clampf(frequency, 0.1, 10.0)

## Get the frequency weight for how likely a terrain is to appear.
func get_terrain_frequency(terrain : int) -> float:
	if _terrain_frequencies.has(terrain):
		return _terrain_frequencies[terrain]
	
	return 1.0
