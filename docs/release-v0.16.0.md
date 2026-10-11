## FSE 0.16.0

### New
- `native.write_many(targets, {path = number})`: the same numbers into many engine objects of one class in one call
  (each field's offset found once). fse-std recolours thousands of GUI sprites with it in ~30 ms.
- Draw plugin: `screen = true` layers in pixels of the game window (for drawing over the GUI), and a `poly` shape
  (a line through points; width 0 fills it).

### Fixed
- `native.read` / `native.write` with a `{ptr, type}` table target work at any Lua stack position.

### fse-std 0.6.0 (bundled)
Themes for mod windows, picked and recoloured live per player in the theme window (shortcut bar, or `/fse-theme`):
12 themes, a colour editor, saved and shared themes, themed controls and components, layouts, graphs and glows over
the GUI with the loader, and colouring the game's own windows (with a startup setting for flat, any-colour game
windows). Mods opt in with `window.create{themed = true}` or `theme.adopt(window)`; AI Crew, Smart Research Queue,
EZ Actions and Trash Slot do. Tested in a real client, in multiplayer (server and client in step, no desync) and on a
save made before themes. See the README's "Themes".
