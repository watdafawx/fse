"""Syntax-check our Lua with a real Lua 5.2 (Factorio's version), compiled only, nothing run.
  python fse/test/lua_check.py [PATH ...]     (from anywhere; default: every .lua git knows of in this repo)
Files: git ls-files (tracked + new, not ignored) under the repo, without patches/ (third-party mods), test/run
folders and .claude/worktrees. PATHs: files or folders to check instead.
Needs lupa (it bundles Lua 5.1-5.5): `uv pip install --system lupa`. Exit 1 when a file doesn't compile."""
import subprocess
import sys
from pathlib import Path

try:
    from lupa import lua52
except ImportError:
    sys.exit("lua_check: needs lupa (bundles Lua 5.2):  uv pip install --system lupa")

ROOT = Path(__file__).resolve().parents[2]
SKIP = ("patches/", ".claude/worktrees/")


def files(args):
    if args:
        out = []
        for a in map(Path, args):
            out += sorted(a.rglob("*.lua")) if a.is_dir() else [a]
        return [f for f in out if "/test/run/" not in f.resolve().as_posix()]
    ls = subprocess.run(["git", "ls-files", "--cached", "--others", "--exclude-standard", "-z", "--", "*.lua"],
                        cwd=ROOT, capture_output=True, check=True).stdout.decode("utf-8").split("\0")
    return [ROOT / f for f in sorted(set(ls)) if f and not f.startswith(SKIP) and "/test/run/" not in "/" + f
            and (ROOT / f).exists()]


def main():
    lua = lua52.LuaRuntime()
    compile_ = lua.eval("function(src, name) local f, err = load(src, name, 't') return err end")
    checked, bad = 0, []
    for f in files(sys.argv[1:]):
        src = f.read_bytes()
        if src.startswith(b"\xef\xbb\xbf"):
            src = src[3:]  # (a UTF-8 BOM: the game reads past it)
        try:
            name = f.resolve().relative_to(ROOT).as_posix()
        except ValueError:
            name = str(f)
        err = compile_(src, "@" + name)
        checked += 1
        if err is not None:
            bad.append(err.decode("utf-8", "replace") if isinstance(err, bytes) else str(err))
    for b in bad:
        print("FAIL", b)
    print(f"{checked - len(bad)}/{checked} Lua files compile" + (f", {len(bad)} don't" if bad else ""))
    sys.exit(1 if bad else 0)


if __name__ == "__main__":
    main()
