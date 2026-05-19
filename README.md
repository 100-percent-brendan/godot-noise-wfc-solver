Noise-Based Wave Function Collapse Solver
=========================================
This simple tiled model wave function collapse (WFC) solver uses a noise function to inform the initial placement of tiles, prior to invalid tile removal and the application of the WFC algorithm.

This method was devised as an improvement to one of my earlier [implementations of wave function collapse](https://github.com/100-percent-brendan/godot-stm-wfc-solver/tree/main) algorithm.
While many components have been pulled forward, this is a functional rewrite and contains many fundemental improvements over the original.

As the project has been implemented in Godot using many built-in constructs, the solver can be used indirectly (or directly with a few minor improvements) to populate a production Godot tile map.
