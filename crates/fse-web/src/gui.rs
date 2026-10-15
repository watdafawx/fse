//! The game's own windows on screen: where they are, so a HUD shell (shell.rs) can step aside when one covers it.
//! agui::Gui::render (the main thread, once a frame, the thread that also changes the widgets) is hooked; after it
//! draws, the widget tree is walked from the Gui's baseWidget (the game's one Gui, a global render reads; its `this`
//! is unused): a visible widget filling (nearly) the whole screen is a
//! container (the screen, the game view's layers) and is looked into; any other visible widget is a box (a window, a
//! panel, the toolbar, a mod's screen frame) and is taken whole, its children not looked at. Boxes are in game client
//! pixels (the GUI's own), the shells' units. Walked only while some shell asks (HUD shells: shell.rs sets WANTED).
//! Everything comes from factorio.pdb (plugins/web.needs.json); without it there are no boxes (HUD shells then only
//! step aside for other shells).

use std::sync::atomic::{AtomicBool, AtomicU32, Ordering};
use std::sync::{Mutex, OnceLock};
use std::time::Instant;

use fse_plugin as fp;
use retour::GenericDetour;
use serde_json::{json, Value};
use windows_sys::Win32::System::LibraryLoader::GetModuleHandleW;
use windows_sys::Win32::System::Memory::{VirtualQuery, MEMORY_BASIC_INFORMATION, MEM_COMMIT, PAGE_GUARD, PAGE_NOACCESS};
use windows_sys::Win32::System::ProcessStatus::{GetModuleInformation, MODULEINFO};
use windows_sys::Win32::System::Threading::GetCurrentProcess;

type Render = unsafe extern "C" fn(usize);
type AbsRect = unsafe extern "C" fn(usize, *mut [i32; 4]) -> *mut [i32; 4];

const RENDER: &str = "?render@Gui@agui@@QEAAXXZ";
const ABS_RECT: &str = "?getAbsoluteRectangle@Widget@agui@@QEBA?AVRectangle@2@XZ";
const VISIBLE_MASK: u32 = 0x20004; // (usageBitMask: agui::Widget::setVisible sets 0x4; 0x20000 hides it too)
const VISIBLE: u32 = 0x4;
const MAX_DEPTH: u32 = 8;
const MAX_WIDGETS: usize = 4000;
const FULL: f64 = 0.9; // (a widget this much of the screen's width and height is a container)

static HOOK: OnceLock<GenericDetour<Render>> = OnceLock::new();
static ENGINE: OnceLock<Engine> = OnceLock::new();
pub static WANTED: AtomicBool = AtomicBool::new(false);
static DUMP: AtomicBool = AtomicBool::new(false);
static FRAME: AtomicU32 = AtomicU32::new(0);
static BOXES: Mutex<Option<Boxes>> = Mutex::new(None);
static DUMPED: Mutex<Option<Value>> = Mutex::new(None);

struct Engine {
    abs_rect: AbsRect,
    base: usize,      // agui::Gui.baseWidget
    children: usize,  // agui::Widget.children (a std::vector: begin, end)
    private: usize,   // agui::Widget.privateChildren (the same)
    usage: usize,     // agui::Widget.usageBitMask
    text: usize,      // agui::Widget.text (for the dump)
    exe: usize,
    exe_end: usize,   // (a widget's vtable is in the exe's image)
    global: usize,    // (where the game keeps its Gui*: render reads it, its `this` is unused (null))
}

/// the global Gui* render reads: its first `mov rdi, [rip + disp32]` (48 8B 3D), in its first 64 bytes
unsafe fn gui_global(render: usize) -> Option<usize> {
    let code = std::slice::from_raw_parts(render as *const u8, 64);
    (0..57).find(|&i| code[i] == 0x48 && code[i + 1] == 0x8B && code[i + 2] == 0x3D).map(|i| {
        let disp = i32::from_le_bytes([code[i + 3], code[i + 4], code[i + 5], code[i + 6]]);
        (render + i + 7).wrapping_add_signed(disp as isize)
    })
}

#[derive(Clone)]
pub struct Boxes {
    pub at: Instant,
    pub screen: [i32; 2],
    pub boxes: Vec<[i32; 4]>,
}

fn off(c: &str, f: &str) -> Result<usize, String> {
    fp::field_offset(c, f).map(|v| v as usize).ok_or(format!("{c}.{f} not in this build"))
}

