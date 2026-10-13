//! Shells: a mod's window as a web page over the game, with holes ("engine islands") where the game's own GUI shows
//! through. A shell is a borderless popup owned by the game window (so it stays above it and goes with it) holding a
//! WebView2 view; its window region is its rectangle (or the page's solid parts) minus the islands' rectangles, so
//! the game is seen, and clicked, through every hole. The mod puts a bare screen frame of engine widgets (a camera,
//! slots, choose-elem buttons) exactly under each hole (fse-std's shell.lua).
//!
//! Any number of shells, keyed "<owner mod>/<name>". They live on the overlay thread (it pumps their messages and the
//! WebView2 callbacks); every function below only queues a command for it and wakes it, so any thread may call.
//!
//! Lua (game thread, fse-std/shell.lua) -> native, all JSON:
//!   web.shell_open   {owner, name, page, rect: [x, y, w, h] (game client px), scale, gu, esc, radius, theme, bg,
//!                    visible}  (scale: CSS px -> screen px; gu: one game GUI unit in CSS px)
//!   web.shell_set    {owner, name, rect?, visible?, scale?, radius?}
//!   web.shell_send   {owner, name, env: {t: "msg", data} | {t: "theme", theme} | ...}  (to the page, in order)
//!   web.shell_close  {owner, name}
//!   web.shell_take   {owner} -> [{type: "ready" | "layout" | "message" | "closed" | "visible", shell, ...}]
//!   web.shell_status -> every shell's window, region, holes, keyboard owner, page; the islands' lag (tests, dev)
//!   web.shell_eval   {owner, name, js} (tests, dev)
//! Page -> native (window.ipc.postMessage, shell.js): hello, layout {islands, solid}, msg {data}, esc, close,
//! set {visible}, focus {web}, drag {phase, mode, dx, dy}, log {text}.
//!
//! Keyboard: the game keeps it. A shell never activates on a click (WS_EX_NOACTIVATE, MA_NOACTIVATE); only when the
//! page focuses a text field (focus {web: true}) does the shell become the foreground window, and it hands the
//! keyboard back to the game when the field loses focus, on Esc, or when it hides.
//! Pages come from the web plugin's server: "shell/demo.html" (fse's web folder) or "__mod__/path.html" (an unzipped
//! mod in the mods folder, served at /mod/<mod>/path.html). The page's folder is watched: a saved file reloads it
//! (FSE_SHELL_LIVE=0: off), and the page says hello again (the mod hears "ready" and sends its state again).

use std::cell::RefCell;
use std::collections::{BTreeMap, HashMap};
use std::num::NonZeroIsize;
use std::path::PathBuf;
use std::sync::atomic::{AtomicU32, AtomicUsize, Ordering};
use std::sync::Mutex;
use std::time::{Instant, SystemTime};

use raw_window_handle::{HandleError, HasWindowHandle, RawWindowHandle, Win32WindowHandle, WindowHandle};
use serde_json::{json, Value};
use windows_sys::Win32::Foundation::{HWND, LPARAM, LRESULT, POINT, RECT, WPARAM};
use windows_sys::Win32::Graphics::Gdi::{
    ClientToScreen, CombineRgn, CreateRectRgn, CreateRoundRectRgn, CreateSolidBrush, DeleteObject, GetRegionData,
    GetWindowRgn, PtInRegion, SetWindowRgn, HRGN, RGNDATAHEADER, RGN_DIFF, RGN_OR,
};
use windows_sys::Win32::System::LibraryLoader::GetModuleHandleW;
use windows_sys::Win32::System::Threading::GetCurrentThreadId;
use windows_sys::Win32::UI::HiDpi::GetDpiForWindow;
use windows_sys::Win32::UI::WindowsAndMessaging::{
    CreateWindowExW, DefWindowProcW, DestroyWindow, EnumChildWindows, GetClassNameW, GetClientRect,
    GetForegroundWindow, GetGUIThreadInfo, GetWindowRect, IsIconic, IsWindow, IsWindowVisible, LoadCursorW,
    PostMessageW, RegisterClassW, SetForegroundWindow, SetTimer, SetWindowLongPtrW, SetWindowPos, ShowWindow,
    WindowFromPoint, GUITHREADINFO, GWLP_HWNDPARENT, HWND_MESSAGE, IDC_ARROW, MA_ACTIVATE, MA_NOACTIVATE,
    SWP_NOACTIVATE, SWP_NOMOVE, SWP_NOZORDER, SWP_SHOWWINDOW, SW_HIDE, WA_INACTIVE, WM_ACTIVATE, WM_APP, WM_CLOSE,
    WM_MOUSEACTIVATE, WM_TIMER, WNDCLASSW, WS_CLIPCHILDREN, WS_EX_NOACTIVATE, WS_EX_TOOLWINDOW, WS_POPUP,
};
use wry::WebViewBuilderExtWindows;

use crate::overlay::wide;

const WM_CMD: u32 = WM_APP + 20;
const FOLLOW: usize = 1; // (timer: follow the game window, ~60 per s)
const LIVE: usize = 2; // (timer: the pages' files, twice a second)
const SHOW_ANYWAY_MS: u128 = 2500; // (a page that never lays out is shown after this)

static HOST: AtomicUsize = AtomicUsize::new(0);
static HOST_THREAD: AtomicU32 = AtomicU32::new(0);
static GAME: AtomicUsize = AtomicUsize::new(0);
static CMDS: Mutex<Vec<Value>> = Mutex::new(Vec::new());
static EVENTS: Mutex<Vec<Event>> = Mutex::new(Vec::new());
static SHELLS: Mutex<BTreeMap<String, Shell>> = Mutex::new(BTreeMap::new());
static LAG: Mutex<Lag> = Mutex::new(Lag { n: 0, sum_ms: 0.0, max_ms: 0.0, last_ms: 0.0 });
static BASE: Mutex<String> = Mutex::new(String::new());

thread_local! {
    static VIEWS: RefCell<HashMap<String, wry::WebView>> = RefCell::new(HashMap::new());
    static CONTEXT: RefCell<Option<wry::WebContext>> = const { RefCell::new(None) };
    static BUSY: std::cell::Cell<bool> = const { std::cell::Cell::new(false) };
    static FOLLOWED: RefCell<(usize, [i32; 4], bool, u32, u32)> = const { RefCell::new((0, [0; 4], false, 0, 0)) };
}

