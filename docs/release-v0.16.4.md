## FSE 0.16.4

fse-std 0.6.7 (bundled):

- Window settings: `window.create{settings = true}` puts a gear by the close button; `theme.menu` opens a panel
  under the title bar (`keep_opened` keeps it open on clicks inside). It closes when its window is hidden.
- `theme.over`: a frame kept over an element of a window.
- Frames stuck to a window (rails, docks, drawers) follow its visibility, and follow it when the game moves it.