/// the hook; why not when it can't be
pub unsafe fn install() -> Result<(), String> {
    let render = fp::engine_symbol(RENDER).ok_or("agui::Gui::render not in this build")?;
    let abs = fp::engine_symbol(ABS_RECT).ok_or("agui::Widget::getAbsoluteRectangle not in this build")?;
    let _ = ENGINE.set(Engine {
        abs_rect: std::mem::transmute::<usize, AbsRect>(abs),
        base: off("agui::Gui", "baseWidget")?,
        children: off("agui::Widget", "children")?,
        private: off("agui::Widget", "privateChildren")?,
        usage: off("agui::Widget", "usageBitMask")?,
        text: off("agui::Widget", "text")?,
        exe: GetModuleHandleW(std::ptr::null()) as usize,
        global: gui_global(render).ok_or("agui::Gui::render: no global Gui* in it (another build?)")?,
        exe_end: {
            let mut mi: MODULEINFO = std::mem::zeroed();
            GetModuleInformation(GetCurrentProcess(), GetModuleHandleW(std::ptr::null()), &mut mi,
                std::mem::size_of::<MODULEINFO>() as u32);
            mi.lpBaseOfDll as usize + mi.SizeOfImage as usize
        },
    });
    let e = ENGINE.get().unwrap();
    fp::log(&format!("game windows: Gui.baseWidget +{}, Widget.children +{}, usageBitMask +{}, text +{}",
        e.base, e.children, e.usage, e.text));
    let h = GenericDetour::<Render>::new(std::mem::transmute::<usize, Render>(render), render_hook)
        .map_err(|e| format!("hook: {e}"))?;
    let h = HOOK.get_or_init(|| h);
    h.enable().map_err(|e| format!("hook: {e}"))
}

/// the boxes of the last walk, if one ran in the last half second
pub fn boxes() -> Option<Boxes> {
    let b = BOXES.lock().unwrap().clone()?;
    (b.at.elapsed().as_millis() < 500).then_some(b)
}

/// every widget looked at in the next walk (tests, dev): asks for one, waits up to a second
pub fn dump() -> Result<String, String> {
    if ENGINE.get().is_none() {
        return Err("no GUI hook (factorio.pdb?)".into());
    }
    *DUMPED.lock().unwrap() = None;
    DUMP.store(true, Ordering::Relaxed);
    for _ in 0..100 {
        if let Some(v) = DUMPED.lock().unwrap().take() {
            return Ok(v.to_string());
        }
        std::thread::sleep(std::time::Duration::from_millis(10));
    }
    DUMP.store(false, Ordering::Relaxed);
    Err("no frame drawn in a second".into())
}

unsafe extern "C" fn render_hook(this: usize) {
    // (`this` goes on to the game's render as it came; the Gui is the global one)
    HOOK.get().unwrap().call(this);
    let dump = DUMP.load(Ordering::Relaxed);
    // (every other frame is plenty: a window opening shows the HUD's step aside within ~30 ms)
    if !dump && (!WANTED.load(Ordering::Relaxed) || FRAME.fetch_add(1, Ordering::Relaxed) % 2 != 0) {
        return;
    }
    let Some(e) = ENGINE.get() else { return };
    let gui = read(e.global).unwrap_or(0);
    let root = if gui != 0 { read(gui + e.base).unwrap_or(0) } else { 0 };
    if !widget(e, root) {
        if dump {
            let vt = read(root).unwrap_or(0);
            let words: Vec<String> = (0..20).map(|i| format!("{:x}", read(gui + i * 8).unwrap_or(0))).collect();
            DUMP.store(false, Ordering::Relaxed);
            *DUMPED.lock().unwrap() = Some(json!({"error": "no root widget", "gui": format!("{gui:x}"),
                "root": format!("{root:x}"), "root_vtable": format!("{vt:x}"), "exe": format!("{:x}-{:x}", e.exe, e.exe_end),
                "gui_words": words}));
        }
        return;
    }
    let screen = rect(e, root);
    if screen[2] <= 0 || screen[3] <= 0 {
        return;
    }
    let mut walk = Walk { e, screen, boxes: Vec::new(), seen: 0, dump: dump.then(Vec::new) };
    walk.visit(root, 0);
    if let Some(list) = walk.dump.take() {
        DUMP.store(false, Ordering::Relaxed);
        *DUMPED.lock().unwrap() = Some(json!({"screen": screen, "widgets": list, "boxes": walk.boxes}));
    }
    // (should more than one Gui draw a frame, the biggest is the game's: a smaller one only replaces a stale walk)
    let mut b = BOXES.lock().unwrap();
    let area = |s: [i32; 2]| s[0] as i64 * s[1] as i64;
    let keep = b.as_ref().map(|old| old.at.elapsed().as_millis() > 100 || area([screen[2], screen[3]]) >= area(old.screen))
        .unwrap_or(true);
    if keep {
        *b = Some(Boxes { at: Instant::now(), screen: [screen[2], screen[3]], boxes: walk.boxes });
    }
}