struct Event {
    owner: String,
    at: Instant,
    layout: bool,
    v: Value,
}

struct Lag {
    n: u64,
    sum_ms: f64,
    max_ms: f64,
    last_ms: f64,
}

#[derive(Default, Clone)]
struct Shell {
    owner: String,
    name: String,
    hwnd: usize,
    want_visible: bool, // (what Lua or the page asked)
    ready: bool,        // (the page said hello)
    laid_out: bool,     // (its first layout came: shown from then on, so it never flashes empty)
    rect: [i32; 4],     // (game client px)
    scale: f64,
    zoom: f64,
    radius: i32,
    esc: bool,
    holes: BTreeMap<String, [i32; 4]>, // (shell client px)
    solid: Option<Vec<[i32; 5]>>,
    keyboard_web: bool,
    url: String,
    watch: Option<PathBuf>,
    stamp: Option<SystemTime>,
    outbox: Vec<String>,
    drag_start: Option<[i32; 4]>,
    opened: Option<Instant>,
    bg: (u8, u8, u8),
    init: String,
    reloads: u32,
    to_page: u64,
    from_page: u64,
}

struct Parent(HWND);

impl HasWindowHandle for Parent {
    fn window_handle(&self) -> Result<WindowHandle<'_>, HandleError> {
        let h = NonZeroIsize::new(self.0 as isize).ok_or(HandleError::Unavailable)?;
        Ok(unsafe { WindowHandle::borrow_raw(RawWindowHandle::Win32(Win32WindowHandle::new(h))) })
    }
}

/// the web plugin's address, "http://127.0.0.1:8790" (from its ".../?token=..." url)
pub fn set_base(url: &str) {
    *BASE.lock().unwrap() = url.split("/?").next().unwrap_or(url).trim_end_matches('/').to_string();
}

/// an unzipped mod's folder in the mods folder: "<name>" or "<name>_<version>" (FSE_MODS, set by the core); else one
/// of the game's own (base, core, space-age, quality, elevated-rails) in its data folder, so a page can show the game's
/// icons (/mod/base/graphics/icons/iron-plate.png)
pub fn mod_dir(name: &str) -> Option<PathBuf> {
    let game = || -> Option<PathBuf> {
        let exe = std::env::current_exe().ok()?;  // (<game>/bin/x64/factorio.exe)
        let d = exe.parent()?.parent()?.parent()?.join("data").join(name);
        (!name.is_empty() && !name.contains(['/', '\\', '.']) && d.is_dir()).then_some(d)
    };
    let Some(mods) = std::env::var("FSE_MODS").ok().map(PathBuf::from) else { return game() };
    let exact = mods.join(name);
    if exact.is_dir() {
        return Some(exact);
    }
    let prefix = format!("{name}_");
    let Ok(dir) = std::fs::read_dir(&mods) else { return game() };
    let mut found: Vec<PathBuf> = dir.flatten()
        .filter(|e| e.file_name().to_string_lossy().starts_with(&prefix) && e.path().is_dir())
        .map(|e| e.path()).collect();
    found.sort();
    found.pop().or_else(game)
}

/// a file of a zipped mod in the mods folder ("<name>_<version>.zip", the newest; its files under one top folder):
/// for a page's images (a mod's icons), as a page of an unzipped mod is served
pub fn mod_zip_file(name: &str, path: &str) -> Option<Vec<u8>> {
    let mods = PathBuf::from(std::env::var("FSE_MODS").ok()?);
    let prefix = format!("{name}_");
    let mut zips: Vec<PathBuf> = std::fs::read_dir(&mods).ok()?.flatten()
        .filter(|e| { let n = e.file_name().to_string_lossy().to_string(); n.starts_with(&prefix) && n.ends_with(".zip") })
        .map(|e| e.path()).collect();
    zips.sort();
    let mut z = zip::ZipArchive::new(std::fs::File::open(zips.pop()?).ok()?).ok()?;
    let root = z.file_names().find_map(|n| n.split_once('/').map(|(r, _)| r.to_string()))?;
    let mut f = z.by_name(&format!("{root}/{path}")).ok()?;
    let mut out = Vec::with_capacity(f.size() as usize);
    std::io::Read::read_to_end(&mut f, &mut out).ok()?;
    Some(out)
}

/// a page -> (its url, the file on disk)
fn resolve(page: &str) -> Result<(String, Option<PathBuf>), String> {
    if page.contains("..") || page.contains(':') {
        return Err(format!("shell page {page}: a path under fse's web folder or \"__mod__/path\""));
    }
    let base = BASE.lock().unwrap().clone();
    if let Some(rest) = page.strip_prefix("__") {
        let (m, path) = rest.split_once("__/").ok_or(format!("shell page {page}: \"__mod__/path\""))?;
        let file = mod_dir(m).map(|d| d.join(path));
        return Ok((format!("{base}/mod/{m}/{path}"), file));
    }
    let page = page.trim_start_matches('/');
    Ok((format!("{base}/{page}"), Some(crate::home().join("web").join(page))))
}

fn key_of(v: &Value) -> Result<String, String> {
    let owner = v.get("owner").and_then(Value::as_str).ok_or("shell: no owner")?;
    let name = v.get("name").and_then(Value::as_str).ok_or("shell: no name")?;
    Ok(format!("{owner}/{name}"))
}

fn rect_of(v: &Value) -> Option<[i32; 4]> {
    let a = v.as_array()?;
    if a.len() != 4 {
        return None;
    }
    let n = |i: usize| a[i].as_f64().map(|f| f.round() as i32);
    Some([n(0)?, n(1)?, n(2)?.max(1), n(3)?.max(1)])
}

fn command(cmd: Value) {
    CMDS.lock().unwrap().push(cmd);
    let host = HOST.load(Ordering::Relaxed);
    if host != 0 {
        unsafe { PostMessageW(host as HWND, WM_CMD, 0, 0) };
    }
}

