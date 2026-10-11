## FSE 0.16.1

fse-std 0.6.1 (bundled):
- "Colour the game's own windows" reaches scroll panes, tabs and slots too: inventories, crafting, production,
  trains, the quick bar. Every game menu a script can open was checked one by one (test/run_vanilla_menus.py).
- Flat game windows: slot grids keep their tiling, frames open on one side keep it open, the map view stays
  see-through; the game's text follows the theme only here (on the game's own textures it would go unreadable).
- `theme.adopt` knows more styles (subheader and heading labels, list panes and rows, flib's title bar), so mod
  windows follow light themes fully; the theme window fits the monospace themes.

Smart Research Queue 1.1.7 and EZ Actions 0.2.5 are in the mod catalog.