/// `len` bytes at `at` can be read (committed, not guarded): a widget's memory checked before it is looked at
fn readable(at: usize, len: usize) -> bool {
    if at < 0x10000 {
        return false;
    }
    let mut mbi: MEMORY_BASIC_INFORMATION = unsafe { std::mem::zeroed() };
    let got = unsafe { VirtualQuery(at as *const _, &mut mbi, std::mem::size_of::<MEMORY_BASIC_INFORMATION>()) };
    got != 0 && mbi.State == MEM_COMMIT && mbi.Protect & (PAGE_GUARD | PAGE_NOACCESS) == 0 && mbi.Protect != 0
        && at + len <= mbi.BaseAddress as usize + mbi.RegionSize
}

unsafe fn read(at: usize) -> Option<usize> {
    readable(at, 8).then(|| *(at as *const usize))
}

/// `w` looks like a widget: its memory readable, its vtable in the exe
unsafe fn widget(e: &Engine, w: usize) -> bool {
    readable(w, e.text + 32) && {
        let vt = *(w as *const usize);
        vt >= e.exe && vt < e.exe_end
    }
}

unsafe fn rect(e: &Engine, w: usize) -> [i32; 4] {
    let mut r = [0i32; 4];
    (e.abs_rect)(w, &mut r);
    r
}

struct Walk<'a> {
    e: &'a Engine,
    screen: [i32; 4],
    boxes: Vec<[i32; 4]>,
    seen: usize,
    dump: Option<Vec<Value>>,
}

impl Walk<'_> {
    unsafe fn visit(&mut self, w: usize, depth: u32) {
        self.seen += 1;
        if self.seen > MAX_WIDGETS {
            return;
        }
        let e = self.e;
        if !widget(e, w) {
            return;
        }
        let usage = *((w + e.usage) as *const u32);
        let visible = usage & VISIBLE_MASK == VISIBLE;
        let r = if visible { rect(e, w) } else { [0; 4] };
        let full = r[2] as f64 >= self.screen[2] as f64 * FULL && r[3] as f64 >= self.screen[3] as f64 * FULL;
        let kids: Vec<usize> = list(w + e.children).iter().chain(list(w + e.private)).copied().collect();
        let is_box = visible && depth > 0 && !full && r[2] > 0 && r[3] > 0;
        if let Some(list) = self.dump.as_mut() {
            let vt = *(w as *const usize);
            list.push(json!({"depth": depth, "rect": r, "visible": visible, "usage": usage,
                "vtable": format!("{:x}", vt.wrapping_sub(e.exe)), "text": text(w + e.text), "children": kids.len(),
                "box": is_box}));
        }
        if !visible {
            return;
        }
        if is_box {
            self.boxes.push(r);
            return;
        }
        if depth < MAX_DEPTH {
            for k in kids {
                if k != 0 {
                    self.visit(k, depth + 1);
                }
            }
        }
    }
}

/// a std::vector<Widget*> at `at` (begin, end): its pointers, or none when it doesn't look like one
unsafe fn list<'a>(at: usize) -> &'a [usize] {
    let (first, last) = (*(at as *const usize), *((at + 8) as *const usize));
    let ok = first != 0 && last > first && (last - first) % 8 == 0 && (last - first) / 8 < 10_000
        && readable(first, last - first);
    if ok { std::slice::from_raw_parts(first as *const usize, (last - first) / 8) } else { &[] }
}

/// MSVC's std::string at `at`, first 40 bytes, lossy
unsafe fn text(at: usize) -> String {
    let size = *((at + 16) as *const usize);
    let cap = *((at + 24) as *const usize);
    if size == 0 || size > 1 << 20 {
        return String::new();
    }
    let p = if cap < 16 { at as *const u8 } else { *(at as *const *const u8) };
    String::from_utf8_lossy(std::slice::from_raw_parts(p, size.min(40))).into_owned()
}