fn push(owner: &str, layout: bool, v: Value) {
    EVENTS.lock().unwrap().push(Event { owner: owner.to_string(), at: Instant::now(), layout, v });
}

// ---- the functions (any thread) ---------------------------------------------------------------------------------

pub fn open(input: &str) -> Result<String, String> {
    let v: Value = serde_json::from_str(input).map_err(|e| format!("shell_open: {e}"))?;
    let key = key_of(&v)?;
    let page = v.get("page").and_then(Value::as_str).ok_or("shell_open: no page")?;
    let (url, file) = resolve(page)?;
    let rect = v.get("rect").and_then(rect_of).ok_or("shell_open: rect [x, y, w, h] in pixels")?;
    let mut shells = SHELLS.lock().unwrap();
    let s = shells.entry(key.clone()).or_default();
    let (owner, name) = key.split_once('/').unwrap();
    s.owner = owner.into();
    s.name = name.into();
    s.rect = rect;
    s.scale = v.get("scale").and_then(Value::as_f64).unwrap_or(1.0).clamp(0.25, 8.0);
    s.esc = v.get("esc").and_then(Value::as_bool).unwrap_or(true);
    s.radius = v.get("radius").and_then(Value::as_i64).unwrap_or(0) as i32;
    s.want_visible = v.get("visible").and_then(Value::as_bool).unwrap_or(true);
    if let Some(bg) = v.get("bg").and_then(Value::as_array) {
        let c = |i: usize| bg.get(i).and_then(Value::as_f64).map(|f| (f.clamp(0.0, 1.0) * 255.0) as u8).unwrap_or(0x24);
        s.bg = (c(0), c(1), c(2));
    } else {
        s.bg = (0x24, 0x24, 0x24);
    }
    s.init = json!({"name": name, "owner": owner, "scale": s.scale, "esc": s.esc,
                    "gu": v.get("gu").and_then(Value::as_f64).unwrap_or(1.0),
                    "theme": v.get("theme").cloned().unwrap_or(Value::Null)}).to_string();
    if s.url != url {
        s.url = url;
        s.ready = false;
        s.laid_out = false;
        s.opened = Some(Instant::now());
    }
    s.watch = file.and_then(|f| f.parent().map(|p| p.to_path_buf()));
    drop(shells);
    command(json!({"op": "open", "key": key}));
    Ok("ok".into())
}

pub fn set(input: &str) -> Result<String, String> {
    let v: Value = serde_json::from_str(input).map_err(|e| format!("shell_set: {e}"))?;
    let key = key_of(&v)?;
    let mut shells = SHELLS.lock().unwrap();
    let s = shells.get_mut(&key).ok_or(format!("shell_set: no shell {key}"))?;
    if let Some(r) = v.get("rect").and_then(rect_of) {
        s.rect = r;
    }
    if let Some(b) = v.get("visible").and_then(Value::as_bool) {
        s.want_visible = b;
    }
    if let Some(f) = v.get("scale").and_then(Value::as_f64) {
        s.scale = f.clamp(0.25, 8.0);
    }
    if let Some(r) = v.get("radius").and_then(Value::as_i64) {
        s.radius = r as i32;
    }
    drop(shells);
    command(json!({"op": "sync", "key": key}));
    Ok("ok".into())
}

pub fn send(input: &str) -> Result<String, String> {
    let v: Value = serde_json::from_str(input).map_err(|e| format!("shell_send: {e}"))?;
    let key = key_of(&v)?;
    let env = v.get("env").ok_or("shell_send: no env")?.to_string();
    let mut shells = SHELLS.lock().unwrap();
    let s = shells.get_mut(&key).ok_or(format!("shell_send: no shell {key}"))?;
    s.outbox.push(env);
    drop(shells);
    command(json!({"op": "flush", "key": key}));
    Ok("ok".into())
}

pub fn close(input: &str) -> Result<String, String> {
    let v: Value = serde_json::from_str(input).map_err(|e| format!("shell_close: {e}"))?;
    let key = key_of(&v)?;
    if let Some(s) = SHELLS.lock().unwrap().get_mut(&key) {
        s.want_visible = false;
    }
    command(json!({"op": "close", "key": key}));
    Ok("ok".into())
}

pub fn eval(input: &str) -> Result<String, String> {
    let v: Value = serde_json::from_str(input).map_err(|e| format!("shell_eval: {e}"))?;
    let key = key_of(&v)?;
    let js = v.get("js").and_then(Value::as_str).ok_or("shell_eval: no js")?;
    command(json!({"op": "eval", "key": key, "js": js}));
    Ok("ok".into())
}

/// the events for one owner mod's shells (the game thread, every tick while it has shells)
pub fn take(input: &str) -> Result<String, String> {
    let v: Value = serde_json::from_str(input).unwrap_or(Value::Null);
    let owner = v.get("owner").and_then(Value::as_str).unwrap_or(input);
    let mut events = EVENTS.lock().unwrap();
    if events.is_empty() {
        return Ok("[]".into());
    }
    let now = Instant::now();
    let mut out = Vec::new();
    let mut lag = LAG.lock().unwrap();
    events.retain(|e| {
        if e.owner != owner {
            return true;
        }
        if e.layout {
            let ms = (now - e.at).as_secs_f64() * 1000.0;
            lag.n += 1;
            lag.sum_ms += ms;
            lag.max_ms = lag.max_ms.max(ms);
            lag.last_ms = ms;
        }
        out.push(e.v.clone());
        false
    });
    Ok(Value::Array(out).to_string())
}

unsafe fn region_of(hwnd: HWND) -> (Vec<[i32; 4]>, HRGN) {
    let rgn = CreateRectRgn(0, 0, 0, 0);
    if GetWindowRgn(hwnd, rgn) == 0 {
        return (Vec::new(), rgn); // (no region: the whole window)
    }
    let size = GetRegionData(rgn, 0, std::ptr::null_mut());
    let mut buf = vec![0u8; size as usize];
    if size == 0 || GetRegionData(rgn, size, buf.as_mut_ptr() as *mut _) == 0 {
        return (Vec::new(), rgn);
    }
    let head = &*(buf.as_ptr() as *const RGNDATAHEADER);
    let rects = std::slice::from_raw_parts(buf.as_ptr().add(head.dwSize as usize) as *const RECT, head.nCount as usize);
    (rects.iter().map(|r| [r.left, r.top, r.right, r.bottom]).collect(), rgn)
}

