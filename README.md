Noise-Based Wave Function Collapse Solver
=========================================
This simple tiled model wave function collapse (WFC) solver uses a noise function to inform the initial placement of tiles.

This method was devised as an improvement to one of my earlier [implementations of wave function collapse](https://github.com/100-percent-brendan/godot-stm-wfc-solver/tree/main) algorithm.
While some components are similar, this is a complete reimagining and contains many fundemental improvements over the original.

As the project has been implemented in Godot using many built-in constructs, the solver can be used indirectly (or directly with a few minor improvements) to populate a production Godot tile map.

Basic Steps
-----------

- Setup
 - A tile set is input to establish what tiles, terrains, and terrain layouts are available
 - 

Project-Specific Definitions
----------------------------
**Terrain Layout:** An array containing the terrain indices of the 8-edge pieces of a tile or group of tiles. This defines its boundary interface to other tiles, as well as what tiles it is considered equivilent to.
