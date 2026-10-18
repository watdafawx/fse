// remote_hello.py without the SDK: the remote-mod protocol is plain HTTP + JSON (Node 18+, no packages).
//
//   node fse/examples/remote_hello.mjs
//
// Token: FSE_WEB_TOKEN, else web-token.txt in FSE_HOME or fse's dist folder. Port: FSE_WEB_URL, else 18790.
import { readFileSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const home = process.env.FSE_HOME ?? join(dirname(fileURLToPath(import.meta.url)), "..", "dist");
const token = process.env.FSE_WEB_TOKEN ?? readFileSync(join(home, "web-token.txt"), "utf8").trim();
const base = process.env.FSE_WEB_URL ?? "http://127.0.0.1:18790";
const headers = { Authorization: `Bearer ${token}` };

// remote.call(iface, fn, ...args) on the game thread
async function call(iface, fn, ...args) {
  const res = await fetch(`${base}/api/game`, {
    method: "POST", headers, body: JSON.stringify({ interface: iface, function: fn, args }),
  });
  const ans = await res.json();
  if (!ans.ok) throw new Error(ans.error);
  return ans.result;
}

await call("$game", "subscribe", "on_research_finished");
await call("$game", "print", "remote-hello (node) is listening");
let since; // (none at first: only what comes next)
for (;;) {
  const q = new URLSearchParams({ client: "remote-hello-node", names: "game/", wait: "20000" });
  if (since !== undefined) q.set("since", since);
  const ans = await (await fetch(`${base}/api/events?${q}`, { headers })).json();
  since = ans.next;
  for (const ev of ans.events) {
    if (ev.name === "game/on_research_finished") {
      await call("$game", "print", `${ev.data.research.name} done - heard by node`);
    }
  }
}
