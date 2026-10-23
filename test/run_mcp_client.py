"""mcp_game.py's client tools end to end over stdio: a probe mod (made here, under test/run) with a button and a text
field on the screen; start with a client, a shot (an image), the button clicked through the window (on_gui_click
counted), text typed into the field, E opening the inventory, reload with the client back. Opens a game window
(posted input only): close your own Factorio first."""
import base64
import json
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
PROBE = HERE / "run" / "mcp-client-probe"
PROBE.mkdir(parents=True, exist_ok=True)
(PROBE / "info.json").write_text(json.dumps({"name": "mcp-client-probe", "version": "0.1.0", "title": "mcp probe",
                                             "author": "fse", "factorio_version": "2.1", "dependencies": ["base"]}))
(PROBE / "control.lua").write_text("""
script.on_event(defines.events.on_player_joined_game, function(e)
  local s = game.get_player(e.player_index).gui.screen
  if s.mcp_btn then return end
  local b = s.add{type = "button", name = "mcp_btn", caption = "probe"}
  b.location = {200, 200}
  b.style.width, b.style.height = 160, 60
  local t = s.add{type = "textfield", name = "mcp_text"}
  t.location = {200, 320}
  t.style.width = 200
end)
script.on_event(defines.events.on_gui_click, function(e)
  if e.element.name == "mcp_btn" then storage.clicks = (storage.clicks or 0) + 1 end
end)
""")

srv = subprocess.Popen([sys.executable, str(HERE / "mcp_game.py")], stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                       text=True, encoding="utf-8")
ids = iter(range(1, 1000))
failed = []


def rpc(method, params=None):
    srv.stdin.write(json.dumps({"jsonrpc": "2.0", "id": next(ids), "method": method, "params": params or {}}) + "\n")
    srv.stdin.flush()
    return json.loads(srv.stdout.readline())


def tool(tool_name, **args):
    r = rpc("tools/call", {"name": tool_name, "arguments": args})["result"]
    return r["content"], r["isError"]


def text_of(content):
    return " | ".join(c["text"] for c in content if c["type"] == "text")


def lua(code):
    return text_of(tool("lua", mod="mcp-client-probe", code=code)[0])


def check(name, ok, got):
    print(("PASS " if ok else "FAIL ") + name + " :: " + str(got).replace("\n", " | ")[:300], flush=True)
    if not ok:
        failed.append(name)


def at_button():
    """the button's middle in window pixels: its location times the GUI scale, plus half its size"""
    sc = float(lua("return game.get_player(1).display_scale"))
    return int((200 + 80) * sc), int((200 + 30) * sc)


rpc("initialize", {"protocolVersion": "2025-06-18", "capabilities": {}, "clientInfo": {"name": "t"}})
try:
    content, err = tool("start", mod=str(PROBE), base=["base"], client=True)
    check("started with a client", not err and "client joined" in text_of(content), text_of(content))
    if err:
        sys.exit(1)
    content, err = tool("shot", width=0)  # (full size: click coordinates are window pixels)
    img = [c for c in content if c["type"] == "image"]
    check("shot is an image", not err and img and len(base64.b64decode(img[0]["data"])) > 10000, text_of(content))
    x, y = at_button()
    content, err = tool("click", x=x, y=y, shot=False)
    check("click answered", not err, text_of(content))
    check("the click reached on_gui_click", lua("return storage.clicks") == "1", lua("return storage.clicks"))
    lua("game.get_player(1).gui.screen.mcp_text.focus()")
    tool("type", text="abc", shot=False)
    got = lua("return game.get_player(1).gui.screen.mcp_text.text")
    check("typed into the field", got == "abc", got)
    lua("game.get_player(1).gui.screen.mcp_text.destroy()")  # (a focused field would take the E as typing)
    content, err = tool("key", key="e")
    got = lua("local p = game.get_player(1) return p.opened_self")
    check("E opens the inventory (with a shot)", got == "true" and any(c["type"] == "image" for c in content), got)
    tool("key", key="escape", shot=False)
    content, err = tool("ticks", n=120)
    check("ticks with a client", not err and "errors" not in text_of(content), text_of(content))
    content, err = tool("reload")
    check("reload brings the client back", not err and "client joined" not in text_of(content)
          and lua("return #game.connected_players") == "1", text_of(content))
    tool("shot", width=0)  # (the last shot was scaled down: clicks are in its pixels)
    x, y = at_button()
    content, _ = tool("click", x=x, y=y)
    check("a click after reload", lua("return storage.clicks") == "2", lua("return storage.clicks") + " " + text_of(content))
finally:
    print(text_of(tool("stop")[0]))
    srv.stdin.close()
    srv.wait(30)
print("ALL PASS" if not failed else "FAILED: " + ", ".join(failed))
sys.exit(1 if failed else 0)
