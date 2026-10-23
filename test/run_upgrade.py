"""fse-std upgraded under an existing save, in a real client: a save made with fse-std from before themes (git
commit OLD) is loaded with the current one; the existing player must get the themes (probe, theme window).
Exit code 1 when a check failed. Don't run it while you play."""
import io, json, shutil, subprocess, sys, tarfile, time
from pathlib import Path

OLD = "08f25ff"  # (the last commit before themes: fse-std 0.3.1)
NATIVE = Path(__file__).resolve().parents[1]
REPO = NATIVE.parent
from factorio_paths import run_dir, watch_game  # noqa: E402
RUN = run_dir(Path(__file__).resolve().parent / "run")
MODS = RUN / "upgrade-mods"
OUT = RUN / "script-output"


def mods(fse_std):
    shutil.rmtree(MODS, ignore_errors=True)
    MODS.mkdir(parents=True)
    fse_std(MODS / "fse-std")
    shutil.copytree(NATIVE / "test" / "upgrade-test", MODS / "upgrade-test")
    (MODS / "upgrade-test" / "info.json").write_text(json.dumps({"name": "upgrade-test", "version": "0.0.1",
        "title": "upgrade test", "author": "mtopfox", "factorio_version": "2.1", "dependencies": ["base", "fse-std"]}))
    names = ["base", "fse-std", "upgrade-test"]
    (MODS / "mod-list.json").write_text(json.dumps({"mods": [{"name": n, "enabled": n in names} for n in
                                                             names + ["elevated-rails", "quality", "space-age"]]}))


def old_fse_std(dest):
    tar = subprocess.run(["git", "-C", str(REPO), "archive", OLD, "fse/mods/fse-std"], capture_output=True, check=True).stdout
    with tarfile.open(fileobj=io.BytesIO(tar)) as t:
        for m in t.getmembers():
            if m.isfile():
                rel = Path(m.name).relative_to("fse/mods/fse-std")
                (dest / rel).parent.mkdir(parents=True, exist_ok=True)
                (dest / rel).write_bytes(t.extractfile(m).read())


def run(args, done, secs=180):
    launch = [str(NATIVE / "dist" / "fse-launcher.exe"), "--config", str(RUN / "config.ini"), "--mod-directory", str(MODS)]
    game = watch_game(launch + args)
    end = time.time() + secs
    while time.time() < end and not (OUT / done).exists() and game.poll() is None:
        time.sleep(1)
    time.sleep(2)
    game.kill()
    log = (RUN / "factorio-current.log").read_text(errors="replace").splitlines()
    return [l for l in log if "Error" in l or "error (handled)" in l]


for f in OUT.glob("upgrade-*"):
    f.unlink()
save = RUN / "upgrade.zip"
save.unlink(missing_ok=True)
(RUN / "saves" / "_autosave-upgrade.zip").unlink(missing_ok=True)
mods(old_fse_std)
launch = [str(NATIVE / "dist" / "fse-launcher.exe"), "--config", str(RUN / "config.ini"), "--mod-directory", str(MODS)]
subprocess.run(launch + ["--create", str(save)], capture_output=True)
errors = run(["--load-game", str(save)], "upgrade-done1.txt")
for f in OUT.glob("upgrade-*"):  # (phase 1 ran on after its save: nothing of it counts)
    f.unlink()
mods(lambda dest: shutil.copytree(NATIVE / "mods" / "fse-std", dest))
errors += run(["--load-game", str(RUN / "saves" / "_autosave-upgrade.zip")], "upgrade-done2.txt")
print("errors:", "\n".join(errors)[-1500:] or "none")
res = OUT / "upgrade-result.json"
if not res.exists():
    print("no result")
    sys.exit(1)
checks = json.loads(res.read_text())
for c in checks:
    print("ok  " if c["ok"] else "FAIL", c["name"], "" if c["ok"] else c.get("detail", ""))
sys.exit(1 if errors or any(not c["ok"] for c in checks) else 0)