/// the browser's own input window inside a shell (Chrome_RenderWidgetHostHWND), for tests that post a click to it
unsafe fn browser_window(hwnd: HWND) -> usize {
    unsafe extern "system" fn each(h: HWND, lp: LPARAM) -> i32 {
        let mut buf = [0u16; 64];
        let n = GetClassNameW(h, buf.as_mut_ptr(), 64);
        if String::from_utf16_lossy(&buf[..n.max(0) as usize]) == "Chrome_RenderWidgetHostHWND" {
            *(lp as *mut usize) = h as usize;
            return 0;
        }
        1
    }
    let mut found = 0usize;
    EnumChildWindows(hwnd, Some(each), &mut found as *mut usize as LPARAM);
    found
}

pub fn status() -> Result<String, String> {
    let game = GAME.load(Ordering::Relaxed) as HWND;
    let mut info: GUITHREADINFO = unsafe { std::mem::zeroed() };
    info.cbSize = std::mem::size_of::<GUITHREADINFO>() as u32;
    let thread = HOST_THREAD.load(Ordering::Relaxed);
    let active = if thread != 0 && unsafe { GetGUIThreadInfo(thread, &mut info) } != 0 { info.hwndActive as usize } else { 0 };
    let fg = unsafe { GetForegroundWindow() } as usize;
    let origin = unsafe { client_origin(game) };
    let mut out = serde_json::Map::new();
    // (a copy: no lock held while windows are asked about, and the overlay thread never waits on a status)
    let shells: Vec<(String, Shell)> = SHELLS.lock().unwrap().iter().map(|(k, s)| (k.clone(), s.clone())).collect();
    for (key, s) in &shells {
        let hwnd = s.hwnd as HWND;
        let mut wr: RECT = unsafe { std::mem::zeroed() };
        unsafe { GetWindowRect(hwnd, &mut wr) };
        let (region, rgn) = unsafe { region_of(hwnd) };
        let mut holes = serde_json::Map::new();
        for (id, h) in &s.holes {
            let (cx, cy) = (h[0] + h[2] / 2, h[1] + h[3] / 2);
            // (open: the shell's region leaves the hole's middle out; at: the window the screen shows there)
            let open = !region.is_empty() && unsafe { PtInRegion(rgn, cx, cy) } == 0;
            let at = unsafe { WindowFromPoint(POINT { x: wr.left + cx, y: wr.top + cy }) } as usize;
            holes.insert(id.clone(), json!({"rect": h, "game": [s.rect[0] + h[0], s.rect[1] + h[1], h[2], h[3]],
                                            "open": open, "window_there": at, "game_there": at == game as usize}));
        }
        unsafe { DeleteObject(rgn) };
        out.insert(key.clone(), json!({
            "owner": s.owner, "name": s.name, "hwnd": s.hwnd, "browser_hwnd": unsafe { browser_window(hwnd) },
            "visible": s.hwnd != 0 && unsafe { IsWindowVisible(hwnd) } != 0, "want_visible": s.want_visible,
            "ready": s.ready, "laid_out": s.laid_out, "rect": s.rect,
            "screen": [wr.left, wr.top, wr.right - wr.left, wr.bottom - wr.top],
            "placed_right": s.hwnd == 0 || (wr.left - origin.0 == s.rect[0] && wr.top - origin.1 == s.rect[1]),
            "scale": s.scale, "zoom": s.zoom, "dpi": if s.hwnd != 0 { unsafe { GetDpiForWindow(hwnd) } } else { 0 },
            "holes": holes, "region": region, "solid": s.solid,
            "keyboard": if s.keyboard_web { "web" } else { "game" },
            "active": s.hwnd != 0 && active == s.hwnd, "foreground": s.hwnd != 0 && fg == s.hwnd,
            "url": s.url, "reloads": s.reloads, "to_page": s.to_page, "from_page": s.from_page,
            "outbox": s.outbox.len(),
        }));
    }
    // (one lock at a time: take() holds EVENTS while it takes LAG, so holding LAG while taking EVENTS here could
    // deadlock the game thread against this one)
    let waiting = EVENTS.lock().unwrap().len();
    let (n, sum_ms, max_ms, last_ms) = {
        let lag = LAG.lock().unwrap();
        (lag.n, lag.sum_ms, lag.max_ms, lag.last_ms)
    };
    let avg = if n > 0 { sum_ms / n as f64 } else { 0.0 };
    Ok(json!({"host": HOST.load(Ordering::Relaxed) != 0, "game": game as usize, "game_origin": [origin.0, origin.1],
              "game_foreground": fg == game as usize, "host_active": active, "shells": out,
              "lag": {"n": n, "avg_ms": avg, "max_ms": max_ms, "last_ms": last_ms},
              "events_waiting": waiting}).to_string())
}

// ---- the overlay thread -----------------------------------------------------------------------------------------

unsafe fn client_origin(game: HWND) -> (i32, i32) {
    let mut p = POINT { x: 0, y: 0 };
    if !game.is_null() {
        ClientToScreen(game, &mut p);
    }
    (p.x, p.y)
}

/// (try_lock: a window message can come in while this thread holds the lock)
fn find(hwnd: HWND) -> Option<String> {
    SHELLS.try_lock().ok()?.iter().find(|(_, s)| s.hwnd == hwnd as usize).map(|(k, _)| k.clone())
}

fn with_view<R>(key: &str, f: impl FnOnce(&wry::WebView) -> R) -> Option<R> {
    VIEWS.with(|v| v.try_borrow().ok().and_then(|v| v.get(key).map(f)))
}

/// the layout as the mod sees it: the shell's rectangle and each island's, in game client pixels
fn layout_event(s: &Shell) -> Value {
    let mut islands = serde_json::Map::new();
    for (id, h) in &s.holes {
        islands.insert(id.clone(), json!([s.rect[0] + h[0], s.rect[1] + h[1], h[2], h[3]]));
    }
    json!({"type": "layout", "shell": s.name, "rect": s.rect, "islands": islands,
           "shown": s.want_visible && s.laid_out})
}

