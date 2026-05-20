Noise-Based Wave Function Collapse Solver
=========================================
This simple tiled model wave function collapse (WFC) solver uses a noise function to inform the initial placement of tiles.
This governs the overall shape of the terrain.

This method was devised as an improvement to one of my earlier [implementations of wave function collapse](https://github.com/100-percent-brendan/godot-stm-wfc-solver/tree/main) algorithm.
While some components are similar, this is a complete reimagining and contains many fundemental improvements over the original.

As the project has been implemented in Godot using many built-in constructs, the solver can be used indirectly (or directly with a few minor improvements) to populate a production Godot tile map.

Animation
---------
**Place Animation Here**

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
2. No one size fits all for noise. For any noise algorithm chosen, it is as much art as science, and should be tailored to the use case. Careful tuning of noise can lead to a more organic feeling, as well.
3. The problem of mapping a floating point number to a terrain index has an established solution. After carefully researching the issue, I discovered the problem can be solved using a concept from graph theory known as the route inspection (Chinese postman) problem. The notion is, that you want to explore all transitions (edges) between the terrains to find (or make) what is known as a Eulerian. This is the most efficient path to explore all edges.
   1. Alternatively, I had originally considered trying to build a solver to find the Hamiltonian that included all terrains. Unlike a Eulerian which explores edges, a Hamiltonian explores all vertices (terrains). While this may work adaquately, it would leave some terrain transitions unexplored.
4. By applying carefully curated noise, complete retries (restarts) are not (or are very rarely) required. Originally, I had considered applying retry logic. I discovered that with noise, however, it is largely unnecessary. In my implementation, local resets are used to prevent states where tile placement may get stuck.
   1. I found it was possible to get some extreme forms of noise to get stuck or fail, but by applying some deterministic variability to the radius that resets occurred in, I was able to side-step this.
5. By using noise to collapse the initial placement of tiles, I was able to speed up the process of finding a complete tile map by a substantial amount.

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
   - A terrain distribution is calculated from the most efficient sequence for all terrains, informed by the probability configuration; this maps all terrains between 0.0 and 1.0
- Initialize the Grid
   - Setup an output grid, standing in for a tile map
- Place Default Tiles
   - Use noise generator to place default tiles on the grid; all tiles have uniform solid terrain layouts
- Invalidate
   - Invalidate and remove all tiles that cannot be neighbors; this will be any terrain transition (edge)
- Prepare
   - Calculate the entropy and tile possibilities for each open grid space
- Iterate Over Cell Queue
   - Retrieve the open grid cell with the lowest [Shannon entropy](https://en.wikipedia.org/wiki/Entropy_(information_theory)) or, on conflict, the one that is closest to the center
   - Populate that grid cell with a random tile from its valid possibilities; possibilities are determined by observing its neighbors; weights are used to determine probabilities
   - Propogate changes to its neighbor cells, so they can recalculate entropy and the possibility space
   - If a cell has no valid tiles and there are valid "neighborhood resets" remaining, clear a 3x3, 4x4, or 5x5 area around the cell, propogate changes, and reiterate
   - If a cell has no valid tiles and there are no valid "neighborhood resets" remaining, fail
- Solution or Failure
   - If a solution is found, output the complete solution in the grid
   - If the solver runs out of neighborhood resets and retries, and no solution is found, output an empty grid with the cause of failure

Tile Set Expectations
---------------------
There are several expectations for the supplied tile set:
1. Tile shape shall be square.
2. A terrain set shall be supplied at index 0, with at least one valid terrain.
3. The terrain mode shall be set to match corners and sides.
4. Tiles shall contain terrain data on all edge places.
5. Each tile shall be 1x1 in terms of unit size.
6. There must be edge pieces between bordering terrains allowing placement in all cardinal directions. A very simple subset of the Wang set may be used.
7. Terrains must logically flow such that no terrain is orphaned from the set. For example, water flows to mud flows to grass, but lava should not be on its own.

Running Project
---------------
To run this project from the Godot editor, ensure you have [Godot 4.5 or later](https://godotengine.org/). Import the project from within Godot. You can then Run Project from the play button in the upper-right of the editor.

Project-Specific Definitions
----------------------------
**Edge Tiles:** A tile used to form a connection between two or more terrains. These are necessary to interface terrains within the same tile set.
**Terrain Layout:** An array containing the terrain indices of the 8-edge pieces of a tile or group of tiles. This defines its boundary interface to other tiles, as well as what tiles it is considered equivilent to.
