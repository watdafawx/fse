"""fse-std's themes in a real client (--flat: with the game's windows in flat tiles; --scale 2: the game's GUI scale) (vanilla + fse-std + the theme-test driver): every theme shot, a live colour
edit read back from the engine, the game's own windows coloured and given back. Screenshots in
test/run/script-output/theme-*.png; exit code 1 when a check failed. Don't run it while you play."""
import json, re, shutil, subprocess, sys, time
from pathlib import Path

NATIVE = Path(__file__).resolve().parents[1]
from factorio_paths import run_dir, watch_game  # noqa: E402
RUN = run_dir(Path(__file__).resolve().parent / "run")
MODS = RUN / "theme-mods"
OUT = RUN / "script-output"
shutil.rmtree(MODS, ignore_errors=True)
MODS.mkdir(parents=True)
shutil.copytree(NATIVE / "mods" / "fse-std", MODS / "fse-std")
FLAT = "--flat" in sys.argv  # (the startup setting fstd-flat-game on: the game's windows in flat tiles)
if FLAT:
    st = MODS / "fse-std" / "settings.lua"
    st.write_text(st.read_text().replace("default_value = false", "default_value = true"))
shutil.copytree(NATIVE / "test" / "theme-test", MODS / "theme-test")
(MODS / "theme-test" / "info.json").write_text(json.dumps({"name": "theme-test", "version": "0.0.1",
    "title": "theme test", "author": "mtopfox", "factorio_version": "2.0", "dependencies": ["base", "fse-std"]}))
names = ["base", "fse-std", "theme-test"]
(MODS / "mod-list.json").write_text(json.dumps({"mods": [{"name": n, "enabled": n in names} for n in
                                                         names + ["elevated-rails", "quality", "space-age"]]}))
for f in OUT.glob("theme-*"):
    f.unlink()
save = RUN / "theme.zip"
save.unlink(missing_ok=True)
# --scale N: the game's GUI scale (else automatic), in a config of its own: a scale another test left in the shared
# config.ini doesn't reach this one
config = RUN / "config-theme.ini"
base = re.split(r"(?m)^\[interface\]", (RUN / "config.ini").read_text(encoding="utf-8"))[0]
if "--scale" in sys.argv:
    base += f"[interface]\nui-scale-mode=manual-pixels\ncustom-ui-scale={sys.argv[sys.argv.index('--scale') + 1]}\n"
config.write_text(base, encoding="utf-8")
launch = [str(NATIVE / "dist" / "fse-launcher.exe"), "--config", str(config), "--mod-directory", str(MODS)]
subprocess.run(launch + ["--create", str(save)], capture_output=True)
game = watch_game(launch + ["--load-game", str(save)])
start = time.time()
while time.time() - start < 240 and not (OUT / "theme-done.txt").exists() and game.poll() is None:
    time.sleep(1)
time.sleep(2)
game.kill()  # (the launcher: its job takes the game with it)
log = (RUN / "factorio-current.log").read_text(errors="replace").splitlines()
errors = [l for l in log if "Error" in l or "error (handled)" in l]

# the second run: the save loaded, colours written while it loads (the side menu is drawn in them at once)
for f in ("theme-done2.txt", "theme-after-load.png"):
    (OUT / f).unlink(missing_ok=True)
reload = RUN / "saves" / "_autosave-theme-reload.zip"
if reload.exists():
    game = watch_game(launch + ["--load-game", str(reload)])
    start = time.time()
    while time.time() - start < 180 and not (OUT / "theme-done2.txt").exists() and game.poll() is None:
        time.sleep(1)
    time.sleep(2)
    game.kill()
    log = (RUN / "factorio-current.log").read_text(errors="replace").splitlines()
    errors += [l for l in log if "Error" in l or "error (handled)" in l]
print("errors:", "\n".join(errors)[-2000:] or "none")
res = OUT / "theme-result.json"
if not res.exists():
    print("no result")
    sys.exit(1)
r = json.loads(res.read_text())
# the side menu (research, menu buttons) in the theme's colours: compared with the game's own
from PIL import Image, ImageChops, ImageStat  # noqa: E402


def side_menu_diff(name):
    a, b = OUT / f"theme-{name}.png", OUT / "theme-vanilla-gui-off.png"
    if not (a.exists() and b.exists()):
        return -1
    ia, ib = Image.open(a).convert("RGB"), Image.open(b).convert("RGB")
    # (its research and menu buttons: 256..16 GUI units from the right edge, 48..128 down, at the run's GUI scale)
    s, w = r.get("scale") or 1.25, ia.width
    box = tuple(int(v) for v in (w - 256 * s, 48 * s, w - 16 * s, 128 * s))
    return sum(ImageStat.Stat(ImageChops.difference(ia.crop(box), ib.crop(box))).mean) / 3


for name, label in (("fulgora-vanilla-gui", "side menu drawn again in the theme"),
                    ("after-load", "side menu in the theme straight after a load")):
    d = side_menu_diff(name)
    r["checks"].append({"name": label, "ok": d > 6, "detail": f"mean difference {d:.1f}"})
    if name == "after-load" and d >= 0:
        r["shots"].append(name)
bad = [c for c in r["checks"] if not c["ok"]]
for c in r["checks"]:
    print("ok  " if c["ok"] else "FAIL", c["name"], "" if c["ok"] else c.get("detail", ""))
print("screenshots:", ", ".join(r["shots"]))
sys.exit(1 if bad else 0)