/// a shell's window region: its rectangle (or the page's solid parts) minus the islands. GDI only, no window
/// messages: built while SHELLS is held, given to the window (set_region) after it is let go
unsafe fn region(s: &Shell) -> HRGN {
    let (w, h) = (s.rect[2], s.rect[3]);
    let base = match &s.solid {
        Some(list) if !list.is_empty() => {
            let r = CreateRectRgn(0, 0, 0, 0);
            for p in list {
                let one = if p[4] > 0 { CreateRoundRectRgn(p[0], p[1], p[0] + p[2] + 1, p[1] + p[3] + 1, p[4] * 2, p[4] * 2) }
                          else { CreateRectRgn(p[0], p[1], p[0] + p[2], p[1] + p[3]) };
                CombineRgn(r, r, one, RGN_OR);
                DeleteObject(one);
            }
            r
        }
        _ if s.radius > 0 => CreateRoundRectRgn(0, 0, w + 1, h + 1, s.radius * 2, s.radius * 2),
        _ => CreateRectRgn(0, 0, w, h),
    };
    for hole in s.holes.values() {
        if hole[2] > 0 && hole[3] > 0 {
            let one = CreateRectRgn(hole[0], hole[1], hole[0] + hole[2], hole[1] + hole[3]);
            CombineRgn(base, base, one, RGN_DIFF);
            DeleteObject(one);
        }
    }
    base
}

/// gives a window its region (the system owns it then). SetWindowRgn sends the window (and the WebView's windows in
/// it) messages and repaints: never called with SHELLS held, so a thread waiting on that lock (the game's, in
/// shell_set / shell_send) never waits on this one's messages
unsafe fn set_region(hwnd: HWND, rgn: HRGN) {
    if hwnd.is_null() {
        DeleteObject(rgn);
        return;
    }
    SetWindowRgn(hwnd, rgn, 1);
}

/// puts a shell where it belongs over the game, shown or hidden (no lock held while windows get messages: a hidden
/// active window is sent WM_ACTIVATE at once, and shell_proc looks the shell up)
unsafe fn place(key: &str) {
    let game = GAME.load(Ordering::Relaxed) as HWND;
    let (hwnd, show, rect, zoom) = {
        let mut shells = SHELLS.lock().unwrap();
        let Some(s) = shells.get_mut(key) else { return };
        let hwnd = s.hwnd as HWND;
        if hwnd.is_null() {
            return;
        }
        let late = s.opened.map(|t| t.elapsed().as_millis() > SHOW_ANYWAY_MS).unwrap_or(true);
        let show = s.want_visible && (s.laid_out || late) && !game.is_null() && IsIconic(game) == 0
            && IsWindowVisible(game) != 0;
        if !show {
            s.keyboard_web = false;
        }
        // (zoom: the page's CSS pixel is one GUI unit at the shell's scale; WebView2 already draws at the monitor's DPI)
        let dpi = GetDpiForWindow(hwnd).max(96) as f64;
        let zoom = s.scale / (dpi / 96.0);
        let changed = (zoom - s.zoom).abs() > 1e-6;
        if changed {
            s.zoom = zoom;
        }
        (hwnd, show, s.rect, changed.then_some(zoom))
    };
    if show {
        let (ox, oy) = client_origin(game);
        SetWindowPos(hwnd, std::ptr::null_mut(), ox + rect[0], oy + rect[1], rect[2], rect[3],
                     SWP_NOACTIVATE | SWP_NOZORDER | SWP_SHOWWINDOW);
    } else if IsWindowVisible(hwnd) != 0 {
        let had_keyboard = GetForegroundWindow() == hwnd;
        ShowWindow(hwnd, SW_HIDE);
        if had_keyboard && !game.is_null() {
            SetForegroundWindow(game);
        }
    }
    if let Some(z) = zoom {
        with_view(key, |v| v.zoom(z));
    }
}

unsafe fn keyboard(key: &str, web: bool) {
    let game = GAME.load(Ordering::Relaxed) as HWND;
    let hwnd = {
        let mut shells = SHELLS.lock().unwrap();
        let Some(s) = shells.get_mut(key) else { return };
        s.keyboard_web = web;
        s.hwnd as HWND
    };
    if web {
        SetForegroundWindow(hwnd);
        with_view(key, |v| v.focus());
    } else if !game.is_null() && (GetForegroundWindow() == hwnd || active_of_host() == hwnd as usize) {
        SetForegroundWindow(game);
    }
}

fn active_of_host() -> usize {
    let mut info: GUITHREADINFO = unsafe { std::mem::zeroed() };
    info.cbSize = std::mem::size_of::<GUITHREADINFO>() as u32;
    let thread = HOST_THREAD.load(Ordering::Relaxed);
    if thread != 0 && unsafe { GetGUIThreadInfo(thread, &mut info) } != 0 { info.hwndActive as usize } else { 0 }
}

fn deliver(key: &str) {
    let msgs = {
        let mut shells = SHELLS.lock().unwrap();
        let Some(s) = shells.get_mut(key) else { return };
        if !s.ready {
            return;
        }
        s.to_page += s.outbox.len() as u64;
        std::mem::take(&mut s.outbox)
    };
    for m in msgs {
        with_view(key, |v| v.evaluate_script(&format!("window.__fseShell && window.__fseShell.receive({m})")));
    }
}

