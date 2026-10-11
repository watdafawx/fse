"""fse-std's clickable components in a real client: a fold closed and opened, a search box typed into and cleared,
through the same handlers a click and typing run (the game takes no posted mouse input in game, and the real cursor is
the player's). Exit code 1 when a check failed. Don't run it while you play."""
import json, shutil, subprocess, sys, time
from pathlib import Path

NATIVE = Path(__file__).resolve().parents[1]
from factorio_paths import run_dir  # noqa: E402
RUN = run_dir(Path(__file__).resolve().parent / "run")
MODS = RUN / "clicks-mods"
OUT = RUN / "script-output"
shutil.rmtree(MODS, ignore_errors=True)
MODS.mkdir(parents=True)
shutil.copytree(NATIVE / "mods" / "fse-std", MODS / "fse-std")
shutil.copytree(NATIVE / "test" / "theme-clicks", MODS / "theme-clicks")
(MODS / "theme-clicks" / "info.json").write_text(json.dumps({"name": "theme-clicks", "version": "0.0.1",
    "title": "theme clicks", "author": "mtopfox", "factorio_version": "2.0", "dependencies": ["base", "fse-std"]}))
names = ["base", "fse-std", "theme-clicks"]
(MODS / "mod-list.json").write_text(json.dumps({"mods": [{"name": n, "enabled": n in names} for n in
                                                         names + ["elevated-rails", "quality", "space-age"]]}))
for f in OUT.glob("clicks-*"):
    f.unlink()
save = RUN / "clicks.zip"
save.unlink(missing_ok=True)
launch = [str(NATIVE / "dist" / "fse-launcher.exe"), "--config", str(RUN / "config.ini"), "--mod-directory", str(MODS)]
subprocess.run(launch + ["--create", str(save)], capture_output=True)
game = subprocess.Popen(launch + ["--load-game", str(save)], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
end = time.time() + 180
while time.time() < end and not (OUT / "clicks-result.json").exists() and game.poll() is None:
    time.sleep(1)
time.sleep(1)
game.kill()
log = (RUN / "factorio-current.log").read_text(errors="replace").splitlines()
print("errors:", "\n".join(l for l in log if "Error" in l or "error (handled)" in l)[-1500:] or "none")
r = json.loads((OUT / "clicks-result.json").read_text()) if (OUT / "clicks-result.json").exists() else {}
heard = r.get("searched", [])
checks = [("fold closes and opens on a click", r.get("closed") is True and r.get("reopened") is True),
          ("search hears typing", "find:iron" in heard),
          ("the clear button empties the box and says so", r.get("field_cleared") is True and heard[-1:] == ["find:"])]
for name, ok in checks:
    print("ok  " if ok else "FAIL", name, "" if ok else json.dumps(r))
sys.exit(0 if all(ok for _, ok in checks) else 1)
