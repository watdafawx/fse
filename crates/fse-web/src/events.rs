//! Remote mods: events the game pushes out for programs outside the game.
//!
//! Lua: native.call("web", "emit", '{"name": "srq/need_pick", "data": {...}}') puts an event in a ring (the last
//! 4096). A program long-polls GET /api/events?client=<name>&names=<prefix,...>&since=<seq>&wait=<ms> and gets
//! {"events": [{seq, name, data}], "next": seq, "lost": bool}; it passes `next` as `since` the next time.
//! Without `since` it gets only what comes after its call. A client is "connected" while it polls and for 3 s after
//! (web.clients -> ["srq-planner", ...]), so a mod can tell whether its remote half is there.

use std::collections::{HashMap, VecDeque};
use std::sync::{Condvar, Mutex};
use std::time::{Duration, Instant};

use serde_json::{json, Value};

const KEEP: usize = 4096;
const LINGER: Duration = Duration::from_secs(3);

struct Ring {
    seq: u64,
    list: VecDeque<(u64, Value)>,
}

struct Client {
    polling: u32,
    last: Instant,
}

static RING: Mutex<Ring> = Mutex::new(Ring { seq: 0, list: VecDeque::new() });
static NEW: Condvar = Condvar::new();
static CLIENTS: Mutex<Option<HashMap<String, Client>>> = Mutex::new(None);

/// web.emit {"name": "...", "data": ...} -> its seq
pub fn emit(input: &str) -> Result<String, String> {
    let v: Value = serde_json::from_str(input).map_err(|e| format!("emit: {e}"))?;
    let name = v.get("name").and_then(Value::as_str).ok_or("emit: no name")?.to_string();
    let data = v.get("data").cloned().unwrap_or(Value::Null);
    let mut r = RING.lock().unwrap();
    r.seq += 1;
    let seq = r.seq;
    r.list.push_back((seq, json!({"seq": seq, "name": name, "data": data})));
    while r.list.len() > KEEP {
        r.list.pop_front();
    }
    drop(r);
    NEW.notify_all();
    Ok(seq.to_string())
}

fn mark(client: &str, start: bool) {
    let mut c = CLIENTS.lock().unwrap();
    let e = c.get_or_insert_with(HashMap::new).entry(client.to_string())
        .or_insert(Client { polling: 0, last: Instant::now() });
    if start {
        e.polling += 1;
    } else {
        e.polling = e.polling.saturating_sub(1);
    }
    e.last = Instant::now();
}

/// web.clients -> the programs polling now (or in the last 3 s), as a JSON array of names
pub fn clients() -> String {
    let mut c = CLIENTS.lock().unwrap();
    let map = c.get_or_insert_with(HashMap::new);
    map.retain(|_, e| e.polling > 0 || e.last.elapsed() < LINGER);
    let mut names: Vec<&String> = map.keys().collect();
    names.sort();
    json!(names).to_string()
}

/// GET /api/events: what came after `since` (names starting with one of `names`), waiting up to `wait` for some
pub fn poll(client: Option<&str>, names: &[String], since: Option<u64>, wait: Duration) -> Value {
    if let Some(c) = client {
        mark(c, true);
    }
    let deadline = Instant::now() + wait;
    let mut r = RING.lock().unwrap();
    // (a game restarted under fse-hotreload starts counting again: a `since` from before it means from the start)
    let since = match since {
        Some(s) if s <= r.seq => s,
        Some(_) => 0,
        None => r.seq,
    };
    let answer = loop {
        let out: Vec<Value> = r.list.iter()
            .filter(|(s, e)| *s > since && (names.is_empty() || {
                let n = e["name"].as_str().unwrap_or("");
                names.iter().any(|p| n.starts_with(p.as_str()))
            }))
            .map(|(_, e)| e.clone())
            .collect();
        let now = Instant::now();
        if !out.is_empty() || now >= deadline {
            let lost = r.list.front().map(|(s, _)| *s > since + 1).unwrap_or(false);
            break json!({"events": out, "next": r.seq, "lost": lost});
        }
        r = NEW.wait_timeout(r, deadline - now).unwrap().0;
    };
    drop(r);
    if let Some(c) = client {
        mark(c, false);
    }
    answer
}
