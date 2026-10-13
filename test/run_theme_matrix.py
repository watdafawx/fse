"""Our themed windows under several fse-std themes, in a real client: each (theme, window) opened and screenshot.
  python run_theme_matrix.py [--themes a,b,c | --themes all] [--windows srq,demo,picker,bpgen] [--res WxH] [--scale 2]
                             [--window-scale 150]
Windows: srq (Smart Research Queue's queue window), demo (fse-std-demo's /stddemo), picker (fse-std's theme window),
bpgen (the bpgen window). Default themes, read from fse/mods/fse-std/themes.lua: the "vanilla"-shaped one, the first
dark one with tiles of our own, the first light one. Mods from our source folders (fse/mods, mods, bpgen/mod),
flib from the game's mods folder; the theme-matrix driver sets a theme per player through the "fse-std" remote
interface (set_theme) and opens each window through its mod's interface.
--scale is the game's GUI scale; --window-scale fse-std's own window scale on top of it (the player's "Window size",
percent: 75 90 100 110 125 150 175 200), set through the "fse-std" interface (set_window_scale) before the windows open.
Each window's line says its scale and whether it is on the screen.
Out: test/run/theme-matrix/script-output/theme-matrix/<theme>-<window>.png, theme-matrix.txt. Exit 1 when a window
didn't open, a screenshot is missing, or the game logged an error (watch_game stops the game at once on one).
The user's Factorio must be closed (GUI tests pop windows and fail while it runs)."""
import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
from factorio_paths import BASE_MODS, PATHS, run_dir, stage_mods, user_mod, watch_game, with_deps  # noqa: E402

WINDOW_MODS = {"srq": "smart-research-queue", "demo": "fse-std-demo", "picker": "fse-std", "bpgen": "zzz-bpgen"}


def theme_list():
    """[(name, shape, light)] from fse-std's themes.lua, in its order"""
    src = (HERE.parent / "mods" / "fse-std" / "themes.lua").read_text(encoding="utf-8")
    out = []
    for m in re.finditer(r'^\s*\{\s*name\s*=\s*"([^"]+)"([^\n]*)', src, re.M):
        rest = m.group(2)
        shape = re.search(r'shape\s*=\s*"([^"]+)"', rest)
        if shape:
            out.append((m.group(1), shape.group(1), bool(re.search(r"\blight\s*=\s*true", rest))))
    return out


def default_themes(themes):
    pick = []
    for want in (lambda s, l: s == "vanilla", lambda s, l: s != "vanilla" and not l, lambda s, l: l):
        name = next((n for n, s, l in themes if want(s, l) and n not in pick), None)
        if name:
            pick.append(name)
    return pick


def main():
    ap = argparse.ArgumentParser(usage=__doc__.splitlines()[1].strip())
    ap.add_argument("--themes")
    ap.add_argument("--windows", default="srq,demo,picker,bpgen")
    ap.add_argument("--res")  # (default: the game window's size, so no window is cut off)
    ap.add_argument("--timeout", type=float, default=300)
    ap.add_argument("--scale", type=float)  # (the game's GUI scale, e.g. 1 or 2; default: automatic)
    ap.add_argument("--window-scale", type=int)  # (fse-std's window scale on top, percent, e.g. 150)
    a = ap.parse_args()
    known = theme_list()
    themes = ([n for n, _, _ in known] if a.themes == "all" else a.themes.split(",") if a.themes
              else default_themes(known))
    windows = a.windows.split(",")
    print("themes:", ", ".join(themes), "| windows:", ", ".join(windows), flush=True)

    run = HERE / "run" / "theme-matrix"
    shutil.rmtree(run, ignore_errors=True)  # (a fresh config.ini: a reset dialog would cover the windows)
    run = run_dir(run)
    if a.scale:
        with open(run / "config.ini", "a", encoding="utf-8") as f:
            f.write(f"[interface]\nui-scale-mode=manual-pixels\ncustom-ui-scale={a.scale}\n")
    md, out = run / "mods", run / "script-output"
    mods = with_deps({n: user_mod(n) for n in dict.fromkeys(["fse-std", "flib"] + [WINDOW_MODS[x] for x in windows
                                                                                     if x in WINDOW_MODS])})
    mods["theme-matrix"] = HERE / "theme-matrix"
    stage_mods(md, mods, BASE_MODS)
    drv = md / "theme-matrix"
    (drv / "info.json").write_text(json.dumps({
        "name": "theme-matrix", "version": "0.0.1", "title": "fse-std theme matrix test", "author": "mtopfox",
        "factorio_version": "2.0", "dependencies": ["base", "fse-std"] + [f"? {m}" for m in mods if m != "fse-std"
                                                                         and m != "theme-matrix"]}))
    lua_list = lambda xs: "{ " + ", ".join(json.dumps(x) for x in xs) + " }"  # noqa: E731
    res = "resolution = { %s, %s }, " % tuple(map(int, a.res.lower().split("x"))) if a.res else ""
    ws = f"window_scale = {a.window_scale}, " if a.window_scale else ""
    (drv / "config.lua").write_text(f"return {{ themes = {lua_list(themes)}, windows = {lua_list(windows)}, {res}{ws}}}\n")
    print("mods:", ", ".join(f"{n} ({p.name})" for n, p in mods.items()), flush=True)

    save = run / "matrix.zip"
    common = [str(PATHS["factorio_exe"]), "--config", str(run / "config.ini"), "--mod-directory", str(md)]
    r = subprocess.run(common + ["--create", str(save)], capture_output=True, text=True)
    if r.returncode or not save.exists():
        print("FAIL couldn't make the map:\n" + r.stdout[-3000:])
        sys.exit(1)
    # (Steam restarts a directly started game, dropping our arguments, unless it looks Steam-launched)
    env = dict(os.environ, SteamAppId="427520", SteamGameId="427520")
    game = watch_game(common + ["--load-game", str(save.resolve())], timeout=a.timeout + 60, env=env)
    done = out / "theme-matrix-done.txt"
    t0 = time.time()
    while time.time() - t0 < a.timeout and not done.exists() and game.poll() is None:
        time.sleep(0.5)
    time.sleep(3)  # (screenshots are written a moment after they're asked for)
    game.kill()
    subprocess.run(["taskkill", "/F", "/T", "/PID", str(game.pid)], capture_output=True)
    time.sleep(1)

    fails = []
    res = out / "theme-matrix.txt"
    text = res.read_text(encoding="utf-8", errors="replace") if res.exists() else ""
    print(text.strip() or "no results", flush=True)
    if not done.exists():
        fails.append("the run didn't finish")
    fails += [l for l in text.splitlines() if l.startswith("FAIL")]
    for shot in re.findall(r"^shot (\S+)$", text, re.M):
        p = out / shot
        if not (p.exists() and p.stat().st_size > 0):
            fails.append(f"screenshot missing: {p}")
    log = (run / "factorio-current.log").read_text(encoding="utf-8", errors="replace").splitlines()
    errors = [l for l in log if re.search(r"\bError\b|non-recoverable|error \(handled\)", l)]
    fails += [f"log: {l.strip()}" for l in errors]
    shots = sorted((out / "theme-matrix").glob("*.png"))
    print(f"screenshots ({len(shots)}): {out / 'theme-matrix'}")
    print("ALL PASS" if not fails else f"{len(fails)} FAILED:\n  " + "\n  ".join(fails))
    sys.exit(1 if fails else 0)


if __name__ == "__main__":
    main()
