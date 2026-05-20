Noise-Based Wave Function Collapse Solver
=========================================
This simple tiled model wave function collapse (WFC) solver uses a noise function to inform the initial placement of tiles.
This governs the overall shape of the terrain.

This method was devised as an improvement to one of my earlier [implementations of wave function collapse](https://github.com/100-percent-brendan/godot-stm-wfc-solver/tree/main) algorithm.
While some components are similar, this is a complete reimagining and contains many fundemental improvements over the original.

As the project has been implemented in Godot using many built-in constructs, the solver can be used indirectly (or directly with a few minor improvements) to populate a production Godot tile map.

Problem Framing
---------------
The mission of this project started as a simple question:
- How do I procedurally generate a collection of tiles for the terrain of a video game using 2D noise?

Several subsequent engineering challenges arose from this:
- How do I turn a single floating point noise value into a terrain value that flows neatly between terrains?
- How do I make it feel hand crafted and purposeful?
- How do I make sure the terrain is interesting?
- How do I avoid eternal processing loops?

Discoveries During Implementation
---------------------------------

Basic Steps
-----------

The overarching steps of my process are as follows:

- Setup
 - A tile set is input to establish what tiles, terrains, and terrain layouts are available
 - A noise generator is input to establish the initial placements of the terrains
 - A probability configuration is input to establish the frequency of terrains and edge tiles
 - Tile data is processed so as to build a set of efficient indices for tiles, terrains, and terrain layouts, including grouping tiles by their terrain layouts
 - Probability weights are established for each tile, taking into account terrain layouts, edge tiles, and the probability configuration; edge tiles are intended to have low probability of appearing
 - Indices are built for terrain layouts can neighbor what other terrain layouts
 - A route inspection (Chinese postman) problem solver is executed to find the most efficient sequence for all terrains
 - 


Tile Set Expectations
---------------------

Mapping Terrains to Noise
-------------------------

Route Inspection Problem Solver
-------------------------------

Project-Specific Definitions
----------------------------
**Edge Tiles:** A tile used to form a connection between two or more terrains. These are necessary to interface terrains within the same tile set.
**Terrain Layout:** An array containing the terrain indices of the 8-edge pieces of a tile or group of tiles. This defines its boundary interface to other tiles, as well as what tiles it is considered equivilent to.
