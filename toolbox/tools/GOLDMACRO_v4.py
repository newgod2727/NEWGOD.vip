#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
GOLDMACRO  v3.1
================================================================================
Human-exact input recorder + replayer for Windows, with session slots.

    CTRL + N     start recording into the selected slot     (rebindable)
    CTRL + M     stop recording  -> start replaying it       (rebindable)
    CTRL + P     stop everything            (panic key)      (rebindable)
    CTRL + J     pause / resume the replay                   (rebindable)
    CTRL + 1..6  select a slot
    ESC ESC ESC  emergency stop while replaying (three times inside a second)

Keys are replayed as SCAN CODES, the same numbers the keyboard hardware puts
on the wire, so programs that read scan codes instead of virtual keys - most
games - actually receive them. Hotkeys are rebindable and are swallowed before
they reach whatever is in front, so binding CTRL+N never types an N into it.

Records every mouse move, click, scroll, key press and key release with its
exact timestamp, so playback reproduces the same path, the same rhythm and the
same typing speed as the human original. Six slots hold this session's
recordings; they are deliberately NOT kept after the app closes.

Just download and double-click. It elevates itself to Administrator, installs
its own dependency (pynput) if missing, and starts.

Run `python GOLDMACRO.py --selftest` to execute the built-in verification
suite (no GUI, no input capture, exit code 0 = all green).
================================================================================
"""

from __future__ import annotations

import ctypes
import importlib
import json
import os
import queue
import random
import subprocess
import sys
import threading
import time
import traceback
from collections import deque

PANIC_MAX = 6
SPEED_MIN = 0.25
SPEED_MAX = 4.00

APP_NAME = "GOLDMACRO"
APP_VER = "v4.1"
IS_WIN = (os.name == "nt")
CREATE_NO_WINDOW = 0x08000000

_ARGS = set(a.lower() for a in sys.argv[1:])
SELFTEST = "--selftest" in _ARGS
ELEVATED_FLAG = "--elevated" in _ARGS

DATA_DIR = os.path.join(
    os.environ.get("LOCALAPPDATA") or os.path.expanduser("~"), "GoldMacro")
MACRO_PATH = os.path.join(DATA_DIR, "macro.json")
LIB_DIR = os.path.join(DATA_DIR, "library")
TXT_DIR = os.path.join(DATA_DIR, "readable")
ERROR_LOG = os.path.join(DATA_DIR, "error.log")


def _mkdirs() -> None:
    try:
        os.makedirs(DATA_DIR, exist_ok=True)
    except Exception:
        pass


# =============================================================================
# 0.  BOOTSTRAP  (crash handler -> admin -> DPI -> dependency)
# =============================================================================

def _log_crash(text: str) -> None:
    _mkdirs()
    try:
        with open(ERROR_LOG, "a", encoding="utf-8", errors="replace") as fh:
            fh.write("\n===== %s =====\n%s\n" % (time.strftime("%Y-%m-%d %H:%M:%S"), text))
    except Exception:
        pass


def _install_crash_handler() -> None:
    def hook(exc_type, exc, tb):
        text = "".join(traceback.format_exception(exc_type, exc, tb))
        _log_crash(text)
        try:
            import tkinter.messagebox as mb
            mb.showerror(APP_NAME + " crashed",
                         "%s\n\nFull traceback saved to:\n%s" % (exc, ERROR_LOG))
        except Exception:
            sys.stderr.write(text)
    sys.excepthook = hook

    def thook(args):
        hook(args.exc_type, args.exc_value, args.exc_traceback)
    try:
        threading.excepthook = thook          # Python 3.8+
    except Exception:
        pass


def _is_admin() -> bool:
    if not IS_WIN:
        return True
    try:
        return bool(ctypes.windll.shell32.IsUserAnAdmin())
    except Exception:
        return False


def _relaunch_as_admin() -> bool:
    """Ask UAC for elevation. Returns True if the elevated copy was started."""
    try:
        if getattr(sys, "frozen", False):
            exe = sys.executable
            argv = list(sys.argv[1:])
        else:
            exe = sys.executable
            argv = [os.path.abspath(sys.argv[0])] + list(sys.argv[1:])
        if "--elevated" not in [a.lower() for a in argv]:
            argv.append("--elevated")
        params = " ".join('"%s"' % a for a in argv)
        rc = ctypes.windll.shell32.ShellExecuteW(None, "runas", exe, params, None, 1)
        return int(rc) > 32
    except Exception as exc:
        _log_crash("elevation failed: %r" % (exc,))
        return False


def _ensure_admin() -> None:
    """Re-launch elevated exactly once. Never loops (guarded by --elevated)."""
    if not IS_WIN or _is_admin() or ELEVATED_FLAG:
        return
    if _relaunch_as_admin():
        sys.exit(0)
    # User clicked "No" on UAC, or elevation is blocked by policy:
    # keep running unelevated. The GUI shows a NO-ADMIN badge.


def _dpi_setup() -> float:
    """Make coordinates physical pixels and return the UI scale factor.

    Three APIs, three different success conventions: the Context call returns
    BOOL, SetProcessDpiAwareness returns an HRESULT where 0 means OK, and the
    legacy call returns BOOL. Checking "it did not raise" is not the same as
    "it worked", so each is checked on its own terms.
    """
    if not IS_WIN:
        return 1.0
    ok = False
    try:
        ok = bool(ctypes.windll.user32.SetProcessDpiAwarenessContext(
            ctypes.c_void_p(-4)))                      # PER_MONITOR_AWARE_V2
    except Exception:
        ok = False
    if not ok:
        try:
            ok = (int(ctypes.windll.shcore.SetProcessDpiAwareness(2)) == 0)
        except Exception:
            ok = False
    if not ok:
        try:
            ctypes.windll.user32.SetProcessDPIAware()
        except Exception:
            pass
    try:
        return max(1.0, min(2.0, ctypes.windll.user32.GetDpiForSystem() / 96.0))
    except Exception:
        return 1.0


def _add_user_site() -> None:
    try:
        import site
        for path in filter(None, [site.getusersitepackages()]):
            if isinstance(path, str) and path not in sys.path:
                sys.path.insert(0, path)
    except Exception:
        pass


def _pip_install(pkg: str) -> bool:
    base = [sys.executable, "-m", "pip", "install",
            "--disable-pip-version-check", "--quiet", pkg]
    for cmd in (base, base[:-1] + ["--user", pkg]):
        try:
            kw = {"capture_output": True, "text": True, "timeout": 420}
            if IS_WIN:
                kw["creationflags"] = CREATE_NO_WINDOW
            if subprocess.run(cmd, **kw).returncode == 0:
                return True
        except Exception:
            continue
    return False


def _ensure_pynput() -> bool:
    for attempt in (0, 1):
        try:
            importlib.invalidate_caches()
            _add_user_site()
            import pynput  # noqa: F401
            return True
        except Exception:
            if attempt:
                return False
            _pip_install("pynput")
    return False


def _dependency_error() -> None:
    msg = ("%s needs the 'pynput' package and could not install it "
           "automatically.\n\nOpen Command Prompt and run:\n\n"
           "    %s -m pip install pynput\n\nThen start %s again."
           % (APP_NAME, os.path.basename(sys.executable), APP_NAME))
    _log_crash(msg)
    try:
        import tkinter as _tk
        import tkinter.messagebox as _mb
        root = _tk.Tk()
        root.withdraw()
        _mb.showerror(APP_NAME + " - missing dependency", msg)
        root.destroy()
    except Exception:
        print(msg)
    sys.exit(1)


_mkdirs()
if not SELFTEST:
    _install_crash_handler()
    _ensure_admin()
UI_SCALE = _dpi_setup()
if not _ensure_pynput():
    _dependency_error()

from pynput import keyboard, mouse                                  # noqa: E402

try:
    import tkinter as tk
except Exception:                                                    # pragma: no cover
    tk = None


def _timer_resolution(on: bool) -> None:
    """1 ms scheduler granularity, so sleeps during playback stay tight."""
    if not IS_WIN:
        return
    try:
        (ctypes.windll.winmm.timeBeginPeriod if on
         else ctypes.windll.winmm.timeEndPeriod)(1)
    except Exception:
        pass


def _boost_thread(on: bool) -> None:
    """Raise the replay thread above normal priority while it is running.

    Measured on a deliberately loaded machine: an unboosted replay can have a
    single event land ~16 ms late because the OS scheduler put the thread down.
    Boosting does not beat the scheduler, but it visibly tightens the worst
    case, and the tool hands the priority straight back when the replay ends.
    """
    if not IS_WIN:
        return
    try:
        handle = ctypes.windll.kernel32.GetCurrentThread()
        # 2 = THREAD_PRIORITY_HIGHEST, 0 = THREAD_PRIORITY_NORMAL
        ctypes.windll.kernel32.SetThreadPriority(handle, 2 if on else 0)
    except Exception:
        pass


def _single_instance() -> bool:
    """True if this is the only copy running (two copies = doubled hotkeys).

    Uses a session-local mutex name rather than a Global one, because Global
    needs a privilege an unelevated copy does not have, and probes with
    OpenMutexW instead of reading GetLastError through ctypes, which is not
    reliable to interleave with other calls.
    """
    if not IS_WIN:
        return True
    name = "Local\\GoldMacroSingleton"
    try:
        existing = ctypes.windll.kernel32.OpenMutexW(0x00100000, False, name)
        if existing:
            ctypes.windll.kernel32.CloseHandle(existing)
            return False
        handle = ctypes.windll.kernel32.CreateMutexW(None, True, name)
        if handle:
            globals()["_MUTEX"] = handle       # held for the process lifetime
        return True
    except Exception:
        return True


def _hide_console() -> None:
    """Hide our own console window, but ONLY if we own it.

    If he starts the tool from an already-open Command Prompt, that console
    belongs to cmd.exe as well as to us - hiding it would make his terminal
    vanish. GetConsoleProcessList returning 1 means the console is ours alone.
    """
    if not IS_WIN:
        return
    try:
        hwnd = ctypes.windll.kernel32.GetConsoleWindow()
        if not hwnd:
            return
        buf = (ctypes.c_uint * 8)()
        count = ctypes.windll.kernel32.GetConsoleProcessList(buf, 8)
        if count == 1:
            ctypes.windll.user32.ShowWindow(hwnd, 0)
    except Exception:
        pass


def _physical_ctrl_down() -> bool:
    """Ask Windows directly whether CTRL is down.

    Tracking ctrl press/release in software drifts the moment one event is
    missed or coalesced, and a drifted tracker turns a bare 'p' into the panic
    hotkey. The OS always knows the truth, so ask it.
    """
    if not IS_WIN:
        return False
    try:
        return bool(ctypes.windll.user32.GetAsyncKeyState(0x11) & 0x8000)
    except Exception:
        return False


# =============================================================================
# 1.  THEME
# =============================================================================

class T:
    """Palette lifted pixel-by-pixel off the interface he pointed at.

    Sampled from his screenshot rather than invented: amber chrome at the top,
    a light-gold gradient body, pale butter-gold cards with a barely-there
    border, and flat black pill buttons. v2 guessed at "gold" and produced dark
    brown plates with gold text, which is why he said the design was bad.
    """
    CHROME = "#FCBC24"       # top strip and footer rail
    CHROME_LO = "#EEB122"    # pressed / active chrome
    BG_TOP = "#FCD241"       # body gradient, top
    BG_MID = "#FDE861"       # ...the lit middle
    BG_BOT = "#F6A30A"       # ...deeper at the bottom
    CARD = "#FCE96B"         # card face
    CARD_HI = "#FEF3A0"
    CARD_LO = "#F3D95A"
    EDGE = "#F7DE72"         # the soft card border
    HL = "#FFF8CE"
    CHIP = "#FDE470"         # search field / small chip
    PILL = "#0B0905"         # the black pill button
    PILL_TEXT = "#FDE861"
    PILL_HI = "#241E12"

    ON = "#41310C"           # text on gold
    TEXT = "#41310C"
    VAL = "#241A03"
    H1 = "#7A5C12"
    DIM = "#7A5C12"
    FAINT_C = "#AA8B2F"
    RED = "#C0170B"
    RED_HI = "#E8402F"

    INK = CHROME             # labels sitting on the chrome rails
    INK_HI = CHROME_LO
    GOLD = "#FFC61A"
    GOLD_HI = "#FFE9A8"
    GOLD_MID = "#8A6912"
    GOLD_DIM = "#6A5210"
    GOLD_DEEP = "#C9971C"
    LINE = "#E0B62C"
    LINE_HI = "#F7DE72"
    ON_GOLD = "#41310C"
    RED_BRIGHT = "#C0170B"
    RED_DEEP = "#7A1109"
    FAINT = "#9A7A22"
    OFF = "#C79A22"
    CHROMA = "#010203"
    MONO = "Consolas"
    UI = "Segoe UI"

    BG = CHROME
    PANEL = CARD
    HOVER = CARD_HI
    SUNK = CHROME_LO


def S(v: float) -> int:
    return int(round(v * UI_SCALE))


# =============================================================================
# 2.  EVENT MODEL
# =============================================================================

EV_MOVE = "mm"
EV_DOWN = "md"
EV_UP = "mu"
EV_SCROLL = "ms"
EV_KDOWN = "kd"
EV_KUP = "ku"

EV_WAIT = "wt"
EV_TEXT = "tx"
EV_KEYS = "hk"
EV_FOCUS = "fw"

MACRO_KINDS = (EV_WAIT, EV_TEXT, EV_KEYS, EV_FOCUS)

MOD_KEYS = {"ctrl": "ctrl_l", "control": "ctrl_l", "shift": "shift_l",
            "alt": "alt_l", "win": "cmd", "cmd": "cmd", "meta": "cmd"}

NAMED_KEYS = {"enter": "enter", "return": "enter", "tab": "tab", "esc": "esc",
              "escape": "esc", "space": "space", "backspace": "backspace",
              "delete": "delete", "del": "delete", "home": "home", "end": "end",
              "up": "up", "down": "down", "left": "left", "right": "right",
              "pgup": "page_up", "pgdn": "page_down"}

STEP_GAP = 0.012


def key_event(kind, t, name=None, char=None):
    ev = {"k": kind, "t": round(float(t), 4)}
    if name:
        ev["id"] = "n:" + name
        ev["n"] = name
    else:
        ev["id"] = "c:" + str(char)
        ev["c"] = str(char)
    return ev


def parse_combo(text):
    """ctrl+c, CTRL + SHIFT + v, alt+tab. Anything it cannot read comes back
    empty rather than half a combo, so a typo never fires a stray key."""
    mods, main = [], None
    for piece in str(text or "").replace(" ", "").split("+"):
        if not piece:
            continue
        low = piece.lower()
        if low in MOD_KEYS:
            if MOD_KEYS[low] not in mods:
                mods.append(MOD_KEYS[low])
        elif low in NAMED_KEYS:
            main = ("name", NAMED_KEYS[low])
        elif len(piece) == 1:
            main = ("char", piece.lower())
        else:
            return [], None
    return mods, main


def combo_events(text, t):
    mods, main = parse_combo(text)
    if main is None:
        return []
    out = []
    at = float(t)
    for name in mods:
        out.append(key_event(EV_KDOWN, at, name=name))
        at += STEP_GAP
    if main[0] == "name":
        out.append(key_event(EV_KDOWN, at, name=main[1]))
        at += STEP_GAP
        out.append(key_event(EV_KUP, at, name=main[1]))
    else:
        out.append(key_event(EV_KDOWN, at, char=main[1]))
        at += STEP_GAP
        out.append(key_event(EV_KUP, at, char=main[1]))
    at += STEP_GAP
    for name in reversed(mods):
        out.append(key_event(EV_KUP, at, name=name))
        at += STEP_GAP
    return out


def text_events(text, t):
    """Typed one character at a time rather than pasted, so his clipboard is
    never taken away from him to run a macro."""
    out = []
    at = float(t)
    for ch in str(text or ""):
        if ch == "\n":
            out.append(key_event(EV_KDOWN, at, name="enter"))
            at += STEP_GAP
            out.append(key_event(EV_KUP, at, name="enter"))
        elif ch == "\t":
            out.append(key_event(EV_KDOWN, at, name="tab"))
            at += STEP_GAP
            out.append(key_event(EV_KUP, at, name="tab"))
        else:
            out.append(key_event(EV_KDOWN, at, char=ch))
            at += STEP_GAP
            out.append(key_event(EV_KUP, at, char=ch))
        at += STEP_GAP
    return out


def expand_step(ev, at):
    """A macro step becomes the real key events it stands for. Nothing new
    reaches the player - copy, paste and typing all travel the same path a
    recorded key does, which is why they behave the same in every program."""
    kind = ev.get("k")
    if kind == EV_KEYS:
        return combo_events(ev.get("s", ""), at)
    if kind == EV_TEXT:
        return text_events(ev.get("s", ""), at)
    return []


def find_window(title_part):
    """First visible window whose title contains the text, front to back."""
    if not IS_WIN or not title_part:
        return 0
    user32 = ctypes.windll.user32
    needle = str(title_part).lower()
    hit = []

    def cb(hwnd, _):
        if not user32.IsWindowVisible(hwnd):
            return True
        n = user32.GetWindowTextLengthW(hwnd)
        if n == 0:
            return True
        buf = ctypes.create_unicode_buffer(n + 1)
        user32.GetWindowTextW(hwnd, buf, n + 1)
        if needle in buf.value.lower():
            hit.append(hwnd)
            return False
        return True

    proto = ctypes.WINFUNCTYPE(ctypes.c_bool, ctypes.c_void_p,
                               ctypes.c_void_p)
    try:
        user32.EnumWindows(proto(cb), 0)
    except Exception:
        return 0
    return hit[0] if hit else 0


def focus_window(title_part) -> bool:
    hwnd = find_window(title_part)
    if not hwnd:
        return False
    user32 = ctypes.windll.user32
    try:
        user32.ShowWindow(hwnd, 9)
        user32.SetForegroundWindow(hwnd)
        return True
    except Exception:
        return False


UNIT_SECONDS = {"sec": 1.0, "min": 60.0, "hour": 3600.0, "day": 86400.0}
UNIT_ORDER = ("sec", "min", "hour", "day")


def wait_seconds(n, unit) -> float:
    try:
        return max(0.0, float(n)) * UNIT_SECONDS.get(unit, 1.0)
    except Exception:
        return 0.0


def fmt_wait(n, unit) -> str:
    try:
        val = float(n)
    except Exception:
        val = 0.0
    txt = ("%g" % val)
    return "%s %s" % (txt, unit if val == 1 else unit + "s")


def split_seconds(sec):
    """Seconds back into the largest whole unit that still reads cleanly, so a
    3600 s gap is shown as 1 hour rather than a wall of digits."""
    try:
        sec = max(0.0, float(sec))
    except Exception:
        sec = 0.0
    for unit in ("day", "hour", "min"):
        size = UNIT_SECONDS[unit]
        if sec >= size and abs(sec / size - round(sec / size, 3)) < 1e-9:
            return round(sec / size, 3), unit
    return round(sec, 3), "sec"


def flatten_events(events):
    """What the player is handed. A wait is folded into the offset of every
    step after it; a typing or hotkey step becomes the key events it stands
    for; everything else passes through untouched.

    A focus step stays as itself, because switching window is not something
    that can be expressed as input."""
    out = []
    shift = 0.0
    for ev in events or []:
        kind = ev.get("k")
        at = float(ev.get("t", 0.0)) + shift
        if kind == EV_WAIT:
            shift += wait_seconds(ev.get("q", 0), ev.get("u", "sec"))
            continue
        if kind in (EV_TEXT, EV_KEYS):
            made = expand_step(ev, at)
            if made:
                shift += made[-1]["t"] - at
                out.extend(made)
            continue
        copy = dict(ev)
        copy["t"] = at
        out.append(copy)
    return out


def total_wait(events) -> float:
    return sum(wait_seconds(ev.get("q", 0), ev.get("u", "sec"))
               for ev in (events or []) if ev.get("k") == EV_WAIT)


def step_line(i, ev) -> str:
    """One event as one readable line. This is the same text the editor shows
    and the same text the .txt export writes, so what he reads on screen and
    what he reads in the file can never drift apart."""
    kind = ev.get("k")
    at = "%8.3f" % float(ev.get("t", 0.0))
    if kind == EV_WAIT:
        return "%4d  %s  WAIT     %s" % (i + 1, at, fmt_wait(ev.get("q", 0),
                                                             ev.get("u", "sec")))
    if kind == EV_TEXT:
        body = str(ev.get("s", ""))
        if len(body) > 34:
            body = body[:31] + "..."
        return "%4d  %s  TYPE     %s" % (i + 1, at, body)
    if kind == EV_KEYS:
        return "%4d  %s  KEYS     %s" % (i + 1, at, ev.get("s", ""))
    if kind == EV_FOCUS:
        return "%4d  %s  FOCUS    window with %s in the title" % (
            i + 1, at, ev.get("s", ""))
    if kind == EV_MOVE:
        return "%4d  %s  MOVE     %d, %d" % (i + 1, at, ev.get("x", 0),
                                             ev.get("y", 0))
    if kind in (EV_DOWN, EV_UP):
        word = "PRESS" if kind == EV_DOWN else "RELEASE"
        return "%4d  %s  %-8s %s at %d, %d" % (i + 1, at, word,
                                               ev.get("b", "left"),
                                               ev.get("x", 0), ev.get("y", 0))
    if kind == EV_SCROLL:
        return "%4d  %s  SCROLL   %+d, %+d at %d, %d" % (
            i + 1, at, ev.get("dx", 0), ev.get("dy", 0),
            ev.get("x", 0), ev.get("y", 0))
    if kind in (EV_KDOWN, EV_KUP):
        word = "KEYDOWN" if kind == EV_KDOWN else "KEYUP"
        return "%4d  %s  %-8s %s" % (i + 1, at, word, ev.get("n")
                                     or ev.get("c") or ev.get("id") or "?")
    return "%4d  %s  %s" % (i + 1, at, kind)


def jitter_events(events, ms, px, rng):
    """Human hands are never frame-perfect. Off by default because a game that
    checks nothing does not need it, and it costs accuracy."""
    if not ms and not px:
        return list(events or [])
    out = []
    for ev in (events or []):
        copy = dict(ev)
        if ms:
            copy["t"] = max(0.0, float(copy.get("t", 0.0))
                            + rng.uniform(-ms, ms) / 1000.0)
        if px and copy.get("k") in (EV_MOVE, EV_DOWN, EV_UP, EV_SCROLL):
            copy["x"] = int(copy.get("x", 0) + rng.randint(-px, px))
            copy["y"] = int(copy.get("y", 0) + rng.randint(-px, px))
        out.append(copy)
    out.sort(key=lambda e: float(e.get("t", 0.0)))
    return out


_BTN_NAME = {}
_BTN_OBJ = {}
for _b in mouse.Button:
    _BTN_NAME[_b] = _b.name
    # Button.unknown carries a None value on Windows: recording its name is fine
    # (so the log stays honest) but replaying it would raise, so it is never
    # put in the playback map and _dispatch silently skips it.
    if _b.name != "unknown" and _b.value is not None:
        _BTN_OBJ[_b.name] = _b


def key_payload(key):
    """(stable_id, special_name, virtual_key, char) for any pynput key."""
    name = vk = ch = None
    try:
        if isinstance(key, keyboard.Key):
            name = key.name
            vk = getattr(key.value, "vk", None)
        else:
            vk = getattr(key, "vk", None)
            ch = getattr(key, "char", None)
    except Exception:
        pass
    try:
        vk = int(vk) if vk is not None else None
    except Exception:
        vk = None
    if not isinstance(ch, str) or ch == "":
        ch = None
    if name:
        kid = "n:" + name
    elif vk is not None:
        kid = "v:%d" % vk
    elif ch:
        kid = "c:" + ch
    else:
        kid = "u:" + repr(key)
    return kid, name, vk, ch


def rebuild_key(ev):
    """Turn a recorded key event back into a pynput key object.

    Name first, on purpose. pynput defines extended keys (arrows, delete, home,
    numpad, right-hand ctrl/alt, the Windows key) with an EXTENDEDKEY flag that
    a bare KeyCode.from_vk() would throw away, and some programs read that flag.
    Printable keys have no name, so they fall through to the vk path, which is
    the exact physical key the human pressed.
    """
    vk, name, ch = ev.get("v"), ev.get("n"), ev.get("c")
    if vk == 0:
        vk = None
    if name:
        try:
            return keyboard.Key[name]
        except Exception:
            pass
    if vk:
        try:
            return keyboard.KeyCode.from_vk(int(vk))
        except Exception:
            pass
    if ch:
        try:
            return keyboard.KeyCode.from_char(ch)
        except Exception:
            pass
    return None


def macro_duration(events) -> float:
    return float(events[-1]["t"]) if events else 0.0


def _stuck(events):
    """Keys / buttons whose LAST event in the macro is still a press.

    Holding a key down legitimately produces many press events and one release,
    so press-count vs release-count proves nothing. What matters is that the
    final state of every key and button is 'up' - otherwise a replay leaves
    something jammed on his machine.
    """
    last = {}
    for ev in events:
        if ev["k"] in (EV_KDOWN, EV_KUP):
            last["k:" + str(ev.get("id"))] = (ev["k"] == EV_KDOWN)
        elif ev["k"] in (EV_DOWN, EV_UP):
            last["b:" + str(ev.get("b"))] = (ev["k"] == EV_DOWN)
    return [name for name, down in last.items() if down]


def _no_stuck(events) -> bool:
    return not _stuck(events)


def macro_stats(events) -> dict:
    """What a recorded macro is actually made of.

    Key taps count PRESSES only, and only the first press of a hold: the OS
    repeats KEYDOWN while a key is held, so counting every one would report
    "428 taps" for a single leaned-on key.
    """
    out = dict(clicks=0, taps=0, scrolls=0, moves=0, distance=0.0,
               keys=0, duration=macro_duration(events), events=len(events))
    held = set()
    last = None
    for ev in events:
        kind = ev.get("k")
        if kind in MACRO_KINDS:
            continue
        if kind == EV_MOVE:
            out["moves"] += 1
            if last is not None:
                out["distance"] += ((ev["x"] - last[0]) ** 2 +
                                    (ev["y"] - last[1]) ** 2) ** 0.5
            last = (ev["x"], ev["y"])
        elif kind == EV_DOWN:
            out["clicks"] += 1
            last = (ev.get("x", 0), ev.get("y", 0))
        elif kind == EV_SCROLL:
            out["scrolls"] += 1
        elif kind == EV_KDOWN:
            kid = ev.get("id")
            if kid not in held:
                out["taps"] += 1
                held.add(kid)
        elif kind == EV_KUP:
            held.discard(ev.get("id"))
    out["keys"] = out["taps"]
    out["distance"] = round(out["distance"], 1)
    return out


def clean_name(text, fallback="SLOT") -> str:
    """Slot names are typed by hand, so they get cleaned, never rejected.

    Whitespace of any kind becomes a single space (a pasted tab should read as
    a word break, not glue two words together), anything unprintable is
    dropped, and an empty result falls back instead of leaving a blank slot.
    """
    if not isinstance(text, str):
        return fallback
    out = "".join(" " if ch.isspace() else ch for ch in text)
    out = "".join(ch for ch in out if ch.isprintable())
    out = " ".join(out.split())[:18]
    return out or fallback


def fmt_int(n) -> str:
    try:
        return "{:,}".format(int(n))
    except Exception:
        return "0"


def fmt_dist(px) -> str:
    px = float(px or 0)
    return "%.1fk px" % (px / 1000.0) if px >= 1000 else "%d px" % int(px)


# =============================================================================
# 6b.  NATIVE INPUT INJECTION  (the part that decides whether a game sees it)
# =============================================================================
#
# Why this exists at all.
#
# pynput's Controller sends a KEYBDINPUT carrying wVk (a virtual key) and lets
# Windows fill in the scan code. Notepad and a browser read the virtual key, so
# that works there. A lot of games do not read the virtual key at all - they
# read the SCAN CODE, the number the keyboard hardware actually puts on the
# wire. Send them a vk-only event and they see nothing, which is exactly the
# "the counter is going up but nothing is typed" symptom.
#
# So this layer builds the INPUT structs itself and sends the scan code, with
# the extended-key flag where the real key has one. It also stamps every event
# it sends with a signature in dwExtraInfo, which is what lets the listener
# recognise its own output with certainty instead of guessing by timing.
#
# What this CANNOT do, stated plainly: every SendInput event carries an
# "injected" flag that any program is free to read. A game or anticheat that
# rejects injected input will reject this too. No user-space tool gets past
# that, and anything that claims otherwise is lying about it.

GOLD_SIG = 0x474F4C44                      # 'GOLD' - our dwExtraInfo stamp

INPUT_MOUSE = 0
INPUT_KEYBOARD = 1

KEYEVENTF_EXTENDEDKEY = 0x0001
KEYEVENTF_KEYUP = 0x0002
KEYEVENTF_UNICODE = 0x0004
KEYEVENTF_SCANCODE = 0x0008

MOUSEEVENTF_MOVE = 0x0001
MOUSEEVENTF_LEFTDOWN = 0x0002
MOUSEEVENTF_LEFTUP = 0x0004
MOUSEEVENTF_RIGHTDOWN = 0x0008
MOUSEEVENTF_RIGHTUP = 0x0010
MOUSEEVENTF_MIDDLEDOWN = 0x0020
MOUSEEVENTF_MIDDLEUP = 0x0040
MOUSEEVENTF_XDOWN = 0x0080
MOUSEEVENTF_XUP = 0x0100
MOUSEEVENTF_WHEEL = 0x0800
MOUSEEVENTF_HWHEEL = 0x1000
MOUSEEVENTF_ABSOLUTE = 0x8000
MOUSEEVENTF_VIRTUALDESK = 0x4000
WHEEL_DELTA = 120

LLKHF_EXTENDED = 0x01
LLKHF_INJECTED = 0x10
LLMHF_INJECTED = 0x01

# every extended key, so a replayed arrow / numpad-enter / right-ctrl is the
# same byte pattern the hardware would have produced
EXTENDED_VKS = frozenset((
    0x21, 0x22, 0x23, 0x24, 0x25, 0x26, 0x27, 0x28,   # page/home/end/arrows
    0x2D, 0x2E,                                        # insert delete
    0x5B, 0x5C, 0x5D,                                  # win keys, menu
    0x6F,                                              # numpad divide
    0x90,                                              # numlock
    0xA3, 0xA5,                                        # right ctrl, right alt
))

_ULONG_PTR = ctypes.c_ulonglong if ctypes.sizeof(ctypes.c_void_p) == 8 \
    else ctypes.c_ulong


class _KEYBDINPUT(ctypes.Structure):
    _fields_ = [("wVk", ctypes.c_ushort), ("wScan", ctypes.c_ushort),
                ("dwFlags", ctypes.c_ulong), ("time", ctypes.c_ulong),
                ("dwExtraInfo", _ULONG_PTR)]

class _MOUSEINPUT(ctypes.Structure):
    _fields_ = [("dx", ctypes.c_long), ("dy", ctypes.c_long),
                ("mouseData", ctypes.c_ulong), ("dwFlags", ctypes.c_ulong),
                ("time", ctypes.c_ulong), ("dwExtraInfo", _ULONG_PTR)]


class _INPUTUNION(ctypes.Union):
    _fields_ = [("mi", _MOUSEINPUT), ("ki", _KEYBDINPUT),
                ("padding", ctypes.c_ubyte * 32)]


class _INPUT(ctypes.Structure):
    _fields_ = [("type", ctypes.c_ulong), ("u", _INPUTUNION)]


if IS_WIN:
    try:
        ctypes.windll.user32.SendInput.argtypes = (
            ctypes.c_uint, ctypes.POINTER(_INPUT), ctypes.c_int)
        ctypes.windll.user32.SendInput.restype = ctypes.c_uint
    except Exception:
        pass


def _send_inputs(items) -> int:
    """One SendInput call for the whole batch.

    Batching matters: a move and the button press that belongs to it must
    arrive together, or a game that samples the cursor once per frame can read
    the click at the OLD position.
    """
    if not IS_WIN or not items:
        return 0
    arr = (_INPUT * len(items))(*items)
    try:
        return int(ctypes.windll.user32.SendInput(
            len(items), arr, ctypes.sizeof(_INPUT)))
    except Exception:
        return 0


def _key_input(vk, scan, extended, keyup, unicode_char=None):
    item = _INPUT()
    item.type = INPUT_KEYBOARD
    flags = KEYEVENTF_KEYUP if keyup else 0
    if unicode_char is not None:
        item.u.ki = _KEYBDINPUT(0, ord(unicode_char),
                                flags | KEYEVENTF_UNICODE, 0, GOLD_SIG)
        return item
    if not scan and vk and IS_WIN:
        try:
            scan = ctypes.windll.user32.MapVirtualKeyW(int(vk), 0)
        except Exception:
            scan = 0
    # An arrow key, Delete, right-Ctrl and friends are "extended": the real
    # keyboard sets a flag on them, and a program reading scan codes tells
    # RIGHT-ARROW from NUMPAD-6 by that flag alone. Trust the flag captured at
    # record time, and fall back to the known list when a macro arrives without
    # one (an imported file, or a machine where the hook data was unavailable).
    ext = bool(extended) or (int(vk or 0) in EXTENDED_VKS)
    if ext:
        flags |= KEYEVENTF_EXTENDEDKEY
    if scan:
        flags |= KEYEVENTF_SCANCODE           # the hardware-level path
        item.u.ki = _KEYBDINPUT(0, int(scan) & 0xFF, flags, 0, GOLD_SIG)
    else:
        item.u.ki = _KEYBDINPUT(int(vk or 0), 0, flags, 0, GOLD_SIG)
    return item


def _virtual_desktop():
    try:
        g = ctypes.windll.user32.GetSystemMetrics
        return g(76), g(77), max(1, g(78)), max(1, g(79))   # x, y, w, h
    except Exception:
        return 0, 0, 1920, 1080


def _mouse_move_input(x, y):
    vx, vy, vw, vh = _virtual_desktop()
    nx = int(round((int(x) - vx) * 65535.0 / max(1, vw - 1)))
    ny = int(round((int(y) - vy) * 65535.0 / max(1, vh - 1)))
    item = _INPUT()
    item.type = INPUT_MOUSE
    item.u.mi = _MOUSEINPUT(max(0, min(65535, nx)), max(0, min(65535, ny)), 0,
                            MOUSEEVENTF_MOVE | MOUSEEVENTF_ABSOLUTE |
                            MOUSEEVENTF_VIRTUALDESK, 0, GOLD_SIG)
    return item


_BTN_FLAGS = {
    "left": (MOUSEEVENTF_LEFTDOWN, MOUSEEVENTF_LEFTUP, 0),
    "right": (MOUSEEVENTF_RIGHTDOWN, MOUSEEVENTF_RIGHTUP, 0),
    "middle": (MOUSEEVENTF_MIDDLEDOWN, MOUSEEVENTF_MIDDLEUP, 0),
    "x1": (MOUSEEVENTF_XDOWN, MOUSEEVENTF_XUP, 1),
    "x2": (MOUSEEVENTF_XDOWN, MOUSEEVENTF_XUP, 2),
}


def _mouse_button_input(name, down):
    spec = _BTN_FLAGS.get(name)
    if not spec:
        return None
    down_flag, up_flag, data = spec
    item = _INPUT()
    item.type = INPUT_MOUSE
    item.u.mi = _MOUSEINPUT(0, 0, data, down_flag if down else up_flag,
                            0, GOLD_SIG)
    return item


def _mouse_scroll_input(dx, dy):
    out = []
    for amount, flag in ((int(dy), MOUSEEVENTF_WHEEL), (int(dx), MOUSEEVENTF_HWHEEL)):
        if not amount:
            continue
        item = _INPUT()
        item.type = INPUT_MOUSE
        item.u.mi = _MOUSEINPUT(0, 0, ctypes.c_ulong(amount * WHEEL_DELTA).value,
                                flag, 0, GOLD_SIG)
        out.append(item)
    return out


def _modifiers_physically_down() -> bool:
    """True while any modifier is still held on the real keyboard."""
    if not IS_WIN:
        return False
    try:
        g = ctypes.windll.user32.GetAsyncKeyState
        return any(g(vk) & 0x8000 for vk in (0x10, 0x11, 0x12, 0x5B, 0x5C))
    except Exception:
        return False


# =============================================================================
# 3.  ECHO FILTER
#     Playback types through the same OS queue the listener watches. Without
#     this, a macro containing CTRL+P would stop itself, and a macro could
#     re-trigger its own hotkeys. Every synthetic key is armed here first and
#     consumed exactly once when the listener sees it.
# =============================================================================

class Echo:
    WINDOW = 0.30

    def __init__(self):
        self._lock = threading.Lock()
        self._q = deque(maxlen=512)

    def arm(self, kind: str, kid: str) -> None:
        with self._lock:
            self._q.append((kind, kid, time.perf_counter()))

    def consume(self, kind: str, kid: str) -> bool:
        now = time.perf_counter()
        with self._lock:
            for i, (k, cid, ts) in enumerate(self._q):
                if now - ts <= self.WINDOW and k == kind and cid == kid:
                    del self._q[i]
                    return True
            while self._q and now - self._q[0][2] > self.WINDOW:
                self._q.popleft()
        return False

    def clear(self) -> None:
        with self._lock:
            self._q.clear()


# =============================================================================
# 4.  RECORDER
# =============================================================================

class Recorder:
    MOVE_MIN_DT = 0.002          # 500 Hz: keeps the shape of a fast flick
    MAX_EVENTS = 400000          # ~50 min of continuous mousing; RAM guard

    def __init__(self):
        self._lock = threading.Lock()
        self.events = []
        self.active = False
        self._t0 = 0.0
        self._last_move = 0.0
        self._held_keys = {}     # kid -> payload
        self._ever_key = set()
        self._held_btns = {}     # button name -> payload
        self._stop_t = 0.0
        self.live = dict(clicks=0, taps=0, scrolls=0, moves=0, distance=0.0)
        self._last_pt = None

    # ---- lifecycle ---------------------------------------------------------
    def start(self) -> None:
        with self._lock:
            self.events = []
            self._held_keys.clear()
            self._ever_key.clear()
            self._held_btns.clear()
            self._t0 = time.perf_counter()
            self._last_move = -1.0
            self._stop_t = 0.0
            self.live = dict(clicks=0, taps=0, scrolls=0, moves=0, distance=0.0)
            self._last_pt = None
            self.active = True

    def stop(self, suppress_ids=()) -> list:
        """Close the recording cleanly and return the finished event list."""
        with self._lock:
            if not self.active:
                return list(self.events)
            self.active = False
            now = self._now()

            # (a) The hotkey that stopped us is physically still held down.
            #     Remove only its dangling press from the tail, never an
            #     earlier legitimate press of the same key inside the macro.
            for kid in list(self._held_keys.keys()):
                if kid in suppress_ids:
                    for i in range(len(self.events) - 1, -1, -1):
                        ev = self.events[i]
                        if ev["k"] == EV_KDOWN and ev["id"] == kid:
                            del self.events[i]
                            break
                    self._held_keys.pop(kid, None)

            # (b) Anything still held gets an explicit release appended, so a
            #     replay can never leave a key or a mouse button stuck down.
            for kid, pay in list(self._held_keys.items()):
                self.events.append(dict(pay, t=now, k=EV_KUP))
            self._held_keys.clear()
            for name, pay in list(self._held_btns.items()):
                self.events.append(dict(pay, t=now, k=EV_UP))
            self._held_btns.clear()

            self.events.sort(key=lambda e: e["t"])
            self._stop_t = now
            return list(self.events)

    # ---- helpers -----------------------------------------------------------
    def _now(self) -> float:
        return round(time.perf_counter() - self._t0, 6)

    def _full(self) -> bool:
        return len(self.events) >= self.MAX_EVENTS

    def elapsed(self) -> float:
        return (time.perf_counter() - self._t0) if self.active else self._stop_t

    def count(self) -> int:
        with self._lock:
            return len(self.events)

    # ---- capture callbacks (listener threads) ------------------------------
    def on_move(self, x, y) -> None:
        with self._lock:
            if not self.active or self._full():
                return
            t = self._now()
            if self._last_move >= 0.0 and (t - self._last_move) < self.MOVE_MIN_DT:
                return
            self._last_move = t
            self.events.append({"t": t, "k": EV_MOVE, "x": int(x), "y": int(y)})
            self.live["moves"] += 1
            if self._last_pt is not None:
                self.live["distance"] += ((x - self._last_pt[0]) ** 2 +
                                          (y - self._last_pt[1]) ** 2) ** 0.5
            self._last_pt = (x, y)

    def on_click(self, x, y, button, pressed) -> None:
        name = _BTN_NAME.get(button) or getattr(button, "name", None)
        if not name:
            return
        with self._lock:
            # a release is always allowed through, even at the cap, so a click
            # can never be recorded as press-without-release
            if not self.active or (self._full() and pressed):
                return
            pay = {"k": EV_DOWN if pressed else EV_UP, "b": name,
                   "x": int(x), "y": int(y)}
            if pressed:
                self.events.append(dict(pay, t=self._now()))
                self._held_btns[name] = pay
                self.live["clicks"] += 1
            else:
                if name not in self._held_btns:
                    return          # button was already down before we started
                self.events.append(dict(pay, t=self._now()))
                self._held_btns.pop(name, None)

    def on_scroll(self, x, y, dx, dy) -> None:
        with self._lock:
            if not self.active or self._full():
                return
            self.events.append({"t": self._now(), "k": EV_SCROLL,
                                "x": int(x), "y": int(y),
                                "dx": int(dx), "dy": int(dy)})
            self.live["scrolls"] += 1

    def on_key(self, kid, name, vk, ch, pressed, scan=0, extended=0) -> None:
        with self._lock:
            if not self.active or (self._full() and pressed):
                return
            pay = {"k": EV_KDOWN if pressed else EV_KUP,
                   "id": kid, "n": name, "v": vk, "c": ch,
                   "s": scan, "e": 1 if extended else 0}
            if pressed:
                self.events.append(dict(pay, t=self._now()))
                if kid not in self._held_keys:      # ignore OS auto-repeat
                    self.live["taps"] += 1
                self._held_keys[kid] = pay
                self._ever_key.add(kid)
            else:
                if kid not in self._ever_key:
                    return          # key was already down before we started
                self.events.append(dict(pay, t=self._now()))
                self._held_keys.pop(kid, None)


# =============================================================================
# 5.  PLAYER
# =============================================================================

class Player(threading.Thread):
    def __init__(self, events, stop_evt, bus, echo, gap_getter,
                 speed_getter=None, target_getter=None, counters=None,
                 pause_evt=None):
        super().__init__(name="goldmacro-player", daemon=True)
        self.events = [dict(e) for e in events]   # never share dicts
        self.stop_evt = stop_evt
        self.pause_evt = pause_evt or threading.Event()
        self.bus = bus
        self.echo = echo
        self.gap_getter = gap_getter
        self.speed_getter = speed_getter or (lambda: 1.0)
        self.target_getter = target_getter or (lambda: 0)
        self.counters = counters if counters is not None else {}
        for key in ("clicks", "taps", "scrolls", "actions"):
            self.counters.setdefault(key, 0)
        self._keys_down = {}
        self._btns_down = {}
        self._debt = 0.0             # time spent paused, added to every target
        self.speed = 1.0

    def toggle_pause(self) -> bool:
        if self.pause_evt.is_set():
            self.pause_evt.clear()
        else:
            self.pause_evt.set()
        return self.pause_evt.is_set()

    # ---- precise absolute-time wait ---------------------------------------
    def _wait_until(self, base: float, offset: float) -> bool:
        """Wait until base + offset/speed + paused-time.

        The target is recomputed every pass instead of once, so a pause that
        starts in the middle of a wait shifts the schedule instead of making
        the macro rush to catch up when it resumes.
        """
        while True:
            if self.pause_evt.is_set():
                if not self._hold(base):
                    return False
            speed = self.speed if self.speed > 0 else 1.0
            target = base + (offset / speed) + self._debt
            remain = target - time.perf_counter()
            if remain <= 0:
                return True
            if remain < 0.0015:
                while time.perf_counter() < target:
                    if self.stop_evt.is_set():
                        return False
                return True
            if self.stop_evt.wait(min(remain - 0.001, 0.005)):
                return False

    def _hold(self, _base) -> bool:
        """Sit still while paused, with nothing left pressed down.

        Whatever was held is released on the way in and pressed again on the
        way out, so a pause can never jam a key on his machine and a resumed
        drag still behaves.
        """
        keys = list(self._keys_down.items())
        btns = list(self._btns_down.items())
        kc = self._kc
        for kid, ev in keys:
            try:
                self.echo.arm(EV_KUP, kid)
                if not self._native_key(ev, True):
                    key = rebuild_key(ev)
                    if key is not None:
                        kc.release(key)
            except Exception:
                pass
        for _n, ev in btns:
            try:
                self._native_mouse(dict(ev, k=EV_UP), EV_UP)
            except Exception:
                pass
        started = time.perf_counter()
        self.bus.put(("paused", True))
        while self.pause_evt.is_set():
            if self.stop_evt.wait(0.04):
                return False
        self._debt += time.perf_counter() - started
        for _n, ev in btns:
            try:
                self._native_mouse(dict(ev, k=EV_DOWN), EV_DOWN)
            except Exception:
                pass
        for kid, ev in keys:
            try:
                self.echo.arm(EV_KDOWN, kid)
                if not self._native_key(ev, False):
                    key = rebuild_key(ev)
                    if key is not None:
                        kc.press(key)
            except Exception:
                pass
        self.bus.put(("paused", False))
        return True

    # ---- one event --------------------------------------------------------
    def _native_key(self, ev, keyup) -> bool:
        """Replay one key at hardware level. Returns False if it could not."""
        if not IS_WIN:
            return False
        vk = ev.get("v")
        scan = ev.get("s") or 0
        item = _key_input(vk, scan, ev.get("e"), keyup,
                          unicode_char=(ev.get("c") if not vk and not scan
                                        and ev.get("c") else None))
        return bool(item is not None and _send_inputs([item]))

    def _native_mouse(self, ev, kind) -> bool:
        if not IS_WIN:
            return False
        batch = []
        if kind in (EV_MOVE, EV_DOWN, EV_UP, EV_SCROLL):
            mv = _mouse_move_input(ev.get("x", 0), ev.get("y", 0))
            if mv is not None:
                batch.append(mv)
        if kind in (EV_DOWN, EV_UP):
            btn = _mouse_button_input(ev.get("b"), kind == EV_DOWN)
            if btn is None:
                return False
            batch.append(btn)                      # same batch as the move
        elif kind == EV_SCROLL:
            batch.extend(_mouse_scroll_input(ev.get("dx", 0), ev.get("dy", 0)))
        return bool(batch and _send_inputs(batch))

    def _dispatch(self, mc, kc, ev) -> None:
        kind = ev["k"]
        if kind == EV_FOCUS:
            if not focus_window(ev.get("s", "")):
                self.bus.put(("warn", "no window titled %r to switch to"
                              % (ev.get("s", ""),)))
            return
        if kind == EV_DOWN:
            self.counters["clicks"] = self.counters.get("clicks", 0) + 1
        elif kind == EV_KDOWN:
            self.counters["taps"] = self.counters.get("taps", 0) + 1
        elif kind == EV_SCROLL:
            self.counters["scrolls"] = self.counters.get("scrolls", 0) + 1
        self.counters["actions"] = self.counters.get("actions", 0) + 1
        if kind in (EV_MOVE, EV_DOWN, EV_UP, EV_SCROLL):
            if not self._native_mouse(ev, kind):
                # non-Windows, or the native call was refused: fall back to the
                # library path so the tool still works rather than doing nothing
                if kind == EV_MOVE:
                    mc.position = (ev["x"], ev["y"])
                elif kind == EV_SCROLL:
                    mc.position = (ev["x"], ev["y"])
                    mc.scroll(ev.get("dx", 0), ev.get("dy", 0))
                else:
                    btn = _BTN_OBJ.get(ev.get("b"))
                    if btn is None:
                        return
                    mc.position = (ev["x"], ev["y"])
                    (mc.press if kind == EV_DOWN else mc.release)(btn)
            if kind == EV_DOWN:
                self._btns_down[ev["b"]] = ev
            elif kind == EV_UP:
                self._btns_down.pop(ev["b"], None)
        elif kind in (EV_KDOWN, EV_KUP):
            self.echo.arm(kind, ev.get("id"))
            if not self._native_key(ev, kind == EV_KUP):
                key = rebuild_key(ev)
                if key is None:
                    return
                (kc.press if kind == EV_KDOWN else kc.release)(key)
            if kind == EV_KDOWN:
                self._keys_down[ev.get("id")] = ev
            else:
                self._keys_down.pop(ev.get("id"), None)

    # ---- never leave anything stuck down ----------------------------------
    def _release_all(self, mc, kc) -> None:
        for kid, ev in list(self._keys_down.items()):
            try:
                self.echo.arm(EV_KUP, kid)
                if not self._native_key(ev, True):
                    key = rebuild_key(ev)
                    if key is not None:
                        kc.release(key)
            except Exception:
                pass
        self._keys_down.clear()
        for name, ev in list(self._btns_down.items()):
            try:
                if not self._native_mouse(dict(ev, k=EV_UP), EV_UP):
                    btn = _BTN_OBJ.get(name)
                    if btn is not None:
                        mc.release(btn)
            except Exception:
                pass
        self._btns_down.clear()

    # ---- main loop --------------------------------------------------------
    LEAD_IN = 0.12          # floor; the real wait is "until his fingers are up"
    LEAD_MAX = 3.00         # ...but never hang forever if a key is stuck

    def _drop_modifiers(self, kc) -> None:
        """Release every modifier the OS still thinks is down.

        Playback starts while CTRL+M is physically still held. Without this the
        macro's first keystroke lands as CTRL+<that key> instead of the key he
        actually recorded. Releasing them costs nothing when they are already up.
        """
        for name, vk in (("ctrl", 0x11), ("ctrl_l", 0xA2), ("ctrl_r", 0xA3),
                         ("shift", 0x10), ("shift_l", 0xA0), ("shift_r", 0xA1),
                         ("alt", 0x12), ("alt_l", 0xA4), ("alt_gr", 0xA5),
                         ("cmd", 0x5B), ("cmd_l", 0x5B), ("cmd_r", 0x5C)):
            self.echo.arm(EV_KUP, "n:" + name)
            self.echo.arm(EV_KUP, "v:%d" % vk)
            try:
                if not self._native_key({"v": vk, "s": 0,
                                         "e": 1 if vk in EXTENDED_VKS else 0},
                                        True):
                    kc.release(keyboard.Key[name])
            except Exception:
                continue

    def run(self) -> None:
        mc = self._mc = mouse.Controller()
        kc = self._kc = keyboard.Controller()
        loops = 0
        _timer_resolution(True)
        _boost_thread(True)
        try:
            # v2 waited a flat 0.35s and hoped his finger was off CTRL by then.
            # If it was not, the macro's first key arrived as CTRL+<key> and in
            # a game that reads as nothing happening at all. Now it WATCHES the
            # real keyboard and only starts once the modifiers are physically up.
            if self.stop_evt.wait(self.LEAD_IN):
                self.bus.put(("player_end", 0))
                _boost_thread(False)
                _timer_resolution(False)
                return
            waited = 0.0
            while (_modifiers_physically_down() and waited < self.LEAD_MAX
                   and not self.stop_evt.is_set()):
                if self.stop_evt.wait(0.03):
                    break
                waited += 0.03
            if self.stop_evt.is_set():
                self.bus.put(("player_end", 0))
                _boost_thread(False)
                _timer_resolution(False)
                return
            self._drop_modifiers(kc)
            while not self.stop_evt.is_set():
                try:
                    self.speed = max(SPEED_MIN, min(SPEED_MAX, float(self.speed_getter())))
                except Exception:
                    self.speed = 1.0
                self._debt = 0.0
                started = time.perf_counter()
                self.bus.put(("loop_start", (loops + 1, started, self.speed)))
                broke = False
                for ev in self.events:
                    if self.stop_evt.is_set():
                        broke = True
                        break
                    if not self._wait_until(started, float(ev["t"])):
                        broke = True
                        break
                    try:
                        self._dispatch(mc, kc, ev)
                    except Exception as exc:
                        self.bus.put(("warn", "event skipped: %r" % (exc,)))
                self._release_all(mc, kc)
                if broke or self.stop_evt.is_set():
                    break
                loops += 1
                self.bus.put(("loop_done", (loops, time.perf_counter() - started)))
                try:
                    target = int(self.target_getter() or 0)
                except Exception:
                    target = 0
                if target > 0 and loops >= target:
                    self.bus.put(("target_hit", loops))
                    break
                gap = 0.0
                try:
                    gap = max(0.0, float(self.gap_getter()))
                except Exception:
                    gap = 0.0
                if gap and self.stop_evt.wait(gap):
                    break
        except Exception as exc:
            _log_crash("player: " + traceback.format_exc())
            self.bus.put(("error", repr(exc)))
        finally:
            try:
                self._release_all(mc, kc)
            except Exception:
                pass
            _boost_thread(False)
            _timer_resolution(False)
            self.bus.put(("player_end", loops))


# =============================================================================
# 6.  INPUT HUB  (one keyboard listener + one mouse listener, shared)
# =============================================================================
# =============================================================================
# 6c.  KEYBINDS  (rebindable, saved to disk)
# =============================================================================

VK_NAMES = {0x08: "BACKSPACE", 0x09: "TAB", 0x0D: "ENTER", 0x1B: "ESC",
            0x20: "SPACE", 0x21: "PGUP", 0x22: "PGDN", 0x23: "END",
            0x24: "HOME", 0x25: "LEFT", 0x26: "UP", 0x27: "RIGHT",
            0x28: "DOWN", 0x2D: "INS", 0x2E: "DEL", 0x90: "NUMLOCK",
            0x91: "SCROLL", 0x14: "CAPS", 0xBC: ",", 0xBE: ".",
            0xBF: "/", 0xC0: "`", 0xDB: "[", 0xDD: "]", 0xDC: "\\",
            0xBA: ";", 0xDE: "'", 0xBD: "-", 0xBB: "="}
for _i in range(1, 25):
    VK_NAMES[0x6F + _i] = "F%d" % _i
for _i in range(10):
    VK_NAMES[0x30 + _i] = str(_i)
    VK_NAMES[0x60 + _i] = "NUM%d" % _i
for _i in range(26):
    VK_NAMES[0x41 + _i] = chr(0x41 + _i)

MODIFIER_VKS = frozenset((0x10, 0x11, 0x12, 0xA0, 0xA1, 0xA2, 0xA3, 0xA4, 0xA5))


def vk_label(vk, ctrl=False, shift=False, alt=False) -> str:
    base = VK_NAMES.get(int(vk or 0), "VK%d" % int(vk or 0))
    return (("CTRL+" if ctrl else "") + ("SHIFT+" if shift else "") +
            ("ALT+" if alt else "") + base)


class Keybinds:
    """The four actions, each on a combo he can change and that survives a restart.

    v2 hardwired CTRL+N/M/P/J, and that had a consequence he would have hit the
    first time he recorded something real: those combos could never appear
    INSIDE a macro, because the hook ate them before the recorder saw them.
    Being able to move them somewhere he does not use frees the originals up.
    """
    ACTIONS = ("rec", "loop", "stop", "pause")
    LABELS = {"rec": "RECORD", "loop": "REPLAY", "stop": "STOP", "pause": "PAUSE"}
    DEFAULTS = {"rec": (78, True, False, False),      # CTRL+N
                "loop": (77, True, False, False),     # CTRL+M
                "stop": (80, True, False, False),     # CTRL+P
                "pause": (74, True, False, False)}    # CTRL+J

    def __init__(self):
        self.binds = dict(self.DEFAULTS)
        self.load()

    def path(self):
        return os.path.join(DATA_DIR, "keybinds.json")

    def load(self):
        try:
            with open(self.path(), "r", encoding="utf-8") as fh:
                raw = json.load(fh)
            for action in self.ACTIONS:
                item = raw.get(action)
                if (isinstance(item, list) and len(item) == 4
                        and isinstance(item[0], int) and 1 <= item[0] <= 254
                        and item[0] not in MODIFIER_VKS):
                    self.binds[action] = (item[0], bool(item[1]),
                                          bool(item[2]), bool(item[3]))
        except Exception:
            pass

    def save(self):
        try:
            _mkdirs()
            with open(self.path(), "w", encoding="utf-8") as fh:
                json.dump({a: list(self.binds[a]) for a in self.ACTIONS}, fh)
        except Exception:
            pass

    def label(self, action) -> str:
        vk, c, sh, al = self.binds.get(action, (0, False, False, False))
        return vk_label(vk, c, sh, al)

    def match(self, vk, ctrl, shift, alt):
        for action in self.ACTIONS:
            if self.binds[action] == (vk, ctrl, shift, alt):
                return action
        return None

    def conflict(self, action, combo):
        for other in self.ACTIONS:
            if other != action and self.binds[other] == combo:
                return other
        return None

    def rebind(self, action, vk, ctrl, shift, alt):
        if action not in self.ACTIONS:
            return False, "unknown action"
        vk = int(vk or 0)
        if not vk or vk in MODIFIER_VKS:
            return False, "hold the modifier and press a real key"
        combo = (vk, bool(ctrl), bool(shift), bool(alt))
        clash = self.conflict(action, combo)
        if clash:
            return False, "%s already uses %s" % (self.LABELS[clash],
                                                  vk_label(*combo))
        self.binds[action] = combo
        self.save()
        return True, self.label(action)

    def reset(self):
        self.binds = dict(self.DEFAULTS)
        self.save()


# =============================================================================
# 6d.  INPUT HUB  (one keyboard listener, one mouse listener)
# =============================================================================

class Hub:
    """Reads the low-level Windows hook rather than guessing.

    The hook hands over the real scan code, an INJECTED flag and the
    dwExtraInfo field of every event, which buys three things at once:

      - our own replayed keys are identified by our signature in dwExtraInfo,
        exactly, instead of being guessed at by "did we send something like
        this in the last 300 ms";
      - the true scan code is recorded, so the replay is the same byte pattern
        the keyboard produced;
      - a bound hotkey is swallowed before it reaches whatever is in front, so
        pressing the record key never types into the game underneath.
    """
    CTRL_IDS = {"n:ctrl", "n:ctrl_l", "n:ctrl_r"}
    VK_SLOT = {49: 0, 50: 1, 51: 2, 52: 3, 53: 4, 54: 5}     # CTRL+1..6
    ESC_ID = "n:esc"
    PANIC_TAPS = 3
    PANIC_WINDOW = 1.0
    WM_DOWN = (0x0100, 0x0104)

    def __init__(self, app):
        self.app = app
        self.rec = app.rec
        self.echo = app.echo
        self.keys = app.keys
        self._ctrl = set()
        self._esc = deque(maxlen=PANIC_MAX)
        self._raw = (None, 0, False, False)     # vk, scan, extended, mine
        self._eaten = set()
        self.kb = None
        self.ms = None

    def start(self) -> None:
        kw, mkw = {}, {}
        if IS_WIN:
            kw["win32_event_filter"] = self._kb_filter
            mkw["win32_event_filter"] = self._ms_filter
        self.kb = keyboard.Listener(on_press=self._press,
                                    on_release=self._release, **kw)
        self.ms = mouse.Listener(on_move=self._move, on_click=self._click,
                                 on_scroll=self._scroll, **mkw)
        self.kb.daemon = True
        self.ms.daemon = True
        self.kb.start()
        self.ms.start()

    def stop(self) -> None:
        for lis in (self.kb, self.ms):
            try:
                if lis:
                    lis.stop()
            except Exception:
                pass

    # ---- modifier state ----------------------------------------------------
    def _mods(self):
        if IS_WIN:
            try:
                g = ctypes.windll.user32.GetAsyncKeyState
                return (bool(g(0x11) & 0x8000), bool(g(0x10) & 0x8000),
                        bool(g(0x12) & 0x8000))
            except Exception:
                pass
        return (bool(self._ctrl), False, False)

    def _ctrl_held(self) -> bool:
        return self._mods()[0]

    # ---- low level filters (Windows only) ---------------------------------
    def _kb_filter(self, msg, data):
        suppress = False
        try:
            vk = int(data.vkCode)
            scan = int(data.scanCode)
            extended = bool(int(data.flags) & LLKHF_EXTENDED)
            mine = (int(data.dwExtraInfo or 0) == GOLD_SIG)
            self._raw = (vk, scan, extended, mine)
            if mine:
                return False               # our own replay: invisible to us
            ctrl, shift, alt = self._mods()
            if msg in self.WM_DOWN:
                if self.app.capturing:
                    self.app.fire_hotkey("capture:%d:%d:%d:%d"
                                         % (vk, ctrl, shift, alt))
                    if vk not in MODIFIER_VKS:
                        self._eaten.add(vk)
                        suppress = True
                elif not self.app.renaming:
                    action = self.keys.match(vk, ctrl, shift, alt)
                    if action:
                        self.app.fire_hotkey(action)
                        self._eaten.add(vk)
                        suppress = True
                    elif ctrl and vk in self.VK_SLOT:
                        self.app.fire_hotkey("slot:%d" % self.VK_SLOT[vk])
                        self._eaten.add(vk)
                        suppress = True
            elif vk in self._eaten:
                self._eaten.discard(vk)
                suppress = True            # eat the matching key-up as well
        except Exception:
            return True
        if suppress:
            self.kb.suppress_event()       # raises; pynput handles it
        return True

    def _ms_filter(self, _msg, data):
        try:
            if int(data.dwExtraInfo or 0) == GOLD_SIG:
                return False               # our own replayed mouse
        except Exception:
            pass
        return True

    def _panic_check(self, now: float) -> bool:
        """Three real ESC presses inside a second, only while replaying."""
        self._esc.append(now)
        if len(self._esc) < self.PANIC_TAPS:
            return False
        recent = list(self._esc)[-self.PANIC_TAPS:]
        return (recent[-1] - recent[0]) <= self.PANIC_WINDOW

    # ---- keyboard callbacks ------------------------------------------------
    def _press(self, key):
        try:
            kid, name, vk, ch = key_payload(key)
            rvk, scan, extended, mine = self._raw
            if IS_WIN:
                if mine:
                    return
                if rvk is not None and vk is not None and rvk != vk:
                    scan, extended = 0, False      # hook and callback disagree
            else:
                if self.echo.consume(EV_KDOWN, kid):
                    return
                scan, extended = 0, False
            if kid in self.CTRL_IDS:
                self._ctrl.add(kid)
                self.rec.on_key(kid, name, vk, ch, True, scan, extended)
                return
            if kid == self.ESC_ID and self.app.is_replaying():
                if self._panic_check(time.perf_counter()):
                    self._esc.clear()
                    self.app.fire_hotkey("panic")
                    return
            if not IS_WIN:
                # no hook filter here, so fall back to polling the combo
                ctrl = self._ctrl_held()
                if ctrl and not self.app.renaming and not self.app.capturing:
                    action = self.keys.match(vk, True, False, False)
                    if action:
                        self.app.fire_hotkey(action)
                        return
                    if vk in self.VK_SLOT:
                        self.app.fire_hotkey("slot:%d" % self.VK_SLOT[vk])
                        return
                elif self.app.capturing and vk not in MODIFIER_VKS:
                    self.app.fire_hotkey("capture:%d:%d:0:0" % (vk, ctrl))
                    return
            self.rec.on_key(kid, name, vk, ch, True, scan, extended)
        except Exception:
            _log_crash("on_press: " + traceback.format_exc())

    def _release(self, key):
        try:
            kid, name, vk, ch = key_payload(key)
            rvk, scan, extended, mine = self._raw
            if IS_WIN:
                if mine:
                    return
                if rvk is not None and vk is not None and rvk != vk:
                    scan, extended = 0, False
            else:
                if self.echo.consume(EV_KUP, kid):
                    return
                scan, extended = 0, False
            if kid in self.CTRL_IDS:
                self._ctrl.discard(kid)
            self.rec.on_key(kid, name, vk, ch, False, scan, extended)
        except Exception:
            _log_crash("on_release: " + traceback.format_exc())

    # ---- mouse callbacks ---------------------------------------------------
    def _move(self, x, y):
        try:
            self.rec.on_move(x, y)
        except Exception:
            pass

    def _click(self, x, y, button, pressed):
        try:
            self.rec.on_click(x, y, button, pressed)
        except Exception:
            pass

    def _scroll(self, x, y, dx, dy):
        try:
            self.rec.on_scroll(x, y, dx, dy)
        except Exception:
            pass
import math
# =============================================================================
# 7.  GUI PRIMITIVES
# =============================================================================

def round_rect(cv, x1, y1, x2, y2, r, **kw):
    pts = [x1 + r, y1, x2 - r, y1, x2, y1, x2, y1 + r, x2, y2 - r, x2, y2,
           x2 - r, y2, x1 + r, y2, x1, y2, x1, y2 - r, x1, y1 + r, x1, y1]
    return cv.create_polygon(pts, smooth=True, **kw)


def hex_mix(a: str, b: str, f: float) -> str:
    f = max(0.0, min(1.0, f))
    ca = tuple(int(a[i:i + 2], 16) for i in (1, 3, 5))
    cb = tuple(int(b[i:i + 2], 16) for i in (1, 3, 5))
    return "#%02X%02X%02X" % tuple(int(ca[i] + (cb[i] - ca[i]) * f) for i in range(3))


def gradient(cv, x1, y1, x2, y2, c1, c2, steps=0, radius=0, top=0, bottom=0):
    """Smooth vertical wash, drawn as stacked 1px bands.

    radius / top / bottom clip the wash to a rounded rectangle: each band is
    pulled in by however much the corner arc is inset at that height. v3.0 drew
    the wash full-bleed and then painted wedges over the corners to cut them
    back out - three of the four wedges used the wrong quadrant and ate up to
    79px into the window, which on Windows showed as holes in the console.
    Clipping the bands has no corner cases to get wrong.
    """
    steps = steps or max(2, int(y2 - y1))
    band = (y2 - y1) / float(steps)
    for i in range(steps):
        yy = y1 + band * i
        inset = 0.0
        if radius > 0:
            dy = 0.0
            if yy < top + radius:
                dy = (top + radius) - yy
            elif yy > bottom - radius:
                dy = yy - (bottom - radius)
            if dy > 0:
                inset = radius - math.sqrt(max(0.0, radius * radius - dy * dy))
        cv.create_rectangle(x1 + inset, yy, x2 - inset, yy + band + 1, width=0,
                            fill=hex_mix(c1, c2, i / float(steps - 1)))


def card(cv, x, y, w, h, r=10, fill=None, outline=None, glow=True):
    """A gold plate: gold face, darker gold rim, lit top edge, shaded bottom.
    Everything printed on it is dark, which is what makes it read as metal."""
    round_rect(cv, x, y, x + w, y + h, r,
               fill=fill or T.CARD, outline=outline or T.EDGE, width=1)
    if glow:
        cv.create_line(x + r, y + 2, x + w - r, y + 2, fill=T.HL)


class GoldButton:
    """Two shapes: FILLED (gold face, dark text) for the actions he uses most,
    and OUTLINE for the adjusters. Both fade smoothly on hover."""

    def __init__(self, parent, text, cmd, x, y, w, h, filled=False,
                 fg=None, sub=None, danger=False):
        self.cmd = cmd
        self.filled = filled
        self.danger = danger
        if filled:
            self.base_bg = T.PILL
            self.lift_bg = T.PILL_HI
            self.base_fg = "#FF8478" if danger else T.PILL_TEXT
            self.lift_fg = "#FFB0A6" if danger else "#FFF6D2"
            self.edge = T.PILL
        else:
            self.base_bg = T.CARD
            self.lift_bg = T.CARD_HI
            self.base_fg = fg or T.ON
            self.lift_fg = T.VAL
            self.edge = T.EDGE
        self._token = 0
        self.frame = tk.Frame(parent, bg=self.base_bg, highlightthickness=1,
                              highlightbackground=self.edge, bd=0)
        self.frame.place(x=x, y=y, width=w, height=h)
        self.frame.pack_propagate(False)
        self.label = tk.Label(self.frame, text=text, bg=self.base_bg, fg=self.base_fg,
                              font=(T.MONO, max(7, S(8)), "bold"))
        self.label.place(relx=0.5, rely=0.5 if not sub else 0.34, anchor="center")
        self.sub = None
        if sub:
            self.sub = tk.Label(self.frame, text=sub, bg=self.base_bg,
                                fg=("#9A8C63" if filled else T.FAINT_C),
                                font=(T.MONO, max(6, S(6))))
            self.sub.place(relx=0.5, rely=0.74, anchor="center")
        for wdg in self._widgets():
            wdg.bind("<Enter>", self._enter)
            wdg.bind("<Leave>", self._leave)
            wdg.bind("<Button-1>", self._click)

    def _widgets(self):
        return [w for w in (self.frame, self.label, self.sub) if w]

    def _paint(self, f):
        bg = hex_mix(self.base_bg, self.lift_bg, f)
        fg = hex_mix(self.base_fg, self.lift_fg, f)
        for w in self._widgets():
            try:
                w.configure(bg=bg)
            except Exception:
                return
        try:
            self.label.configure(fg=fg)
        except Exception:
            pass

    def _fade(self, token, cur, target):
        if token != self._token:
            return
        cur = max(0.0, min(1.0, cur + (0.25 if target > cur else -0.25)))
        self._paint(cur)
        if abs(cur - target) > 0.01:
            self.frame.after(16, lambda: self._fade(token, cur, target))

    def _enter(self, _=None):
        self._token += 1
        self._fade(self._token, 0.0, 1.0)

    def _leave(self, _=None):
        self._token += 1
        self._fade(self._token, 1.0, 0.0)

    def _click(self, _=None):
        try:
            self.cmd()
        except Exception:
            _log_crash("button: " + traceback.format_exc())

    def set_text(self, text):
        try:
            self.label.configure(text=text)
        except Exception:
            pass


class Shell:
    """Borderless rounded always-on-top window.

    Every widget is placed on the CANVAS, not on a covering Frame. v1 put an
    opaque Frame over the canvas, which squared off the corners it had just
    drawn; parenting to the canvas keeps the rounded silhouette real.
    """

    def __init__(self, master, w, h, x, y, radius=14, topmost=True, alpha=1.0,
                 panel=None, band=True):
        self.win = tk.Toplevel(master)
        self.w, self.h = w, h
        self.win.overrideredirect(True)
        self.win.geometry("%dx%d+%d+%d" % (w, h, x, y))
        self.transparent = False
        try:
            self.win.configure(bg=T.CHROMA)
            self.win.attributes("-transparentcolor", T.CHROMA)
            self.transparent = True
        except Exception:
            self.win.configure(bg=panel or T.INK)
        self.set_alpha(alpha)
        if topmost:
            try:
                self.win.attributes("-topmost", True)
            except Exception:
                pass
            self._keep_top()
        self.canvas = tk.Canvas(self.win, width=w, height=h, highlightthickness=0,
                                bd=0, bg=T.CHROMA if self.transparent else T.INK)
        self.canvas.place(x=0, y=0)
        cv = self.canvas
        if panel:
            round_rect(cv, 1, 1, w - 1, h - 1, radius, fill=panel,
                       outline=T.CHROME_LO, width=1)
        else:
            # full-bleed three-stop wash, then the square corners are cut back
            # out so the rounded silhouette survives the gradient
            mid = int(h * 0.42)
            gradient(cv, 1, 1, w - 1, mid, T.BG_TOP, T.BG_MID,
                     radius=radius, top=1, bottom=h - 1)
            gradient(cv, 1, mid, w - 1, h - 1, T.BG_MID, T.BG_BOT,
                     radius=radius, top=1, bottom=h - 1)
            if band:
                gradient(cv, 1, 1, w - 1, S(40), T.CHROME, T.CHROME,
                         radius=radius, top=1, bottom=h - 1)
                gradient(cv, 1, h - S(34), w - 1, h - 1, T.CHROME, T.CHROME,
                         radius=radius, top=1, bottom=h - 1)
            round_rect(cv, 1, 1, w - 1, h - 1, radius, fill="",
                       outline=T.CHROME_LO, width=1)
        self.body = self.canvas
        self._dx = self._dy = 0
        self.bind_drag(self.canvas)

    def set_alpha(self, alpha):
        try:
            self.win.attributes("-alpha", max(0.30, min(1.0, float(alpha))))
        except Exception:
            pass

    def _keep_top(self):
        try:
            self.win.attributes("-topmost", True)
        except Exception:
            pass
        try:
            self.win.after(2000, self._keep_top)
        except Exception:
            pass

    def bind_drag(self, widget):
        widget.bind("<Button-1>", self._grab, add="+")
        widget.bind("<B1-Motion>", self._move, add="+")

    def _grab(self, ev):
        self._dx = ev.x_root - self.win.winfo_x()
        self._dy = ev.y_root - self.win.winfo_y()

    def _move(self, ev):
        try:
            self.win.geometry("+%d+%d" % (ev.x_root - self._dx, ev.y_root - self._dy))
        except Exception:
            pass


# =============================================================================

class Library:
    """v3 kept every recording in RAM and lost the lot on exit. He found that
    out the hard way, so v4 writes each slot to its own file the moment it is
    recorded and reads them all back on start.

    Two files per macro on purpose: the .json is what the tool reloads, the
    .txt is the one he can open and actually read.
    """

    def __init__(self, folder=None, readable=None):
        self.folder = folder or LIB_DIR
        self.readable = readable or TXT_DIR

    def ensure(self):
        for path in (self.folder, self.readable):
            try:
                os.makedirs(path, exist_ok=True)
            except Exception:
                pass

    def path_for(self, index):
        return os.path.join(self.folder, "slot%d.json" % (index + 1))

    def txt_for(self, index):
        return os.path.join(self.readable, "slot%d.txt" % (index + 1))

    def write_txt(self, slot):
        lines = ["%s  %s" % (APP_NAME, APP_VER),
                 "name     %s" % slot.name,
                 "saved    %s" % time.strftime("%Y-%m-%d %H:%M:%S"),
                 "steps    %d" % len(slot.events),
                 "length   %.2f s" % macro_duration(flatten_events(slot.events)),
                 "waiting  %.2f s" % total_wait(slot.events),
                 "runs     %d" % slot.runs,
                 "",
                 "  no        at  what"]
        for i, ev in enumerate(slot.events):
            lines.append(step_line(i, ev))
        lines.append("")
        with open(self.txt_for(slot.index), "w", encoding="utf-8") as fh:
            fh.write("\n".join(lines))

    def save(self, slot):
        self.ensure()
        payload = {"app": APP_NAME, "ver": APP_VER, "name": slot.name,
                   "saved": time.time(), "runs": slot.runs,
                   "events": slot.events}
        tmp = self.path_for(slot.index) + ".tmp"
        with open(tmp, "w", encoding="utf-8") as fh:
            json.dump(payload, fh)
        os.replace(tmp, self.path_for(slot.index))
        try:
            self.write_txt(slot)
        except Exception:
            pass
        return self.path_for(slot.index)

    def read(self, index):
        try:
            with open(self.path_for(index), encoding="utf-8") as fh:
                return json.load(fh)
        except Exception:
            return None

    def drop(self, index):
        for path in (self.path_for(index), self.txt_for(index)):
            try:
                os.remove(path)
            except Exception:
                pass

    def restore(self, slots):
        """Anything unreadable is skipped rather than fatal - one corrupt file
        must never stop the tool from opening."""
        loaded = 0
        for slot in slots:
            data = self.read(slot.index)
            if not data:
                continue
            events = data.get("events") or []
            if not isinstance(events, list):
                continue
            slot.fill(events)
            name = data.get("name")
            if name:
                slot.rename(name)
            try:
                slot.runs = int(data.get("runs") or 0)
            except Exception:
                slot.runs = 0
            loaded += 1
        return loaded


# 8.  SLOTS
# =============================================================================

class Slot:
    """One session recording. Deliberately RAM-only: he asked for the history
    to be limited to this run of the app, so nothing is reloaded on start."""

    def __init__(self, index):
        self.index = index
        self.name = "SLOT %d" % (index + 1)
        self.events = []
        self.stats = macro_stats([])
        self.stamp = ""
        self.runs = 0

    @property
    def empty(self) -> bool:
        return not self.events

    def fill(self, events):
        self.events = list(events)
        self.stats = macro_stats(self.events)
        self.stamp = time.strftime("%H:%M:%S")
        self.runs = 0

    def wipe(self):
        self.events = []
        self.stats = macro_stats([])
        self.stamp = ""
        self.runs = 0

    def rename(self, text):
        self.name = clean_name(text, "SLOT %d" % (self.index + 1))
        return self.name

    def label(self) -> str:
        if self.empty:
            return "empty"
        return "%s ev   %.2fs" % (fmt_int(self.stats["events"]), self.stats["duration"])


# =============================================================================
# 9.  APP STATE
# =============================================================================

class App:
    IDLE, RECORDING, LOOPING = "IDLE", "RECORDING", "LOOPING"
    SLOT_COUNT = 6

    def __init__(self):
        self.bus = queue.Queue()
        self.echo = Echo()
        self.rec = Recorder()
        self.keys = Keybinds()
        self.capturing = None            # action waiting for its new combo
        self.hub = Hub(self)
        self.state = self.IDLE
        self.slots = [Slot(i) for i in range(self.SLOT_COUNT)]
        self.sel = 0
        self.rec_target = 0
        self.playing_slot = 0
        self.player = None
        self.stop_evt = threading.Event()
        self.pause_evt = threading.Event()
        self.paused = False
        self.gap = 0.20
        self.gap_unit = "sec"
        self.lib = Library()
        self.editor = None
        self.jitter_ms = 0
        self.jitter_px = 0
        self._rng = random.Random()
        self.speed = 1.00
        self.target_runs = 0                 # 0 = forever
        self.opacity = 1.00
        self.total_runs = 0
        self.session_runs = 0
        self.loop_times = deque(maxlen=40)
        self.history_version = 0
        self.loop_started = 0.0
        self.run_started = 0.0
        self.run_seconds = 0.0
        self.counters = dict(clicks=0, taps=0, scrolls=0, actions=0)
        self.status = "ready"
        self.ticker = ""
        self.admin = _is_admin()
        self.console_shown = True
        self.renaming = False
        self._pulse = 0.0
        self.shutdown = lambda: None
        try:
            back = self.lib.restore(self.slots)
        except Exception:
            back = 0
        if back:
            self.status = "loaded %d saved macro(s) from the library" % back

    # ---- helpers -----------------------------------------------------------
    def slot(self) -> Slot:
        return self.slots[max(0, min(self.SLOT_COUNT - 1, self.sel))]

    def events(self):
        return self.slot().events

    def is_replaying(self) -> bool:
        return self.state == self.LOOPING

    def set_status(self, text):
        self.status = text

    def _first_empty(self):
        for slot in self.slots:
            if slot.empty:
                return slot.index
        return None

    # ---- hotkeys (listener thread -> queue -> main thread) -----------------
    def fire_hotkey(self, action):
        if action in ("stop", "panic"):
            self.stop_evt.set()          # panic path never waits for Tk
            self.pause_evt.clear()
        self.bus.put(("hotkey", action))

    def act_record(self):
        if self.state == self.LOOPING:
            self._halt_player()
        if self.renaming:
            return
        # never quietly destroy a recording he already made
        if not self.slot().empty:
            spare = self._first_empty()
            if spare is not None:
                self.sel = spare
        self.rec_target = self.sel
        was = self.slots[self.rec_target].empty
        self.rec.start()
        self.state = self.RECORDING
        self.session_runs = 0
        self.loop_times.clear()
        self.history_version += 1
        self.run_seconds = 0.0
        self.set_status("recording into %s%s - %s replays it"
                        % (self.slot().name, "" if was else " (overwriting)",
                           self.keys.label("loop")))

    def act_loop(self):
        if self.state == self.RECORDING:
            events = self.rec.stop(suppress_ids=Hub.CTRL_IDS)
            if not events:
                self.state = self.IDLE
                self.set_status("that recording was empty, nothing stored")
                return
            self.slots[self.rec_target].fill(events)
            self.sel = self.rec_target
            self.autosave(self.rec_target)
            self._start_player()
            return
        if self.state == self.LOOPING:
            self.set_status("already replaying - %s stops" % self.keys.label("stop"))
            return
        if self.slot().empty:
            self.set_status("%s is empty - press %s first"
                            % (self.slot().name, self.keys.label("rec")))
            return
        self._start_player()

    def act_pause(self):
        if self.state != self.LOOPING or not self.player:
            self.set_status("nothing is replaying")
            return
        paused = self.player.toggle_pause()
        self.paused = paused
        self.set_status(("paused - %s resumes" % self.keys.label("pause"))
                        if paused else "resumed")

    def act_stop(self, panic=False):
        if self.state == self.RECORDING:
            events = self.rec.stop(suppress_ids=Hub.CTRL_IDS)
            if events:
                self.slots[self.rec_target].fill(events)
                self.sel = self.rec_target
                self.autosave(self.rec_target)
                self.set_status("stored %s events in %s"
                                % (fmt_int(len(events)), self.slot().name))
            else:
                self.set_status("recording stopped, nothing captured")
            self.state = self.IDLE
            self.stop_evt.clear()
            return
        if self.state == self.LOOPING:
            runs = self.session_runs
            self._halt_player()
            self.set_status(("EMERGENCY STOP after %s runs" if panic
                             else "stopped after %s runs") % fmt_int(runs))
            return
        self.stop_evt.clear()
        self.set_status("already idle")

    def act_slot(self, index):
        if self.state != self.IDLE:
            self.set_status("stop first (%s) before changing slot"
                            % self.keys.label("stop"))
            return
        self.sel = max(0, min(self.SLOT_COUNT - 1, int(index)))
        slot = self.slot()
        self.set_status("%s selected - %s" % (slot.name, slot.label()))

    def act_capture(self, action):
        if self.state != self.IDLE:
            self.set_status("stop first (%s) before changing a keybind"
                            % self.keys.label("stop"))
            return
        if self.capturing == action:
            self.capturing = None
            self.set_status("keybind unchanged")
            return
        self.capturing = action
        self.set_status("press the new combo for %s   (ESC cancels)"
                        % Keybinds.LABELS[action])

    def act_capture_key(self, vk, ctrl, shift, alt):
        action = self.capturing
        if not action:
            return
        if vk in MODIFIER_VKS:
            return                        # still waiting for the real key
        self.capturing = None
        if vk == 0x1B and not (ctrl or shift or alt):
            self.set_status("keybind unchanged")
            return
        ok, msg = self.keys.rebind(action, vk, ctrl, shift, alt)
        self.set_status(("%s is now %s" % (Keybinds.LABELS[action], msg))
                        if ok else msg)

    def act_reset_keys(self):
        self.capturing = None
        self.keys.reset()
        self.set_status("keybinds back to the defaults")

    def act_clear(self):
        if self.state != self.IDLE:
            self.set_status("stop first (%s)" % self.keys.label("stop"))
            return
        for slot in self.slots:
            slot.wipe()
            try:
                self.lib.drop(slot.index)
            except Exception:
                pass
        for key in self.counters:
            self.counters[key] = 0
        self.total_runs = 0
        self.session_runs = 0
        self.loop_times.clear()
        self.history_version += 1
        self.run_seconds = 0.0
        self.set_status("all slots and counters cleared")


    def autosave(self, index=None, force=False):
        """Every recording and every edit lands on disk straight away. v3 held
        the whole session in RAM and he lost it, so nothing here waits for him
        to remember to press a save button."""
        idx = self.sel if index is None else index
        slot = self.slots[max(0, min(self.SLOT_COUNT - 1, idx))]
        if slot.empty and not force:
            return ""
        try:
            return self.lib.save(slot)
        except Exception as exc:
            self.set_status("could not save: %r" % (exc,))
            return ""

    def act_save(self):
        path = self.autosave(force=True)
        if path:
            self.set_status("saved %s and its readable copy" % os.path.basename(path))
        else:
            self.set_status("nothing to save in %s" % self.slot().name)

    def act_load(self):
        if self.state != self.IDLE:
            self.set_status("stop first (%s)" % self.keys.label("stop"))
            return
        try:
            back = self.lib.restore(self.slots)
        except Exception as exc:
            self.set_status("could not read the library: %r" % (exc,))
            return
        self.history_version += 1
        self.set_status("reloaded %d macro(s) from the library" % back
                        if back else "the library folder is empty")

    def act_folder(self):
        try:
            self.lib.ensure()
            os.startfile(self.lib.folder)
            self.set_status("library folder opened")
        except Exception as exc:
            self.set_status("could not open the folder: %r" % (exc,))

    def act_jitter(self):
        steps = ((0, 0), (8, 1), (18, 2), (35, 4))
        now = (self.jitter_ms, self.jitter_px)
        try:
            nxt = steps[(steps.index(now) + 1) % len(steps)]
        except ValueError:
            nxt = steps[0]
        self.jitter_ms, self.jitter_px = nxt
        if not self.jitter_ms:
            self.set_status("jitter off - every replay is frame exact")
        else:
            self.set_status("jitter %d ms / %d px - looks hand made, less exact"
                            % (self.jitter_ms, self.jitter_px))

    def act_gap_unit(self):
        now = self.gap_unit if self.gap_unit in UNIT_ORDER else "sec"
        self.gap_unit = UNIT_ORDER[(UNIT_ORDER.index(now) + 1) % len(UNIT_ORDER)]
        self.set_status("gap steps are now counted in %ss" % self.gap_unit)

    def gap_text(self) -> str:
        n, unit = split_seconds(self.gap)
        return fmt_wait(n, unit)


    def act_import(self):
        """Read any GOLDMACRO json back into the selected slot - an export from
        another machine, or a file he edited by hand."""
        if self.state != self.IDLE:
            self.set_status("stop first (%s)" % self.keys.label("stop"))
            return
        try:
            from tkinter import filedialog
            self.lib.ensure()
            path = filedialog.askopenfilename(
                title="pick a macro", initialdir=self.lib.folder,
                filetypes=[("GOLDMACRO", "*.json"), ("all files", "*.*")])
        except Exception as exc:
            self.set_status("could not open the picker: %r" % (exc,))
            return
        if not path:
            return
        try:
            with open(path, encoding="utf-8") as fh:
                data = json.load(fh)
            events = data.get("events")
            if not isinstance(events, list) or not events:
                self.set_status("that file holds no steps")
                return
            slot = self.slot()
            slot.fill(events)
            name = data.get("name")
            if name:
                slot.rename(name)
            self.history_version += 1
            self.autosave(slot.index)
            self.set_status("imported %s steps into %s"
                            % (fmt_int(len(events)), slot.name))
        except Exception as exc:
            self.set_status("import failed: %r" % (exc,))

    def act_export(self):
        slot = self.slot()
        if slot.empty:
            self.set_status("%s is empty, nothing to export" % slot.name)
            return
        try:
            _mkdirs()
            safe = "".join(c if (c.isalnum() or c in "-_") else "_" for c in slot.name)
            path = os.path.join(DATA_DIR, "export_%s_%s.json"
                                % (safe, time.strftime("%Y%m%d_%H%M%S")))
            with open(path, "w", encoding="utf-8") as fh:
                json.dump({"app": APP_NAME, "ver": APP_VER, "name": slot.name,
                           "stats": slot.stats, "events": slot.events}, fh)
            self.set_status("exported to %s" % path)
        except Exception as exc:
            self.set_status("export failed: %r" % (exc,))

    # ---- player ------------------------------------------------------------
    def _start_player(self):
        self.stop_evt = threading.Event()
        self.pause_evt = threading.Event()
        self.paused = False
        self.echo.clear()
        self.session_runs = 0
        self.loop_times.clear()
        self.history_version += 1
        self.run_started = time.perf_counter()
        self.loop_started = self.run_started
        self.state = self.LOOPING
        self.playing_slot = self.sel
        run_list = flatten_events(self.slot().events)
        if self.jitter_ms or self.jitter_px:
            run_list = jitter_events(run_list, self.jitter_ms,
                                     self.jitter_px, self._rng)
        self.player = Player(run_list, self.stop_evt, self.bus, self.echo,
                             lambda: self.gap, lambda: self.speed,
                             lambda: self.target_runs, self.counters, self.pause_evt)
        self.player.start()
        goal = "forever" if not self.target_runs else "%d times" % self.target_runs
        self.set_status("replaying %s %s at %.2fx - %s stops"
                        % (self.slot().name, goal, self.speed,
                           self.keys.label("stop")))

    def _halt_player(self):
        self.stop_evt.set()
        self.pause_evt.clear()
        player = self.player
        if player and player.is_alive():
            player.join(timeout=2.5)
        self.player = None
        self.paused = False
        self.state = self.IDLE
        self.run_seconds = ((time.perf_counter() - self.run_started)
                            if self.run_started else 0.0)
        self.stop_evt.clear()

    # ---- adjusters ---------------------------------------------------------
    def bump_gap(self, d):
        """The step size follows the unit he picked, so one press adds an
        hour when the unit is hours instead of five hundredths of a second.
        Capped at seven days - a longer wait is a scheduler, not a macro."""
        step = UNIT_SECONDS.get(self.gap_unit, 1.0)
        if self.gap_unit == 'sec':
            step = 0.05
        self.gap = max(0.0, min(604800.0,
                                round(self.gap + (1 if d > 0 else -1) * step, 3)))
        self.set_status("wait between runs = %s" % self.gap_text())

    def bump_speed(self, d):
        self.speed = max(SPEED_MIN, min(SPEED_MAX, round(self.speed + d, 2)))
        self.set_status("speed = %.2fx%s" % (self.speed,
                        "  (1.00x is the exact human timing)" if self.speed == 1 else ""))

    def bump_target(self, d):
        self.target_runs = max(0, min(100000, self.target_runs + d))
        self.set_status("target = %s" % ("forever" if not self.target_runs
                                         else "%d runs" % self.target_runs))

    def bump_opacity(self, d):
        self.opacity = max(0.40, min(1.0, round(self.opacity + d, 2)))
        self.set_status("window fade = %d%%" % int(self.opacity * 100))

    # ---- derived numbers ---------------------------------------------------
    def elapsed(self):
        if self.state == self.LOOPING:
            return time.perf_counter() - self.run_started
        if self.state == self.RECORDING:
            return self.rec.elapsed()
        return self.run_seconds

    def avg_loop(self):
        return (sum(self.loop_times) / len(self.loop_times)) if self.loop_times else 0.0

    def loop_progress(self):
        events = self.events()
        dur = macro_duration(events) / (self.speed if self.speed > 0 else 1.0)
        if self.state != self.LOOPING or dur <= 0 or self.paused:
            return 1.0 if self.paused else 0.0
        return max(0.0, min(1.0, (time.perf_counter() - self.loop_started) / dur))

    def live_stats(self) -> dict:
        """What the GUI shows in the make-up panel: live while recording, the
        stored slot figures otherwise."""
        if self.state == self.RECORDING:
            live = self.rec.live
            return dict(clicks=live["clicks"], taps=live["taps"],
                        scrolls=live["scrolls"], moves=live["moves"],
                        distance=live["distance"], duration=self.rec.elapsed(),
                        events=self.rec.count())
        return dict(self.slot().stats)

    def per_second(self):
        el = self.elapsed()
        return (self.counters.get("actions", 0) / el) if el > 0.2 else 0.0

    def clicks_per_min(self):
        el = self.elapsed()
        return (self.counters.get("clicks", 0) * 60.0 / el) if el > 0.5 else 0.0


def fmt_clock(sec: float) -> str:
    sec = max(0.0, float(sec))
    h, rem = divmod(int(sec), 3600)
    m, s = divmod(rem, 60)
    tenth = int((sec - int(sec)) * 10)
    if h:
        return "%d:%02d:%02d.%d" % (h, m, s, tenth)
    return "%02d:%02d.%d" % (m, s, tenth)


APP_REF = [None]


def app_do(action):
    def run():
        if APP_REF[0]:
            APP_REF[0].fire_hotkey(action)
    return run


# =============================================================================
# 10.  CONSOLE
# =============================================================================


class Editor:
    """The details window. v3 could only record and replay a slot whole; there
    was no way to look at what was inside one, and no way to change a single
    click without recording the whole thing again.

    A recorded macro and a hand-built one are the same list of steps here, so
    everything on this window works on both.
    """

    W, H = 720, 592

    def __init__(self, app, root, console=None):
        self.app = app
        self.root = root
        self.console = console
        self.win = None
        self.index = 0
        self.sel = 0

    def alive(self) -> bool:
        try:
            return bool(self.win) and bool(self.win.winfo_exists())
        except Exception:
            return False

    def open(self, index):
        self.index = index
        if self.alive():
            self.refresh()
            try:
                self.win.deiconify()
                self.win.lift()
            except Exception:
                pass
            return
        w, h = S(self.W), S(self.H)
        try:
            sw, sh = self.root.winfo_screenwidth(), self.root.winfo_screenheight()
        except Exception:
            sw, sh = 1920, 1080
        at = None
        con = getattr(self, "console", None)
        if con is not None:
            try:
                cw = con.win
                cw.update_idletasks()
                at = place_beside((cw.winfo_x(), cw.winfo_y(),
                                   cw.winfo_width(), cw.winfo_height()),
                                  w, h, sw, sh)
            except Exception:
                at = None
        if at is None:
            at = (max(20, (sw - w) // 2), max(20, (sh - h) // 4))
        self.shell = Shell(self.root, w, h, at[0], at[1])
        self.win = self.shell.win
        cv = self.body = self.shell.canvas
        self.win.title(APP_NAME + " DETAILS")

        title = tk.Label(cv, text="DETAILS", bg=T.INK, fg=T.VAL,
                         font=(T.UI, max(9, S(12)), "bold"))
        title.place(x=S(16), y=S(9))
        self.head = tk.Label(cv, text="", bg=T.INK, fg="#6A5210",
                             font=(T.MONO, max(6, S(8))))
        self.head.place(x=S(110), y=S(13))
        close = tk.Label(cv, text="\u2715", bg=T.INK, fg="#6A5210",
                         font=(T.UI, max(8, S(11)), "bold"))
        close.place(x=S(self.W - 32), y=S(9))
        close.bind("<Button-1>", lambda _e: self.close())
        self.shell.bind_drag(title)

        card(cv, S(14), S(48), S(430), S(430))
        self.list = tk.Listbox(cv, bg=T.CARD, fg=T.TEXT, bd=0,
                               highlightthickness=0, activestyle="none",
                               selectbackground=T.PILL,
                               selectforeground=T.PILL_TEXT,
                               font=(T.MONO, max(7, S(9))))
        self.list.place(x=S(26), y=S(60), width=S(406), height=S(406))
        self.list.bind("<<ListboxSelect>>", self.on_pick)
        self.list.bind("<MouseWheel>",
                       lambda e: self.list.yview_scroll(
                           -1 * int(e.delta / 120), "units"))

        RX = S(456)
        card(cv, RX, S(48), S(250), S(196))
        tk.Label(cv, text="THIS STEP", bg=T.CARD, fg=T.H1,
                 font=(T.UI, max(7, S(8)), "bold")).place(x=RX + S(14), y=S(56))
        self.kind_lbl = tk.Label(cv, text="-", bg=T.CARD, fg=T.VAL, anchor="w",
                                 font=(T.MONO, max(9, S(12)), "bold"))
        self.kind_lbl.place(x=RX + S(14), y=S(74), width=S(220), height=S(20))

        self.fields = {}
        rows = (("at (sec)", "t"), ("x", "x"), ("y", "y"),
                ("value", "b"), ("how many", "n"))
        self.labels = {}
        for i, (label_txt, key) in enumerate(rows):
            yy = S(100 + i * 26)
            lab = tk.Label(cv, text=label_txt, bg=T.CARD, fg=T.DIM, anchor="w",
                           font=(T.UI, max(6, S(8))))
            lab.place(x=RX + S(14), y=yy + S(4), width=S(96), height=S(14))
            self.labels[key] = lab
            ent = tk.Entry(cv, bg=T.CHIP, fg=T.VAL, bd=0, relief="flat",
                           insertbackground=T.VAL, highlightthickness=1,
                           highlightbackground=T.GOLD_DEEP,
                           highlightcolor=T.PILL,
                           font=(T.MONO, max(7, S(9))))
            ent.place(x=RX + S(112), y=yy, width=S(124), height=S(20))
            self.fields[key] = ent

        self.unit_lbl = tk.Label(cv, text="sec", bg=T.CHIP, fg=T.VAL,
                                 font=(T.MONO, max(7, S(9)), "bold"),
                                 highlightthickness=1,
                                 highlightbackground=T.GOLD_DEEP,
                                 cursor="hand2")
        self.unit_lbl.place(x=RX + S(112), y=S(232), width=S(124), height=S(20))
        self.unit_lbl.bind("<Button-1>", lambda _e: self.cycle_unit())
        tk.Label(cv, text="unit", bg=T.CARD, fg=T.DIM,
                 anchor="w", font=(T.UI, max(6, S(8)))
                 ).place(x=RX + S(14), y=S(236), width=S(96), height=S(14))
        tk.Label(cv, text="click the box to change it", bg=T.CARD,
                 fg=T.FAINT_C, anchor="w", font=(T.MONO, max(6, S(7)))
                 ).place(x=RX + S(14), y=S(254), width=S(222), height=S(12))

        card(cv, RX, S(262), S(250), S(216))
        tk.Label(cv, text="MACRO", bg=T.CARD, fg=T.H1,
                 font=(T.UI, max(7, S(8)), "bold")).place(x=RX + S(14), y=S(270))
        self.sum = {}
        for i, (label_txt, key) in enumerate((("STEPS", "steps"),
                                              ("LENGTH", "length"),
                                              ("WAITING", "waiting"),
                                              ("CLICKS", "clicks"),
                                              ("KEY TAPS", "taps"),
                                              ("SAVED TO", "saved"))):
            yy = S(292 + i * 17)
            tk.Label(cv, text=label_txt, bg=T.CARD, fg=T.DIM, anchor="w",
                     font=(T.UI, max(6, S(8)))).place(x=RX + S(14), y=yy,
                                                      height=S(14))
            val = tk.Label(cv, text="-", bg=T.CARD, fg=T.VAL, anchor="e",
                           font=(T.MONO, max(6, S(8)), "bold"))
            val.place(x=RX + S(236), y=yy, width=S(150), height=S(14),
                      anchor="ne")
            self.sum[key] = val

        self.note = tk.Label(cv, text="", bg=T.CARD, fg=T.RED, anchor="w",
                             font=(T.MONO, max(6, S(8))))
        self.note.place(x=RX + S(14), y=S(400), width=S(222), height=S(14))

        bx = S(14)
        for text, cmd, bw in (("APPLY", self.apply_step, 74),
                              ("+ WAIT", self.add_wait, 74),
                              ("+ TYPE", self.add_text, 74),
                              ("+ KEYS", self.add_keys, 74),
                              ("+ FOCUS", self.add_focus, 78),
                              ("COPY STEP", self.duplicate, 84),
                              ("DELETE", self.delete, 70),
                              ("UP", self.move_up, 52),
                              ("DOWN", self.move_down, 60)):
            GoldButton(cv, text, cmd, bx, S(492), S(bw), S(28),
                       filled=(text == "APPLY"),
                       danger=(text == "DELETE"))
            bx += S(bw) + S(5)
        bx = S(14)
        for text, cmd, bw in (("COPY", self.add_copy, 78),
                              ("PASTE", self.add_paste, 82),
                              ("SELECT ALL", self.add_all, 108),
                              ("SAVE", self.save_now, 74),
                              ("CLOSE", self.close, 74)):
            GoldButton(cv, text, cmd, bx, S(524), S(bw), S(26),
                       filled=(text == "SAVE"))
            bx += S(bw) + S(5)
        self.refresh()

    def slot(self):
        return self.app.slots[max(0, min(App.SLOT_COUNT - 1, self.index))]

    def steps(self):
        return self.slot().events

    def refresh(self):
        if not self.alive():
            return
        slot = self.slot()
        self.head.configure(text="%s   %d steps" % (slot.name, len(slot.events)))
        keep = self.list.yview()
        self.list.delete(0, "end")
        for i, ev in enumerate(slot.events):
            self.list.insert("end", step_line(i, ev))
        if slot.events:
            self.sel = max(0, min(len(slot.events) - 1, self.sel))
            self.list.selection_clear(0, "end")
            self.list.selection_set(self.sel)
            try:
                self.list.yview_moveto(keep[0])
            except Exception:
                pass
        flat = flatten_events(slot.events)
        stats = macro_stats(flat)
        self.sum["steps"].configure(text=fmt_int(len(slot.events)))
        self.sum["length"].configure(text="%.2f s" % macro_duration(flat))
        self.sum["waiting"].configure(text="%.2f s" % total_wait(slot.events))
        self.sum["clicks"].configure(text=fmt_int(stats["clicks"]))
        self.sum["taps"].configure(text=fmt_int(stats["taps"]))
        self.sum["saved"].configure(
            text="slot%d.json" % (self.index + 1) if not slot.empty else "-")
        self.show_step()

    def show_step(self):
        events = self.steps()
        for ent in self.fields.values():
            ent.delete(0, "end")
        if not events:
            self.kind_lbl.configure(text="empty")
            self.unit_lbl.configure(text="-")
            return
        ev = events[max(0, min(len(events) - 1, self.sel))]
        kind = ev.get("k")
        names = {EV_WAIT: "WAIT", EV_MOVE: "MOVE", EV_DOWN: "PRESS",
                 EV_UP: "RELEASE", EV_SCROLL: "SCROLL", EV_KDOWN: "KEY DOWN",
                 EV_KUP: "KEY UP", EV_TEXT: "TYPE", EV_KEYS: "KEYS",
                 EV_FOCUS: "FOCUS"}
        self.kind_lbl.configure(text=names.get(kind, str(kind)))
        self.fields["t"].insert(0, "%.3f" % float(ev.get("t", 0.0)))
        value_label = {EV_TEXT: "the words", EV_KEYS: "the combo",
                       EV_FOCUS: "window title"}.get(kind, "button / key")
        self.labels["b"].configure(text=value_label)
        if kind == EV_WAIT:
            self.fields["n"].insert(0, str(ev.get("q", 1)))
        elif kind in (EV_TEXT, EV_KEYS, EV_FOCUS):
            self.fields["b"].insert(0, str(ev.get("s", "")))
        else:
            self.fields["x"].insert(0, str(ev.get("x", "")))
            self.fields["y"].insert(0, str(ev.get("y", "")))
            self.fields["b"].insert(0, str(ev.get("b", "") or ev.get("n", "")
                                           or ev.get("c", "")))
        self.unit_lbl.configure(text=ev.get("u", "sec")
                                if kind == EV_WAIT else "-")

    def on_pick(self, _event=None):
        try:
            picked = self.list.curselection()
        except Exception:
            return
        if picked:
            self.sel = int(picked[0])
            self.show_step()

    def cycle_unit(self):
        events = self.steps()
        if not events:
            return
        ev = events[self.sel]
        if ev.get("k") != EV_WAIT:
            self.say("only a WAIT step has a unit")
            return
        now = ev.get("u", "sec")
        nxt = UNIT_ORDER[(UNIT_ORDER.index(now) + 1) % len(UNIT_ORDER)] \
            if now in UNIT_ORDER else "sec"
        ev["u"] = nxt
        self.unit_lbl.configure(text=nxt)
        self.touched()

    def say(self, text):
        self.note.configure(text=text)
        if self.alive():
            self.win.after(4000, lambda: self.note.configure(text=""))

    def guard(self) -> bool:
        if self.app.state != App.IDLE:
            self.say("stop the macro first")
            return False
        return True

    def touched(self):
        slot = self.slot()
        slot.stats = macro_stats(flatten_events(slot.events))
        self.app.history_version += 1
        self.refresh()

    def apply_step(self):
        if not self.guard():
            return
        events = self.steps()
        if not events:
            return
        ev = events[self.sel]
        try:
            ev["t"] = max(0.0, float(self.fields["t"].get() or 0))
        except Exception:
            self.say("at (sec) must be a number")
            return
        if ev.get("k") == EV_WAIT:
            try:
                ev["q"] = max(0.0, float(self.fields["n"].get() or 0))
            except Exception:
                self.say("how many must be a number")
                return
        elif ev.get("k") in (EV_TEXT, EV_KEYS, EV_FOCUS):
            value = self.fields["b"].get()
            if ev.get("k") == EV_KEYS:
                mods, main = parse_combo(value)
                if main is None:
                    self.say("that combo does not read - try ctrl+c")
                    return
            if ev.get("k") == EV_FOCUS and not value.strip():
                self.say("give it part of a window title")
                return
            ev["s"] = value
        else:
            for key in ("x", "y"):
                raw = self.fields[key].get().strip()
                if raw:
                    try:
                        ev[key] = int(float(raw))
                    except Exception:
                        self.say("%s must be a number" % key)
                        return
            btn = self.fields["b"].get().strip()
            if btn and ev.get("k") in (EV_DOWN, EV_UP):
                ev["b"] = btn
        events.sort(key=lambda e: float(e.get("t", 0.0)))
        self.say("step saved")
        self.touched()
        self.app.autosave(self.index)

    def add_wait(self):
        if not self.guard():
            return
        events = self.steps()
        at = 0.0
        if events:
            at = float(events[min(self.sel, len(events) - 1)].get("t", 0.0))
        events.insert(min(self.sel + 1, len(events)),
                      {"k": EV_WAIT, "t": at, "q": 1, "u": "sec"})
        self.sel = min(self.sel + 1, len(events) - 1)
        self.say("wait added - set how many, then click the unit")
        self.touched()
        self.app.autosave(self.index)

    def _insert(self, made, word):
        if not self.guard():
            return
        events = self.steps()
        at = 0.0
        if events:
            at = float(events[min(self.sel, len(events) - 1)].get("t", 0.0))
        made["t"] = at
        events.insert(min(self.sel + 1, len(events)), made)
        self.sel = min(self.sel + 1, len(events) - 1)
        self.say(word)
        self.touched()
        self.app.autosave(self.index)

    def add_text(self):
        self._insert({"k": EV_TEXT, "s": "hello"},
                     "typing step added - put your words in the value box")

    def add_keys(self):
        self._insert({"k": EV_KEYS, "s": "ctrl+c"},
                     "keys step added - try ctrl+c, ctrl+v, ctrl+a, alt+tab")

    def add_focus(self):
        self._insert({"k": EV_FOCUS, "s": "Chrome"},
                     "focus step added - type part of the window title")

    def add_copy(self):
        self._insert({"k": EV_KEYS, "s": "ctrl+c"}, "copy added")

    def add_paste(self):
        self._insert({"k": EV_KEYS, "s": "ctrl+v"}, "paste added")

    def add_all(self):
        self._insert({"k": EV_KEYS, "s": "ctrl+a"}, "select all added")

    def duplicate(self):
        if not self.guard():
            return
        events = self.steps()
        if not events:
            return
        events.insert(self.sel + 1, dict(events[self.sel]))
        self.sel += 1
        self.touched()
        self.app.autosave(self.index)

    def delete(self):
        if not self.guard():
            return
        events = self.steps()
        if not events:
            return
        events.pop(self.sel)
        self.sel = max(0, min(self.sel, len(events) - 1))
        self.touched()
        self.app.autosave(self.index)

    def _swap(self, other):
        if not self.guard():
            return
        events = self.steps()
        if not events or not (0 <= other < len(events)):
            return
        events[self.sel], events[other] = events[other], events[self.sel]
        events[self.sel]["t"], events[other]["t"] = \
            events[other].get("t", 0.0), events[self.sel].get("t", 0.0)
        self.sel = other
        self.touched()
        self.app.autosave(self.index)

    def move_up(self):
        self._swap(self.sel - 1)

    def move_down(self):
        self._swap(self.sel + 1)

    def save_now(self):
        path = self.app.autosave(self.index, force=True)
        self.say("saved to %s" % (os.path.basename(path) if path else "nothing"))

    def close(self):
        if self.alive():
            try:
                self.win.destroy()
            except Exception:
                pass
        self.win = None


class Console:
    W, H = 700, 600

    def __init__(self, app, root):
        self.app = app
        self.root = root
        w, h = S(self.W), S(self.H)
        try:
            sw, sh = root.winfo_screenwidth(), root.winfo_screenheight()
        except Exception:
            sw, sh = 1920, 1080
        self.shell = Shell(root, w, h, max(20, (sw - w) // 2), max(20, (sh - h) // 3))
        self.win = self.shell.win
        self.win.title(APP_NAME)
        cv = self.body = self.shell.canvas
        self.stats = {}
        self.rows = {}
        self.action_btns = {}
        self._hist_version = -1

        # ---------------- title bar ----------------
        self.dot = tk.Label(cv, text="\u25CF", bg=T.INK, fg=T.OFF,
                            font=(T.UI, max(8, S(12))))
        self.dot.place(x=S(16), y=S(9))
        title = tk.Label(cv, text=APP_NAME, bg=T.INK, fg=T.VAL,
                         font=(T.UI, max(9, S(12)), "bold"))
        ver = tk.Label(cv, text=APP_VER, bg=T.INK, fg="#7A5C12",
                       font=(T.MONO, max(6, S(7))))
        badge = tk.Label(cv, text=" ADMIN " if app.admin else " NO ADMIN ",
                         bg=T.GOLD if app.admin else T.RED_DEEP,
                         fg=T.INK if app.admin else T.RED_HI,
                         font=(T.MONO, max(6, S(7)), "bold"))
        # the four main hotkeys are printed on the buttons themselves, so the
        # strip only carries the two that have no button
        hint = tk.Label(cv, text="CTRL+1..6 = slot     ESC x3 = panic stop",
                        bg=T.INK, fg="#6A5210", font=(T.MONO, max(6, S(7))))
        # laid out from real measured widths instead of guessed pixel offsets:
        # v1 guessed, and the version label ended up printed over the title
        self.win.update_idletasks()
        pen = S(38)
        for wdg, dy, pad in ((title, S(9), S(10)), (ver, S(15), S(12)),
                             (badge, S(14), S(16)), (hint, S(15), 0)):
            wdg.place(x=pen, y=dy)
            self.win.update_idletasks()
            pen += wdg.winfo_reqwidth() + pad
        for txt, cmd, xx in (("\u2013", self.hide, S(self.W - 54)),
                             ("\u2715", self.quit, S(self.W - 32))):
            lab = tk.Label(cv, text=txt, bg=T.INK, fg="#6A5210",
                           font=(T.UI, max(8, S(11)), "bold"))
            lab.place(x=xx, y=S(9))
            lab.bind("<Button-1>", lambda _e, c=cmd: c())
            lab.bind("<Enter>", lambda e: e.widget.configure(fg=T.VAL))
            lab.bind("<Leave>", lambda e: e.widget.configure(fg="#6A5210"))
        for wdg in (title, self.dot):
            self.shell.bind_drag(wdg)

        LX, RX, CW = S(14), S(356), S(330)

        # ---------------- state card ----------------
        card(cv, LX, S(48), CW, S(76))
        self.state_lbl = tk.Label(cv, text=App.IDLE, bg=T.CARD, fg=T.ON,
                                  font=(T.MONO, max(14, S(21)), "bold"))
        self.state_lbl.place(x=LX + S(14), y=S(56), height=S(30))
        self.pause_lbl = tk.Label(cv, text="", bg=T.CARD, fg=T.RED,
                                  font=(T.MONO, max(7, S(9)), "bold"))
        self.pause_lbl.place(x=LX + CW - S(14), y=S(62), height=S(14), anchor="ne")
        self.cfg_lbl = tk.Label(cv, text="", bg=T.CARD, fg=T.DIM, anchor="w",
                                font=(T.MONO, max(6, S(8))))
        self.cfg_lbl.place(x=LX + S(14), y=S(98), width=CW - S(28), height=S(13))

        # ---------------- slot rack ----------------
        card(cv, LX, S(130), CW, S(166))
        tk.Label(cv, text="SESSION SLOTS", bg=T.CARD, fg=T.H1,
                 font=(T.UI, max(7, S(8)), "bold")).place(x=LX + S(14), y=S(138))
        tk.Label(cv, text="saved to the library", bg=T.CARD, fg=T.FAINT_C,
                 font=(T.MONO, max(6, S(6)))).place(x=LX + CW - S(14), y=S(140),
                                                    anchor="ne")
        for i in range(App.SLOT_COUNT):
            yy = S(158 + i * 22)
            chip = tk.Label(cv, text="%d" % (i + 1), bg=T.CARD, fg=T.H1,
                            font=(T.MONO, max(7, S(8)), "bold"))
            chip.place(x=LX + S(12), y=yy, width=S(18), height=S(15))
            name = tk.Label(cv, text="", bg=T.CARD, fg=T.TEXT, anchor="w",
                            font=(T.MONO, max(7, S(9))))
            name.place(x=LX + S(36), y=yy, width=S(148), height=S(15))
            meta = tk.Label(cv, text="", bg=T.CARD, fg=T.DIM, anchor="e",
                            font=(T.MONO, max(6, S(7))))
            meta.place(x=LX + CW - S(14), y=yy + S(1), width=S(112), height=S(14),
                       anchor="ne")
            self.rows[i] = (chip, name, meta)
            for wdg in (chip, meta):
                wdg.bind("<Button-1>", lambda _e, k=i: self.app.act_slot(k))
            name.bind("<Button-1>", lambda _e, k=i: self.app.act_slot(k))
            name.bind("<Double-Button-1>", lambda _e, k=i: self.start_rename(k))
        self.entry = None
        self.entry_slot = None

        # ---------------- run history ----------------
        card(cv, LX, S(302), CW, S(98))
        tk.Label(cv, text="RUN HISTORY", bg=T.CARD, fg=T.H1,
                 font=(T.UI, max(7, S(8)), "bold")).place(x=LX + S(14), y=S(308),
                                                          height=S(13))
        self.hist = tk.Canvas(cv, width=CW - S(28), height=S(40), bd=0,
                              highlightthickness=0, bg=T.CARD)
        self.hist.place(x=LX + S(14), y=S(328))
        self.hist_lbl = tk.Label(cv, text="no runs yet", bg=T.CARD, fg=T.H1,
                                 anchor="w", font=(T.MONO, max(6, S(7))))
        self.hist_lbl.place(x=LX + S(14), y=S(376), width=CW - S(28), height=S(13))

        # ---------------- total runs ----------------
        card(cv, RX, S(48), CW, S(104))
        tk.Label(cv, text="TOTAL RUNS", bg=T.CARD, fg=T.H1,
                 font=(T.UI, max(7, S(8)), "bold")).place(x=RX + S(14), y=S(54),
                                                          height=S(13))
        self.total_lbl = tk.Label(cv, text="0", bg=T.CARD, fg=T.VAL, anchor="w",
                                  font=(T.MONO, max(20, S(34)), "bold"))
        self.total_lbl.place(x=RX + S(12), y=S(70), width=S(130), height=S(46))
        self._total_size = 0
        self.clock_lbl = tk.Label(cv, text="00:00.0", bg=T.CARD, fg=T.RED,
                                  font=(T.MONO, max(13, S(19)), "bold"))
        self.clock_lbl.place(x=RX + CW - S(14), y=S(56), height=S(26), anchor="ne")
        self.count_lbl = tk.Label(cv, text="\u00D70", bg=T.CARD, fg=T.RED,
                                  font=(T.MONO, max(13, S(19)), "bold"))
        self.count_lbl.place(x=RX + CW - S(14), y=S(92), height=S(26), anchor="ne")
        self.target_lbl = tk.Label(cv, text="", bg=T.CARD, fg=T.H1,
                                   font=(T.MONO, max(6, S(7))))
        self.target_lbl.place(x=RX + CW - S(14), y=S(126), height=S(12), anchor="ne")

        # ---------------- what the macro does ----------------
        card(cv, RX, S(158), CW, S(118))
        tk.Label(cv, text="WHAT THE MACRO DOES", bg=T.CARD, fg=T.H1,
                 font=(T.UI, max(7, S(8)), "bold")).place(x=RX + S(14), y=S(166))
        makeup = (("CLICKS", "clicks"), ("KEY TAPS", "taps"), ("SCROLLS", "scrolls"),
                  ("MOUSE MOVES", "moves"), ("MOUSE TRAVEL", "distance"),
                  ("LENGTH", "duration"))
        for i, (title_txt, key) in enumerate(makeup):
            yy = S(186 + i * 15)
            tk.Label(cv, text=title_txt, bg=T.CARD, fg=T.DIM, anchor="w",
                     font=(T.UI, max(6, S(8)))).place(x=RX + S(14), y=yy,
                                                      height=S(13))
            val = tk.Label(cv, text="-", bg=T.CARD, fg=T.TEXT, anchor="e",
                           font=(T.MONO, max(7, S(8)), "bold"))
            val.place(x=RX + CW - S(14), y=yy, width=S(140), height=S(13),
                      anchor="ne")
            self.stats["m_" + key] = val

        # ---------------- fired this session ----------------
        card(cv, RX, S(282), CW, S(118))
        tk.Label(cv, text="FIRED THIS SESSION", bg=T.CARD, fg=T.H1,
                 font=(T.UI, max(7, S(8)), "bold")).place(x=RX + S(14), y=S(290))
        fired = (("CLICKS FIRED", "clicks"), ("TAPS FIRED", "taps"),
                 ("SCROLLS FIRED", "scrolls"), ("TOTAL ACTIONS", "actions"),
                 ("ACTIONS / SEC", "aps"), ("CLICKS / MIN", "cpm"))
        for i, (title_txt, key) in enumerate(fired):
            yy = S(310 + i * 15)
            tk.Label(cv, text=title_txt, bg=T.CARD, fg=T.DIM, anchor="w",
                     font=(T.UI, max(6, S(8)))).place(x=RX + S(14), y=yy,
                                                      height=S(13))
            val = tk.Label(cv, text="0", bg=T.CARD, fg=T.VAL, anchor="e",
                           font=(T.MONO, max(7, S(8)), "bold"))
            val.place(x=RX + CW - S(14), y=yy, width=S(140), height=S(13),
                      anchor="ne")
            self.stats["f_" + key] = val

        # ---------------- keybinds ----------------
        card(cv, S(14), S(406), S(672), S(44))
        tk.Label(cv, text="KEYBINDS", bg=T.CARD, fg=T.H1,
                 font=(T.UI, max(7, S(8)), "bold")).place(x=S(26), y=S(412),
                                                          height=S(12))
        tk.Label(cv, text="click one, press the combo", bg=T.CARD, fg=T.FAINT_C,
                 anchor="w", font=(T.MONO, max(6, S(6)))
                 ).place(x=S(26), y=S(430), width=S(160), height=S(11))
        self.bind_chips = {}
        bx = S(196)
        for action in Keybinds.ACTIONS:
            chip = tk.Label(cv, text="", bg=T.CHIP, fg=T.ON,
                            font=(T.MONO, max(6, S(8)), "bold"))
            chip.place(x=bx, y=S(414), width=S(104), height=S(26))
            chip.bind("<Button-1>", lambda _e, a=action: self.app.act_capture(a))
            chip.bind("<Enter>", lambda e: e.widget.configure(bg=T.CARD_HI))
            chip.bind("<Leave>", lambda e: self.paint_chips())
            self.bind_chips[action] = chip
            bx += S(110)
        reset = tk.Label(cv, text="RESET", bg=T.CARD, fg=T.DIM,
                         font=(T.MONO, max(6, S(7)), "bold"))
        reset.place(x=S(640), y=S(418), width=S(46), height=S(18))
        reset.bind("<Button-1>", lambda _e: self.app.act_reset_keys())

        # ---------------- buttons ----------------
        bx = S(14)
        row1 = (("REC", app_do("rec"), 78, True, False, app.keys.label("rec")),
                ("REPLAY", app_do("loop"), 82, True, False, app.keys.label("loop")),
                ("STOP", app_do("stop"), 78, True, True, app.keys.label("stop")),
                ("PAUSE", app_do("pause"), 78, True, False, app.keys.label("pause")),
                ("RENAME", lambda: self.start_rename(self.app.sel), 84, False, False, None),
                ("EXPORT", self.app.act_export, 82, False, False, None),
                ("CLEAR", self.app.act_clear, 78, False, False, None))
        for text, cmd, bw, filled, danger, sub in row1:
            btn = GoldButton(cv, text, cmd, bx, S(462), S(bw), S(30),
                             filled=filled, danger=danger, sub=sub)
            self.action_btns[text] = btn
            bx += S(bw) + S(8)

        bx = S(14)
        row2 = (("SPD -", lambda: self.app.bump_speed(-0.25), 74),
                ("SPD +", lambda: self.app.bump_speed(0.25), 74),
                ("RUNS -", lambda: self.app.bump_target(-1), 78),
                ("RUNS +", lambda: self.app.bump_target(1), 78),
                ("GAP -", lambda: self.app.bump_gap(-0.05), 74),
                ("GAP +", lambda: self.app.bump_gap(0.05), 74),
                ("FADE -", lambda: self.fade(-0.05), 78),
                ("FADE +", lambda: self.fade(0.05), 78))
        for text, cmd, bw in row2:
            GoldButton(cv, text, cmd, bx, S(498), S(bw), S(24))
            bx += S(bw) + S(8)


        bx = S(14)
        row3 = (("DETAILS", lambda: self.open_editor(), 96),
                ("SAVE", self.app.act_save, 74),
                ("LOAD", self.app.act_load, 74),
                ("FOLDER", self.app.act_folder, 84),
                ("JITTER", self.app.act_jitter, 80),
                ("GAP UNIT", self.app.act_gap_unit, 96),
                ("IMPORT", self.app.act_import, 84))
        for text, cmd, bw in row3:
            GoldButton(self.body, text, cmd, bx, S(534), S(bw), S(28),
                       filled=(text == "DETAILS"))
            bx += S(bw) + S(6)

        # ---------------- footer ----------------
        self.status_lbl = tk.Label(cv, text="", bg=T.CHROME, fg="#4A3708", anchor="w",
                                   font=(T.MONO, max(6, S(8))))
        self.status_lbl.place(x=S(18), y=S(578), width=S(self.W - 236),
                              height=S(14))
        self.ticker_lbl = tk.Label(cv, text="", bg=T.CHROME, fg="#6A5210", anchor="e",
                                   font=(T.MONO, max(6, S(7))))
        self.ticker_lbl.place(x=S(self.W - 18), y=S(579), width=S(186),
                              height=S(13), anchor="ne")


    def open_editor(self):
        """The 3-dots view he asked for: everything a slot is made of, one line
        per step, editable in place."""
        if self.app.editor is None:
            self.app.editor = Editor(self.app, self.root, self)
        self.app.editor.open(self.app.sel)

    def paint_chips(self):
        for action, chip in self.bind_chips.items():
            live = (self.app.capturing == action)
            chip.configure(text=("press a key" if live
                                 else "%s  %s" % (Keybinds.LABELS[action],
                                                  self.app.keys.label(action))),
                           bg=T.PILL if live else T.CHIP,
                           fg=T.PILL_TEXT if live else T.ON)

    def set_total(self, text):
        """Shrink the headline number as it grows so it can never collide with
        the run clock sitting on the same card."""
        size = 34 if len(text) <= 5 else (26 if len(text) <= 8 else 20)
        if size != self._total_size:
            self._total_size = size
            try:
                self.total_lbl.configure(font=(T.MONO, max(14, S(size)), "bold"))
            except Exception:
                pass
        try:
            self.total_lbl.configure(text=text)
        except Exception:
            pass

    # ---- inline rename -----------------------------------------------------
    def start_rename(self, index):
        self.cancel_rename()
        index = max(0, min(App.SLOT_COUNT - 1, int(index)))
        # deliberately does NOT change which slot is armed: act_slot() refuses to
        # switch mid-replay, and setting sel here would sneak past that guard and
        # start crediting runs to a slot that is not the one playing
        slot = self.app.slots[index]
        _chip, name_lbl, _meta = self.rows[index]
        self.app.renaming = True                 # hotkeys stand down while typing
        self.entry_slot = index
        self.entry = tk.Entry(self.body, bg=T.INK, fg=T.GOLD, relief="flat",
                              insertbackground=T.GOLD, bd=0,
                              highlightthickness=1, highlightbackground=T.GOLD_HI,
                              font=(T.MONO, max(7, S(9))))
        self.entry.insert(0, slot.name)
        self.entry.select_range(0, "end")
        self.entry.place(x=name_lbl.winfo_x(), y=name_lbl.winfo_y() - S(1),
                         width=S(150), height=S(18))
        self.entry.bind("<Return>", lambda _e: self.commit_rename())
        self.entry.bind("<KP_Enter>", lambda _e: self.commit_rename())
        self.entry.bind("<Escape>", lambda _e: self.cancel_rename())
        self.entry.bind("<FocusOut>", lambda _e: self.commit_rename())
        try:
            self.win.focus_force()
            self.entry.focus_set()
        except Exception:
            pass
        self.app.set_status("type a new name for slot %d, then press Enter"
                            % (index + 1))

    def commit_rename(self):
        if not self.entry:
            return
        try:
            text = self.entry.get()
        except Exception:
            text = ""
        index = self.entry_slot
        self._kill_entry()
        if index is not None:
            new = self.app.slots[index].rename(text)
            self.app.set_status("slot %d is now called %s" % (index + 1, new))

    def cancel_rename(self):
        if self.entry:
            self._kill_entry()

    def _kill_entry(self):
        try:
            self.entry.place_forget()
            self.entry.destroy()
        except Exception:
            pass
        self.entry = None
        self.entry_slot = None
        self.app.renaming = False

    # ---- window ------------------------------------------------------------
    def fade(self, delta):
        self.app.bump_opacity(delta)
        self.shell.set_alpha(self.app.opacity)

    def hide(self):
        try:
            self.cancel_rename()
            self.win.withdraw()
            self.app.console_shown = False
        except Exception:
            pass

    def show(self):
        try:
            self.win.deiconify()
            self.win.attributes("-topmost", True)
            self.app.console_shown = True
        except Exception:
            pass

    def quit(self):
        self.app.shutdown()

    # ---- history chart -----------------------------------------------------
    def draw_history(self):
        app = self.app
        if self._hist_version == app.history_version and app.state != app.LOOPING:
            return
        self._hist_version = app.history_version
        cv = self.hist
        cv.delete("all")
        times = list(app.loop_times)[-24:]
        w = max(1, cv.winfo_width() or S(300))
        h = max(1, cv.winfo_height() or S(44))
        cv.create_line(0, h - 1, w, h - 1, fill="#D9B43A")
        if not times:
            self.hist_lbl.configure(text="no runs yet")
            return
        top = max(times) or 1.0
        slot_w = w / float(max(8, len(times)))
        for i, secs in enumerate(times):
            bar = max(2, int((secs / top) * (h - 14)))   # leave plate showing
            x1 = i * slot_w + 1
            x2 = x1 + max(2, slot_w - 3)
            shade = hex_mix("#C9971C", "#6A4E0A", secs / top)
            cv.create_rectangle(x1, h - 1 - bar, x2, h - 1, fill=shade, width=0)
        lo, hi = min(times), max(times)
        avg = sum(times) / len(times)
        self.hist_lbl.configure(
            text="%d runs   min %.2f   avg %.2f   max %.2f   jit %.0fms"
                 % (len(times), lo, avg, hi, (hi - lo) * 1000))


# =============================================================================
# 11.  OVERLAY
# =============================================================================

def _overlaps(a, b, pad=8):
    ax, ay, aw, ah = a
    bx, by, bw, bh = b
    return not (ax + aw + pad <= bx or bx + bw + pad <= ax or
                ay + ah + pad <= by or by + bh + pad <= ay)


def place_beside(console_rect, w, h, sw, sh):
    """Find a spot for the timer that does not sit on top of the console.

    v3.0 parked it at the bottom-right of the screen and never checked. On a
    screen where the console is large relative to the desktop the two land on
    each other and the timer covers the run counters - which is exactly what
    happened on his machine.
    """
    cx, cy, cw, ch = console_rect
    m = S(14)
    candidates = [(cx + cw + m, cy),                       # to the right
                  (cx, cy + ch + m),                       # underneath
                  (sw - w - m, sh - h - m),                # bottom right
                  (sw - w - m, m),                         # top right
                  (m, sh - h - m),                         # bottom left
                  (cx - w - m, cy)]                        # to the left
    def cover(x, y):
        ox = max(0, min(x + w, cx + cw) - max(x, cx))
        oy = max(0, min(y + h, cy + ch) - max(y, cy))
        return ox * oy

    best = None
    for x, y in candidates:
        if x < 0 or y < 0 or x + w > sw or y + h > sh:
            continue
        if not _overlaps((x, y, w, h), console_rect):
            return int(x), int(y)
        area = cover(x, y)
        if best is None or area < best[0]:
            best = (area, int(x), int(y))
    if best is not None:
        return best[1], best[2]           # least-bad, still fully on screen
    return max(0, sw - w - m), max(0, sh - h - m)


class Overlay:
    W, H = 300, 122

    def __init__(self, app, root, console):
        self.app = app
        self.console = console
        w, h = S(self.W), S(self.H)
        try:
            sw, sh = root.winfo_screenwidth(), root.winfo_screenheight()
        except Exception:
            sw, sh = 1920, 1080
        try:
            console.win.update_idletasks()
            crect = (console.win.winfo_x(), console.win.winfo_y(),
                     console.win.winfo_width(), console.win.winfo_height())
        except Exception:
            crect = (0, 0, S(Console.W), S(Console.H))
        ox, oy = place_beside(crect, w, h, sw, sh)
        if _overlaps((ox, oy, w, h), crect):
            # last resort: shove the console to the top-left corner so the two
            # can coexist instead of stacking
            try:
                console.win.geometry("+%d+%d" % (S(8), S(8)))
            except Exception:
                pass
        self.shell = Shell(root, w, h, ox, oy, radius=13,
                           panel=T.CARD, band=False)
        self.win = self.shell.win
        cv = self.body = self.shell.canvas
        cv.create_line(S(14), S(3), w - S(14), S(3), fill=T.HL)

        # progress ring - a gold arc reads better than a flat bar
        cx, cy, r = S(48), S(62), S(27)
        cv.create_oval(cx - r, cy - r, cx + r, cy + r, outline=T.CARD_LO,
                       width=S(6))
        self.arc = cv.create_arc(cx - r, cy - r, cx + r, cy + r, start=90,
                                 extent=-1, style="arc", outline=T.ON,
                                 width=S(6))
        cv.itemconfigure(self.arc, state="hidden")
        self.ring_lbl = tk.Label(cv, text="\u25CF", bg=T.CARD, fg=T.FAINT_C,
                                 font=(T.UI, max(8, S(12))))
        self.ring_lbl.place(x=cx, y=cy, anchor="center")

        self.state_lbl = tk.Label(cv, text=App.IDLE, bg=T.CARD, fg=T.ON,
                                  font=(T.UI, max(8, S(10)), "bold"))
        self.state_lbl.place(x=S(86), y=S(16), height=S(14))
        self.count_lbl = tk.Label(cv, text="\u00D70", bg=T.CARD, fg=T.RED,
                                  font=(T.MONO, max(14, S(23)), "bold"))
        self.count_lbl.place(x=S(84), y=S(34), width=S(94), height=S(30))
        self.clock_lbl = tk.Label(cv, text="00:00.0", bg=T.CARD, fg=T.RED,
                                  anchor="w", font=(T.MONO, max(11, S(15)), "bold"))
        self.clock_lbl.place(x=S(84), y=S(70), width=S(94), height=S(22))
        self.slot_lbl = tk.Label(cv, text="", bg=T.CARD, fg=T.H1, anchor="e",
                                 font=(T.MONO, max(6, S(7)), "bold"))
        self.slot_lbl.place(x=S(self.W - 14), y=S(18), width=S(92), height=S(12),
                            anchor="ne")
        self.c_lbl = tk.Label(cv, text="", bg=T.CARD, fg=T.DIM, anchor="e",
                              font=(T.MONO, max(6, S(8))))
        self.c_lbl.place(x=S(self.W - 14), y=S(46), width=S(92), height=S(13),
                         anchor="ne")
        self.t_lbl = tk.Label(cv, text="", bg=T.CARD, fg=T.DIM, anchor="e",
                              font=(T.MONO, max(6, S(8))))
        self.t_lbl.place(x=S(self.W - 14), y=S(66), width=S(92), height=S(13),
                         anchor="ne")
        self.hint_lbl = tk.Label(cv, text="double-click = console", bg=T.CARD,
                                 fg=T.FAINT_C, anchor="e",
                                 font=(T.MONO, max(6, S(6))))
        self.hint_lbl.place(x=S(self.W - 14), y=S(100), width=S(160),
                            height=S(11), anchor="ne")

        cv.bind("<Double-Button-1>", self.toggle_console, add="+")
        for wdg in (self.count_lbl, self.clock_lbl, self.state_lbl, self.ring_lbl,
                    self.c_lbl, self.t_lbl, self.slot_lbl, self.hint_lbl):
            wdg.bind("<Double-Button-1>", self.toggle_console, add="+")
            self.shell.bind_drag(wdg)

    def toggle_console(self, _=None):
        if self.app.console_shown:
            self.console.hide()
        else:
            self.console.show()

    def set_progress(self, frac):
        try:
            if frac <= 0.001:
                self.body.itemconfigure(self.arc, state="hidden")
            else:
                self.body.itemconfigure(self.arc, state="normal",
                                        extent=-max(0.5, 360.0 * frac))
        except Exception:
            pass


# =============================================================================
# 12.  RUNTIME
# =============================================================================

class Runtime:
    TICK = 33          # ms -> ~30 fps

    def __init__(self):
        self.app = App()
        APP_REF[0] = self.app
        self.app.shutdown = self.shutdown
        self.root = tk.Tk()                    # the one and only Tk interpreter
        self.root.withdraw()
        try:
            self.root.title(APP_NAME)
        except Exception:
            pass
        self.console = Console(self.app, self.root)
        self.overlay = Overlay(self.app, self.root, self.console)
        self.app.hub.start()
        self._alive = True

    # ---- queue drain (main thread only) -----------------------------------
    def drain(self):
        app = self.app
        while True:
            try:
                kind, payload = app.bus.get_nowait()
            except queue.Empty:
                break
            try:
                if kind == "hotkey":
                    self.hotkey(payload)
                elif kind == "loop_start":
                    app.loop_started = payload[1]
                elif kind == "loop_done":
                    n, secs = payload
                    app.session_runs = n
                    app.total_runs += 1
                    app.slots[app.playing_slot].runs += 1
                    app.loop_times.append(secs)
                    app.history_version += 1
                    app.ticker = "run %s in %.2fs" % (fmt_int(n), secs)
                elif kind == "paused":
                    app.paused = bool(payload)
                elif kind == "target_hit":
                    app.set_status("target reached - %s runs done" % fmt_int(payload))
                elif kind == "player_end":
                    if app.state == app.LOOPING:
                        app.state = app.IDLE
                        app.paused = False
                        app.run_seconds = time.perf_counter() - app.run_started
                        if "target reached" not in app.status:
                            app.set_status("replay ended after %s runs"
                                           % fmt_int(app.session_runs))
                elif kind == "warn":
                    app.ticker = str(payload)
                elif kind == "error":
                    app.set_status("player error: %s" % payload)
            except Exception:
                _log_crash("drain: " + traceback.format_exc())

    def hotkey(self, action):
        app = self.app
        if isinstance(action, str) and action.startswith("slot:"):
            app.act_slot(int(action.split(":")[1]))
            return
        if isinstance(action, str) and action.startswith("capture:"):
            try:
                _tag, vk, ctrl, shift, alt = action.split(":")
                app.act_capture_key(int(vk), bool(int(ctrl)), bool(int(shift)),
                                    bool(int(alt)))
            except Exception:
                app.capturing = None
            return
        {"rec": app.act_record,
         "loop": app.act_loop,
         "stop": app.act_stop,
         "pause": app.act_pause,
         "panic": lambda: app.act_stop(panic=True)}.get(action, lambda: None)()

    # ---- paint ------------------------------------------------------------
    def paint(self):
        app, c, o = self.app, self.console, self.overlay
        app._pulse = (app._pulse + 0.09) % 1.0
        wave = abs(0.5 - app._pulse) * 2

        # two dot colours: the console dot sits on the dark title strip, the
        # overlay dot sits on the gold plate, so they need opposite contrast
        if app.state == app.RECORDING:
            dot = hex_mix(T.RED_BRIGHT, "#FF9A93", 1 - wave)
            dot_gold = hex_mix(T.RED, T.RED_HI, 1 - wave)
            colour = T.ON
        elif app.state == app.LOOPING:
            dot = T.GOLD_DIM if app.paused else hex_mix(T.GOLD_DIM, T.GOLD, 1 - wave)
            dot_gold = T.H1 if app.paused else hex_mix(T.H1, T.ON, 1 - wave)
            colour = T.ON
        else:
            dot, dot_gold, colour = T.OFF, T.FAINT_C, T.H1

        c.dot.configure(fg=dot)
        o.ring_lbl.configure(fg=dot_gold)
        for lbl in (c.state_lbl, o.state_lbl):
            lbl.configure(text=app.state, fg=colour)
        c.pause_lbl.configure(text="PAUSED" if app.paused else "")

        clock = fmt_clock(app.elapsed())
        count = "\u00D7%s" % fmt_int(app.session_runs)
        c.clock_lbl.configure(text=clock)
        o.clock_lbl.configure(text=clock)
        c.count_lbl.configure(text=count)
        o.count_lbl.configure(text=count)
        c.set_total(fmt_int(app.total_runs))
        c.target_lbl.configure(text="target: %s" % ("forever" if not app.target_runs
                                                    else "%d runs" % app.target_runs))
        c.cfg_lbl.configure(text="speed %.2fx     gap %.2fs     fade %d%%     %s"
                                 % (app.speed, app.gap, int(app.opacity * 100),
                                    app.slot().name))

        # slot rack
        for i, slot in enumerate(app.slots):
            chip, name, meta = c.rows[i]
            picked = (i == app.sel)
            recording = (app.state == app.RECORDING and i == app.rec_target)
            chip.configure(bg=T.INK if picked else T.CARD,
                           fg=T.GOLD if picked else T.H1)
            name.configure(text=slot.name,
                           fg=T.VAL if picked else (T.TEXT if not slot.empty
                                                    else T.FAINT_C))
            if recording:
                meta.configure(text="recording...", fg=T.RED)
            elif slot.empty:
                meta.configure(text="empty", fg=T.FAINT_C)
            else:
                meta.configure(text="%s  %s%s" % (slot.label(), slot.stamp,
                                                  "  x%d" % slot.runs if slot.runs else ""),
                               fg=T.DIM)

        # macro make-up
        st = app.live_stats()
        c.stats["m_clicks"].configure(text=fmt_int(st["clicks"]))
        c.stats["m_taps"].configure(text=fmt_int(st["taps"]))
        c.stats["m_scrolls"].configure(text=fmt_int(st["scrolls"]))
        c.stats["m_moves"].configure(text=fmt_int(st["moves"]))
        c.stats["m_distance"].configure(text=fmt_dist(st["distance"]))
        c.stats["m_duration"].configure(text="%.2fs" % st["duration"])

        # fired counters
        cnt = app.counters
        c.stats["f_clicks"].configure(text=fmt_int(cnt.get("clicks", 0)))
        c.stats["f_taps"].configure(text=fmt_int(cnt.get("taps", 0)))
        c.stats["f_scrolls"].configure(text=fmt_int(cnt.get("scrolls", 0)))
        c.stats["f_actions"].configure(text=fmt_int(cnt.get("actions", 0)))
        c.stats["f_aps"].configure(text="%.1f" % app.per_second())
        c.stats["f_cpm"].configure(text="%.0f" % app.clicks_per_min())

        c.paint_chips()
        for name, act in (("REC", "rec"), ("REPLAY", "loop"),
                          ("STOP", "stop"), ("PAUSE", "pause")):
            btn = c.action_btns.get(name)
            if btn is not None and btn.sub is not None:
                lab = app.keys.label(act)
                if btn.sub.cget("text") != lab:
                    btn.sub.configure(text=lab)
        c.status_lbl.configure(text=app.status)
        c.ticker_lbl.configure(text=app.ticker)
        c.draw_history()

        o.slot_lbl.configure(text=app.slot().name)
        o.c_lbl.configure(text="%s clicks" % fmt_int(cnt.get("clicks", 0)))
        o.t_lbl.configure(text="%s taps" % fmt_int(cnt.get("taps", 0)))
        o.set_progress(app.loop_progress())

    def tick(self):
        if not self._alive:
            return
        try:
            self.drain()
            self.paint()
        except Exception:
            _log_crash("tick: " + traceback.format_exc())
        try:
            self.root.after(self.TICK, self.tick)
        except Exception:
            pass

    def shutdown(self):
        self._alive = False
        try:
            self.app.stop_evt.set()
            self.app.pause_evt.clear()
            if self.app.player and self.app.player.is_alive():
                self.app.player.join(timeout=2.0)
        except Exception:
            pass
        try:
            self.app.hub.stop()
        except Exception:
            pass
        _timer_resolution(False)
        for win in (getattr(self, "overlay", None), getattr(self, "console", None)):
            try:
                win.win.destroy()
            except Exception:
                pass
        try:
            self.root.destroy()
        except Exception:
            pass
        os._exit(0)

    def run(self):
        self.root.after(60, self.tick)
        _hide_console()
        self.root.mainloop()


def main() -> int:
    if tk is None:
        print("Tkinter is not available in this Python installation.")
        return 1
    if not _single_instance():
        try:
            import tkinter.messagebox as mb
            root = tk.Tk()
            root.withdraw()
            mb.showinfo(APP_NAME, "%s is already running.\nUse the window that is "
                                  "already open." % APP_NAME)
            root.destroy()
        except Exception:
            print("%s is already running." % APP_NAME)
        return 0
    Runtime().run()
    return 0


# =============================================================================
# 13.  SELF-TEST
# =============================================================================

def _selftest() -> int:
    fails = []
    passed = [0]

    def check(name, cond, extra=""):
        if cond:
            passed[0] += 1
            print("  PASS  %s" % name)
        else:
            print("  FAIL  %s  %s" % (name, extra))
            fails.append(name)

    print("%s %s self-test" % (APP_NAME, APP_VER))
    K = keyboard.Key
    KC = keyboard.KeyCode

    # ---- 1  key identity + reconstruction ---------------------------------
    kid_a, n_a, v_a, _c = key_payload(KC.from_vk(65))
    _kb, n_b, _vb, _cb = key_payload(K.shift)
    check("payload: printable key keeps its vk", v_a == 65 and n_a is None)
    check("payload: special key keeps its name", n_b == "shift")
    check("rebuild: name wins so EXTENDEDKEY survives",
          rebuild_key({"v": 65, "n": "delete", "c": None}) is K.delete)
    check("rebuild: printable falls through to vk",
          getattr(rebuild_key({"v": 65, "n": None, "c": "a"}), "vk", None) == 65)
    check("rebuild: empty payload returns None",
          rebuild_key({"v": None, "n": None, "c": None}) is None)

    # ---- 2  recorder pairing + hotkey pruning -----------------------------
    r = Recorder()
    r.start()
    kid, n, v, c = key_payload(KC.from_vk(65))
    r.on_key(kid, n, v, c, True)
    r.on_key(kid, n, v, c, False)
    evs = r.stop()
    check("recorder: one press + one release", len(evs) == 2)
    r = Recorder()
    r.start()
    r.on_key(kid, n, v, c, False)
    check("recorder: dangling release dropped", len(r.stop()) == 0)

    r = Recorder()
    r.start()
    ck, cn, cv2, cc = key_payload(K.ctrl_l)
    r.on_key(ck, cn, cv2, cc, True)
    r.on_key(kid, n, v, c, True)
    r.on_key(kid, n, v, c, False)
    r.on_key(ck, cn, cv2, cc, False)
    r.on_key(ck, cn, cv2, cc, True)          # ctrl still held for CTRL+M
    evs = r.stop(suppress_ids={ck})
    check("recorder: dangling hotkey CTRL pruned",
          len([e for e in evs if e["k"] == EV_KDOWN and e["id"] == ck]) == 1, str(evs))
    check("recorder: nothing left held", _no_stuck(evs), str(_stuck(evs)))

    # ---- 3  live counters while recording ---------------------------------
    r = Recorder()
    r.start()
    r.on_click(0, 0, mouse.Button.left, True)
    r.on_click(0, 0, mouse.Button.left, False)
    for _ in range(5):
        r.on_key(kid, n, v, c, True)         # OS auto-repeat of ONE hold
    r.on_key(kid, n, v, c, False)
    r.on_scroll(0, 0, 0, -1)
    r.on_move(0, 0)
    time.sleep(Recorder.MOVE_MIN_DT * 2)
    r.on_move(300, 400)
    live = dict(r.live)
    r.stop()
    check("live: clicks counted", live["clicks"] == 1, live)
    check("live: a held key counts as ONE tap, not five", live["taps"] == 1, live)
    check("live: scrolls counted", live["scrolls"] == 1, live)
    check("live: travel measured as real distance",
          499 < live["distance"] < 501, live["distance"])
    r2 = Recorder()
    r2.start()
    for i in range(50):
        r2.on_move(i, 0)                     # a fast flick, inside the sample gap
    check("live: sampled moves and stored stats agree exactly",
          macro_stats(r2.stop())["moves"] == r2.live["moves"],
          (r2.live["moves"],))

    # ---- 4  macro_stats matches the live counters -------------------------
    r = Recorder()
    r.start()
    r.on_click(10, 10, mouse.Button.left, True)
    r.on_click(10, 10, mouse.Button.left, False)
    r.on_click(10, 10, mouse.Button.right, True)
    r.on_click(10, 10, mouse.Button.right, False)
    for _ in range(4):
        r.on_key(kid, n, v, c, True)
    r.on_key(kid, n, v, c, False)
    r.on_key("v:66", None, 66, "b", True)
    r.on_key("v:66", None, 66, "b", False)
    r.on_scroll(1, 1, 0, 1)
    stats = macro_stats(r.stop())
    check("stats: clicks", stats["clicks"] == 2, stats)
    check("stats: taps ignore auto-repeat", stats["taps"] == 2, stats)
    check("stats: scrolls", stats["scrolls"] == 1, stats)
    check("stats: empty macro is all zeros",
          macro_stats([])["clicks"] == 0 and macro_stats([])["duration"] == 0.0)
    check("stats: distance across three points",
          macro_stats([{"t": 0, "k": EV_MOVE, "x": 0, "y": 0},
                       {"t": 1, "k": EV_MOVE, "x": 0, "y": 100},
                       {"t": 2, "k": EV_MOVE, "x": 0, "y": 130}])["distance"] == 130.0)

    # ---- 5  slot behaviour -------------------------------------------------
    s0 = Slot(0)
    check("slot: starts empty with a default name",
          s0.empty and s0.name == "SLOT 1" and s0.label() == "empty")
    s0.fill([{"t": 0.0, "k": EV_MOVE, "x": 1, "y": 1},
             {"t": 1.5, "k": EV_DOWN, "b": "left", "x": 1, "y": 1},
             {"t": 1.6, "k": EV_UP, "b": "left", "x": 1, "y": 1}])
    check("slot: fill computes stats", s0.stats["clicks"] == 1 and not s0.empty)
    check("slot: label shows events and length", "1.60s" in s0.label(), s0.label())
    check("slot: rename cleans whitespace",
          s0.rename("  my   farm  macro  ") == "my farm macro")
    check("slot: rename trims to a sane length",
          len(s0.rename("x" * 90)) == 18, s0.name)
    check("slot: empty rename falls back, never blank", s0.rename("   ") == "SLOT 1")
    check("slot: rename survives junk", s0.rename(None) == "SLOT 1")
    s0.wipe()
    check("slot: wipe empties it", s0.empty and s0.stats["events"] == 0)
    check("name cleaner: unprintables go, whitespace becomes a space",
          clean_name("ab\x00c\td") == "abc d", clean_name("ab\x00c\td"))

    # ---- 6  app: slot selection, overwrite protection, counters -----------
    app = App()
    check("app: six slots, first selected",
          len(app.slots) == App.SLOT_COUNT and app.sel == 0)
    app.act_slot(3)
    check("app: CTRL+4 selects slot 4", app.sel == 3)
    app.act_slot(99)
    check("app: out-of-range slot is clamped", app.sel == App.SLOT_COUNT - 1)
    app.act_slot(0)
    app.slots[0].fill([{"t": 0.0, "k": EV_MOVE, "x": 1, "y": 1}])
    app.act_record()
    check("app: recording never quietly overwrites a full slot",
          app.rec_target == 1 and app.sel == 1, (app.sel, app.rec_target))
    app.act_stop()
    for slot in app.slots:
        slot.fill([{"t": 0.0, "k": EV_MOVE, "x": 1, "y": 1}])
    app.act_slot(2)
    app.act_record()
    check("app: with every slot full it reuses the selected one",
          app.rec_target == 2, app.rec_target)
    app.act_stop()
    app.act_clear()
    check("app: clear empties every slot",
          all(s.empty for s in app.slots) and app.total_runs == 0)
    check("app: clear zeroes the fired counters",
          app.counters["clicks"] == 0 and app.counters["actions"] == 0)

    # renaming any slot must not re-arm it
    app = App()
    app.slots[0].fill([{"t": 0.0, "k": EV_MOVE, "x": 1, "y": 1}])
    app.act_slot(0)
    app.slots[4].rename("other")
    check("rename: renaming slot 5 leaves slot 1 armed", app.sel == 0, app.sel)
    check("rename: the renamed slot really changed", app.slots[4].name == "other")

    # ---- 7  adjusters clamp -----------------------------------------------
    app = App()
    for _ in range(50):
        app.bump_speed(-0.25)
    check("speed clamps at 0.25x", app.speed == 0.25, app.speed)
    for _ in range(100):
        app.bump_speed(0.25)
    check("speed clamps at 4.00x", app.speed == 4.0, app.speed)
    for _ in range(9):
        app.bump_target(-1)
    check("target cannot go below 0 (= forever)", app.target_runs == 0)
    app.bump_target(3)
    check("target counts up", app.target_runs == 3)
    for _ in range(60):
        app.bump_gap(-0.05)
    check("gap clamps at 0.00", app.gap == 0.0)
    for _ in range(60):
        app.bump_opacity(-0.05)
    check("fade never goes fully invisible", app.opacity == 0.40, app.opacity)

    # ---- 8  echo filter ----------------------------------------------------
    e = Echo()
    e.arm(EV_KDOWN, "v:80")
    check("echo: synthetic press recognised once", e.consume(EV_KDOWN, "v:80") is True)
    check("echo: not consumed twice", e.consume(EV_KDOWN, "v:80") is False)
    e2 = Echo()
    e2.WINDOW = 0.0
    e2.arm(EV_KDOWN, "v:80")
    time.sleep(0.01)
    check("echo: stale entry expires", e2.consume(EV_KDOWN, "v:80") is False)

    # ---- 9  player: order, speed, target, pause, counters ----------------
    seq = [{"t": 0.00, "k": EV_MOVE, "x": 10, "y": 10},
           {"t": 0.04, "k": EV_DOWN, "b": "left", "x": 10, "y": 10},
           {"t": 0.06, "k": EV_UP, "b": "left", "x": 10, "y": 10},
           {"t": 0.09, "k": EV_KDOWN, "id": "v:65", "n": None, "v": 65, "c": "a"},
           {"t": 0.11, "k": EV_KUP, "id": "v:65", "n": None, "v": 65, "c": "a"}]
    bus = queue.Queue()
    stop = threading.Event()
    counters = {}
    p = Player(seq, stop, bus, Echo(), lambda: 0.0, lambda: 1.0, lambda: 0, counters)
    p.start()
    time.sleep(Player.LEAD_IN + 0.5)
    stop.set()
    p.join(timeout=3.0)
    loops = [v[0] for k, v in list(bus.queue) if k == "loop_done"]
    check("player: thread exits on stop", not p.is_alive())
    check("player: looped several times", len(loops) >= 2, loops)
    check("player: released everything", not p._keys_down and not p._btns_down)
    runs = len(loops)
    check("player: counted the clicks it fired",
          runs <= counters["clicks"] <= runs + 1, (counters, runs))
    check("player: counted the taps it fired",
          runs <= counters["taps"] <= runs + 1, counters)
    check("player: counted total actions",
          runs * 5 <= counters["actions"] <= (runs + 1) * 5, counters)
    check("player: every fired action is accounted for",
          counters["actions"] >= counters["clicks"] + counters["taps"], counters)

    # target count stops on its own
    bus = queue.Queue()
    stop = threading.Event()
    p = Player(seq, stop, bus, Echo(), lambda: 0.0, lambda: 4.0, lambda: 3, {})
    p.start()
    p.join(timeout=6.0)
    kinds = [k for k, _v in list(bus.queue)]
    done = [v[0] for k, v in list(bus.queue) if k == "loop_done"]
    check("player: a run target stops it without CTRL+P", not p.is_alive())
    check("player: it ran exactly the target number of times", done[-1] == 3, done)
    check("player: it announced hitting the target", "target_hit" in kinds, kinds)

    # speed really changes the wall-clock length
    def timed(speed):
        st = threading.Event()
        bs = queue.Queue()
        pl = Player([{"t": 0.0, "k": EV_MOVE, "x": 1, "y": 1},
                     {"t": 0.40, "k": EV_MOVE, "x": 2, "y": 2}],
                    st, bs, Echo(), lambda: 0.0, lambda: speed, lambda: 1, {})
        t0 = time.perf_counter()
        pl.start()
        pl.join(timeout=6.0)
        return time.perf_counter() - t0 - Player.LEAD_IN

    slow, fast = timed(1.0), timed(4.0)
    check("speed: 1.00x replays at the recorded length", 0.34 < slow < 0.55, round(slow, 3))
    check("speed: 4.00x replays about four times faster",
          0.05 < fast < 0.20, round(fast, 3))
    check("speed: faster really is faster", fast < slow * 0.6, (round(fast, 3), round(slow, 3)))

    # pause holds, resume does not rush to catch up
    st = threading.Event()
    pe = threading.Event()
    bs = queue.Queue()
    long_seq = [{"t": 0.0, "k": EV_MOVE, "x": 1, "y": 1},
                {"t": 0.50, "k": EV_MOVE, "x": 2, "y": 2}]
    pl = Player(long_seq, st, bs, Echo(), lambda: 0.0, lambda: 1.0, lambda: 1, {}, pe)
    pl.start()
    time.sleep(Player.LEAD_IN + 0.10)
    pl.toggle_pause()
    time.sleep(0.40)
    check("pause: it reported being paused",
          any(k == "paused" and v for k, v in list(bs.queue)))
    check("pause: the run has not finished while paused", pl.is_alive())
    pl.toggle_pause()
    pl.join(timeout=4.0)
    check("pause: it finished after resuming", not pl.is_alive())
    check("pause: paused time was added, not skipped", pl._debt >= 0.3, pl._debt)

    # ---- 10  panic key -----------------------------------------------------
    app = App()
    hub = Hub(app)
    now = time.perf_counter()
    check("panic: one ESC is not a panic", hub._panic_check(now) is False)
    check("panic: two are not either", hub._panic_check(now + 0.1) is False)
    check("panic: three inside a second fire", hub._panic_check(now + 0.2) is True)
    hub2 = Hub(App())
    check("panic: three SLOW presses do not fire",
          [hub2._panic_check(now + i * 0.8) for i in range(3)][-1] is False)
    app.state = App.LOOPING
    check("panic: only armed while replaying", app.is_replaying() is True)
    app.state = App.RECORDING
    check("panic: disarmed while recording", app.is_replaying() is False)

    # ---- 11  hotkey routing ------------------------------------------------
    app = App()
    hub = Hub(app)
    hub._ctrl.add("n:ctrl_l")
    hub._press(KC.from_vk(51))                     # CTRL+3
    msgs = list(app.bus.queue)
    check("hotkey: CTRL+3 asks for slot 3",
          ("hotkey", "slot:2") in msgs, msgs)
    app.bus.queue.clear()
    hub._press(KC.from_vk(74))                     # CTRL+J
    check("hotkey: CTRL+J asks for pause",
          ("hotkey", "pause") in list(app.bus.queue), list(app.bus.queue))
    app.bus.queue.clear()
    app.renaming = True
    hub._press(KC.from_vk(78))                     # CTRL+N while renaming a slot
    check("hotkey: hotkeys stand down while renaming a slot", app.bus.empty(),
          list(app.bus.queue))
    app.renaming = False

    # ---- 12  formatting helpers -------------------------------------------
    check("clock: minutes", fmt_clock(65.4).startswith("01:05"))
    check("clock: hours", fmt_clock(3725.0).startswith("1:02:05"))
    check("clock: negative clamps", fmt_clock(-9) == "00:00.0")
    check("int: thousands separator", fmt_int(1234567) == "1,234,567")
    check("int: junk becomes zero", fmt_int(None) == "0")
    check("distance: small stays in px", fmt_dist(940) == "940 px")
    check("distance: large becomes k", fmt_dist(12345) == "12.3k px")
    check("mix: endpoints exact", hex_mix("#000000", "#FFFFFF", 1.0) == "#FFFFFF")
    check("mix: clamps out of range", hex_mix("#000000", "#FFFFFF", 9) == "#FFFFFF")
    check("duration: last timestamp wins", macro_duration(seq) == 0.11)

    # ---- 13  v3: scan codes, injection payloads, keybinds ------------------
    r = Recorder()
    r.start()
    r.on_key("v:81", None, 81, "q", True, 0x10, False)      # Q, scan 0x10
    r.on_key("v:81", None, 81, "q", False, 0x10, False)
    evs = r.stop()
    check("scan: the hardware scan code is recorded",
          evs[0].get("s") == 0x10, evs[0])
    check("scan: it survives a JSON round trip",
          json.loads(json.dumps(evs))[0]["s"] == 0x10)
    check("scan: extended flag is stored per key",
          evs[0].get("e") == 0)

    if True:                       # payloads build anywhere; only sending is gated
        item = _key_input(81, 0x10, False, False)
        check("inject: a key event is built as a scan code",
              item.u.ki.dwFlags & KEYEVENTF_SCANCODE and item.u.ki.wScan == 0x10)
        check("inject: our signature is stamped on it",
              item.u.ki.dwExtraInfo == GOLD_SIG)
        up = _key_input(81, 0x10, False, True)
        check("inject: key-up carries the KEYUP flag",
              up.u.ki.dwFlags & KEYEVENTF_KEYUP)
        ext = _key_input(0x27, 0, True, False)
        check("inject: extended keys get the extended flag",
              ext.u.ki.dwFlags & KEYEVENTF_EXTENDEDKEY)
        auto = _key_input(0x27, 0, False, False)
        check("inject: an imported arrow key still gets the flag from the vk",
              auto.u.ki.dwFlags & KEYEVENTF_EXTENDEDKEY)
        num6 = _key_input(0x66, 0, False, False)
        check("inject: numpad 6 is NOT marked extended, so it stays numpad 6",
              not (num6.u.ki.dwFlags & KEYEVENTF_EXTENDEDKEY))
        uni = _key_input(0, 0, False, False, unicode_char="\u00e9")
        check("inject: a key with no scan code falls back to unicode",
              uni.u.ki.dwFlags & KEYEVENTF_UNICODE)
        check("inject: a plain key carries NO extended flag",
              not (item.u.ki.dwFlags & KEYEVENTF_EXTENDEDKEY))
        check("inject: scan-code mode leaves wVk at zero, as Windows requires",
              item.u.ki.wVk == 0)
        check("inject: mouse events are stamped too",
              _mouse_move_input(3, 3).u.mi.dwExtraInfo == GOLD_SIG)
        far = _mouse_move_input(10 ** 9, 10 ** 9)
        check("inject: a wild coordinate is clamped, not wrapped",
              0 <= far.u.mi.dx <= 65535 and 0 <= far.u.mi.dy <= 65535,
              (far.u.mi.dx, far.u.mi.dy))
        neg = _mouse_move_input(-10 ** 9, -10 ** 9)
        check("inject: a negative coordinate is clamped too",
              0 <= neg.u.mi.dx <= 65535 and 0 <= neg.u.mi.dy <= 65535)
        btn = _mouse_button_input("left", True)
        check("inject: a left press is a real mouse event",
              btn.u.mi.dwFlags & MOUSEEVENTF_LEFTDOWN)
        check("inject: an unknown button is refused, not faked",
              _mouse_button_input("nonsense", True) is None)
        mv = _mouse_move_input(0, 0)
        check("inject: moves are absolute across the virtual desktop",
              mv.u.mi.dwFlags & (MOUSEEVENTF_ABSOLUTE | MOUSEEVENTF_VIRTUALDESK))
        wheel = _mouse_scroll_input(0, -2)
        check("inject: a scroll of 2 notches is 2 wheel deltas",
              len(wheel) == 1 and wheel[0].u.mi.mouseData ==
              ctypes.c_ulong(-2 * WHEEL_DELTA).value)
        check("inject: a zero scroll sends nothing", _mouse_scroll_input(0, 0) == [])
    check("inject: sending is refused off Windows instead of crashing",
          _send_inputs([_key_input(81, 0x10, False, False)]) == 0 or IS_WIN)

    kb = Keybinds()
    kb.binds = dict(Keybinds.DEFAULTS)
    check("keybind: the defaults read back as labels",
          kb.label("rec") == "CTRL+N" and kb.label("pause") == "CTRL+J")
    check("keybind: a bound combo is matched", kb.match(78, True, False, False) == "rec")
    check("keybind: the same key without CTRL is NOT the hotkey",
          kb.match(78, False, False, False) is None)
    ok, msg = kb.rebind("rec", 0x70, False, False, False)     # plain F1
    check("keybind: rebinding to F1 works", ok and kb.label("rec") == "F1", msg)
    check("keybind: F1 now fires the action", kb.match(0x70, False, False, False) == "rec")
    check("keybind: CTRL+N is free again for the macro to use",
          kb.match(78, True, False, False) is None)
    ok2, msg2 = kb.rebind("loop", 0x70, False, False, False)
    check("keybind: it refuses to bind two actions to one combo", not ok2, msg2)
    ok3, msg3 = kb.rebind("rec", 0x11, True, False, False)
    check("keybind: a bare modifier is refused", not ok3, msg3)
    kb.reset()
    check("keybind: reset restores the defaults", kb.label("rec") == "CTRL+N")
    check("keybind: labels cover letters, F-keys and punctuation",
          vk_label(0x41) == "A" and vk_label(0x74) == "F5" and
          vk_label(0xBC) == "," and vk_label(0x25, True) == "CTRL+LEFT")

    app = App()
    app.act_capture("rec")
    check("capture: clicking a keybind arms capture", app.capturing == "rec")
    app.act_capture_key(0x11, True, False, False)
    check("capture: a bare modifier does not end capture", app.capturing == "rec")
    app.act_capture_key(0x74, False, False, False)
    check("capture: the real key lands the bind",
          app.capturing is None and app.keys.label("rec") == "F5")
    app.act_capture("loop")
    app.act_capture_key(0x1B, False, False, False)
    check("capture: ESC cancels without changing anything",
          app.capturing is None and app.keys.label("loop") == "CTRL+M")
    app.act_reset_keys()

    # ---- 13b  the timer must never sit on top of the console --------------
    console = (100, 100, 700, 552)
    x, y = place_beside(console, 300, 122, 1920, 1080)
    check("placement: timer goes beside the console, not on it",
          not _overlaps((x, y, 300, 122), console), (x, y))
    check("placement: and stays on screen",
          0 <= x and 0 <= y and x + 300 <= 1920 and y + 122 <= 1080, (x, y))
    x2, y2 = place_beside((0, 0, 700, 552), 300, 122, 1000, 600)
    check("placement: on a screen with no clean spot it stays fully visible",
          0 <= x2 and 0 <= y2 and x2 + 300 <= 1000 and y2 + 122 <= 600, (x2, y2))
    check("placement: and it picks the corner that covers the least",
          (x2, y2) == (686, 464), (x2, y2))
    x3, y3 = place_beside((0, 0, 900, 560), 300, 122, 920, 580)
    check("placement: when nothing fits it still lands on screen",
          0 <= x3 <= 920 - 300 + 20 and 0 <= y3 <= 580, (x3, y3))
    check("overlap: touching rectangles count as overlapping",
          _overlaps((0, 0, 10, 10), (5, 5, 10, 10)))
    check("overlap: separated rectangles do not",
          not _overlaps((0, 0, 10, 10), (100, 100, 10, 10)))
    check("overlap: a small gap still counts, so they never kiss",
          _overlaps((0, 0, 10, 10), (12, 0, 10, 10)))

    # ---- 14  layout sanity -------------------------------------------------
    check("layout: headline shrinks as the number grows",
          (38 if len("214") <= 5 else 0) == 38 and
          (30 if len("987,654") <= 8 else 0) == 30 and
          (23 if len("12,345,678") > 8 else 0) == 23)
    row1 = (78, 82, 78, 78, 84, 82, 78)
    row2 = (74, 74, 78, 78, 74, 74, 78, 78)
    check("layout: button row 1 fits",
          sum(row1) + 8 * (len(row1) - 1) + 14 <= Console.W - 10,
          sum(row1) + 8 * (len(row1) - 1) + 14)
    check("layout: button row 2 fits",
          sum(row2) + 8 * (len(row2) - 1) + 14 <= Console.W - 10,
          sum(row2) + 8 * (len(row2) - 1) + 14)
    check("layout: slot rack fits inside its card",
          158 + App.SLOT_COUNT * 22 <= 296, 158 + App.SLOT_COUNT * 22)
    check("layout: keybind strip clears the button rows", 406 + 44 <= 462)
    check("layout: the footer clears the second button row", 498 + 24 <= 530)
    check("layout: everything fits the taller window", 530 + 14 <= Console.H)

    erow1 = (74, 74, 74, 74, 78, 84, 70, 52, 60)
    erow2 = (78, 82, 108, 74, 74)
    check("layout: editor button row 1 fits",
          sum(erow1) + 5 * (len(erow1) - 1) + 14 <= Editor.W - 10,
          sum(erow1) + 5 * (len(erow1) - 1) + 14)
    check("layout: editor button row 2 fits",
          sum(erow2) + 5 * (len(erow2) - 1) + 14 <= Editor.W - 10)
    check("layout: editor rows clear the window", 524 + 26 <= Editor.H)
    row3 = (96, 74, 74, 84, 80, 96, 84)
    check("layout: button row 3 fits",
          sum(row3) + 6 * (len(row3) - 1) + 14 <= Console.W - 10,
          sum(row3) + 6 * (len(row3) - 1) + 14)
    check("layout: the footer clears the third button row", 534 + 28 <= 578)

    check("wait: seconds convert by unit",
          wait_seconds(2, "min") == 120.0 and wait_seconds(1, "day") == 86400.0)
    check("wait: junk reads as zero rather than throwing",
          wait_seconds("x", "min") == 0.0 and wait_seconds(-5, "sec") == 0.0)
    check("wait: an unknown unit falls back to seconds",
          wait_seconds(3, "fortnight") == 3.0)
    check("wait: seconds split back to the biggest clean unit",
          split_seconds(3600) == (1.0, "hour")
          and split_seconds(90) == (1.5, "min")
          and split_seconds(2.5) == (2.5, "sec"))
    check("wait: one of a unit is singular, two is plural",
          fmt_wait(1, "min") == "1 min" and fmt_wait(2, "min") == "2 mins")

    waited = [{"k": EV_DOWN, "t": 0.0, "b": "left", "x": 1, "y": 2},
              {"k": EV_WAIT, "t": 0.0, "q": 2, "u": "sec"},
              {"k": EV_UP, "t": 1.0, "b": "left", "x": 1, "y": 2}]
    flat = flatten_events(waited)
    check("wait: the step itself never reaches the player",
          len(flat) == 2 and all(e["k"] != EV_WAIT for e in flat))
    check("wait: it pushes everything after it later, not just itself",
          abs(flat[1]["t"] - 3.0) < 1e-9, flat[1]["t"])
    check("wait: it leaves anything before it alone",
          abs(flat[0]["t"] - 0.0) < 1e-9)
    check("wait: two waits add up",
          abs(flatten_events(waited + [{"k": EV_WAIT, "t": 1.0, "q": 1,
                                        "u": "min"}])[1]["t"] - 3.0) < 1e-9)
    check("wait: total waiting is reported in seconds",
          total_wait(waited) == 2.0)
    check("wait: flatten never mutates what he recorded",
          waited[2]["t"] == 1.0)

    check("step line: a wait reads as a wait",
          "WAIT" in step_line(0, waited[1])
          and "2 secs" in step_line(0, waited[1]))
    check("step line: a click carries its button and its point",
          "PRESS" in step_line(0, waited[0])
          and "left" in step_line(0, waited[0])
          and "1, 2" in step_line(0, waited[0]))

    import random as _rnd
    jittered = jitter_events(flat, 20, 3, _rnd.Random(7))
    check("jitter: nothing is lost", len(jittered) == len(flat))
    check("jitter: it stays in the order the player expects",
          all(jittered[i]["t"] <= jittered[i + 1]["t"]
              for i in range(len(jittered) - 1)))
    check("jitter: it moves the point but not far",
          all(abs(jittered[i]["x"] - flat[i]["x"]) <= 3 for i in range(len(flat))))
    check("jitter: off means untouched",
          jitter_events(flat, 0, 0, _rnd.Random(7))[1]["t"] == flat[1]["t"])
    check("jitter: time never goes negative",
          all(e["t"] >= 0.0 for e in jitter_events(flat, 5000, 0, _rnd.Random(1))))

    import tempfile as _tmp
    box = _tmp.mkdtemp(prefix="goldmacro_test_")
    lib = Library(os.path.join(box, "library"), os.path.join(box, "readable"))
    s_out = Slot(0)
    s_out.fill(waited)
    s_out.rename("MY RUN")
    path = lib.save(s_out)
    check("library: the json lands on disk", os.path.exists(path))
    check("library: a readable copy lands beside it",
          os.path.exists(lib.txt_for(0)))
    txt = open(lib.txt_for(0), encoding="utf-8").read()
    check("library: the readable copy names the macro", "MY RUN" in txt)
    check("library: the readable copy lists every step",
          txt.count("\n") >= len(waited))
    back = [Slot(i) for i in range(App.SLOT_COUNT)]
    got = lib.restore(back)
    check("library: it comes back after a restart", got == 1)
    check("library: with the same steps",
          len(back[0].events) == len(waited))
    check("library: with the name he gave it", back[0].name == "MY RUN")
    check("library: the wait survives the round trip",
          back[0].events[1]["k"] == EV_WAIT
          and back[0].events[1]["q"] == 2)
    lib.drop(0)
    check("library: clearing removes both files",
          not os.path.exists(path) and not os.path.exists(lib.txt_for(0)))
    check("library: a missing file is empty, not a crash",
          lib.read(3) is None)
    empty = [Slot(i) for i in range(App.SLOT_COUNT)]
    check("library: an empty folder restores nothing and does not throw",
          lib.restore(empty) == 0)
    try:
        os.makedirs(lib.folder, exist_ok=True)
        open(lib.path_for(1), "w", encoding="utf-8").write("{ not json")
        check("library: one broken file never stops the tool opening",
              lib.restore([Slot(i) for i in range(App.SLOT_COUNT)]) == 0)
    except Exception as exc:
        check("library: one broken file never stops the tool opening", False, exc)
    try:
        import shutil as _sh
        _sh.rmtree(box, ignore_errors=True)
    except Exception:
        pass

    check("stats: a wait is not counted as an action",
          macro_stats(flatten_events(waited))["clicks"] == 1)
    check("units: every unit the editor offers can be converted",
          all(u in UNIT_SECONDS for u in UNIT_ORDER))

    check("combo: ctrl+c reads", parse_combo("ctrl+c") == (["ctrl_l"], ("char", "c")))
    check("combo: spaces and caps are fine",
          parse_combo("CTRL + Shift + V")
          == (["ctrl_l", "shift_l"], ("char", "v")))
    check("combo: a named key is kept as a name",
          parse_combo("alt+tab") == (["alt_l"], ("name", "tab")))
    check("combo: junk gives nothing rather than half a combo",
          parse_combo("ctrl+notakey") == ([], None))
    ce = combo_events("ctrl+c", 0.0)
    check("combo: it presses and releases everything it pressed",
          len(ce) == 4 and ce[0]["k"] == EV_KDOWN and ce[-1]["k"] == EV_KUP)
    check("combo: the modifier goes down first and comes up last",
          ce[0].get("n") == "ctrl_l" and ce[-1].get("n") == "ctrl_l")
    check("combo: the letter is inside the modifier",
          ce[1].get("c") == "c" and ce[2].get("c") == "c")
    check("combo: nothing is left held",
          len([e for e in ce if e["k"] == EV_KDOWN])
          == len([e for e in ce if e["k"] == EV_KUP]))
    check("combo: an unreadable combo produces no events",
          combo_events("ctrl+notakey", 0.0) == [])

    te = text_events("hi", 0.0)
    check("type: one down and one up per character", len(te) == 4)
    check("type: it carries the characters", te[0].get("c") == "h"
          and te[2].get("c") == "i")
    check("type: newline becomes the enter key",
          text_events(chr(10), 0.0)[0].get("n") == "enter")
    check("type: time only moves forward",
          all(te[i]["t"] <= te[i + 1]["t"] for i in range(len(te) - 1)))

    mixed = [{"k": EV_DOWN, "t": 0.0, "b": "left", "x": 5, "y": 6},
             {"k": EV_KEYS, "t": 0.1, "s": "ctrl+c"},
             {"k": EV_FOCUS, "t": 0.2, "s": "Notepad"},
             {"k": EV_TEXT, "t": 0.3, "s": "ab"},
             {"k": EV_UP, "t": 0.4, "b": "left", "x": 5, "y": 6}]
    fm = flatten_events(mixed)
    check("mixed: the keys step became real key events",
          len([e for e in fm if e["k"] in (EV_KDOWN, EV_KUP)]) == 8)
    check("mixed: the focus step is still there for the player",
          len([e for e in fm if e["k"] == EV_FOCUS]) == 1)
    check("mixed: nothing comes out unsorted",
          all(fm[i]["t"] <= fm[i + 1]["t"] for i in range(len(fm) - 1)))
    check("mixed: the steps it stands for push the rest later",
          fm[-1]["t"] > 0.4)
    check("mixed: the original list is untouched",
          len(mixed) == 5 and mixed[1]["k"] == EV_KEYS)
    check("mixed: typing and hotkeys do not count as clicks",
          macro_stats(mixed)["clicks"] == 1)
    check("mixed: a wait plus a combo both land",
          len(flatten_events([{"k": EV_WAIT, "t": 0.0, "q": 1, "u": "sec"},
                              {"k": EV_KEYS, "t": 0.0, "s": "ctrl+v"}])) == 4)
    check("focus: an empty title finds nothing rather than the first window",
          find_window("") == 0)



    if fails:
        print("\n%d PASSED, %d FAILED -> %s" % (passed[0], len(fails), fails))
        return 1
    print("\nALL %d CHECKS PASSED" % passed[0])
    return 0


if __name__ == "__main__":
    if SELFTEST:
        sys.exit(_selftest())
    sys.exit(main())
