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
- How do I procedurally generate a collection of tiles for the terrain of a video game using simple 2D noise?

Several subsequent engineering challenges arose from this:
- How do I turn a single floating point noise value into a terrain index that flows neatly between connected terrain?
- How do I make the terrain feel hand crafted and purposeful?
- How do I make sure the terrain is interesting?
- How do I avoid eternal processing loops?
- How do I avoid garbage?

Discoveries During Implementation
---------------------------------
I made several discoveries during implementation of this solver including:
1. A more minimalist tileset is prefered over the full blob tileset. While blob tilesets are useful for other terrain applications, I discovered that having too many possible edge tile options led to a lot of terrain garbage. Reducing the tile set led to a better effect.
2. No one size fits all for noise. For any noise algorithm chosen, it is as much art as science, and should be tailored to the use case. Careful tuning of noise can lead to a more organic feeling.
3. The problem of mapping a floating point number to a terrain index has an established solution. After carefully analyzing the issue, I discovered the problem can apply a concept from graph theory known as the route inspection (Chinese postman) problem. The notion is, that you want to explore all transitions (edges) between the terrains to find (or make) what is known as a Eulerian.
   1. Alternatively, I had originally considered trying to find the Hamiltonian that included all terrains. Unlike a Eulerian which explores edges, a Hamiltonian explores all vertices (terrains). While this may work adaquately, it would leave some terrain transitions unexplored.
4. 

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
