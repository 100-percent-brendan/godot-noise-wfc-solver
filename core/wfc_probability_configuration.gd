class_name WFCProbabilityConfiguration extends Node
## A configuration class for wave function collapse (WFC) solver probabilities.
##
## This stores weights and modifiers intended to configure the solver.

## The base weight for how likely the edge between two terrains is to appear.
var _terrain_edge_weight : float = 1.0 / 80.0

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
