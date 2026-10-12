"""Input for a real game window without touching the user's desktop: messages posted to the game's window (never
global input), and its picture via PrintWindow (whatever is in front of it). Used by run_gu_buttons.py and
run_theme_matrix.py."""
import ctypes
import subprocess
import time
from ctypes import wintypes

u32 = ctypes.windll.user32
u32.SetProcessDPIAware()


def game_window(pid=None, timeout=30):
    """the biggest visible titled window of the game process `pid` (else of any factorio.exe: another test's or the
    user's game may be running too, so pass the pid), or None"""
    end = time.time() + timeout
    while True:
        if pid:
            pids = {pid}
        else:
            out = subprocess.run(["tasklist", "/FI", "IMAGENAME eq factorio.exe", "/FO", "CSV", "/NH"],
                                 capture_output=True, text=True).stdout
            pids = {int(l.split('","')[1]) for l in out.splitlines() if l.startswith('"factorio')}
        found = []

        @ctypes.WINFUNCTYPE(wintypes.BOOL, wintypes.HWND, wintypes.LPARAM)
        def each(h, _):
            p = wintypes.DWORD()
            u32.GetWindowThreadProcessId(h, ctypes.byref(p))
            if p.value in pids and u32.IsWindowVisible(h) and u32.GetWindowTextLengthW(h) > 0:
                r = wintypes.RECT()
                u32.GetClientRect(h, ctypes.byref(r))
                found.append((r.right * r.bottom, h))
            return True
        u32.EnumWindows(each, 0)
        if found or time.time() > end:
            return max(found)[1] if found else None
        time.sleep(0.5)


def focus(h):
    # (the game takes posted input only while it thinks it has the focus)
    u32.PostMessageW(h, 0x0006, 1, 0)  # WM_ACTIVATE
    u32.PostMessageW(h, 0x0007, 0, 0)  # WM_SETFOCUS
    time.sleep(0.2)


def click(h, x, y):
    """a left click at client pixel (x, y)"""
    focus(h)
    at = int(y) << 16 | int(x)
    u32.PostMessageW(h, 0x0200, 0, at)  # WM_MOUSEMOVE
    time.sleep(0.2)
    u32.PostMessageW(h, 0x0201, 1, at)  # WM_LBUTTONDOWN
    time.sleep(0.08)
    u32.PostMessageW(h, 0x0202, 0, at)  # WM_LBUTTONUP


def grab(h, path):
    """the game window's own picture (PrintWindow) saved to `path`; False when the window has no size"""
    from PIL import Image
    g32 = ctypes.windll.gdi32
    r = wintypes.RECT()
    u32.GetClientRect(h, ctypes.byref(r))
    w, ht = r.right, r.bottom
    if w <= 0 or ht <= 0:
        return False
    dc = u32.GetDC(h)
    mem = g32.CreateCompatibleDC(dc)
    bmp = g32.CreateCompatibleBitmap(dc, w, ht)
    g32.SelectObject(mem, bmp)
    u32.PrintWindow(h, mem, 3)  # PW_CLIENTONLY | PW_RENDERFULLCONTENT
    buf = ctypes.create_string_buffer(w * ht * 4)
    g32.GetBitmapBits(bmp, len(buf), buf)
    Image.frombuffer("RGBA", (w, ht), buf, "raw", "BGRA", 0, 1).convert("RGB").save(path)
    g32.DeleteObject(bmp)
    g32.DeleteDC(mem)
    u32.ReleaseDC(h, dc)
    return True