/// a message from a page (on the overlay thread: WebView2 calls back on it)
fn on_page(key: &str, body: &str) {
    let Ok(m) = serde_json::from_str::<Value>(body) else { return };
    let t = m.get("t").and_then(Value::as_str).unwrap_or("");
    let owner = key.split('/').next().unwrap_or("").to_string();
    let mut shells = SHELLS.lock().unwrap();
    let Some(s) = shells.get_mut(key) else { return };
    s.from_page += 1;
    let hwnd = s.hwnd as HWND;
    let name = s.name.clone();
    match t {
        "hello" => {
            s.ready = true;
            let zoom = s.zoom;
            drop(shells);
            with_view(key, |v| v.zoom(zoom)); // (a navigation may reset it)
            push(&owner, false, json!({"type": "ready", "shell": name}));
            deliver(key);
        }
        "layout" => {
            let mut holes = BTreeMap::new();
            if let Some(map) = m.get("islands").and_then(Value::as_object) {
                for (id, r) in map {
                    if let Some(r) = r.as_array().filter(|a| a.len() == 4) {
                        let n = |i: usize| r[i].as_f64().unwrap_or(0.0).round() as i32;
                        holes.insert(id.clone(), [n(0), n(1), n(2).max(0), n(3).max(0)]);
                    }
                }
            }
            s.holes = holes;
            s.solid = m.get("solid").and_then(Value::as_array).map(|list| {
                list.iter().filter_map(|r| r.as_array()).map(|r| {
                    let n = |i: usize| r.get(i).and_then(Value::as_f64).unwrap_or(0.0).round() as i32;
                    [n(0), n(1), n(2), n(3), n(4)]
                }).collect()
            });
            let rgn = unsafe { region(s) };
            let first = !s.laid_out;
            s.laid_out = true;
            let ev = layout_event(s);
            drop(shells);
            unsafe { set_region(hwnd, rgn) };
            push(&owner, true, ev);
            if first {
                unsafe { place(key) };
            }
        }
        "msg" => {
            drop(shells);
            push(&owner, false, json!({"type": "message", "shell": name, "data": m.get("data").cloned().unwrap_or(Value::Null)}));
        }
        "esc" | "close" => {
            if t == "esc" && !s.esc {
                return;
            }
            s.want_visible = false;
            drop(shells);
            unsafe { place(key) };
            push(&owner, false, json!({"type": "closed", "shell": name, "why": t}));
        }
        "set" => {
            if let Some(b) = m.get("visible").and_then(Value::as_bool) {
                s.want_visible = b;
                drop(shells);
                unsafe { place(key) };
                push(&owner, false, json!({"type": "visible", "shell": name, "visible": b}));
            }
        }
        "focus" => {
            let web = m.get("web").and_then(Value::as_bool).unwrap_or(false);
            drop(shells);
            unsafe { keyboard(key, web) };
        }
        "drag" => {
            let phase = m.get("phase").and_then(Value::as_str).unwrap_or("");
            let resize = m.get("mode").and_then(Value::as_str) == Some("resize");
            let d = |k: &str| m.get(k).and_then(Value::as_f64).unwrap_or(0.0).round() as i32;
            if phase == "start" {
                s.drag_start = Some(s.rect);
                return;
            }
            let Some(st) = s.drag_start else { return };
            s.rect = if resize { [st[0], st[1], (st[2] + d("dx")).max(120), (st[3] + d("dy")).max(80)] }
                     else { [st[0] + d("dx"), st[1] + d("dy"), st[2], st[3]] };
            if phase == "end" {
                s.drag_start = None;
            }
            let rgn = if resize { Some(unsafe { region(s) }) } else { None };
            let ev = layout_event(s);
            drop(shells);
            if let Some(rgn) = rgn {
                unsafe { set_region(hwnd, rgn) };
            }
            unsafe { place(key) };
            push(&owner, true, ev);
        }
        "log" => {
            drop(shells);
            fse_plugin::log(&format!("shell {key}: {}", m.get("text").and_then(Value::as_str).unwrap_or("")));
        }
        _ => {}
    }
}

fn with_context<R>(f: impl FnOnce(&mut wry::WebContext) -> R) -> Option<R> {
    CONTEXT.with(|c| {
        let mut c = c.try_borrow_mut().ok()?;
        // (its own profile: its browser runs with flags of its own, so it can't share the panel's)
        let ctx = c.get_or_insert_with(|| wry::WebContext::new(Some(crate::home().join("webview-shell"))));
        Some(f(ctx))
    })
}

unsafe fn open_on_host(key: &str) {
    fse_plugin::log(&format!("shell {key}: open"));
    let game = GAME.load(Ordering::Relaxed) as HWND;
    // (its window made without SHELLS held: CreateWindowExW sends it messages; only this thread makes them)
    let Some((old, rect)) = SHELLS.lock().unwrap().get(key).map(|s| (s.hwnd, s.rect)) else { return };
    if old == 0 || IsWindow(old as HWND) == 0 {
        let class = wide("fse_shell");
        let title = wide(&format!("fse shell {key}"));
        let h = CreateWindowExW(WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE, class.as_ptr(), title.as_ptr(),
                                WS_POPUP | WS_CLIPCHILDREN, 0, 0, rect[2], rect[3], game,
                                std::ptr::null_mut(), GetModuleHandleW(std::ptr::null()), std::ptr::null());
        if h.is_null() {
            fse_plugin::log(&format!("shell {key}: could not make its window"));
            return;
        }
        let mut shells = SHELLS.lock().unwrap();
        match shells.get_mut(key) {
            Some(s) => {
                s.hwnd = h as usize;
                s.zoom = 0.0;
            }
            None => {
                drop(shells);
                DestroyWindow(h); // (closed meanwhile)
                return;
            }
        }
    }
    let (hwnd, url, init, bg, need_view, name) = {
        let shells = SHELLS.lock().unwrap();
        let Some(s) = shells.get(key) else { return };
        let need = VIEWS.with(|v| v.try_borrow().map(|v| !v.contains_key(key)).unwrap_or(false));
        (s.hwnd as HWND, s.url.clone(), s.init.clone(), s.bg, need, s.name.clone())
    };
    let size = SHELLS.lock().unwrap().get(key).map(|s| s.rect);
    if let Some(r) = size {
        // (the size first, so the page lays out at it; place() below moves and shows it)
        SetWindowPos(hwnd, std::ptr::null_mut(), 0, 0, r[2], r[3], SWP_NOMOVE | SWP_NOACTIVATE | SWP_NOZORDER);
    }
    let rgn = SHELLS.lock().unwrap().get(key).map(|s| region(s));
    if let Some(rgn) = rgn {
        set_region(hwnd, rgn);
    }
    if need_view {
        let k = key.to_string();
        let script = format!("window.__fseShellInit = {init};");
        let built = with_context(|ctx| {
            wry::WebViewBuilder::new_with_web_context(ctx)
                .with_url(&url)
                .with_background_color((bg.0, bg.1, bg.2, 0xff))
                .with_initialization_script(script)
                .with_hotkeys_zoom(false)
                .with_focused(false)
                .with_background_throttling(wry::BackgroundThrottlingPolicy::Disabled)
                .with_default_context_menus(false)
                // (a page behind the user's other windows must still lay out and animate: no occlusion throttling)
                .with_additional_browser_args("--disable-features=msWebOOUI,msPdfOOUI,msSmartScreenProtection,CalculateNativeWinOcclusion --disable-renderer-backgrounding --disable-background-timer-throttling --disable-backgrounding-occluded-windows")
                .with_ipc_handler(move |req: wry::http::Request<String>| {
                    guarded("page message", || {
                        on_page(&k, req.body());
                        0
                    });
                })
                .build(&Parent(hwnd))
        });
        let Some(built) = built else { return };
        match built {
            Ok(view) => {
                VIEWS.with(|v| v.try_borrow_mut().map(|mut v| v.insert(key.to_string(), view)).ok());
            }
            Err(e) => {
                fse_plugin::log(&format!("shell {key}: no WebView2 ({e})"));
                let owner = key.split('/').next().unwrap_or("").to_string();
                push(&owner, false, json!({"type": "closed", "shell": name, "why": format!("no WebView2: {e}")}));
                return;
            }
        }
    } else {
        // (open again with another page: load it; the same page stays as it is)
        let current = with_view(key, |v| v.url().unwrap_or_default()).unwrap_or_default();
        if current.split('?').next() != Some(url.split('?').next().unwrap_or("")) {
            with_view(key, |v| v.load_url(&url));
        }
    }
    place(key);
}

