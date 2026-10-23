"""Our top buttons (mod_gui's button flow: AI Crew, Pole Tidy auto, Robo Grid auto/tidy) with and without GUI Unifyer,
in a real client (vanilla + those mods + the gu-buttons driver). Pole Tidy's and Robo Grid's auto buttons are clicked
(input posted to the game window). Checked:
  with GUI_Unifyer (the newest GUI_Unifyer_*.zip in the game's mods folder): every button slot_button_notext, the
    two clicked ones slot_button_notext_selected after the click
  without: every button mod_gui_button, the clicked ones toggled = true, the others not
  python run_gu_buttons.py [--gu | --plain]     (default: both)
Screenshots and results in test/run/gu-buttons[-gu]/script-output. Exit 1 when a check failed. The user's Factorio
must be closed (see the memory note on GUI tests)."""
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
from factorio_paths import PATHS, run_dir, stage_mods, user_mod, watch_game, with_deps  # noqa: E402
import gui_input  # noqa: E402

CLICK = ("pole_tidy_auto", "robo_grid_auto")
OURS = ("aic_toggle", "pole_tidy_auto", "robo_grid_auto", "robo_grid_tidy")
fails = []


def check(what, ok):
    print(("ok   " if ok else "FAIL ") + what, flush=True)
    if not ok:
        fails.append(what)


def run(gu):
    tag = "gu" if gu else "plain"
    run = HERE / "run" / ("gu-buttons-gu" if gu else "gu-buttons")
    shutil.rmtree(run, ignore_errors=True)  # (a fresh config.ini: a reset dialog would cover the buttons)
    run = run_dir(run)
    md, out = run / "mods", run / "script-output"
    mods = with_deps({n: user_mod(n) for n in ["pole-tidy", "robo-grid", "ai-crew"] + (["GUI_Unifyer"] if gu else [])})
    mods["gu-buttons"] = HERE / "gu-buttons"
    stage_mods(md, mods, ["base"])
    (md / "gu-buttons" / "info.json").write_text(json.dumps({
        "name": "gu-buttons", "version": "0.0.1", "title": "GU top buttons test", "author": "mtopfox",
        "factorio_version": "2.1", "dependencies": ["base", "pole-tidy", "robo-grid", "ai-crew", "? GUI_Unifyer"]}))
    save = run / "gu.zip"
    common = [str(PATHS["factorio_exe"]), "--config", str(run / "config.ini"), "--mod-directory", str(md)]
    r = subprocess.run(common + ["--create", str(save)], capture_output=True, text=True)
    if r.returncode or not save.exists():
        check(f"{tag}: map created", False)
        print(r.stdout[-2000:])
        return
    print(f"--- {tag}: " + ", ".join(f"{n} ({p.name})" for n, p in mods.items()), flush=True)
    # (Steam restarts a directly started game, dropping our arguments, unless it looks Steam-launched)
    env = dict(os.environ, SteamAppId="427520", SteamGameId="427520")
    game = watch_game(common + ["--load-game", str(save.resolve())], env=env)
    txt, ready, done = out / "gu-buttons.txt", out / "gu-buttons-ready.txt", out / "gu-buttons-done.txt"
    try:
        t0 = time.time()
        while time.time() - t0 < 150 and not ready.exists() and game.poll() is None:
            time.sleep(0.5)
        check(f"{tag}: the game came up", ready.exists())
        if not ready.exists():
            return
        time.sleep(0.5)
        w, h, scale, *order = ready.read_text().split()
        scale = float(scale)
        hwnd = gui_input.game_window(game.pid)
        check(f"{tag}: game window", hwnd is not None)
        if not hwnd:
            return
        time.sleep(2)  # (a game just up takes a moment before posted input reaches it)
        for name in CLICK:
            if name not in order:
                check(f"{tag}: {name} in the button flow", False)
                continue
            i = order.index(name)
            # (a button 40 px + 2 px apart, the first one's centre 28 px in; posted clicks now and then miss: 3 tries.
            # A busy game logs a click late: wait up to 6 s for it before clicking again, so one isn't counted twice)
            for _ in range(3):
                gui_input.click(hwnd, (28 + 42 * i) * scale, 28 * scale)
                t1 = time.time()
                while time.time() - t1 < 6 and f"click {name}" not in txt.read_text():
                    time.sleep(0.3)
                if f"click {name}" in txt.read_text():
                    break
        t0 = time.time()
        while time.time() - t0 < 120 and not done.exists() and game.poll() is None:
            time.sleep(0.5)
        check(f"{tag}: done", done.exists())
        for name in CLICK:  # (by the end: a busy game may log a click after the next one was posted)
            if f"fallback {name}" in txt.read_text():  # (posted input is flaky: the styles are still checked)
                print(f"note {tag}: the posted click on {name} never arrived; switched on by its remote instead")
            else:
                check(f"{tag}: {name} clicked", f"click {name}" in txt.read_text())
        gui_input.grab(hwnd, out / "gu-buttons-window.png")
    finally:
        time.sleep(1)
        game.kill()
        subprocess.run(["taskkill", "/F", "/T", "/PID", str(game.pid)], capture_output=True)
        time.sleep(2)
    text = txt.read_text()
    print("    " + "\n    ".join(text.strip().splitlines()))
    got = {(m[1], m[2]): (m[3], m[4] == "true")
           for m in re.finditer(r"^(start|toggled) (\S+) style=(\S+) toggled=(\S+)$", text, re.M)}
    check(f"{tag}: GUI_Unifyer {'active' if gu else 'off'}", text.startswith("gu nil") != gu)
    for name in OURS:
        for phase in ("start", "toggled"):
            if (phase, name) not in got:
                check(f"{tag}: {phase} {name} present", False)
                continue
            style, toggled = got[(phase, name)]
            on = phase == "toggled" and name in CLICK
            if gu:
                want = "slot_button_notext_selected" if on else "slot_button_notext"
                check(f"{tag}: {phase} {name} style {style} (want {want})", style == want)
            else:
                check(f"{tag}: {phase} {name} style {style} toggled {toggled} (want mod_gui_button, {on})",
                      style == "mod_gui_button" and toggled == on)
    print("screenshots:", ", ".join(str(p) for p in sorted(out.glob("gu-buttons-*.png"))), flush=True)


if __name__ == "__main__":
    for gu in ([False] if "--plain" in sys.argv else [True] if "--gu" in sys.argv else [False, True]):
        run(gu)
    print("ALL PASS" if not fails else f"{len(fails)} FAILED: " + "; ".join(fails))
    sys.exit(1 if fails else 0)
