"""The smallest remote mod: hears finished research from outside the game and answers in chat.

    python fse/examples/remote_hello.py      (save this file while it runs: it restarts, the game keeps going)

Needs the game started through fse (dist/fse-launcher.exe or FSE installed) with the fse-bridge mod, singleplayer.
The same in plain HTTP, no SDK: remote_hello.mjs.
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "py"))  # (fse_remote.py; installed: <game>/fse/py)
from fse_remote import Remote  # noqa: E402

r = Remote("remote-hello")


@r.on_connect
def hello():
    r.subscribe("on_research_finished")  # kept in the save: sent out as "game/on_research_finished"
    r.call("$game", "print", "remote-hello is listening")


@r.on("game/on_research_finished")
def finished(ev):
    tech = ev["data"]["research"]["name"]
    r.call("$game", "print", f"{tech} done - heard outside the game")


r.run(watch=True)