unsafe fn close_on_host(key: &str) {
    let removed = SHELLS.lock().unwrap().remove(key);
    let view = VIEWS.with(|v| v.try_borrow_mut().ok().and_then(|mut v| v.remove(key)));
    drop(view);
    if let Some(s) = removed {
        let hwnd = s.hwnd as HWND;
        let had = GetForegroundWindow() == hwnd;
        if !hwnd.is_null() {
            DestroyWindow(hwnd);
        }
        let game = GAME.load(Ordering::Relaxed) as HWND;
        if had && !game.is_null() {
            SetForegroundWindow(game);
        }
    }
}

/// (not while commands run: building a WebView pumps messages, and a command inside another must wait for it)
unsafe fn run_commands() {
    if BUSY.with(|b| b.replace(true)) {
        return;
    }
    loop {
        let cmds: Vec<Value> = std::mem::take(&mut *CMDS.lock().unwrap());
        if cmds.is_empty() {
            break;
        }
        run_list(cmds);
    }
    BUSY.with(|b| b.set(false));
}

unsafe fn run_list(cmds: Vec<Value>) {
    for c in cmds {
        let key = c.get("key").and_then(Value::as_str).unwrap_or("").to_string();
        match c.get("op").and_then(Value::as_str).unwrap_or("") {
            "open" => open_on_host(&key),
            "sync" => {
                let rgn = SHELLS.lock().unwrap().get(&key).filter(|s| s.hwnd != 0).map(|s| (s.hwnd as HWND, region(s)));
                if let Some((h, rgn)) = rgn {
                    set_region(h, rgn);
                }
                place(&key);
                let ev = SHELLS.lock().unwrap().get(&key).map(|s| (s.owner.clone(), layout_event(s)));
                if let Some((owner, ev)) = ev {
                    push(&owner, true, ev);
                }
            }
            "flush" => deliver(&key),
            "close" => close_on_host(&key),
            "eval" => {
                let js = c.get("js").and_then(Value::as_str).unwrap_or("").to_string();
                with_view(&key, |v| v.evaluate_script(&js));
            }
            _ => {}
        }
    }
}

/// the game window moved, was resized, minimised, made again (fullscreen switch): the shells go with it
unsafe fn follow() {
    if SHELLS.lock().unwrap().is_empty() {
        return;
    }
    let Some((last, last_rect, last_hidden, n, last_dpi)) = FOLLOWED.with(|f| f.try_borrow().ok().map(|f| *f)) else { return };
    let mut game = crate::overlay::game_window() as HWND;
    if n % 30 == 0 || IsWindow(game) == 0 {
        let found = crate::overlay::find_game() as HWND;
        if !found.is_null() {
            game = found;
        }
    }
    GAME.store(game as usize, Ordering::Relaxed);
    let mut r: RECT = std::mem::zeroed();
    GetClientRect(game, &mut r);
    let (ox, oy) = client_origin(game);
    let now = [ox, oy, r.right, r.bottom];
    let hidden = IsIconic(game) != 0 || IsWindowVisible(game) == 0;
    let keys: Vec<(String, usize)> = SHELLS.lock().unwrap().iter().map(|(k, s)| (k.clone(), s.hwnd)).collect();
    let dpi = keys.first().map(|k| GetDpiForWindow(k.1 as HWND)).unwrap_or(0);
    if game as usize != last {
        for (_, h) in &keys {
            if *h != 0 {
                SetWindowLongPtrW(*h as HWND, GWLP_HWNDPARENT, game as isize);
            }
        }
    }
    // (a shell still waiting for its page's layout is shown once SHOW_ANYWAY_MS is up)
    let waiting = SHELLS.lock().unwrap().values().any(|s| s.want_visible && !s.laid_out && s.hwnd != 0
        && IsWindowVisible(s.hwnd as HWND) == 0);
    if game as usize != last || now != last_rect || hidden != last_hidden || dpi != last_dpi || waiting {
        for (k, _) in &keys {
            place(k);
        }
    }
    FOLLOWED.with(|f| f.try_borrow_mut().map(|mut f| *f = (game as usize, now, hidden, n.wrapping_add(1), dpi)).ok());
}

