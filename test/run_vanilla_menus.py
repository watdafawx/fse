"""the game's own menus with fse-std's "colour the game's own windows" on, in a real client (--flat: with the startup
setting "flat game windows" too; --theme <name>, aquilo without): every menu a script can open, shot to test/run/script-output/menus-*.png and
put together in menus-sheet.png. A look check, no pass/fail. Don't run it while you play."""
import json, shutil, subprocess, sys, time
from pathlib import Path

from PIL import Image

NATIVE = Path(__file__).resolve().parents[1]
from factorio_paths import run_dir, watch_game  # noqa: E402
RUN = run_dir(Path(__file__).resolve().parent / "run")
MODS = RUN / "menus-mods"
OUT = RUN / "script-output"
shutil.rmtree(MODS, ignore_errors=True)
MODS.mkdir(parents=True)
shutil.copytree(NATIVE / "mods" / "fse-std", MODS / "fse-std")
if "--flat" in sys.argv:
    st = MODS / "fse-std" / "settings.lua"
    st.write_text(st.read_text().replace("default_value = false", "default_value = true"))
shutil.copytree(NATIVE / "test" / "vanilla-menus", MODS / "vanilla-menus")
if "--theme" in sys.argv:  # (--theme <name>: another theme than aquilo)
    c = MODS / "vanilla-menus" / "control.lua"
    c.write_text(c.read_text().replace('local THEME = "aquilo"', f'local THEME = "{sys.argv[sys.argv.index("--theme") + 1]}"'))
(MODS / "vanilla-menus" / "info.json").write_text(json.dumps({"name": "vanilla-menus", "version": "0.0.1",
    "title": "vanilla menus", "author": "mtopfox", "factorio_version": "2.1", "dependencies": ["base", "fse-std"]}))
names = ["base", "fse-std", "vanilla-menus", "elevated-rails", "quality", "space-age"]
(MODS / "mod-list.json").write_text(json.dumps({"mods": [{"name": n, "enabled": True} for n in names]}))
for f in OUT.glob("menus-*"):
    f.unlink()
save = RUN / "menus.zip"
save.unlink(missing_ok=True)
launch = [str(NATIVE / "dist" / "fse-launcher.exe"), "--config", str(RUN / "config.ini"), "--mod-directory", str(MODS)]
subprocess.run(launch + ["--create", str(save)], capture_output=True)
game = watch_game(launch + ["--load-game", str(save)])
end = time.time() + 240
while time.time() < end and not (OUT / "menus-done.txt").exists() and game.poll() is None:
    time.sleep(1)
time.sleep(2)
game.kill()
log = (RUN / "factorio-current.log").read_text(errors="replace").splitlines()
print("errors:", "\n".join(l for l in log if "Error" in l or "error (handled)" in l)[-1500:] or "none")
print((OUT / "menus-log.txt").read_text() if (OUT / "menus-log.txt").exists() else "no log")
shots = sorted(OUT.glob("menus-*.png"))
if shots:
    tiles = [Image.open(s).convert("RGB").resize((640, 360)) for s in shots]
    sheet = Image.new("RGB", (640 * 3, 360 * ((len(tiles) + 2) // 3)))
    for i, t in enumerate(tiles):
        sheet.paste(t, ((i % 3) * 640, (i // 3) * 360))
    sheet.save(OUT / "menus-sheet.png")
    print("sheet:", OUT / "menus-sheet.png", [s.stem for s in shots])