/// newest change time of the files in a folder (and its subfolders, a few levels down)
fn newest(dir: &std::path::Path, depth: u32, budget: &mut u32) -> Option<SystemTime> {
    let mut best: Option<SystemTime> = None;
    for e in std::fs::read_dir(dir).ok()?.flatten() {
        if *budget == 0 {
            break;
        }
        *budget -= 1;
        let Ok(meta) = e.metadata() else { continue };
        let t = if meta.is_dir() {
            if depth == 0 { None } else { newest(&e.path(), depth - 1, budget) }
        } else {
            meta.modified().ok()
        };
        if let Some(t) = t {
            best = Some(best.map_or(t, |b| b.max(t)));
        }
    }
    best
}

fn live() {
    if std::env::var("FSE_SHELL_LIVE").map(|v| v == "0").unwrap_or(false) {
        return;
    }
    let lib = crate::home().join("web").join("shell"); // (shell.js and shell.css: every page uses them)
    let mut budget = 200;
    let lib_t = newest(&lib, 0, &mut budget);
    let mut reload = Vec::new();
    for (k, s) in SHELLS.lock().unwrap().iter_mut() {
        let Some(dir) = &s.watch else { continue };
        let mut budget = 500;
        let t = match (newest(dir, 2, &mut budget), lib_t) {
            (Some(a), Some(b)) => Some(a.max(b)),
            (a, b) => a.or(b),
        };
        if s.stamp.is_some() && t != s.stamp {
            s.ready = false;
            s.reloads += 1;
            reload.push(k.clone());
        }
        s.stamp = t;
    }
    for k in reload {
        with_view(&k, |v| v.reload());
    }
}

/// (a panic must never leave a window procedure: it is logged instead; NB the release profile aborts on panics, so
/// this only helps a debug build: the code here avoids panicking, RefCells are only ever try_borrow'ed)
fn guarded(what: &str, f: impl FnOnce() -> LRESULT) -> LRESULT {
    match std::panic::catch_unwind(std::panic::AssertUnwindSafe(f)) {
        Ok(r) => r,
        Err(e) => {
            let text = e.downcast_ref::<&str>().map(|s| s.to_string())
                .or_else(|| e.downcast_ref::<String>().cloned()).unwrap_or_default();
            fse_plugin::log(&format!("shell: panic in {what}: {text}"));
            0
        }
    }
}

unsafe extern "system" fn host_proc(hwnd: HWND, msg: u32, wp: WPARAM, lp: LPARAM) -> LRESULT {
    guarded("host", || host_msg(hwnd, msg, wp, lp))
}

unsafe extern "system" fn shell_proc(hwnd: HWND, msg: u32, wp: WPARAM, lp: LPARAM) -> LRESULT {
    guarded("shell", || shell_msg(hwnd, msg, wp, lp))
}

unsafe fn host_msg(hwnd: HWND, msg: u32, wp: WPARAM, lp: LPARAM) -> LRESULT {
    match msg {
        WM_CMD => {
            run_commands();
            0
        }
        WM_TIMER => {
            if wp == FOLLOW {
                follow();
            } else if wp == LIVE {
                live();
            }
            0
        }
        _ => DefWindowProcW(hwnd, msg, wp, lp),
    }
}

unsafe fn shell_msg(hwnd: HWND, msg: u32, wp: WPARAM, lp: LPARAM) -> LRESULT {
    match msg {
        // (a click in the page leaves the game the keyboard, unless the page asked for it: a text field)
        WM_MOUSEACTIVATE => {
            let web = find(hwnd).and_then(|k| SHELLS.try_lock().ok()?.get(&k).map(|s| s.keyboard_web)).unwrap_or(false);
            (if web { MA_ACTIVATE } else { MA_NOACTIVATE }) as LRESULT
        }
        WM_ACTIVATE => {
            if (wp & 0xffff) as u32 == WA_INACTIVE {
                if let Some(k) = find(hwnd) {
                    if let Ok(mut shells) = SHELLS.try_lock() {
                        if let Some(s) = shells.get_mut(&k) {
                            s.keyboard_web = false;
                        }
                    }
                }
            }
            DefWindowProcW(hwnd, msg, wp, lp)
        }
        WM_CLOSE => {
            // (Alt+F4 while a text field has the keyboard): closed like Esc
            if let Some(k) = find(hwnd) {
                let (owner, name) = {
                    let Ok(mut shells) = SHELLS.try_lock() else { return 0 };
                    let Some(s) = shells.get_mut(&k) else { return 0 };
                    s.want_visible = false;
                    (s.owner.clone(), s.name.clone())
                };
                place(&k);
                push(&owner, false, json!({"type": "closed", "shell": name, "why": "close"}));
            }
            0
        }
        _ => DefWindowProcW(hwnd, msg, wp, lp),
    }
}

/// makes the shells' host (a message window and the shell window class); on the overlay thread, before its loop
pub unsafe fn create_host(game: usize) {
    GAME.store(game, Ordering::Relaxed);
    let inst = GetModuleHandleW(std::ptr::null());
    let class = wide("fse_shell");
    let wc = WNDCLASSW { lpfnWndProc: Some(shell_proc), hInstance: inst, lpszClassName: class.as_ptr(),
                         hCursor: LoadCursorW(std::ptr::null_mut(), IDC_ARROW),
                         hbrBackground: CreateSolidBrush(0x242424), ..std::mem::zeroed() };
    RegisterClassW(&wc);
    let hclass = wide("fse_shell_host");
    let hc = WNDCLASSW { lpfnWndProc: Some(host_proc), hInstance: inst, lpszClassName: hclass.as_ptr(), ..std::mem::zeroed() };
    RegisterClassW(&hc);
    let host = CreateWindowExW(0, hclass.as_ptr(), hclass.as_ptr(), 0, 0, 0, 0, 0, HWND_MESSAGE, std::ptr::null_mut(), inst,
                               std::ptr::null());
    if host.is_null() {
        fse_plugin::log("shell: could not make its host window");
        return;
    }
    HOST_THREAD.store(GetCurrentThreadId(), Ordering::Relaxed);
    SetTimer(host, FOLLOW, 15, None);
    SetTimer(host, LIVE, 500, None);
    HOST.store(host as usize, Ordering::Relaxed);
    if !CMDS.lock().unwrap().is_empty() {
        PostMessageW(host, WM_CMD, 0, 0);
    }
}
