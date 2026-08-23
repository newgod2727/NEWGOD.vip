"""
TOOLBOX - a small launcher pinned to the top left of the desktop.

It does not run any tool itself. Each row starts that tool's own .py in its own
window, exactly as double clicking the file used to, so every script keeps its
own settings. Clicking a row that is already running closes it again.

Pinned, not draggable, and deliberately not topmost: it is pushed to the bottom
of the window order every few seconds so it sits on the desktop and never
covers what you are working on.
"""

import base64
import ctypes
import ctypes.wintypes
import datetime
import glob
import io
import json
import os
import re
import shutil
import socket
import subprocess
import sys
import threading
import time
import traceback
import winreg
import tkinter as tk

import psutil

HERE = os.path.dirname(os.path.abspath(__file__))
IS_DESKTOP = socket.gethostname().upper().startswith("DESKTOP-PC")
ROBLOX = os.path.expandvars(r"%LOCALAPPDATA%\Fishstrap\Fishstrap.exe")
BOOTLOG = os.path.join(HERE, "toolbox_boot.log")
GAMEMODE_STATE = os.path.join(HERE, "gamemode.json")
DESKFLOW_CONF = r"C:\ProgramData\Deskflow\deskflow-server.conf"

EYE_STATE = os.path.join(HERE, "eye.json")

EYE_WARM = {
    (False, False): (1.0, 1.0, 1.0),
    (False, True): (1.0, 0.93, 0.84),
    (True, False): (1.0, 0.80, 0.58),
    (True, True): (1.0, 0.77, 0.52),
}

EYE_LEVELS = ((100, 1.00), (85, 1.20), (70, 1.45), (55, 1.75), (40, 2.10))


def eye_ramp(warm, gamma):
    """One 3x256 gamma table.

    Dimming is done by bending the curve, not by scaling it. Windows refuses a
    ramp whose entries sit more than 32768 away from the straight line, and a
    plain multiply blows past that the moment warm and dim are both on. A power
    curve drops the midtones hard while the white point barely moves, so the
    screen reads much darker and every entry stays inside what Windows accepts.
    Nothing here touches the backlight, so a PWM panel cannot start flickering.
    """
    r, g, b = warm
    arr = (ctypes.c_ushort * 768)()
    for i in range(256):
        base = 65535.0 * ((i / 255.0) ** gamma)
        arr[i] = max(0, min(65535, int(base * r)))
        arr[256 + i] = max(0, min(65535, int(base * g)))
        arr[512 + i] = max(0, min(65535, int(base * b)))
    return arr


def eye_write(night, truetone, level):
    """Push the table onto the screen. True only if the driver took it."""
    gamma = dict(EYE_LEVELS).get(level, 1.00)
    ramp = eye_ramp(EYE_WARM[(bool(night), bool(truetone))], gamma)
    hdc = ctypes.windll.user32.GetDC(0)
    try:
        return bool(ctypes.windll.gdi32.SetDeviceGammaRamp(hdc, ctypes.byref(ramp)))
    except Exception:
        return False
    finally:
        try:
            ctypes.windll.user32.ReleaseDC(0, hdc)
        except Exception:
            pass


def eye_load():
    try:
        with open(EYE_STATE, "r", encoding="utf-8-sig") as fh:
            d = json.load(fh)
        return bool(d.get("night")), bool(d.get("truetone")), int(d.get("level", 100))
    except Exception:
        return False, False, 100


def eye_save(night, truetone, level):
    try:
        tmp = EYE_STATE + ".new"
        with open(tmp, "w", encoding="utf-8") as fh:
            json.dump({"night": bool(night), "truetone": bool(truetone),
                       "level": int(level)}, fh)
        os.replace(tmp, EYE_STATE)
    except Exception:
        pass


def dark_mode_read():
    try:
        with winreg.OpenKey(winreg.HKEY_CURRENT_USER,
                            r"SOFTWARE\Microsoft\Windows\CurrentVersion\Themes\Personalize") as k:
            return int(winreg.QueryValueEx(k, "AppsUseLightTheme")[0]) == 0
    except Exception:
        return True


def dark_mode_write(dark):
    """The broadcast goes to every top level window on the machine and waits up
    to 200 ms on each one that does not answer. With seven Roblox clients open
    that is the panel frozen for over a second, so the write is handed to a
    worker and the button comes back immediately."""
    value = 0 if dark else 1
    try:
        with winreg.OpenKey(winreg.HKEY_CURRENT_USER,
                            r"SOFTWARE\Microsoft\Windows\CurrentVersion\Themes\Personalize",
                            0, winreg.KEY_SET_VALUE) as k:
            winreg.SetValueEx(k, "AppsUseLightTheme", 0, winreg.REG_DWORD, value)
            winreg.SetValueEx(k, "SystemUsesLightTheme", 0, winreg.REG_DWORD, value)
        threading.Thread(target=lambda: ctypes.windll.user32.SendMessageTimeoutW(
            0xFFFF, 0x001A, 0, ctypes.c_wchar_p("ImmersiveColorSet"), 0x0002, 200,
            ctypes.byref(ctypes.c_ulong())), daemon=True).start()
        return True
    except Exception:
        return False


def eye_matches(night, truetone, level):
    """Whether the table on the screen right now is still ours."""
    gamma = dict(EYE_LEVELS).get(level, 1.00)
    want = eye_ramp(EYE_WARM[(bool(night), bool(truetone))], gamma)
    cur = (ctypes.c_ushort * 768)()
    hdc = ctypes.windll.user32.GetDC(0)
    try:
        if not ctypes.windll.gdi32.GetDeviceGammaRamp(hdc, ctypes.byref(cur)):
            return False
    except Exception:
        return False
    finally:
        try:
            ctypes.windll.user32.ReleaseDC(0, hdc)
        except Exception:
            pass
    for i in (64, 128, 192, 255, 320, 384, 448, 511, 576, 640, 704, 767):
        if abs(int(cur[i]) - int(want[i])) > 600:
            return False
    return True



def note(line):
    """Started from pyw.exe there is no console, so a panel that dies before it
    draws leaves nothing behind at all. Every start and every fatal error goes
    in here instead, which is the only way to tell "did not run at boot" apart
    from "ran at boot and crashed"."""
    try:
        with open(BOOTLOG, "a", encoding="utf-8") as fh:
            fh.write(f"{datetime.datetime.now():%Y-%m-%d %H:%M:%S}  {line}\n")
    except Exception:
        pass

MEMLOG = os.path.join(HERE, "memwatch.log")

# Page 5 reads the accounts from here rather than having them written into this
# file. One place holds the secrets, and it is a place you edit and can delete -
# not a script that gets copied, backed up and pasted into chats.
#
# One account per line:  username | password        (a tab works too)
# A line starting with # is ignored.
ACCOUNTS_FILE = os.path.join(HERE, "accounts.txt")


def read_accounts():
    """Returns [(username, password)], and never raises. A missing or unreadable
    file gives an empty list, and page 5 says so on the panel rather than in a
    console nobody has open."""
    out = []
    try:
        with open(ACCOUNTS_FILE, "r", encoding="utf-8") as fh:
            for line in fh:
                line = line.rstrip("\r\n").strip()
                if not line or line.startswith("#"):
                    continue
                # Split on the first separator only, so a password containing
                # | or spaces survives intact. A line with no separator at all
                # is still kept - it is a username waiting for its password,
                # not a line to drop silently.
                pw = ""
                user = line
                for sep in ("|", "\t"):
                    if sep in line:
                        user, _, pw = line.partition(sep)
                        break
                out.append((user.strip(), pw.strip()))
    except Exception:
        pass
    return out


def accounts_stamp():
    """Modification time, so the page can reload itself the moment the file is
    saved instead of waiting to be told."""
    try:
        return os.path.getmtime(ACCOUNTS_FILE)
    except Exception:
        return 0.0


def memnote():
    """One line every 20 s: free RAM, and what Claude and python are holding.
    Claude has died twice with nothing in the Windows event log, which means the
    only way to tell "ran out of memory" apart from "crashed" is to have been
    watching. Roughly 4 KB a day, trimmed at 2 MB."""
    while True:
        try:
            if os.path.exists(MEMLOG) and os.path.getsize(MEMLOG) > 2_000_000:
                with open(MEMLOG, "r", encoding="utf-8") as fh:
                    keep = fh.readlines()[-5000:]
                with open(MEMLOG, "w", encoding="utf-8") as fh:
                    fh.writelines(keep)
            vm = psutil.virtual_memory()
            claude = py = 0
            cmb = pymb = 0
            for p in psutil.process_iter(["name", "memory_info"]):
                try:
                    n = (p.info["name"] or "").lower()
                    rss = p.info["memory_info"].rss if p.info["memory_info"] else 0
                except Exception:
                    continue
                if n.startswith("claude"):
                    claude += 1
                    cmb += rss
                elif n.startswith("node") or n.startswith("python") or n.startswith("pythonw"):
                    py += 1
                    pymb += rss
            with open(MEMLOG, "a", encoding="utf-8") as fh:
                fh.write(f"{datetime.datetime.now():%Y-%m-%d %H:%M:%S}  "
                         f"free={vm.available / 2**20:.0f}MB  "
                         f"claude={claude}/{cmb / 2**20:.0f}MB  "
                         f"node+py={py}/{pymb / 2**20:.0f}MB\n")
        except Exception:
            pass
        time.sleep(20)


BG = "#0b0b0e"
PANEL = "#16161d"
EDGE = "#2a2a35"
TEXT = "#e6e6ee"
DIM = "#78788a"
ON = "#2f9e5a"
ACCENT = "#ffb347"
GM_ON = "#2f9e5a"
GM_ON_HOVER = "#3fb56b"
GM_OFF = "#7a2320"
GM_OFF_HOVER = "#9b3029"

WIDTH = 236

# How tall the accounts list is allowed to get before it starts scrolling.
#
# One account card is a bold name line plus a row of two buttons plus its own
# border and padding - about 60 px measured on the panel. Four accounts fit in
# the sidebar today and page 5 was already almost full; he is going to add five
# to ten more, which at 60 px each is another 300 to 600 px against a sidebar
# that is only as tall as the screen. Tk does not complain when a widget runs
# off the bottom - it simply does not draw, which is the same silence that hid
# the third titlebar button. So the list gets a viewport instead: it grows with
# the accounts up to this height and scrolls after that, and the card itself is
# untouched.
# Measured 2026-08-20, and the number that matters is not the window height, it is
# page 1. Every page shares one slot and the slot is as tall as its tallest page:
# page1 473, page2 382, page3 383, page4 206, page6 207. The first version let
# page 5 grow to 548, so the slot grew by 75 px, the whole bottom stack was pushed
# down and RELAUNCH was left as a red sliver with its text cut in half.
#
# So the list is capped by what is left of page 1's height after the fixed parts
# of page 5: title 27, note 25 on one line, the two file buttons 36, AUTO
# RELAUNCHING 36, and about 30 of padding. 473 - 154 = 319, and 312 leaves a
# little back.
#
# Then he pointed at the gap: with page 5 at 462 the page arrows sat at y=624 and
# RELAUNCH starts at 753, so 94 px of the sidebar was empty. The bottom stack is
# packed from the bottom edge, so the pages slot can grow into that gap without
# moving RELAUNCH at all. Measured: RELAUNCH y=753 h=55, the arrows need 35 plus
# padding, so the slot may reach 558 and the list may have 408.
#
# This is now only a ceiling. The real height comes from _acct_room(), which
# asks the panel how much of the shared page slot page 5 has left over once
# its title, note and two button rows are paid for.
ACCT_MAX_H = 408

# The report row is not a script. It was pointed at
# C:\roblox mcp\report.py, which exists on neither machine, so it could
# only ever print 找不到. It opens the report window instead - his words,
# 2026-08-13 18:02: "it was not incuding roblox that hack only, it was
# incuding all bug ... it will makr down what happend ... so i can tpe
# indie waht happend".
REPORT_ROW = "::report::"
AUTO_OFF_FLAG = os.path.join(HERE, "autorelaunch_off.flag")

TOOLS = [
    ("autoclicker21.py", "左鍵連點"),
    ("minecraft_rightclicker.py", "右鍵連點"),
    ("minecraft_mining_holder.py", "按住左鍵"),
    ("minecraft_sequence_clicker.py", "右鍵加序列"),
    ("clcik with chosing.py", "定點連點"),
    ("pc_autotyper.py", "循環打字"),
    ("typewordinf.py", "右鍵觸發打字"),
    ("GOLDMACRO_v3.py", "GOLDMACRO v3"),
    (os.path.join(os.path.expanduser("~"), "Documents", "GOLDAUTOCLICKER",
                  "GOLDAUTOCLICKER.exe"), "GOLD 自動點擊"),
    ("farm_watch.py", "BOT 看門狗"),
    (REPORT_ROW, "產生現況報告"),
]

# Page 2. Each row force closes every process of one thing.
#
# Matched on the process name and nothing else, because matching on the command
# line would make "claude" hit any node window that merely mentions it. "real"
# is listed exactly rather than by prefix for the same reason - a prefix would
# take Realtek's audio service with it.
END_TASKS = [
    ("[Claude]", ("claude", "anthropicclaude", "claude code")),
    ("[REAL.EXE]", ("real", "real-mcp")),
    ("[ROBLOX]", ("robloxplayerbeta", "robloxcrashhandler",
                  "robloxplayerlauncher", "roblox", "fishstrap")),
    ("[WhatsApp]", ("whatsapp", "whatsapp.root")),
    ("[Spotify]", ("spotify",)),
    ("[Discord]", ("discord",)),
]

# Page 3. Opens the same things page 2 closes.
#
# No fixed .exe paths. Real and Discord are Squirrel installs whose folder carries
# the version number, so a hard coded path dies at the next update - those are
# globbed and the newest wins. Claude, WhatsApp and Spotify are Store apps with no
# stable .exe to point at, so they go through the shell's AppsFolder by app id.
#
# Sixth field is the process name to check before opening, written out rather than
# derived from the exe. Deriving it worked only by accident: the Store rows have no
# exe to derive from, so the fallback guessed from the app id, and a third Store
# app added later would silently have been treated as Spotify.
#
# Seventh field is a substring the process's exe PATH must contain for that check
# to count it. Empty means the name alone is enough.
#
# Claude needs it and the name alone was wrong twice over. There are two Claude
# installs on this machine - a stale Squirrel one under AppData\AnthropicClaude
# and the live MSIX one under Program Files\WindowsApps - and the button pointed
# at the stale one. Worse, sixteen processes are called claude.exe: fifteen are
# the desktop app's Electron children and one is the Claude Code CLI, so a
# name-only check reports "already running" even when the desktop app is closed
# and the only claude.exe alive is the terminal you are typing in.
# Page 4 uses this too. Written once so the repair button and the open button can
# never drift apart.
CLAUDE_AUMID = "Claude_pzs8sxrjxfjjc!Claude"

OPEN_APPS = [
    ("[Claude]", "store", CLAUDE_AUMID, "", "", "claude", r"\WindowsApps\Claude_"),
    ("[REAL.EXE]", "squirrel", r"%LOCALAPPDATA%\Real", "real-*", "Real.exe", "real", ""),
    ("[Discord]", "squirrel", r"%LOCALAPPDATA%\Discord", "app-*", "Discord.exe", "discord", ""),
    ("[WhatsApp]", "store", "5319275A.WhatsAppDesktop_cv1g1gvanyjgm!App", "", "", "whatsapp", ""),
    ("[Spotify]", "store", "SpotifyAB.SpotifyMusic_zpdnekdrzrea0!Spotify", "", "", "spotify", ""),
]


class Toolbox:
    def __init__(self, root):
        self.root = root
        self.procs = {}
        self.rows = {}
        self._layer = None
        self._layer_at = 0.0
        self._acct_stamp = 0.0
        self.gamemode = False
        self.gmbtn = None
        self._gm_saw_roblox = False
        self._gm_busy = False
        self._gm_misses = 0
        self._gm_since = 0.0
        self._gm_lock = threading.Lock()
        self._game_running = False
        # name -> [first seen, last seen]. The sweep in _watch is already walking
        # every process every few seconds, so keeping the two stamps costs nothing
        # and is the only way the report can say what VANISHED - a scan run at the
        # moment he presses the button can only ever see what is still alive.
        self._proc_seen = {}
        self._proc_lock = threading.Lock()

        self.root.overrideredirect(True)
        self.root.configure(bg=BG)
        self.root.attributes("-topmost", False)

        # No scrolling. The window is simply made as tall as its own content,
        # capped at the working area so it never runs under the taskbar.
        self.body = tk.Frame(self.root, bg=BG)
        self.body.pack(fill="both", expand=True)

        self._build()
        self.root.update_idletasks()
        self._place()
        # Assert the geometry a second time once Tk has finished settling. The
        # page-measuring loop in _build packs and unpacks all three pages and
        # pumps update_idletasks while doing it, and on this machine that left
        # the window as a 160x28 stub at the bottom right of the screen - the
        # geometry set here was being overridden by a late relayout. Re-applying
        # it after the event loop has run once costs nothing and pins it.
        self.root.after(200, self._place)

        threading.Thread(target=self._watch, daemon=True).start()
        threading.Thread(target=memnote, daemon=True).start()
        threading.Thread(target=self._hotkey_thread, daemon=True).start()
        self.root.after(500, self._sink)
        self.root.after(1000, self._watch_accounts)
        self.root.after(1200, self._eye_tick)
        self.root.after(1500, self._boost_tick)
        self.root.after(60, self._err_fit)
        self.root.after(300, self._gamemode_restore_start)

    def _place(self):
        """Full height of the work area, not the height of the content. It is a
        sidebar, so it runs from the top of the screen down to the taskbar and
        the launch buttons sit at the very bottom."""
        try:
            self.root.geometry(f"{WIDTH}x{self._work_height()}+0+0")
        except Exception as exc:
            note(f"geometry failed: {exc}")

    def _work_height(self):
        """Screen height minus the taskbar, read from Windows rather than guessed."""
        class RECT(ctypes.Structure):
            _fields_ = [("left", ctypes.c_long), ("top", ctypes.c_long),
                        ("right", ctypes.c_long), ("bottom", ctypes.c_long)]
        try:
            r = RECT()
            SPI_GETWORKAREA = 0x0030
            if ctypes.windll.user32.SystemParametersInfoW(SPI_GETWORKAREA, 0,
                                                          ctypes.byref(r), 0):
                return r.bottom - r.top
        except Exception:
            pass
        return self.root.winfo_screenheight() - 48

    # --- window layer ------------------------------------------------------
    def _sink(self):
        """Sit on the desktop, but come to the front when reached for.

        The original version only ever pushed to HWND_BOTTOM, every three
        seconds, forever. On a desktop that always has Claude, Real and Roblox
        open that means the panel is permanently invisible - it is running
        perfectly and you cannot see or press a single button, which is
        indistinguishable from dead and is exactly what "totally not working"
        turned out to be.

        So the layer is now decided by where the cursor is. Touch the left edge
        of the screen, or be anywhere over the panel, and it comes to the top;
        move away and it drops back to the bottom. Nothing is reserved from
        Windows and nothing is left behind if this process dies, which is why
        this rather than registering a real AppBar: a leaked AppBar keeps a
        236 px strip of the desktop for itself until the next reboot.
        """
        try:
            hwnd = ctypes.windll.user32.GetParent(self.root.winfo_id()) or self.root.winfo_id()
            GWL_EXSTYLE, NOACTIVATE, TOOLWINDOW = -20, 0x08000000, 0x00000080
            style = ctypes.windll.user32.GetWindowLongW(hwnd, GWL_EXSTYLE)
            # Written only when it differs. The old line wrote the same two bits
            # back twenty times a second for the entire session; SetWindowLongW
            # on GWL_EXSTYLE is a window manager call, not a variable assignment.
            if style | NOACTIVATE | TOOLWINDOW != style:
                ctypes.windll.user32.SetWindowLongW(hwnd, GWL_EXSTYLE,
                                                    style | NOACTIVATE | TOOLWINDOW)

            class POINT(ctypes.Structure):
                _fields_ = [("x", ctypes.c_long), ("y", ctypes.c_long)]

            pt = POINT()
            ctypes.windll.user32.GetCursorPos(ctypes.byref(pt))
            # The trigger strip is the first three columns of pixels. Once the
            # panel is up, anywhere over the panel keeps it up, so the pointer
            # never has to cross a gap on its way to a button.
            over = (pt.x <= 2) or (0 <= pt.x <= WIDTH and 0 <= pt.y <= self._work_height())

            # Never while Roblox is up. A topmost window over a fullscreen game
            # takes DWM out of independent flip for as long as it is there, and
            # in a game the pointer reaches x<=2 constantly - every strafe into
            # the left edge was raising this panel over the client and costing
            # frames until the pointer came back.
            if self._game_running:
                over = False

            HWND_TOPMOST, HWND_BOTTOM = -1, 1
            NOMOVE, NOSIZE, NOACT = 0x0002, 0x0001, 0x0010
            want = HWND_TOPMOST if over else HWND_BOTTOM

            # Only when it actually changes. The first version of this re-asserted
            # HWND_BOTTOM on every single tick, and at five ticks a second that is
            # a desktop-wide z-order change five times a second - it made the whole
            # machine lag. The re-assert still happens, but on its own slow clock.
            now = time.time()
            if want != self._layer:
                ctypes.windll.user32.SetWindowPos(hwnd, want, 0, 0, 0, 0,
                                                  NOMOVE | NOSIZE | NOACT)
                self._layer = want
                self._layer_at = now
            elif now - self._layer_at > (0.3 if over else (60 if self._game_running else 5)):
                # Both directions have to be re-claimed, not just the bottom one.
                # Only re-asserting the bottom was the bug: once the panel had been
                # raised, any window opened or clicked afterwards landed above it and
                # the panel stayed put, so every press went to that window instead.
                # A maximised Claude covers the whole 236 px strip, which is exactly
                # what "I cannot press anything on the toolbox" was.
                ctypes.windll.user32.SetWindowPos(hwnd, want, 0, 0, 0, 0,
                                                  NOMOVE | NOSIZE | NOACT)
                self._layer_at = now
        except Exception:
            pass
        # Reading the cursor is cheap and has to be quick to feel like a reveal.
        # Nothing else in this loop touches the window unless the layer changes.
        # 50 ms rather than 200: at 200 the pointer could reach a button and click
        # it before the panel had come up, and that click went to the window behind.
        # With a game up there is nothing to reveal - the panel is pinned down -
        # so the tick drops to 500 ms and the z-order re-assert to once a minute.
        # A SetWindowPos on the desktop is a composition event the game pays for,
        # and at 5 s that was a hitch twelve times a minute for nothing.
        self.root.after(500 if self._game_running else 50, self._sink)

    # --- ui ----------------------------------------------------------------
    def _build(self):
        titlebar = tk.Frame(self.body, bg=BG)
        titlebar.pack(fill="x", padx=10, pady=(10, 0))
        tk.Label(titlebar, text="TOOLBOX", bg=BG, fg=ACCENT,
                 font=("Segoe UI", 17, "bold"), anchor="w").pack(side="left")
        tk.Button(titlebar, text="\u27F3", bg="#2a2a38", fg=ACCENT,
                  activebackground="#3a3a48", activeforeground="white",
                  font=("Segoe UI", 13, "bold"), relief="flat", bd=0, padx=10, pady=2,
                  cursor="hand2",
                  command=self._refresh_panel).pack(side="right")

        self.meter = tk.Label(self.body, text="", bg=BG, fg=DIM, anchor="w",
                              font=("Segoe UI", 10))
        self.meter.pack(fill="x", padx=10, pady=(0, 2))

        # Totals alone never answer the question that matters, which is what is
        # eating the memory right now. Processes are grouped by name because a
        # browser shows up as thirty separate entries otherwise.
        self.hogs = tk.Label(self.body, text="", bg=PANEL, fg=TEXT, anchor="w",
                             justify="left", font=("Consolas", 9), padx=8, pady=6)
        self.hogs.pack(fill="x", padx=10, pady=(0, 4))

        tk.Button(self.body, text="清理背景程式", bg="#3a3a48", fg=TEXT,
                  activebackground="#4a4a5c", activeforeground=TEXT,
                  font=("Segoe UI", 10, "bold"), relief="flat",
                  command=self._cleanup).pack(fill="x", padx=10, pady=(0, 8))

        # Two pages in the same slot. Page 1 was already full to the bottom of
        # the sidebar, so anything new has to live behind the arrows rather than
        # push the launch buttons off the screen.
        self.pages = tk.Frame(self.body, bg=BG)
        self.pages.pack(fill="x")

        self.page1 = tk.Frame(self.pages, bg=BG)
        self.page2 = tk.Frame(self.pages, bg=BG)
        self.page3 = tk.Frame(self.pages, bg=BG)
        self.page4 = tk.Frame(self.pages, bg=BG)
        self.page5 = tk.Frame(self.pages, bg=BG)
        self.page6 = tk.Frame(self.pages, bg=BG)
        self.page7 = tk.Frame(self.pages, bg=BG)

        for filename, name in TOOLS:
            self.rows[filename] = self._row(self.page1, filename, name)

        tk.Label(self.page2, text="END TASK", bg=BG, fg=ACCENT, anchor="w",
                 font=("Segoe UI", 12, "bold")).pack(fill="x", padx=10, pady=(6, 6))
        # Six rows now instead of three, so the height that suited three would
        # run off the bottom of the sidebar. They are shorter and tighter.
        for label, names in END_TASKS:
            tk.Button(self.page2, text=label, bg="#4a1f1f", fg="#ffb3b3",
                      activebackground="#6b2a2a", activeforeground="white",
                      font=("Segoe UI", 11, "bold"), relief="flat", height=1,
                      pady=6,
                      command=lambda l=label, n=names: self._end_task(l, n)).pack(
                          fill="x", padx=10, pady=2)

        if IS_DESKTOP:
            tk.Button(self.page2, text="[TRANSLATE]", bg="#4a1f1f", fg="#ffb3b3",
                      activebackground="#6b2a2a", activeforeground="white",
                      font=("Segoe UI", 11, "bold"), relief="flat", height=1, pady=6,
                      command=self._translate_stop).pack(fill="x", padx=10, pady=2)

        tk.Label(self.page3, text="OPEN", bg=BG, fg=ACCENT, anchor="w",
                 font=("Segoe UI", 12, "bold")).pack(fill="x", padx=10, pady=(6, 6))
        for row in OPEN_APPS:
            tk.Button(self.page3, text=row[0], bg="#1f3a4a", fg="#b3e0ff",
                      activebackground="#2a5a6b", activeforeground="white",
                      font=("Segoe UI", 11, "bold"), relief="flat", height=1,
                      pady=6,
                      command=lambda a=row: self._open_app(*a)).pack(
                          fill="x", padx=10, pady=2)

        if IS_DESKTOP:
            tk.Button(self.page3, text="[TRANSLATE]", bg="#1f3a4a", fg="#b3e0ff",
                      activebackground="#2a5a6b", activeforeground="white",
                      font=("Segoe UI", 11, "bold"), relief="flat", height=1, pady=6,
                      command=self._translate_open).pack(fill="x", padx=10, pady=2)
        # Press once, approve once, and the admin launch stops asking forever.
        tk.Button(self.page3, text="不再問管理員  設定一次", bg="#3a2a4a",
                  fg="#d9b3ff", activebackground="#4d3a63", activeforeground="white",
                  font=("Segoe UI", 10, "bold"), relief="flat", height=1, pady=6,
                  command=self._setup_admin_task).pack(fill="x", padx=10, pady=(8, 2))

        if IS_DESKTOP:
            tk.Button(self.page3, text="[BACKUP]", bg="#1f3a4a", fg="#b3e0ff",
                      activebackground="#2a5a6b", activeforeground="white",
                      font=("Segoe UI", 11, "bold"), relief="flat", height=1, pady=6,
                      command=self._account_backup).pack(fill="x", padx=10, pady=2)

        # Page 4. One button, because there is only ever one thing to do here.
        #
        # The error is always 0x80073D02 "the following apps need to be closed":
        # the Store tries to finish Claude's update registration, Claude is still
        # running, the registration fails, and the launcher then tells you to go
        # to Advanced options and hit Repair. Nothing is corrupt - on 2026-08-05
        # the same error hit Spotify, PC Manager, myHP and Xbox in the same
        # update round. Closing every claude process and re-registering the
        # package is exactly what that Repair button does, minus the digging.
        tk.Label(self.page4, text="修復", bg=BG, fg=ACCENT, anchor="w",
                 font=("Segoe UI", 12, "bold")).pack(fill="x", padx=10, pady=(6, 2))
        tk.Label(self.page4, text="Claude 開不到、叫你去「進階選項 → 修復」的時候按這個",
                 bg=BG, fg=DIM, anchor="w", font=("Segoe UI", 9),
                 wraplength=WIDTH - 24, justify="left").pack(fill="x", padx=10, pady=(0, 6))
        self.fixbtn = tk.Button(self.page4, text="修復 CLAUDE 並重開",
                                bg="#4a3a1e", fg=ACCENT, activebackground="#5c4826",
                                activeforeground=ACCENT, font=("Segoe UI", 12, "bold"),
                                relief="flat", height=2, command=self._fix_claude)
        self.fixbtn.pack(fill="x", padx=10, pady=2)
        tk.Label(self.page4,
                 text="會關掉全部 Claude 程序(包括 Claude Code),\n"
                      "重新註冊套件,再重新開啟 Claude。\n"
                      "對話同設定不會刪。",
                 bg=PANEL, fg=TEXT, anchor="w", justify="left",
                 font=("Segoe UI", 9), padx=8, pady=6).pack(fill="x", padx=10, pady=(4, 2))

        # Page 5. Press a button, it copies, and the button itself says so for a
        # moment - on a panel with no console that confirmation is the only way
        # to tell a copy that worked from a click that missed.
        tk.Label(self.page5, text="帳號", bg=BG, fg=ACCENT, anchor="w",
                 font=("Segoe UI", 12, "bold")).pack(fill="x", padx=10, pady=(6, 2))
        self.acctnote = tk.Label(self.page5, text="", bg=BG, fg=DIM, anchor="w",
                                 font=("Segoe UI", 9), wraplength=WIDTH - 24,
                                 justify="left")
        self.acctnote.pack(fill="x", padx=10, pady=(0, 6))
        self.acctwrap = tk.Frame(self.page5, bg=BG)
        self.acctwrap.pack(fill="x")
        self.acctview = tk.Canvas(self.acctwrap, bg=BG, highlightthickness=0,
                                  bd=0, height=ACCT_MAX_H, yscrollincrement=1)
        self.acctview.pack(side="left", fill="both", expand=True)
        self.accttrack = tk.Frame(self.acctwrap, bg=BG, width=6)
        self.accttrack.pack(side="right", fill="y")
        self.accttrack.pack_propagate(False)
        self.acctgrip = tk.Frame(self.accttrack, bg=ACCENT, width=4)
        self.acctbox = tk.Frame(self.acctview, bg=BG)
        self._acctwin = self.acctview.create_window((0, 0), window=self.acctbox,
                                                    anchor="nw")
        self.acctbox.bind("<Configure>", self._acct_scrollregion)
        self.acctview.bind("<Configure>", self._acct_width)
        self.acctview.bind_all("<MouseWheel>", self._acct_wheel, add="+")
        acctnav = tk.Frame(self.page5, bg=BG)
        acctnav.pack(fill="x", padx=10, pady=(6, 2))
        tk.Button(acctnav, text="開啟 accounts.txt", bg=PANEL, fg=TEXT,
                  activebackground="#22222c", activeforeground=TEXT,
                  font=("Segoe UI", 10, "bold"), relief="flat", pady=4,
                  command=self._open_accounts_file).pack(side="left", fill="x",
                                                         expand=True, padx=(0, 2))
        tk.Button(acctnav, text="重新讀取", bg=PANEL, fg=TEXT,
                  activebackground="#22222c", activeforeground=TEXT,
                  font=("Segoe UI", 10, "bold"), relief="flat", pady=4,
                  command=self._build_accounts).pack(side="left", fill="x",
                                                     expand=True, padx=(2, 0))
        self._build_accounts()

        autorow = tk.Frame(self.page5, bg=BG)
        autorow.pack(fill="x", padx=10, pady=(6, 2))
        self.autobtn = tk.Button(autorow, text="AUTO RELAUNCHING", bg=PANEL, fg=TEXT,
                                 activebackground="#22222c", activeforeground=TEXT,
                                 font=("Segoe UI", 10, "bold"), relief="flat", pady=4,
                                 command=self._auto_relaunch_toggle)
        self.autobtn.pack(fill="x")
        self._auto_relaunch_paint()

        tk.Label(self.page6, text="視窗大小", bg=BG, fg=ACCENT, anchor="w",
                 font=("Segoe UI", 11, "bold")).pack(fill="x", padx=10, pady=(4, 2))
        self.sizenote = tk.Label(self.page6, text="", bg=BG, fg=DIM, anchor="w",
                                 justify="left", font=("Segoe UI", 9))
        self.sizenote.pack(fill="x", padx=10, pady=(0, 4))
        self.save_slot = "A"
        slotrow = tk.Frame(self.page6, bg=BG)
        slotrow.pack(fill="x", padx=10, pady=(2, 2))
        self.slotbtns = {}
        for key in self.SAVE_SLOTS:
            b = tk.Button(slotrow, text=key, bg=PANEL, fg=TEXT,
                          activebackground="#22222c", activeforeground=TEXT,
                          font=("Segoe UI", 10, "bold"), relief="flat", pady=3,
                          command=lambda k=key: self._pick_save(k))
            b.pack(side="left", expand=True, fill="x", padx=1)
            self.slotbtns[key] = b

        sizerow = tk.Frame(self.page6, bg=BG)
        sizerow.pack(fill="x", padx=10, pady=(4, 2))
        tk.Button(sizerow, text="\u5132\u5b58\u73fe\u5728\u7684\u5927\u5c0f", bg=PANEL, fg=TEXT,
                  activebackground="#22222c", activeforeground=TEXT,
                  font=("Segoe UI", 10, "bold"), relief="flat", pady=4,
                  command=self._save_roblox_layout).pack(fill="x")

        applyrow = tk.Frame(self.page6, bg=BG)
        applyrow.pack(fill="x", padx=10, pady=(2, 2))
        tk.Button(applyrow, text="\u5957\u7528\u9019\u500b\u5b58\u6a94", bg="#1f3a1f", fg="#b6f2b6",
                  activebackground="#274a27", activeforeground="#b6f2b6",
                  font=("Segoe UI", 10, "bold"), relief="flat", pady=4,
                  command=self._apply_roblox_layout).pack(fill="x")

        self._pick_save("A")

        # The arrows sit directly under the last row of whichever page is up,
        # which on page 1 is GOLDMACRO v3.
        nav = tk.Frame(self.body, bg=BG)
        nav.pack(fill="x", padx=10, pady=(6, 0))
        tk.Button(nav, text="<", bg=PANEL, fg=TEXT, activebackground="#22222c",
                  activeforeground=TEXT, font=("Segoe UI", 11, "bold"),
                  relief="flat", width=4,
                  command=lambda: self._show_page(self.page - 1)).pack(side="left")
        self.pagelabel = tk.Label(nav, text="", bg=BG, fg=DIM,
                                  font=("Segoe UI", 10))
        self.pagelabel.pack(side="left", expand=True)
        tk.Button(nav, text=">", bg=PANEL, fg=TEXT, activebackground="#22222c",
                  activeforeground=TEXT, font=("Segoe UI", 11, "bold"),
                  relief="flat", width=4,
                  command=lambda: self._show_page(self.page + 1)).pack(side="right")

        # The arrows used to sit directly under whichever page was showing, so they
        # jumped every time the page changed - page 2 and 3 are shorter than page 1.
        # The slot is pinned to page 1's height once, and the pages are placed inside
        # it rather than packed, so nothing below them can move again.
        # Measured by showing each page once. A frame that has never been managed
        # reports a requested height of 1, so asking without packing it first gives
        # the wrong number.
        # The accounts list is the one elastic thing on any page, so it is
        # flattened to a single pixel while the slot is being measured. Left
        # alone it is born at ACCT_MAX_H, which made page 5 the tallest page by
        # far, which made the slot 75 px taller than page 1, which pushed the
        # bottom stack down until RELAUNCH was squeezed out of the window
        # entirely - the live panel at 18:16 on 2026-08-20 had 128 px of empty
        # background where the red button belongs and no red anywhere.
        #
        # Measuring it at 1 makes the slot the tallest of the fixed pages, and
        # _acct_room then hands the list whatever is left over. The elastic part
        # fills the slot instead of setting it.
        try:
            self.acctview.configure(height=1)
        except Exception:
            pass
        self._build_eye()
        slot = 0
        for p in (self.page1, self.page2, self.page3, self.page4, self.page5,
                  self.page6, self.page7):
            p.pack(fill="x")
            self.root.update_idletasks()
            slot = max(slot, p.winfo_reqheight())
            p.pack_forget()
        self.pages.configure(height=slot)
        self.pages.pack_propagate(False)
        self._acct_scrollregion()
        # The slot's real height is not known until the window has been mapped,
        # and the call above therefore runs against a reqheight. Refitting on
        # every Configure of the slot means the list picks up the true number as
        # soon as there is one, and again if the sidebar is ever a different
        # height. The slot cannot resize itself - pack_propagate is off and the
        # height is fixed - so this cannot feed back on itself.
        self.pages.bind("<Configure>", self._acct_scrollregion)

        self.page = 1
        self._show_page(1)

        # Packed from the bottom up so the launch block stays glued to the
        # bottom edge however tall the sidebar ends up.
        self.err = tk.Label(self.body, text="", bg=BG, fg="#ff6b6b", anchor="w",
                            font=("Segoe UI", 9), wraplength=WIDTH - 24, justify="left")
        self.err.pack(side="bottom", fill="x", padx=10, pady=(4, 6))

        self.fishbtn = tk.Button(self.body, text="ROBLOX 設定  Fishstrap", bg="#4a3a1e",
                                 fg=ACCENT, activebackground="#5c4826",
                                 activeforeground=ACCENT,
                                 font=("Segoe UI", 11, "bold"), relief="flat", height=2,
                                 command=self._fishstrap)
        self.fishbtn.pack(side="bottom", fill="x", padx=10, pady=(4, 0))
        tk.Button(self.body, text="LAUNCH ROBLOX  管理員", bg="#2b3f66", fg="white",
                  activebackground="#3a558c", activeforeground="white",
                  font=("Segoe UI", 11, "bold"), relief="flat", height=2,
                  command=self._roblox_admin).pack(side="bottom", fill="x", padx=10, pady=(4, 0))
        tk.Button(self.body, text="LAUNCH ROBLOX", bg="#1f6f43", fg="white",
                  activebackground="#2f9e5a", activeforeground="white",
                  font=("Segoe UI", 13, "bold"), relief="flat", height=2,
                  command=self._roblox).pack(side="bottom", fill="x", padx=10)

        # Desktop only, and not out of tidiness. Real lives on the desktop by his
        # standing rule - no real .exe on the laptop, everything mirrored across
        # and the laptop copy deleted by hand. The laptop still had
        # AppData\Local\Real\real-1.9.0\Real.exe sitting there on 2026-08-14, but
        # it is on its way out, so a button pointing at it would be a button
        # pointing at nothing.
        if IS_DESKTOP:
            self.realbtn = tk.Button(self.body, text="RELAUNCH", bg="#7a1f1f",
                                     fg="white", activebackground="#a02828",
                                     activeforeground="white", relief="flat",
                                     height=2, font=("Segoe UI", 11, "bold"),
                                     command=self._real_refresh)
            self.realbtn.pack(side="bottom", fill="x", padx=10, pady=(0, 6))

        if not IS_DESKTOP:
            self.gmbtn = tk.Button(self.body, text="GAME MODE  OFF", fg="white",
                                   activeforeground="white", relief="flat", height=2,
                                   font=("Segoe UI", 13, "bold"),
                                   command=self._gamemode_toggle)
            self.gmbtn.pack(side="bottom", fill="x", padx=10, pady=(0, 6))
            self._gamemode_paint()

        tk.Frame(self.body, bg=EDGE, height=1).pack(side="bottom", fill="x",
                                                    padx=10, pady=8)

    GOTO_FILE = os.path.join(HERE, "gotopage.txt")

    def _goto_page_file(self):
        """Let a page be turned by writing a number into a file.

        Not a feature for him - he has the arrows. This exists because I cannot
        see any page but the one that happens to be up. The panel pins itself to
        the bottom of the z order every three seconds, so a synthetic click on
        the arrow is swallowed by whatever desktop window is above it, and the
        one workaround left was to raise the panel and click a hardcoded pixel.
        That pixel moved twice in one evening - the arrows sat at y=776 in one
        capture and y=728 in the next - so every check of a page I had just
        changed was really a check of page 1 with a screenshot to prove it.

        A number in a file cannot miss. The file is deleted as soon as it is
        read, so nothing sticks and he can never land on a page he did not
        choose.
        """
        try:
            if not os.path.exists(self.GOTO_FILE):
                return
            with open(self.GOTO_FILE, "r", encoding="utf-8-sig") as fh:
                want = int((fh.read() or "").strip())
        except Exception:
            want = None
        try:
            os.remove(self.GOTO_FILE)
        except Exception:
            pass
        if want:
            try:
                self._show_page(want)
            except Exception:
                pass

    ACCOUNT_JSON = r"C:\Users\desktop\AppData\Local\Real\data\accounts.json"
    BACKUP_JSON = os.path.join(HERE, "account_backup.json")
    BACKUP_MD = os.path.join(HERE, "ACCOUNT_BACKUP.md")

    LOGIN_ORDER = ("ZAKI_SKYWARS", "BRTH_TKKFCBKOA", "viper_skywars",
                   "Nitsan_skywars", "Brian1KB_skywars", "Spajk_skywars",
                   "Jay_skywars")

    def _login_order(self, rows):
        """His order, given on 2026-08-20: the three leaders first, then the bots.

        His words: "it login following should be ZAKI, then BRTH then VIPER, then
        others bot like ABC then E bot". ZAKI leads EggWars, BRTH leads the duo,
        VIPER plays solo alone; A B C fill out the EggWars four and E is the
        duo's second.

        Matched on display name first and username second, because he calls them
        by the display name and Real stores both. Anything not on his list goes
        on the end in the order Real has it, and says so rather than being
        silently sorted somewhere - a new account he has not placed yet is
        exactly the case where a guess would be wrong.
        """
        known = []
        rest = []
        for row in rows:
            disp = (row.get("display_name") or "").strip()
            user = (row.get("username") or "").strip()
            rank = None
            for i, want in enumerate(self.LOGIN_ORDER):
                if want == disp or want == user:
                    rank = i
                    break
            if rank is None:
                rest.append(row)
            else:
                known.append((rank, row))
        known.sort(key=lambda pair: pair[0])
        return [r for _rank, r in known], rest

    def _account_backup(self):
        """Write down which account belongs to which group, and in what order.

        His ask on 2026-08-20: "add a [BACKUP] it will detect those acount and put
        back thme at which group and using the same username, if it dindt it will
        auto telling the login following".

        The group is not a Real setting file - it lives on each account inside
        data\\accounts.json as a group field, which is why this reads the account
        list rather than hunting for a groups file. Measured 2026-08-20 22:0x:
        ABCD EGG has four, EF DUO has two, G solo has one.

        Two jobs in one button, chosen by what it finds. If the account list is
        there, this is a backup: it writes the mapping out. If the list is gone
        or empty - a reinstall, a lost vault - there is nothing to back up and
        the only useful thing left is the last mapping and the order to type them
        back in, so it reads the newest backup and puts that on the panel instead.

        The cookies are never touched. This holds names, ids and group names, so
        it can tell him what to do but can never log anything in by itself.
        """
        rows = []
        read_err = None
        try:
            with open(self.ACCOUNT_JSON, "r", encoding="utf-8-sig") as fh:
                data = json.load(fh)
            if isinstance(data, dict):
                data = data.get("accounts") or []
            for a2 in data or []:
                if not isinstance(a2, dict):
                    continue
                rows.append({
                    "username": a2.get("username"),
                    "display_name": a2.get("display_name"),
                    "user_id": a2.get("user_id"),
                    "group": a2.get("group"),
                })
        except Exception as exc:
            read_err = str(exc)

        if rows:
            missing = self._groups_missing(rows)
            if missing:
                self._restore_groups(rows, missing)
            else:
                self._backup_write(rows)
        else:
            self._backup_restore_note(read_err)

    def _keep_dated_copy(self, payload):
        """One dated copy per real change, not one per press.

        He pressed BACKUP eight times inside eighteen seconds on 2026-08-21 at
        00:25 and got eight identical dated files. Pressing a button that looks
        like it did nothing is a reasonable thing to do; leaving eight copies of
        the same seven accounts behind is not a reasonable thing for the button
        to do about it. The dated copy is a history, and a history of a thing
        that did not change is noise.
        """
        try:
            fresh = json.dumps(payload.get("accounts"), sort_keys=True,
                               ensure_ascii=False)
        except Exception:
            return
        newest = None
        try:
            olds = sorted(glob.glob(os.path.join(HERE, "account_backup_*.json")))
            if olds:
                with open(olds[-1], "r", encoding="utf-8-sig") as fh:
                    newest = json.dumps((json.load(fh) or {}).get("accounts"),
                                        sort_keys=True, ensure_ascii=False)
        except Exception:
            newest = None
        if newest == fresh:
            return
        try:
            dated = os.path.join(
                HERE, "account_backup_%s.json"
                % datetime.datetime.now().strftime("%Y-%m-%d_%H%M%S"))
            shutil.copyfile(self.BACKUP_JSON, dated)
        except Exception:
            pass

    def _groups_missing(self, rows):
        """Which accounts have lost their group, and what it used to be.

        Returns a dict of username to the group the last backup says it belongs
        to, for accounts that are in Real right now but have no group on them.
        Empty dict means nothing to restore.
        """
        try:
            with open(self.BACKUP_JSON, "r", encoding="utf-8-sig") as fh:
                old = json.load(fh) or {}
        except Exception:
            return {}
        want = {}
        for r in old.get("accounts") or []:
            u = (r.get("username") or "").strip()
            g = (r.get("group") or "").strip()
            if u and g:
                want[u] = g
        out = {}
        for r in rows:
            u = (r.get("username") or "").strip()
            g = (r.get("group") or "").strip()
            if u and not g and want.get(u):
                out[u] = want[u]
        return out

    def _restore_groups(self, rows, missing):
        """Put the accounts back into their groups, for real, in Real's own file.

        This is the half he actually asked for and did not get. His words on
        2026-08-20: "it will detect those acount and put back thme at which group".
        The first version only wrote the mapping down and told him what to type,
        so when he pressed it he saw a message and nothing moved - and he pressed
        it eight more times.

        It is restorable because of where Real keeps the group: not in a settings
        file, but as a field on each account inside data\\accounts.json. So
        putting an account back into its group is writing one string back. The
        cookies are never read and never written - this touches the group field
        and nothing else, so it can rebuild the grouping and can never log
        anything in.

        accounts.json is copied beside itself before the write. If Real is open
        it holds the old list in memory, so Real has to be restarted to see this.
        """
        try:
            with open(self.ACCOUNT_JSON, "r", encoding="utf-8-sig") as fh:
                live = json.load(fh)
        except Exception as exc:
            self._fail("BACKUP 讀不回 accounts.json：" + str(exc))
            return
        wrapped = None
        if isinstance(live, dict):
            wrapped = live
            live = live.get("accounts") or []
        done = 0
        for a2 in live or []:
            if not isinstance(a2, dict):
                continue
            u = (a2.get("username") or "").strip()
            g = missing.get(u)
            if not g:
                continue
            a2["group"] = g
            if isinstance(a2.get("groups"), list):
                a2["groups"] = [g]
            else:
                a2["groups"] = g
            done += 1
        if not done:
            self._backup_write(rows)
            return
        try:
            shutil.copyfile(self.ACCOUNT_JSON, self.ACCOUNT_JSON + ".before-restore")
            out = wrapped if wrapped is not None else live
            if wrapped is not None:
                wrapped["accounts"] = live
            tmp = self.ACCOUNT_JSON + ".new"
            with open(tmp, "w", encoding="utf-8") as fh:
                json.dump(out, fh, indent=2, ensure_ascii=False)
                fh.flush()
                os.fsync(fh.fileno())
            os.replace(tmp, self.ACCOUNT_JSON)
        except Exception as exc:
            self._fail("BACKUP 寫不回 accounts.json：" + str(exc))
            return
        note("account backup: restored %d accounts into their groups" % done)
        self.note_status("放回了 %d 個帳號，現在即刻重開 Real；"
                         "重開之前不要在 Real 裡面改東西" % done)

    def _backup_write(self, rows):
        """The account list is there, so save it."""
        ordered, rest = self._login_order(rows)
        groups = {}
        for r in rows:
            groups.setdefault(r.get("group") or "(no group)", []).append(r)
        stamp = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        payload = {
            "saved": stamp,
            "accounts": rows,
            "login_order": [r.get("display_name") or r.get("username")
                             for r in ordered + rest],
            "unplaced": [r.get("display_name") or r.get("username") for r in rest],
        }
        try:
            tmp = self.BACKUP_JSON + ".new"
            with open(tmp, "w", encoding="utf-8") as fh:
                json.dump(payload, fh, indent=2, ensure_ascii=False)
                fh.flush()
                os.fsync(fh.fileno())
            os.replace(tmp, self.BACKUP_JSON)
            self._keep_dated_copy(payload)
        except Exception as exc:
            self._fail("BACKUP 寫不入：" + str(exc))
            return

        lines = ["# 帳號備份", "", "備份時間 " + stamp, ""]
        lines.append("## 登入次序")
        lines.append("")
        for i, r in enumerate(ordered + rest, 1):
            lines.append("%d. %s  (%s)  %s" % (
                i, r.get("display_name") or "?", r.get("username") or "?",
                r.get("group") or "(no group)"))
        if rest:
            lines.append("")
            lines.append("下面這幾個不在你定過那個次序裏面，排在最後："
                         + ", ".join((r.get("display_name") or r.get("username") or "?")
                                      for r in rest))
        lines.append("")
        lines.append("## 組別")
        lines.append("")
        for g in sorted(groups):
            lines.append("### " + g)
            for r in groups[g]:
                lines.append("- %s  (%s)  id %s" % (
                    r.get("display_name") or "?", r.get("username") or "?",
                    r.get("user_id") or "?"))
            lines.append("")
        try:
            with open(self.BACKUP_MD, "w", encoding="utf-8") as fh:
                fh.write("\n".join(lines))
        except Exception:
            pass

        note("account backup: %d accounts, %d groups" % (len(rows), len(groups)))
        names = "、".join(sorted(groups))
        self.note_status("%d 個帳號、%d 個組全部齊（%s），沒有東西要放回，已經抜低"
                         % (len(rows), len(groups), names))

    def _backup_restore_note(self, read_err):
        """Nothing to back up, so tell him how to put them back instead."""
        try:
            with open(self.BACKUP_JSON, "r", encoding="utf-8-sig") as fh:
                old = json.load(fh)
        except Exception:
            self._fail("讀不到帳號，而且以前也沒有備份過："
                       + (read_err or "accounts.json 是空的"))
            return
        order = old.get("login_order") or []
        by_name = {}
        for r in old.get("accounts") or []:
            key = r.get("display_name") or r.get("username")
            by_name[key] = r
        lines = ["# 帳號不見了，照這個次序登回來", "",
                 "這份是 " + str(old.get("saved")) + " 備份的", ""]
        for i, name in enumerate(order, 1):
            r = by_name.get(name) or {}
            lines.append("%d. %s  (%s)  放回組 %s" % (
                i, name, r.get("username") or "?", r.get("group") or "?"))
        try:
            with open(self.BACKUP_MD, "w", encoding="utf-8") as fh:
                fh.write("\n".join(lines))
        except Exception:
            pass
        first = ", ".join(order[:3]) if order else "(備份是空的)"
        note("account backup: nothing to save, showed the login order instead")
        self.note_status("帳號讀不到，先登：" + first)

    def _err_fit(self):
        """The status line only takes room when it has something to say.

        Measured off the panel itself 2026-08-20: the Fishstrap button ends at
        y=994 and the sidebar ends at y=1031, so 37 px sat empty underneath it -
        an empty label, 21 px tall, plus 16 px of its own padding. He pointed
        straight at it. Empty text still reserves a full line in Tk, so the label
        is unpacked while it is empty and packed back in front of the Fishstrap
        button the moment there is a message, which keeps it at the bottom edge
        where it has always been.

        The 37 px do not go to waste: the page slot above grows by exactly that
        much, and _acct_room hands it to the accounts list.
        """
        try:
            has = bool(self.err.cget("text").strip())
            shown = bool(self.err.winfo_manager())
            if has and not shown:
                self.err.pack(side="bottom", fill="x", padx=10, pady=(4, 6),
                              before=self.fishbtn)
            elif not has and shown:
                self.err.pack_forget()
        except Exception:
            pass

    # --- accounts ----------------------------------------------------------
    def _acct_scrollregion(self, _event=None):
        """The list grew or shrank - refit the viewport and the grip."""
        try:
            need = self.acctbox.winfo_reqheight()
            self.acctview.configure(scrollregion=(0, 0, 0, need))
            self.acctview.configure(height=min(need, self._acct_room()))
            self._acct_grip()
        except Exception:
            pass

    def _acct_width(self, event=None):
        """Keep the inner frame exactly as wide as the canvas, or the cards would
        keep their own width and the right edge would fall outside the sidebar."""
        try:
            w = event.width if event else self.acctview.winfo_width()
            self.acctview.itemconfigure(self._acctwin, width=w)
            self._acct_grip()
        except Exception:
            pass

    def _acct_grip(self):
        """His own scrollbar, four pixels of accent, and it disappears when the
        whole list already fits. A native Tk scrollbar is grey Windows chrome and
        does not belong on this panel."""
        try:
            need = self.acctbox.winfo_reqheight()
            view = self._acct_viewh()
            if need <= view:
                self.acctgrip.place_forget()
                return
            top, bottom = self.acctview.yview()
            self.acctgrip.place(relx=0, rely=top, relwidth=1.0,
                                relheight=max(bottom - top, 0.06))
        except Exception:
            pass

    def _acct_viewh(self):
        """The viewport height, taken from what was configured rather than from
        winfo_height().

        winfo_height() reports 1 until the geometry manager has actually laid the
        widget out, and the wheel can fire before that. Measured 2026-08-20: a
        438 px list inside a viewport that reported 1 px made both the scroll test
        and the scrollbar decide the wrong way. The configured value is the one
        this code set itself, so it is true from the first frame.
        """
        try:
            want = int(self.acctview.cget("height"))
        except Exception:
            want = self._acct_room()
        try:
            real = self.acctview.winfo_height()
        except Exception:
            real = 0
        return real if real > 1 else want

    def _acct_room(self):
        """How tall the list may be, asked of the panel instead of written down.

        Every page shares one slot and the slot is as tall as its tallest page, so
        a page 5 that grows past the others pushes the whole bottom stack down and
        RELAUNCH ends up a red sliver with its text cut in half. That is what
        happened on 2026-08-20 and it is why this is measured rather than chosen:
        a constant that is right on my rebuild can be wrong on the real panel, and
        it was - my figure said the page arrows sat at y=624 while the panel on
        screen had them at 795.

        So: take the slot's height, take away what page 5 spends on everything
        that is not the list, and what is left is the list's. ACCT_MAX_H is only
        the ceiling for the case where the slot cannot be read yet.
        """
        try:
            slot = self.pages.winfo_height()
            if slot <= 1:
                slot = self.pages.winfo_reqheight()
            if slot <= 1:
                return ACCT_MAX_H
            used = 0
            for child in self.page5.winfo_children():
                if child is not self.acctwrap:
                    used += child.winfo_reqheight() + 8
            room = slot - used - 8
            if room < 120:
                room = 120
            return min(room, ACCT_MAX_H)
        except Exception:
            return ACCT_MAX_H

    def _acct_glide(self, pixels, step=0):
        """One wheel notch, moved over six frames instead of in one jump."""
        try:
            frames = 6
            if step >= frames:
                self._acct_grip()
                return
            each = int(pixels / frames)
            if each == 0:
                each = 1 if pixels > 0 else -1
            self.acctview.yview_scroll(each, "units")
            self._acct_grip()
            self.root.after(12, lambda: self._acct_glide(pixels, step + 1))
        except Exception:
            pass

    def _acct_over_list(self):
        """Is the pointer actually inside the accounts viewport right now."""
        try:
            px, py = self.acctview.winfo_pointerxy()
            x = self.acctview.winfo_rootx()
            y = self.acctview.winfo_rooty()
            w = self.acctview.winfo_width()
            h = self._acct_viewh()
            return x <= px < x + w and y <= py < y + h
        except Exception:
            return False

    def _acct_wheel(self, event):
        """Bound once, application wide, and it decides by where the pointer is.

        The first version bound the wheel on Enter over the canvas and unbound it
        on Leave. That looked right and could never work: the cards are children
        of the canvas, so the moment the pointer moved onto a card Tk sent Leave
        to the canvas and tore the binding down again, and a card is what covers
        almost the whole list. Measured 2026-08-20 with six accounts, 438 px of
        cards inside a 372 px viewport: the wheel did nothing at all.

        So there is no Enter and no Leave. One binding, and it asks where the
        pointer is. Outside the list it returns without swallowing the event, so
        the wheel keeps behaving normally everywhere else on the panel.
        """
        try:
            if not self._acct_over_list():
                return None
            if self.acctbox.winfo_reqheight() <= self._acct_viewh():
                return None
            # Scroll it the way a web page scrolls: one pixel per unit and the
            # notch glided over several frames, instead of one jump that snaps
            # from card to card. His words: "IT SHOULD LIKE WEBSITE SCROLLING".
            #
            # yscrollincrement is 1, so a unit is a pixel. Left at the default a
            # unit is a tenth of the canvas height, and a canvas that has not
            # been laid out yet reports a height of 1, so a tenth of that is zero
            # and the wheel did nothing at all.
            self._acct_glide(-54 if event.delta > 0 else 54)
        except Exception:
            return None
        return "break"

    def _build_accounts(self):
        """Redrawn rather than patched, so editing accounts.txt and pressing the
        reload button is enough - no restart."""
        for child in self.acctbox.winfo_children():
            child.destroy()

        self._acct_stamp = accounts_stamp()
        accounts = read_accounts()
        if not accounts:
            self.acctnote.config(
                text="accounts.txt 是空的。按下面開啟它,每行寫 帳號|密碼,存檔就會自己更新。",
                fg="#ff9b6b")
            return

        blank = sum(1 for _, pw in accounts if not pw)
        if blank:
            self.acctnote.config(
                text=f"{blank} 個帳號的密碼還是空的。按開啟 accounts.txt,"
                     "貼在 | 後面,存檔就自己更新,不用按重新讀取。",
                fg="#ff9b6b")
        else:
            # One line, because a second line pushes the whole page down and the
            # bottom of the panel is where RELAUNCH lives.
            self.acctnote.config(text=f"{len(accounts)} 個帳號,按一下就複製。",
                                 fg=DIM)
        for user, pw in accounts:
            f = tk.Frame(self.acctbox, bg=PANEL, highlightbackground=EDGE,
                         highlightthickness=1)
            f.pack(fill="x", padx=10, pady=2)
            tk.Label(f, text=user, bg=PANEL, fg=TEXT, anchor="w",
                     font=("Segoe UI", 10, "bold")).pack(fill="x", padx=6, pady=(4, 0))
            row = tk.Frame(f, bg=PANEL)
            row.pack(fill="x", padx=6, pady=(2, 4))
            # The command is attached after the widget exists, because the
            # confirmation has to be written back into the button pressed.
            namebtn = tk.Button(row, text="帳號", bg="#1f3a4a", fg="#b3e0ff",
                                activebackground="#2a5a6b", activeforeground="white",
                                font=("Segoe UI", 10, "bold"), relief="flat", pady=3)
            namebtn.pack(side="left", fill="x", expand=True, padx=(0, 2))
            namebtn.config(command=lambda v=user, b=namebtn: self._copy(v, b, "帳號"))

            # An empty slot says so on its own face. A button reading "密碼" that
            # copies nothing is the same lie as a status line that always reads OK.
            if pw:
                pwbtn = tk.Button(row, text="密碼", bg="#4a3a1e", fg=ACCENT,
                                  activebackground="#5c4826", activeforeground=ACCENT,
                                  font=("Segoe UI", 10, "bold"), relief="flat", pady=3)
                pwbtn.pack(side="left", fill="x", expand=True, padx=(2, 0))
                pwbtn.config(command=lambda v=pw, b=pwbtn: self._copy(v, b, "密碼"))
            else:
                tk.Button(row, text="密碼未填", bg="#4a1f1f", fg="#ffb3b3",
                          activebackground="#6b2a2a", activeforeground="white",
                          font=("Segoe UI", 10, "bold"), relief="flat", pady=3,
                          command=self._open_accounts_file).pack(
                              side="left", fill="x", expand=True, padx=(2, 0))

        self.acctbox.update_idletasks()
        self._acct_scrollregion()
        self.acctview.yview_moveto(0)

    def _watch_accounts(self):
        """Save the file, the page redraws. Pressing a reload button after every
        edit is a step that exists only because the program could not be
        bothered to look."""
        try:
            if accounts_stamp() != self._acct_stamp:
                self._build_accounts()
        except Exception:
            pass
        self._err_fit()
        self._goto_page_file()
        self.root.after(1000, self._watch_accounts)

    def _open_accounts_file(self):
        """Notepad, not the browser. The whole point of this page is not having
        to open Chrome to read one line."""
        try:
            if not os.path.exists(ACCOUNTS_FILE):
                with open(ACCOUNTS_FILE, "w", encoding="utf-8") as fh:
                    fh.write("# 帳號 | 密碼\n")
            subprocess.Popen(["notepad.exe", ACCOUNTS_FILE])
            self._fail("")
        except Exception as exc:
            self._fail(f"開不了 accounts.txt: {exc}")

    def _copy(self, value, button, label):
        """Copies and says so on the button for a second and a half. A silent
        copy and a dead button look the same, and this panel has no console."""
        if not value:
            button.config(text="沒有內容")
            self.root.after(1500, lambda: button.config(text=label))
            return
        try:
            self.root.clipboard_clear()
            self.root.clipboard_append(value)
            self.root.update()
            button.config(text="已複製")
        except Exception as exc:
            button.config(text="複製失敗")
            self._fail(f"複製失敗: {exc}")
        self.root.after(1500, lambda: button.config(text=label))

    def _auto_relaunch_paint(self):
        off = os.path.exists(AUTO_OFF_FLAG)
        self.autobtn.config(
            text="AUTO RELAUNCHING  關" if off else "AUTO RELAUNCHING  開",
            bg=GM_OFF if off else GM_ON,
            activebackground=GM_OFF_HOVER if off else GM_ON_HOVER,
            fg="#ffe3df" if off else "#dcffe9")

    def _auto_relaunch_toggle(self):
        try:
            if os.path.exists(AUTO_OFF_FLAG):
                os.remove(AUTO_OFF_FLAG)
            else:
                with open(AUTO_OFF_FLAG, "w", encoding="utf-8") as fh:
                    fh.write("off")
        except Exception as exc:
            self.autobtn.config(text="AUTO RELAUNCHING 失敗 " + type(exc).__name__,
                                bg=GM_OFF, fg="#ffe3df")
            self.after(4000, self._auto_relaunch_paint)
            return
        self._auto_relaunch_paint()

    SAVE_SLOTS = ("A", "B", "C", "D", "E", "F", "G")

    LAYOUT_FILE = os.path.join(HERE, "roblox_layout.json")

    def _slot_file(self, key):
        return os.path.join(HERE, "roblox_layout_%s.json" % key)

    def _roblox_window_rects(self):
        """Every visible Roblox client window, oldest process first.

        Sorted by process start time so the slots mean the same thing from one
        relaunch to the next - the clients always come up in the order Real
        launches them, so slot 0 is the same account's window every time.
        Measured 2026-08-20 with seven up: that order was E G F D B C A, which
        is exactly the order they sit in inside accounts.json.

        Each row also carries z, its place in the stack. EnumWindows walks the
        desktop from the front backwards, so a smaller z means nearer the
        front. His words on 2026-08-20: "it was ising the cleint psotitong and
        the front and the back also, it need to same as that, add that and not
        only using the client psotiotn beucase that was suck". Position alone
        cannot rebuild an arrangement of seven overlapping windows - put them
        all back in the right place in the wrong order and the one he wants to
        watch is buried."""
        import ctypes
        import ctypes.wintypes

        user32 = ctypes.windll.user32
        user32.SetProcessDPIAware()

        class RECT(ctypes.Structure):
            _fields_ = [("left", ctypes.c_long), ("top", ctypes.c_long),
                        ("right", ctypes.c_long), ("bottom", ctypes.c_long)]

        rows = []
        walked = [0]
        P = ctypes.WINFUNCTYPE(ctypes.c_bool, ctypes.wintypes.HWND,
                               ctypes.wintypes.LPARAM)

        def cb(hwnd, lparam):
            walked[0] += 1
            z = walked[0]
            if not user32.IsWindowVisible(hwnd):
                return True
            pid = ctypes.wintypes.DWORD()
            user32.GetWindowThreadProcessId(hwnd, ctypes.byref(pid))
            try:
                p = psutil.Process(pid.value)
                if p.name().lower() != "robloxplayerbeta.exe":
                    return True
                born = p.create_time()
            except Exception:
                return True
            r = RECT()
            user32.GetWindowRect(hwnd, ctypes.byref(r))
            w, h = r.right - r.left, r.bottom - r.top
            if w < 200 or h < 150:
                return True
            rows.append((born, hwnd, r.left, r.top, w, h, z))
            return True

        user32.EnumWindows(P(cb), 0)
        rows.sort()
        self._last_hwnds = [hw for (_b, hw, _x, _y, _w, _h, _z) in rows]
        return [{"slot": i, "x": x, "y": y, "w": w, "h": h, "z": z}
                for i, (_b, _hw, x, y, w, h, z) in enumerate(rows)]

    def _roblox_hwnds(self):
        self._roblox_window_rects()
        return getattr(self, "_last_hwnds", [])

    def _pick_save(self, key):
        """Choose which save this page is working with, and make it the live one.

        His call 2026-08-15, correcting me: slot means a save slot, not which
        client. He keeps more than one arrangement and wants to pick between
        them, and choosing one immediately copies it onto roblox_layout.json -
        which is the file the relaunch reads at the end of its run. Picking a
        save is therefore the same action as deciding what every future
        relaunch will put on screen.

        There were three. On 2026-08-20, the evening seven clients came up for
        the first time, he asked for four more - "abc 3 slot was no engouht
        alreayd, i need that many". Three saves were sized for a four account
        farm; slot C had just been overwritten with the seven window
        arrangement, so there was nowhere left to keep the old ones. The
        letters now run A to G, one per account.

        SAVE_SLOTS is one list read by both the button row and the note under
        it, because two copies of the same letters is how one of them ends up
        stale."""
        self.save_slot = key
        for k, b in self.slotbtns.items():
            on = (k == key)
            b.config(bg=ACCENT if on else PANEL, fg="#101014" if on else TEXT)
        src = self._slot_file(key)
        if os.path.exists(src):
            try:
                shutil.copyfile(src, self.LAYOUT_FILE)
            except Exception:
                pass
        self._paint_layout_note()

    def _save_roblox_layout(self):
        """Write down where the clients are sitting right now, into this save.

        His call, 2026-08-15: he had to ask for this by hand every time he moved
        a window, because the layout the relaunch restores was only ever written
        by me over SSH. Now he arranges the clients, presses once, and every
        relaunch from then on puts them back exactly there.

        Since 2026-08-20 the row also carries z, so which window is in front
        of which is saved along with where each one sits."""
        rows = self._roblox_window_rects()
        if not rows:
            self._fail("\u6c92\u6709\u627e\u5230 Roblox \u8996\u7a97\uff0c\u6c92\u6709\u5132\u5b58")
            return
        payload = {"saved": datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
                   "windows": rows}
        try:
            for path in (self._slot_file(self.save_slot), self.LAYOUT_FILE):
                tmp = path + ".new"
                with open(tmp, "w", encoding="utf-8") as fh:
                    json.dump(payload, fh, indent=2)
                    fh.flush()
                    os.fsync(fh.fileno())
                os.replace(tmp, path)
        except Exception as exc:
            self._fail("\u5132\u5b58\u4e0d\u5230\uff1a" + str(exc))
            return
        note("roblox layout saved into %s: %d windows" % (self.save_slot, len(rows)))
        self._paint_layout_note()
        self._fail("\u5b58\u6a94 %s \u5df2\u7d93\u8a18\u4f4f %d \u500b\u8996\u7a97"
                   % (self.save_slot, len(rows)))

    def _apply_roblox_layout(self):
        """Put the clients back where this save says, right now.

        Two passes, and the second one is the point. The first moves every
        window to its saved rectangle. The second rebuilds the stack: the
        saves are sorted back-most first and each is raised to the top in
        turn, so the one that was at the front is raised last and ends up at
        the front. Raising them front-first would produce the exact reverse.

        A save written before 2026-08-20 has no z in it. Those still work -
        the windows go back to their places and the stack is left alone,
        which is what that save recorded and all it ever knew."""
        import ctypes
        try:
            with open(self._slot_file(self.save_slot), "r", encoding="utf-8-sig") as fh:
                saved = (json.load(fh) or {}).get("windows") or []
        except Exception:
            self._fail("\u5b58\u6a94 %s \u9084\u672a\u5132\u5b58\u904e" % self.save_slot)
            return
        hwnds = self._roblox_hwnds()
        if not hwnds:
            self._fail("\u6c92\u6709\u627e\u5230 Roblox \u8996\u7a97")
            return
        user32 = ctypes.windll.user32
        done = 0
        for i, d in enumerate(saved):
            if i >= len(hwnds):
                break
            try:
                user32.ShowWindow(hwnds[i], 9)
                user32.MoveWindow(hwnds[i], int(d["x"]), int(d["y"]),
                                  int(d["w"]), int(d["h"]), True)
                done += 1
            except Exception:
                pass
        stacked = self._apply_zorder(saved, hwnds)
        note("roblox layout %s applied to %d windows, %d stacked"
             % (self.save_slot, done, stacked))
        if stacked:
            self._fail("\u5df2\u7d93\u6446\u56de %d \u500b\u8996\u7a97"
                       "\uff0c\u524d\u5f8c\u6b21\u5e8f\u4e5f\u6392\u56de\u4f86" % done)
        else:
            self._fail("\u5df2\u7d93\u6446\u56de %d \u500b\u8996\u7a97"
                       "\uff08\u9019\u500b\u5b58\u6a94\u6c92\u6709\u5b58\u904e\u524d\u5f8c\uff09" % done)

    def _apply_zorder(self, saved, hwnds):
        """Rebuild the front-to-back order. Returns how many were stacked.

        SWP_NOMOVE and SWP_NOSIZE mean this touches nothing but the stack, so
        it cannot undo the rectangles the pass before it just set. NOACTIVATE
        matters as much: without it every raise steals the keyboard focus in
        turn, and on a machine running seven clients that is seven windows
        flashing for the focus while he is trying to use it."""
        import ctypes
        user32 = ctypes.windll.user32
        HWND_TOP = 0
        SWP_NOSIZE = 0x0001
        SWP_NOMOVE = 0x0002
        SWP_NOACTIVATE = 0x0010
        flags = SWP_NOSIZE | SWP_NOMOVE | SWP_NOACTIVATE
        order = []
        for i, d in enumerate(saved):
            if i >= len(hwnds):
                break
            z = d.get("z")
            if z is None:
                return 0
            order.append((int(z), hwnds[i]))
        if not order:
            return 0
        order.sort(reverse=True)
        stacked = 0
        for _z, hwnd in order:
            try:
                user32.SetWindowPos(hwnd, HWND_TOP, 0, 0, 0, 0, flags)
                stacked += 1
            except Exception:
                pass
        return stacked

    def _paint_layout_note(self):
        """One line per save, so the page says what it is holding without a dump.

        The four coordinate rows that used to be here were the thing he called
        messy - they were the same numbers four times over and told him nothing
        he could act on."""
        bits = []
        for key in self.SAVE_SLOTS:
            try:
                with open(self._slot_file(key), "r", encoding="utf-8-sig") as fh:
                    d = json.load(fh)
                n = len(d.get("windows") or [])
                when = (d.get("saved") or "")[5:16]
                mark = "\u25cf" if key == self.save_slot else "\u25cb"
                bits.append("%s %s  %d \u500b  %s" % (mark, key, n, when))
            except Exception:
                mark = "\u25cf" if key == self.save_slot else "\u25cb"
                bits.append("%s %s  \u7a7a" % (mark, key))
        try:
            self.sizenote.config(text="\n".join(bits))
        except Exception:
            pass

    EYE_NAMES = {"dark": "深色模式",
                 "night": "夜覽",
                 "truetone": "原色調"}

    def _build_eye(self):
        tk.Label(self.page7, text="\u8b77\u773c", bg=BG, fg=ACCENT, anchor="w",
                 font=("Segoe UI", 12, "bold")).pack(fill="x", padx=10, pady=(6, 4))

        self.eye_night, self.eye_truetone, self.eye_level = eye_load()
        self.eyebtns = {}
        for key in ("dark", "night", "truetone"):
            b = tk.Button(self.page7, text=self.EYE_NAMES[key], bg="#4a3a1e",
                          fg=ACCENT, activebackground="#5c4826",
                          activeforeground=ACCENT, font=("Segoe UI", 11, "bold"),
                          relief="flat", height=1, pady=6,
                          command=lambda k=key: self._eye_toggle(k))
            b.pack(fill="x", padx=10, pady=2)
            self.eyebtns[key] = b

        tk.Label(self.page7, text="\u4eae\u5ea6", bg=BG, fg=DIM, anchor="w",
                 font=("Segoe UI", 10)).pack(fill="x", padx=10, pady=(6, 2))
        row = tk.Frame(self.page7, bg=BG)
        row.pack(fill="x", padx=10)
        self.eyelevels = {}
        for pct, _gamma in EYE_LEVELS:
            b = tk.Button(row, text=str(pct), bg=PANEL, fg=TEXT,
                          activebackground="#22222c", activeforeground=ACCENT,
                          font=("Segoe UI", 9, "bold"), relief="flat", pady=3,
                          command=lambda p=pct: self._eye_level_set(p))
            b.pack(side="left", fill="x", expand=True, padx=1)
            self.eyelevels[pct] = b

        tk.Button(self.page7, text="\u9084\u539f", bg=PANEL, fg=DIM,
                  activebackground="#22222c", activeforeground=ACCENT,
                  font=("Segoe UI", 10, "bold"), relief="flat", height=1, pady=4,
                  command=self._eye_reset).pack(fill="x", padx=10, pady=(6, 2))

        self.eyenote = tk.Label(self.page7, text="", bg=BG, fg=DIM, anchor="w",
                                font=("Segoe UI", 9), wraplength=WIDTH - 24,
                                justify="left")
        self.eyenote.pack(fill="x", padx=10, pady=(2, 6))
        self._eye_paint()
        if self.eye_night or self.eye_truetone or self.eye_level != 100:
            self._eye_apply(say=False)

    def _eye_paint(self):
        state = {"dark": dark_mode_read(), "night": self.eye_night,
                 "truetone": self.eye_truetone}
        for key, btn in self.eyebtns.items():
            live = state[key]
            btn.config(text="%s   %s" % (self.EYE_NAMES[key],
                                         "\u958b\u555f" if live else "\u95dc\u9589"),
                       bg="#7a5a1e" if live else PANEL,
                       fg=ACCENT if live else DIM)
        for pct, btn in self.eyelevels.items():
            picked = pct == self.eye_level
            btn.config(bg="#7a5a1e" if picked else PANEL,
                       fg=ACCENT if picked else TEXT)

    def _eye_apply(self, say=True):
        ok = eye_write(self.eye_night, self.eye_truetone, self.eye_level)
        eye_save(self.eye_night, self.eye_truetone, self.eye_level)
        self._eye_paint()
        if not ok:
            self._fail("\u8b77\u773c\u5beb\u4e0d\u9032\u986f\u793a\u5361\uff0c"
                       "\u756b\u9762\u6c92\u6709\u8b8a\u3002\u9a45\u52d5\u7a0b\u5f0f"
                       "\u62d2\u7d55\u4e86\u9019\u5f35\u8868")
        elif say:
            self.eyenote.config(
                text="\u591c\u89bd %s\u3000\u539f\u8272\u8abf %s\u3000\u4eae\u5ea6 %d%%" % (
                    "\u958b" if self.eye_night else "\u95dc",
                    "\u958b" if self.eye_truetone else "\u95dc", self.eye_level),
                fg=DIM)
        return ok

    def _eye_toggle(self, key):
        if key == "dark":
            if not dark_mode_write(not dark_mode_read()):
                self._fail("\u6df1\u8272\u6a21\u5f0f\u6539\u4e0d\u5230")
            self._eye_paint()
            return
        if key == "night":
            self.eye_night = not self.eye_night
        else:
            self.eye_truetone = not self.eye_truetone
        self._eye_apply()

    def _eye_level_set(self, pct):
        self.eye_level = pct
        self._eye_apply()

    def _eye_reset(self):
        self.eye_night = False
        self.eye_truetone = False
        self.eye_level = 100
        self._eye_apply()

    def _eye_tick(self):
        """Roblox going fullscreen, a resolution change and a driver reset each
        wipe the gamma table without telling anyone, which is how a setting like
        this quietly stops being on. The table is read back every second and
        only rewritten when something else has replaced it, so there is no
        flicker from writing a value that is already there."""
        try:
            if self.eye_night or self.eye_truetone or self.eye_level != 100:
                if not eye_matches(self.eye_night, self.eye_truetone,
                                   self.eye_level):
                    eye_write(self.eye_night, self.eye_truetone, self.eye_level)
        except Exception:
            pass
        self.root.after(1000, self._eye_tick)

    def _boost_tick(self):
        """Measured 2026-08-24 00:4x: one sweep costs 19.0 ms across 383
        processes, and it used to run right here on the Tk thread - so a panel
        whose whole job that night was to take lag away was handing itself a
        19 ms freeze every second. The timer only starts a worker now, and it
        refuses to start a second one while the first is still out.

        The rule is deliberately NOT the same on the two machines. The laptop
        follows GAME MODE, because that button is his and it is the only thing
        that switches it on there. The desktop has no GAME MODE button and never
        had one, so there is nothing to follow - and on the desktop only the
        boost half runs. Nothing of his is pushed down there without a button to
        show it, which is the whole reason the tame half is left to the laptop."""
        if not getattr(self, "_boost_busy", False):
            if IS_DESKTOP or getattr(self, "gamemode", False):
                self._boost_busy = True
                threading.Thread(target=self._boost_sweep, daemon=True).start()
        self.root.after(1000, self._boost_tick)

    def _boost_sweep(self):
        """Reads the priority back and only writes the ones that have drifted.
        A client that restarts, and every client a RELAUNCH brings back, arrives
        at whatever Windows hands out - measured 2026-08-24 00:2x, one
        RobloxPlayerBeta was sitting at Idle, the lowest class there is."""
        try:
            moved = 0
            for p in psutil.process_iter(["name", "pid"]):
                name = (p.info["name"] or "").rsplit(".", 1)[0]
                if name in self.BOOST_NAMES:
                    want = psutil.ABOVE_NORMAL_PRIORITY_CLASS
                elif name in self.TAME_NAMES and not IS_DESKTOP:
                    want = psutil.BELOW_NORMAL_PRIORITY_CLASS
                else:
                    continue
                try:
                    if p.nice() != want:
                        p.nice(want)
                        moved += 1
                except Exception:
                    pass
            if moved:
                self._boost_fixed = getattr(self, "_boost_fixed", 0) + moved
                note("boost sweep fixed %d drifted priorities, %d since start"
                     % (moved, self._boost_fixed))
        except Exception:
            pass
        finally:
            self._boost_busy = False

    def _show_page(self, n):
        pages = (self.page1, self.page2, self.page3, self.page4, self.page5,
                 self.page6, self.page7)
        n = len(pages) if n > len(pages) else (1 if n < 1 else n)
        self.page = n
        for frame in pages:
            frame.pack_forget()
        pages[n - 1].pack(fill="x")
        self.pagelabel.config(text=f"{n} / {len(pages)}")

    def _row(self, parent, filename, name):
        f = tk.Frame(parent, bg=PANEL, highlightbackground=EDGE, highlightthickness=1)
        f.pack(fill="x", padx=10, pady=2)
        b = tk.Button(f, text=name, bg=PANEL, fg=TEXT, activebackground="#22222c",
                      activeforeground=TEXT, font=("Segoe UI", 12, "bold"),
                      relief="flat", anchor="w", padx=8,
                      command=(self._buglog_popup if filename == REPORT_ROW
                               else lambda p=filename: self._toggle(p)))
        b.pack(fill="x")
        return b

    ERR_HOLD_MS = 20000

    def _err_clear(self, stamp):
        if getattr(self, "_err_stamp", None) == stamp:
            try:
                self.err.config(text="")
                self._err_fit()
            except Exception:
                pass

    def _fail(self, text):
        """The status line is red and it used to stay red for ever. A message from
        twenty minutes ago reads exactly like one from this second, and after the
        relaunch button started writing its finish line here he was left staring at
        red text about something that had already worked. It clears itself now, and
        only if nothing newer has been written in the meantime."""
        stamp = time.time()
        self._err_stamp = stamp
        self.root.after(0, lambda: (self.err.config(text=text), self._err_fit()))
        self.root.after(self.ERR_HOLD_MS, lambda: self._err_clear(stamp))

    # --- cleanup -----------------------------------------------------------
    # Deliberately not a "memory cleaner". Emptying working sets and dumping the
    # standby list only forces Windows to read the same pages back off disk a
    # second later, which is slower, not faster. What genuinely frees memory is
    # closing background apps that are running for no reason, so that is what
    # this does, and only for names that restart themselves when next opened.
    OPTIONAL = [
        "MSPCManager", "MSPCManagerService", "nordsec-threatprotection-service",
        "Fishstrap", "CCXProcess", "Adobe Desktop Service", "AdobeIPCBroker",
        "BlueStacksServices", "vmware-tray", "Grammarly.Desktop", "OneDrive",
        "GoogleDriveFS", "Spotify", "WhatsApp", "WhatsApp.Root", "ms-teams", "Widgets",
        "olk", "SearchApp", "Copilot",
        # Measured on this laptop at 21:24 while Roblox was up, in MB of working
        # set: PhoneExperienceHost 196, MicrosoftSecurityApp 167, CrossDeviceService
        # 152, Microsoft.CmdPal.UI 152, IntelGraphicsSoftware 146 - 813 MB between
        # them, none of it doing anything for a game. Every one is a window or a
        # companion service that comes back the next time it is opened.
        #
        # MsMpEng is deliberately NOT here. MicrosoftSecurityApp is the Defender
        # window; MsMpEng is the scanning engine itself and killing that turns the
        # antivirus off. TextInputHost is not here either - it is the IME, and
        # closing it takes Chinese input with it.
        "PhoneExperienceHost", "CrossDeviceService", "Microsoft.CmdPal.UI",
        "MicrosoftSecurityApp", "IntelGraphicsSoftware",
        # SearchApp above is a dead name on this build. Measured: the process is
        # called SearchHost, so that row has been matching nothing. It matters
        # more than its own 90 MB - SearchHost and Widgets between them own 17 of
        # the 19 msedgewebview2 processes on this machine, 446 MB, and those
        # children go when their host does.
        #
        # msedgewebview2 itself is deliberately not listed. The other two belong
        # to GOLDAUTOCLICKER, and a name match here would close his clicker.
        "SearchHost", "WidgetService",
    ]

    def _cleanup(self):
        freed = 0
        stopped = []
        for proc in psutil.process_iter(["name", "memory_info", "pid"]):
            try:
                name = (proc.info["name"] or "").replace(".exe", "")
                if name not in self.OPTIONAL:
                    continue
                mb = (proc.info["memory_info"].rss if proc.info["memory_info"] else 0) / 2**20
                proc.terminate()
                freed += mb
                if name not in stopped:
                    stopped.append(name)
            except Exception:
                continue
        if stopped:
            self._fail(f"關掉 {len(stopped)} 種,放出約 {freed:.0f} MB")
        else:
            self._fail("沒有可以關的背景程式")

    # --- end task ----------------------------------------------------------
    # "Really end all of it" needs three passes, because each one fails where
    # the next one works. psutil kills the trees this panel is allowed to touch;
    # taskkill /F /T catches what psutil could not walk; and the elevated
    # taskkill is the only thing that can signal a client started with the ADMIN
    # button, which an unelevated panel may not touch at all. Elevation is last
    # and only for survivors, so the UAC prompt appears when it is needed.
    @staticmethod
    def _find(wanted):
        out = []
        for proc in psutil.process_iter(["name"]):
            try:
                name = (proc.info["name"] or "").lower()
            except Exception:
                continue
            if name.endswith(".exe"):
                name = name[:-4]
            if name in wanted or any(name.startswith(w + ".") for w in wanted):
                out.append(proc)
        return out

    BUGLOG_LOCAL = os.path.join(HERE, "BUGLOG.md")
    BUGLOG_REMOTE = r"C:\Users\desktop\Documents\PyToolbox\BUGLOG.md"

    REPORT_MINUTES = 10

    def _buglog_popup(self):
        """Whatever just broke, typed the moment it breaks - and beside it, what this
        machine was actually doing while it broke.

        Pressing the button starts a scan of the last ten minutes immediately in the
        background: what started, what vanished, everything Windows logged as an
        error, what the key programs are doing, and a picture of the screen as it is
        at that second. He types his sentence while that runs, so neither half waits
        for the other. Both land as markdown on both machines, which is the whole
        point - the next conversation reads the machine's own account of those ten
        minutes instead of asking him to remember them."""
        win = tk.Toplevel(self.root)
        win.title("REPORT")
        win.configure(bg=BG)
        win.attributes("-topmost", True)
        win.geometry("560x340")
        tk.Label(win, text="\u767c\u751f\u5497\u54a9\u4e8b", bg=BG, fg=ACCENT,
                 font=("Segoe UI", 15, "bold")).pack(anchor="w", padx=12, pady=(12, 0))
        tk.Label(win, text="\u6253\u4e00\u53e5\u5c31\u5f97\uff0c\u5462\u90e8\u6a5f\u982d "
                 + str(self.REPORT_MINUTES)
                 + " \u5206\u9418\u767c\u751f\u904e\u4e5c\uff0c\u6211\u81ea\u5df1\u67e5\u57cb",
                 bg=BG, fg=DIM, anchor="w",
                 font=("Segoe UI", 10)).pack(fill="x", padx=12, pady=(0, 6))
        entry = tk.Text(win, height=6, bg=PANEL, fg=TEXT, insertbackground=ACCENT,
                        font=("Segoe UI", 12), relief="flat", wrap="word",
                        highlightbackground=ACCENT, highlightthickness=1)
        entry.pack(fill="both", expand=True, padx=12)
        entry.focus_set()
        scanlbl = tk.Label(win, text="\u6383\u7dca\u6a5f...", bg=BG, fg=DIM, anchor="w",
                           font=("Segoe UI", 10), wraplength=520, justify="left")
        scanlbl.pack(fill="x", padx=12, pady=(6, 0))
        state = tk.Label(win, text="", bg=BG, fg=DIM, anchor="w",
                         font=("Segoe UI", 10), wraplength=520, justify="left")
        state.pack(fill="x", padx=12, pady=(2, 0))

        box = {"scan": None, "err": None, "shot": None}

        def paint(text, colour=DIM):
            try:
                scanlbl.configure(text=text, fg=colour)
            except Exception:
                pass

        def scan():
            try:
                text, shot = self._report_scan(
                    lambda t: self.root.after(0, paint, t))
                box["scan"] = text
                box["shot"] = shot
                self.root.after(0, paint,
                                "\u6383\u5b8c\uff1a" + str(text.count("\n") + 1)
                                + " \u884c"
                                + ("\uff0c\u9023\u87a2\u5e55\u76f8" if shot else ""),
                                ACCENT)
            except Exception as exc:
                box["err"] = str(exc)
                self.root.after(0, paint, "\u6383\u6a5f\u5931\u6557: " + str(exc),
                                "#ffb3b3")

        threading.Thread(target=scan, daemon=True).start()

        def send(event=None):
            text = entry.get("1.0", "end").strip()
            if not text:
                state.configure(text="\u6253\u5497\u5b57\u5148", fg="#ffb3b3")
                return "break"
            if box["scan"] is None and box["err"] is None:
                state.configure(text="\u6383\u7dca\u6a5f\uff0c\u7b49\u4e00\u7b49\u5c31\u8a18\u4f4e",
                                fg=DIM)
                win.after(400, send)
                return "break"
            body = text + "\n"
            if box["scan"]:
                body += ("\n<details>\n<summary>"
                         + socket.gethostname() + " \u982d "
                         + str(self.REPORT_MINUTES)
                         + " \u5206\u9418</summary>\n\n```\n"
                         + box["scan"] + "\n```\n</details>\n")
            elif box["err"]:
                body += "\n\u6383\u6a5f\u5931\u6557\uff1a" + box["err"] + "\n"
            if box["shot"]:
                body += "\n\u87a2\u5e55\u76f8\uff1a`" + box["shot"] + "`\n"
            block = ("\n## " + time.strftime("%Y-%m-%d %H:%M:%S") + "  "
                     + socket.gethostname() + "\n\n" + body)
            try:
                with open(self.BUGLOG_LOCAL, "a", encoding="utf-8") as fh:
                    fh.write(block)
            except Exception as exc:
                state.configure(text="\u5beb\u5514\u5230: " + str(exc), fg="#ffb3b3")
                return "break"
            state.configure(text="\u8a18\u4f4e\u5497", fg=ACCENT)
            entry.delete("1.0", "end")
            threading.Thread(target=self._buglog_push, args=(block, state),
                             daemon=True).start()
            return "break"

        tk.Button(win, text="\u8a18\u4f4e", bg="#1f6f43", fg="white", relief="flat",
                  font=("Segoe UI", 13, "bold"), command=send).pack(fill="x", padx=12, pady=10)

    def _report_shot(self):
        """A picture of the screen at the moment he presses. Passive: it reads the
        framebuffer and never touches a window, so nothing moves, flashes or takes
        focus while it happens."""
        out = os.path.join(HERE, "report-" + time.strftime("%Y%m%d-%H%M%S") + ".png")
        self._powershell(
            "Add-Type -AssemblyName System.Windows.Forms,System.Drawing; "
            "$b=[System.Windows.Forms.SystemInformation]::VirtualScreen; "
            "$m=New-Object System.Drawing.Bitmap $b.Width,$b.Height; "
            "$g=[System.Drawing.Graphics]::FromImage($m); "
            "$g.CopyFromScreen($b.X,$b.Y,0,0,$m.Size); "
            "$m.Save('" + out.replace("'", "''")
            + "',[System.Drawing.Imaging.ImageFormat]::Png); $g.Dispose(); $m.Dispose()")
        return out if os.path.exists(out) else None

    def _report_events(self):
        """Everything Windows itself complained about inside the window.
        FilterHashtable rather than Where-Object: the filter runs inside the event
        log service, so this returns in well under a second instead of walking the
        whole log in PowerShell."""
        script = (
            "$t=(Get-Date).AddMinutes(-" + str(self.REPORT_MINUTES) + "); $e=@(); "
            "foreach($l in 'System','Application'){ try { $e+=Get-WinEvent "
            "-FilterHashtable @{LogName=$l;Level=1,2,3;StartTime=$t} "
            "-ErrorAction Stop } catch {} }; "
            "if(-not $e){'(no error events)'} else { $e | Sort-Object TimeCreated | "
            "ForEach-Object { $_.TimeCreated.ToString('HH:mm:ss') + '  ' + $_.LogName "
            "+ '/' + $_.ProviderName + '  id=' + $_.Id + '  ' + "
            "(($_.Message -split [char]10)[0]) } }")
        r = self._powershell(script)
        out = (r.stdout or "").strip()
        return out or ("(event log unreadable) " + (r.stderr or "").strip()[:200])

    KEY_PROGRAMS = ("RobloxPlayerBeta", "Fishstrap", "Real", "ollama",
                    "ollama_llama_server", "llama-server", "deskflow-core",
                    "claude", "GOLDAUTOCLICKER-core", "pythonw", "python")

    def _report_scan(self, say):
        """Everything this machine can say about the last ten minutes, gathered
        fastest step first so the status line keeps moving instead of sitting still
        on the slow one."""
        out = []
        now = time.time()
        cut = now - self.REPORT_MINUTES * 60

        say("\u6383\u7dca\uff1a\u6a5f\u5668\u72c0\u614b")
        try:
            m = psutil.virtual_memory()
            d = psutil.disk_usage("C:" + chr(92))
            out.append("machine " + socket.gethostname()
                       + "   " + time.strftime("%Y-%m-%d %H:%M:%S")
                       + "   uptime " + "%.0f" % ((now - psutil.boot_time()) / 60.0)
                       + " min")
            out.append("ram %.1f / %.1f GB used, %.1f GB free    C: %.0f GB free"
                       % ((m.total - m.available) / 2**30, m.total / 2**30,
                          m.available / 2**30, d.free / 2**30))
        except Exception as exc:
            out.append("machine state unreadable: " + str(exc))

        say("\u6383\u7dca\uff1a\u982d " + str(self.REPORT_MINUTES)
            + " \u5206\u9418\u958b\u5497\u540c\u6b7b\u5497\u4e5c")
        started, gone = [], []
        with self._proc_lock:
            empty = not self._proc_seen
            for name, seen in self._proc_seen.items():
                if seen[0] >= cut:
                    started.append((seen[0], name))
                if cut <= seen[1] <= now - 20:
                    gone.append((seen[1], name))
        started.sort()
        gone.sort()
        stamp = lambda t: time.strftime("%H:%M:%S", time.localtime(t))
        out.append("")
        out.append("started in the last " + str(self.REPORT_MINUTES) + " min: "
                   + (", ".join(n + " " + stamp(t) for t, n in started[-25:]) or "none"))
        out.append("gone in the last " + str(self.REPORT_MINUTES) + " min: "
                   + (", ".join(n + " " + stamp(t) for t, n in gone[-25:]) or "none"))
        if empty:
            out.append("(panel only just started - it has not watched these "
                       + str(self.REPORT_MINUTES) + " minutes)")

        say("\u6383\u7dca\uff1a\u91cd\u8981\u7a0b\u5f0f")
        alive = {}
        for proc in psutil.process_iter(["name", "create_time", "memory_info"]):
            try:
                nm = (proc.info["name"] or "").replace(".exe", "")
                if nm in self.KEY_PROGRAMS:
                    slot = alive.setdefault(nm, [0, 0.0, 0])
                    slot[0] += 1
                    slot[1] = max(slot[1], proc.info["create_time"] or 0)
                    if proc.info["memory_info"]:
                        slot[2] += proc.info["memory_info"].rss
            except Exception:
                continue
        out.append("")
        for nm in self.KEY_PROGRAMS:
            if nm in alive:
                cnt, born, rss = alive[nm]
                out.append("  %-22s %d running, newest %s, %.0f MB"
                           % (nm, cnt, stamp(born), rss / 2**20))
            else:
                out.append("  %-22s not running" % nm)

        say("\u6383\u7dca\uff1a\u7ffb\u8b6f / ollama")
        out.append("")
        out.append("ollama 127.0.0.1:11434  " + self._port_note("127.0.0.1", 11434))
        if not IS_DESKTOP:
            out.append("ollama desktop:11434   "
                       + self._port_note("192.168.1.50", 11434))

        say("\u6383\u7dca\uff1a\u9762\u677f\u81ea\u5df1\u5605\u7d00\u9304")
        out.append("")
        for path, label in ((BOOTLOG, "toolbox_boot.log"), (MEMLOG, "memwatch.log")):
            try:
                with io.open(path, encoding="utf-8", errors="replace") as fh:
                    tail = fh.read().splitlines()[-8:]
                out.append(label + " last 8 lines:")
                out.extend("  " + t for t in tail)
            except Exception as exc:
                out.append(label + " unreadable: " + str(exc))

        say("\u6383\u7dca\uff1aWindows \u932f\u8aa4\u7d00\u9304")
        out.append("")
        out.append("Windows events (Critical/Error/Warning, last "
                   + str(self.REPORT_MINUTES) + " min):")
        for line in self._report_events().splitlines()[:40]:
            out.append("  " + line)

        say("\u6383\u7dca\uff1a\u5f71\u87a2\u5e55")
        shot = None
        try:
            shot = self._report_shot()
        except Exception as exc:
            out.append("screenshot failed: " + str(exc))
        return chr(10).join(out), shot

    @staticmethod
    def _port_note(host, port):
        s = socket.socket()
        s.settimeout(2.0)
        try:
            t0 = time.time()
            s.connect((host, port))
            return "up, %.0f ms" % ((time.time() - t0) * 1000)
        except Exception as exc:
            return "DOWN (" + str(exc) + ")"
        finally:
            try:
                s.close()
            except Exception:
                pass

    RELAUNCH_SCRIPT = os.path.join(HERE, "relaunch_now.py")
    RELAUNCH_OUT = r"C:\Users\desktop\relaunch.out"

    def _real_refresh(self):
        """His word, his steps. He coined [relaunch] on 2026-08-10 19:10 and said so
        in the same breath - "make sure u k what is [realunch] as i will use this
        word many times i create this word" - then gave the steps twice:

            auto close all real.exe adn the roblox all clinet then re open the
            real.exe then open the the account press the tab then press muti launch
            then press the launhc all

            it was end roblox task, end real.exe task, after 3 sec then open
            real.exe then do those 2 psotitong pressing, that was [relaunch script]

        So it is not "restart Real". Roblox goes down too, and after Real comes back
        up the four accounts have to be put back in by clicking Accounts, Multi
        Launch, Launch all and the Fishstrap join - which is why this only runs on
        the desktop: it drives the mouse.

        relaunch_now.py already did all of this, written the night after he said it.
        This button runs that file rather than a second implementation of it, so
        there is one copy of the click positions and one copy of the sequence."""
        if getattr(self, "_real_busy", False):
            return
        self._real_busy = True
        self.realbtn.config(text="RELAUNCH ...", state="disabled")

        def paint(text, colour="white", done=False):
            def work():
                self.realbtn.config(text=text, fg=colour)
                if done:
                    self._real_busy = False
                    self.realbtn.config(state="normal")
                    self.root.after(4000, lambda: self.realbtn.config(
                        text="RELAUNCH", fg="white"))
            self.root.after(0, work)

        def work():
            try:
                if not os.path.exists(self.RELAUNCH_SCRIPT):
                    paint("搵唔到腳本", "#ffb3b3", True)
                    self._fail("RELAUNCH:找不到 " + self.RELAUNCH_SCRIPT)
                    return
                try:
                    os.remove(self.RELAUNCH_OUT)
                except Exception:
                    pass

                exe = sys.executable
                if exe.lower().endswith("python.exe"):
                    cand = exe[:-10] + "pythonw.exe"
                    if os.path.exists(cand):
                        exe = cand
                subprocess.Popen(
                    [exe, self.RELAUNCH_SCRIPT], cwd=HERE, close_fds=True,
                    creationflags=(getattr(subprocess, "DETACHED_PROCESS", 0)
                                   | getattr(subprocess, "CREATE_NO_WINDOW", 0)))
                note("real relaunch started")

                # relaunch_now.py writes one line per step, so the button can show
                # what it is on rather than sitting on one word for two minutes.
                # It waits up to 60 s for the Real window alone, so the ceiling
                # here is generous.
                deadline = time.monotonic() + 180.0
                last = ""
                while time.monotonic() < deadline:
                    time.sleep(0.8)
                    try:
                        with io.open(self.RELAUNCH_OUT, encoding="utf-8",
                                     errors="replace") as fh:
                            lines = [l.strip() for l in fh if l.strip()]
                    except Exception:
                        continue
                    if not lines:
                        continue
                    tail = lines[-1]
                    if tail != last:
                        last = tail
                        short = tail.split(" ", 1)[-1][:26]
                        paint("RELAUNCH " + short)
                    if "=== done ===" in tail:
                        paint("RELAUNCH 完成", ACCENT, True)
                        note("real relaunch " + tail)
                        return
                    if tail.startswith("FAILED") or "FAILED" in tail:
                        paint("RELAUNCH 失敗", "#ffb3b3", True)
                        self._fail("RELAUNCH 失敗:" + tail)
                        return
                paint("RELAUNCH 超時", "#ffb3b3", True)
                self._fail("RELAUNCH 180 秒未完成: " + (last or "(空)"))
                self.root.after(15000,
                                lambda: (self.err.config(text=""), self._err_fit()))
            except Exception as exc:
                paint("RELAUNCH 出錯", "#ffb3b3", True)
                self._fail("RELAUNCH 出錯: " + str(exc))

        threading.Thread(target=work, daemon=True).start()

    def _buglog_push(self, block, state):
        if IS_DESKTOP:
            return
        safe = block.replace("'", "''")
        script = ("$p = '" + self.BUGLOG_REMOTE + "'; "
                  "Add-Content -LiteralPath $p -Value '" + safe + "' -Encoding UTF8; "
                  "Write-Output 'OK'")
        try:
            r = self._remote_ps(script)
            ok = "OK" in (r.stdout or "")
        except Exception:
            ok = False
        try:
            state.configure(text="\u5169\u53f0\u6a5f\u90fd\u8a18\u4f4e\u5497" if ok
                            else "\u672c\u6a5f\u8a18\u4f4e\u5497\uff0cdesktop \u63a8\u5514\u5230",
                            fg=ACCENT if ok else "#ffb3b3")
        except Exception:
            pass

    RESEARCH_LOCAL = os.path.join(HERE, "research-requests.txt")
    RESEARCH_REMOTE = r"C:\Users\desktop\Documents\DeskRun\research-requests.txt"

    def _research_popup(self):
        """A place to drop a question the second it arrives, so it is not lost by the
        time a chat is open. It lands on both machines, because the panel outlives
        any one conversation."""
        win = tk.Toplevel(self.root)
        win.title("RESEARCH")
        win.configure(bg=BG)
        win.attributes("-topmost", True)
        win.geometry("470x200")
        tk.Label(win, text="\u60f3\u67e5\u54a9", bg=BG, fg=ACCENT,
                 font=("Segoe UI", 14, "bold")).pack(anchor="w", padx=12, pady=(12, 4))
        entry = tk.Text(win, height=3, bg=PANEL, fg=TEXT, insertbackground=ACCENT,
                        font=("Segoe UI", 12), relief="flat", wrap="word",
                        highlightbackground=ACCENT, highlightthickness=1)
        entry.pack(fill="both", expand=True, padx=12)
        entry.focus_set()
        state = tk.Label(win, text="", bg=BG, fg=DIM, anchor="w",
                         font=("Segoe UI", 10), wraplength=430, justify="left")
        state.pack(fill="x", padx=12, pady=(4, 0))

        def send(event=None):
            text = entry.get("1.0", "end").strip()
            if not text:
                return "break"
            line = time.strftime("%Y-%m-%d %H:%M:%S") + "  " + text.replace("\n", " ")
            try:
                with open(self.RESEARCH_LOCAL, "a", encoding="utf-8") as fh:
                    fh.write(line + "\n")
            except Exception as exc:
                state.configure(text="\u5beb\u5514\u5230\u672c\u6a5f: " + str(exc), fg="#ffb3b3")
                return "break"
            state.configure(text="\u5df2\u7d93\u8a18\u4f4e", fg=DIM)
            threading.Thread(target=self._research_push, args=(line, state),
                             daemon=True).start()
            entry.delete("1.0", "end")
            return "break"

        entry.bind("<Return>", send)
        tk.Button(win, text="\u8a18\u4f4e", bg="#1f6f43", fg="white", relief="flat",
                  font=("Segoe UI", 12, "bold"), command=send).pack(fill="x", padx=12, pady=10)

    def _research_push(self, line, state):
        safe = line.replace("'", "''")
        script = ("$p = '" + self.RESEARCH_REMOTE + "'; "
                  "New-Item -ItemType Directory -Force -Path (Split-Path $p) | Out-Null; "
                  "Add-Content -LiteralPath $p -Value '" + safe + "' -Encoding UTF8; "
                  "Write-Output 'OK'")
        ok = False
        try:
            r = self._remote_ps(script)
            ok = "OK" in (r.stdout or "")
        except Exception:
            ok = False
        try:
            if ok:
                state.configure(text="\u5169\u53f0\u6a5f\u90fd\u8a18\u4f4e\u5497", fg=ACCENT)
            else:
                state.configure(text="\u672c\u6a5f\u8a18\u4f4e\u5497\uff0cdesktop \u63a8\u5514\u5230",
                                fg="#ffb3b3")
        except Exception:
            pass

    SSH_KEY = r"C:\Users\user\.ssh\desktop_ed25519"
    SSH_HOST = "desktop@192.168.1.50"

    def _remote_ps(self, script, timeout=40):
        """Run PowerShell on the desktop. EncodedCommand because the remote default
        shell is cmd.exe, and a bare pipe character in a PowerShell pipeline gets
        eaten by cmd before PowerShell ever sees it."""
        enc = base64.b64encode(script.encode("utf-16-le")).decode("ascii")
        return subprocess.run(
            ["ssh", "-o", "ConnectTimeout=8", "-i", self.SSH_KEY, self.SSH_HOST,
             "powershell -NoProfile -EncodedCommand " + enc],
            capture_output=True, text=True, timeout=timeout,
            creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0))

    def _translate_stop(self):
        """The translator lives on the desktop, so this button reaches across the
        network rather than killing anything here. Three things go down: the gold
        panel, the goldtalk server, and ollama with the llama-server child that
        actually holds the model in memory."""
        script = (
            "Get-CimInstance Win32_Process -Filter \"Name like 'python%'\" | "
            "Where-Object { $_.CommandLine -like '*panel.pyw*' -or $_.CommandLine -like '*goldtalk*' } | "
            "ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }; "
            "Get-Process -Name ollama,ollama_llama_server,llama-server -ErrorAction SilentlyContinue | "
            "Stop-Process -Force -ErrorAction SilentlyContinue; "
            "$n = @(Get-Process -Name ollama,llama-server -ErrorAction SilentlyContinue).Count; "
            "Write-Output ('LEFT=' + $n)")
        threading.Thread(target=self._translate_worker,
                         args=(script, "TRANSLATE 已經關", "LEFT=0"), daemon=True).start()
        self.note_status("TRANSLATE 關緊 ...")

    PANEL_COUNT = (
        "@(Get-CimInstance Win32_Process -Filter \"Name like 'python%'\" | "
        "Where-Object { $_.CommandLine -like '*panel.pyw*' -and "
        "$_.ExecutablePath -notlike '*\\venv\\Scripts\\*' })")

    def _translate_open(self):
        """Nothing auto-starts any more, so this is the only way it comes up.

        The count has to skip the venv stub. A 3.12 venv on Windows does not hold a
        real interpreter in Scripts - pythonw.exe there is a 263 KB redirector that
        re-executes the base interpreter and then just sits there holding the child.
        Both processes carry panel.pyw on their command line, so a healthy panel has
        always answered PANEL=2 to the old naive count, and the button has always
        reported failure while the translator sat there working perfectly. Measured
        2026-08-14 02:38: stub pid 11684 one thread 5 MB, real panel pid 7032 eleven
        threads 47 MB, parent of the second is the first.

        With the count right, this is idempotent: one already up is left alone,
        none starts one, and anything stranger is cleared out first."""
        script = (
            "if (-not (Get-Process -Name ollama -ErrorAction SilentlyContinue)) { "
            "Start-Process -FilePath 'E:\\tools\\ollama\\ollama.exe' -ArgumentList 'serve' -WindowStyle Hidden }; "
            "$live = " + self.PANEL_COUNT + "; "
            "if ($live.Count -ne 1) { "
            "Get-CimInstance Win32_Process -Filter \"Name like 'python%'\" | "
            "Where-Object { $_.CommandLine -like '*panel.pyw*' } | "
            "ForEach-Object { Stop-Process -Id $_.ProcessId -Force "
            "-ErrorAction SilentlyContinue }; "
            "Start-Sleep -Seconds 2; "
            "Start-ScheduledTask -TaskName 'RbxTransOriginal'; "
            "Start-Sleep -Seconds 6 }; "
            "Write-Output ('PANEL=' + " + self.PANEL_COUNT + ".Count)")
        threading.Thread(target=self._translate_worker,
                         args=(script, "TRANSLATE 已經開", "PANEL=1"), daemon=True).start()
        self.note_status("TRANSLATE 開緊 ...")

    def _translate_worker(self, script, ok_text, expect):
        """On the desktop this runs locally. It used to shell out over ssh no matter
        which machine the panel was on, and on the desktop that meant reaching for a
        key at C:/Users/user/.ssh that only exists on the laptop, so every press threw.
        Two machines, two code paths."""
        try:
            if IS_DESKTOP:
                r = subprocess.run(
                    ["powershell", "-NoProfile", "-Command", script],
                    capture_output=True, text=True, timeout=90,
                    creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0))
            else:
                r = self._remote_ps(script)
        except Exception as exc:
            self.root.after(0, self._fail, "TRANSLATE 失敗: " + str(exc))
            return
        out = (r.stdout or "").strip()
        if expect in out:
            self.root.after(0, self.note_status, ok_text)
        else:
            detail = out or (r.stderr or "").strip()[:120] or "冇回覆"
            self.root.after(0, self._fail, "TRANSLATE 回覆: " + detail)

    def note_status(self, text):
        if getattr(self, "err", None) is not None:
            try:
                self.err.configure(text=text, fg=ACCENT)
                self._err_fit()
            except Exception:
                pass

    def _end_task(self, label, names):
        wanted = tuple(n.lower() for n in names)
        victims = self._find(wanted)
        if not victims:
            self._fail(f"{label} 本來就沒有在跑")
            return
        before = len(victims)

        for proc in victims:
            try:
                for child in proc.children(recursive=True):
                    try:
                        child.kill()
                    except Exception:
                        pass
                proc.kill()
            except Exception:
                pass
        psutil.wait_procs(victims, timeout=3)

        left = self._find(wanted)
        if left:
            for exe in sorted({(p.info["name"] or "") for p in left}):
                try:
                    subprocess.run(["taskkill", "/F", "/T", "/IM", exe],
                                   capture_output=True,
                                   creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0))
                except Exception:
                    pass
            time.sleep(1)
            left = self._find(wanted)

        if left:
            args = " ".join(f'/IM "{exe}"'
                            for exe in sorted({(p.info["name"] or "") for p in left}))
            try:
                ctypes.windll.shell32.ShellExecuteW(
                    None, "runas", "taskkill.exe", f"/F /T {args}", None, 0)
                time.sleep(2)
                left = self._find(wanted)
            except Exception:
                pass

        if left:
            stubborn = ", ".join(sorted({(p.info["name"] or "?") for p in left}))
            self._fail(f"{label} {before - len(left)}/{before},關不掉: {stubborn}")
        else:
            self._fail(f"{label} 已全部關閉,共 {before} 個")

    # --- opening apps ------------------------------------------------------
    @staticmethod
    def _resolve(root, pattern, exe):
        """Squirrel keeps a stub next to Update.exe that it repoints on every
        update, so that one is tried first and never goes stale. Real and
        Discord do not ship that stub, so the versioned folders are globbed and
        the newest mtime wins - which is also what survives an update."""
        root = os.path.expandvars(root)
        stub = os.path.join(root, exe)
        if os.path.exists(stub):
            return stub
        found = [p for p in glob.glob(os.path.join(root, pattern, exe))
                 if os.path.exists(p)]
        if not found:
            return None
        return max(found, key=os.path.getmtime)

    @staticmethod
    def _running(proc, path_needs):
        """Is this app up? Optionally require the exe path to contain a substring."""
        for p in psutil.process_iter(["name", "exe"]):
            try:
                name = (p.info["name"] or "").lower()
                if name.endswith(".exe"):
                    name = name[:-4]
                if name != proc:
                    continue
                if not path_needs:
                    return True
                if path_needs.lower() in (p.info["exe"] or "").lower():
                    return True
            except Exception:
                continue
        return False

    def _matching(self, proc, path_needs):
        """Every live process this button owns, matched the way _running matches.

        path_needs still counts. [Claude] needs it: there is more than one thing
        on this machine called claude, and only the one under WindowsApps is his
        app.
        """
        out = []
        for p in psutil.process_iter(["name", "exe"]):
            try:
                name = (p.info["name"] or "").lower()
                if name.endswith(".exe"):
                    name = name[:-4]
                if name != proc:
                    continue
                if path_needs and path_needs.lower() not in (p.info["exe"] or "").lower():
                    continue
                out.append(p)
            except Exception:
                continue
        return out

    def _kill_for_reopen(self, proc, path_needs):
        """Close what is running so the button can open it fresh. True if it went.

        Kills every process with that name, not one pid. An app that has been
        restarted once leaves the older copy behind when only a single recorded
        pid is killed, and two copies of the same thing is how 12.4 GB went
        missing on this desktop on 2026-08-19. Children go first so a helper
        process cannot hold the parent open.
        """
        victims = self._matching(proc, path_needs)
        if not victims:
            return True
        for p in victims:
            try:
                for child in p.children(recursive=True):
                    try:
                        child.kill()
                    except Exception:
                        pass
                p.kill()
            except Exception:
                pass
        psutil.wait_procs(victims, timeout=4)
        if not self._matching(proc, path_needs):
            return True
        names = set()
        for p in self._matching(proc, path_needs):
            try:
                names.add(p.info["name"] or "")
            except Exception:
                pass
        for name in sorted(n for n in names if n):
            try:
                subprocess.run(["taskkill", "/F", "/T", "/IM", name],
                               capture_output=True,
                               creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0))
            except Exception:
                pass
        deadline = time.monotonic() + 5.0
        while self._matching(proc, path_needs) and time.monotonic() < deadline:
            time.sleep(0.3)
        return not self._matching(proc, path_needs)

    def _open_app(self, label, kind, target, pattern, exe, proc, path_needs=""):
        """His call on 2026-08-21: these are not open buttons any more.

        His words: "it was open not only open it was end now running that shti
        adn doing re open". So a running app is closed first and started again -
        which is what he actually wants from a button he presses when something
        has gone wrong with that app. The old behaviour was to refuse and say
        it is already running, which is true and useless.

        Still never two copies: if the close does not take, this stops rather
        than starting a second one on top of the first.
        """
        reopen = self._running(proc, path_needs)
        if reopen:
            if not self._kill_for_reopen(proc, path_needs):
                self._fail(f"{label} 關不掉,所以沒有重開")
                return
            time.sleep(1.0)
        done = "關完再開了" if reopen else "開了"

        if kind == "store":
            try:
                subprocess.Popen(["explorer.exe", f"shell:AppsFolder\\{target}"],
                                 creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0))
                self._fail(f"{label} {done}")
            except Exception as exc:
                self._fail(f"{label} 開不了: {exc}")
            return

        path = self._resolve(target, pattern, exe)
        if not path:
            self._fail(f"{label} 找不到 {exe}")
            return
        # Through explorer so the app runs at normal integrity even if this panel
        # is not, same reason as the Roblox buttons - but explorer.exe answers
        # instantly whether or not anything started, so this used to report 開了
        # for a launch that never happened. Measured with Real on the desktop
        # 2026-08-14 02:52: explorer.exe with its exe path started nothing, twice,
        # while the same path started directly was up in six seconds. So the
        # result is now checked, and a direct start is the fallback.
        for launch in (["explorer.exe", path], [path]):
            try:
                subprocess.Popen(
                    launch,
                    creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0))
            except Exception as exc:
                self._fail(f"{label} 開不了: {exc}")
                continue
            deadline = time.monotonic() + 10.0
            while (not self._running(proc, path_needs)
                   and time.monotonic() < deadline):
                time.sleep(0.4)
            if self._running(proc, path_needs):
                self._fail(f"{label} {done}")
                return
        self._fail(f"{label} 撳咗但開唔到,10 秒內冇起到: {path}")

    # --- repairing claude --------------------------------------------------
    # The sidebar is deliberately pinned to the BOTTOM of the window order, so a
    # status line at its foot is invisible exactly when this button is needed:
    # Claude's own window is sitting on top of it. That is why the first version
    # of this button looked like it did nothing. The repair therefore gets its
    # own always-on-top window, and every step is also written to
    # toolbox_boot.log so there is a record even if nothing was on screen.
    CLAUDE_PROCS = ("claude", "anthropicclaude", "claude code")

    def _fix_claude(self):
        self.fixbtn.config(state="disabled", text="修復中...")
        win = tk.Toplevel(self.root)
        win.title("修復 Claude")
        win.configure(bg=BG)
        win.attributes("-topmost", True)
        w, h = 480, 330
        win.geometry(f"{w}x{h}+{(win.winfo_screenwidth() - w) // 2}"
                     f"+{(win.winfo_screenheight() - h) // 3}")
        tk.Label(win, text="修復 Claude", bg=BG, fg=ACCENT, anchor="w",
                 font=("Segoe UI", 16, "bold")).pack(fill="x", padx=16, pady=(14, 0))
        tk.Label(win, text="關掉全部 Claude 程序 → 重新註冊套件 → 重新開啟",
                 bg=BG, fg=DIM, anchor="w", font=("Segoe UI", 9)).pack(
                     fill="x", padx=16, pady=(0, 8))
        body = tk.Label(win, text="開始...", bg=PANEL, fg=TEXT, anchor="nw",
                        justify="left", font=("Consolas", 10), padx=10, pady=10,
                        wraplength=w - 56)
        body.pack(fill="both", expand=True, padx=16)
        closebtn = tk.Button(win, text="處理中,等一等", bg="#3a3a48", fg=TEXT,
                             activebackground="#4a4a5c", activeforeground=TEXT,
                             font=("Segoe UI", 11, "bold"), relief="flat",
                             state="disabled", command=win.destroy)
        closebtn.pack(fill="x", padx=16, pady=14)
        self._fixwin = (win, body, closebtn)
        self._fixlines = []
        threading.Thread(target=self._fix_claude_worker, daemon=True).start()

    def _say(self, line):
        """Three places at once, because each one fails where the others work:
        the popup is the only thing visible above Claude, the sidebar line is
        where every other button reports, and the log is the only one that is
        still readable after the screen has been taken over or the panel died."""
        note(f"fix: {line}")
        self._fail(line)
        try:
            self._fixlines.append(line)
            text = "\n".join(self._fixlines)
            self.root.after(0, lambda t=text: self._fixwin[1].config(text=t))
        except Exception:
            pass

    def _fix_done(self, ok):
        def paint():
            try:
                self._fixwin[2].config(state="normal", text="關閉",
                                       bg="#1f6f43" if ok else "#4a1f1f",
                                       fg="white")
                self._fixwin[0].attributes("-topmost", True)
            except Exception:
                pass
            self.fixbtn.config(state="normal", text="修復 CLAUDE 並重開")
        self.root.after(0, paint)

    def _fix_claude_worker(self):
        ok = False
        try:
            # 1 - close every claude process. This is the whole reason Windows'
            # own repair fails: 0x80073D02 is literally "the following apps need
            # to be closed".
            victims = self._find(self.CLAUDE_PROCS)
            before = len(victims)
            self._say(f"1/3  關 Claude,找到 {before} 個程序")
            for proc in victims:
                try:
                    for child in proc.children(recursive=True):
                        try:
                            child.kill()
                        except Exception:
                            pass
                    proc.kill()
                except Exception:
                    pass
            psutil.wait_procs(victims, timeout=5)

            left = self._find(self.CLAUDE_PROCS)
            if left:
                self._say(f"     還有 {len(left)} 個,用 taskkill 再來一次")
                for exe in sorted({(p.info["name"] or "") for p in left}):
                    try:
                        subprocess.run(["taskkill", "/F", "/T", "/IM", exe],
                                       capture_output=True,
                                       creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0))
                    except Exception:
                        pass
                time.sleep(2)
                left = self._find(self.CLAUDE_PROCS)
            if left:
                self._say(f"     關不掉 {len(left)} 個,要重開機再試")
                return
            self._say("     全部關掉了")

            # 2 - re-register. Identical to Settings > Advanced options >
            # Repair, and like that button it keeps chats and settings. Reset is
            # the one that wipes them and this never calls it.
            self._say("2/3  重新註冊套件...")
            ps = (
                "$p = Get-AppxPackage -Name Claude; "
                "if (-not $p) { Write-Output 'NOPKG'; exit } "
                "$m = Join-Path $p.InstallLocation 'AppxManifest.xml'; "
                "if (-not (Test-Path -LiteralPath $m)) { Write-Output 'NOMANIFEST'; exit } "
                "Add-AppxPackage -Register $m -DisableDevelopmentMode; "
                "Write-Output ('OK ' + $p.Version)"
            )
            out = subprocess.run(
                ["powershell", "-NoProfile", "-ExecutionPolicy", "Bypass", "-Command", ps],
                capture_output=True, text=True, encoding="utf-8", errors="replace",
                creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0))
            said = [x for x in (out.stdout or "").strip().splitlines() if x.strip()]
            said = said[-1].strip() if said else ""
            if said == "NOPKG":
                self._say("     這部機已經沒有 Claude 這個套件,要重新安裝")
                return
            if said == "NOMANIFEST":
                self._say("     套件資料夾裡沒有 AppxManifest.xml,要重新安裝")
                return
            if not said.startswith("OK"):
                err = (out.stderr or "").strip().replace("\n", " ")[:200] or "沒有回應"
                self._say(f"     註冊失敗: {err}")
                return
            self._say(f"     {said}")

            # 3 - open it again, through explorer so it runs at normal integrity.
            self._say("3/3  重新開啟 Claude...")
            subprocess.Popen(["explorer.exe", f"shell:AppsFolder\\{CLAUDE_AUMID}"],
                             creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0))
            for _ in range(20):
                time.sleep(1)
                if self._running("claude", r"\WindowsApps\Claude_"):
                    self._say(f"     好了。關掉 {before} 個,現在已經重開。")
                    ok = True
                    return
            self._say("     註冊好了,但 Claude 還沒起來,按第 3 頁的 [Claude] 再試")
        except Exception as exc:
            self._say(f"     修復出錯: {exc}")
        finally:
            self._fix_done(ok)

    # --- game mode ---------------------------------------------------------
    def _powershell(self, command):
        """Runs hidden. A visible console flashing open on top of a game is the
        one thing this panel must never do."""
        return subprocess.run(
            ["powershell", "-NoProfile", "-Command", command],
            capture_output=True, text=True, creationflags=0x08000000)

    def _cpu_floor_read(self):
        """The processor minimum state of the scheme that is already active, as
        two hex indexes, AC first then DC. Parsed by position rather than by
        label because powercfg prints in the system language."""
        out = subprocess.run(["powercfg", "/query", "SCHEME_CURRENT", "SUB_PROCESSOR",
                              "PROCTHROTTLEMIN"], capture_output=True, text=True,
                             creationflags=0x08000000).stdout
        found = []
        for line in out.splitlines():
            for word in line.replace(":", " ").split():
                if word.lower().startswith("0x"):
                    try:
                        found.append(int(word, 16))
                    except ValueError:
                        pass
        return found[-2:] if len(found) >= 2 else None

    def _cpu_floor_write(self, ac, dc):
        """The whole point of writing into the ACTIVE scheme instead of switching
        to High performance: a power scheme carries the screen brightness with it,
        so switching schemes moves the brightness. That is what turned the screen
        dark - Balanced holds 49 and High performance holds 100 on this machine.
        Staying on one scheme means brightness is never touched.

        It answers now. It used to return None on success and on failure alike,
        so every caller read a refused write as a done one: the button went green
        over a CPU that had not moved, and the OFF path deleted the only record
        of the real floor right after failing to put it back. True means both
        indexes were stored AND the scheme was re-activated, because a stored
        index does nothing to the hardware until /setactive runs - measured, a
        value sat inert for twelve seconds and only bit when /setactive was
        called. A half write is rolled back to what was there before, so nobody
        inherits a machine in a state that was never recorded."""
        before = self._cpu_floor_read()
        flags = ("/setacvalueindex", "/setdcvalueindex")
        for i, flag in enumerate(flags):
            value = ac if i == 0 else dc
            r = subprocess.run(["powercfg", flag, "SCHEME_CURRENT", "SUB_PROCESSOR",
                                "PROCTHROTTLEMIN", str(int(value))],
                               capture_output=True, text=True, creationflags=0x08000000)
            if r.returncode != 0:
                if i and before:
                    subprocess.run(["powercfg", flags[0], "SCHEME_CURRENT",
                                    "SUB_PROCESSOR", "PROCTHROTTLEMIN",
                                    str(int(before[0]))], capture_output=True,
                                   text=True, creationflags=0x08000000)
                    subprocess.run(["powercfg", "/setactive", "SCHEME_CURRENT"],
                                   capture_output=True, text=True,
                                   creationflags=0x08000000)
                self._fail(f"CPU 最低頻寫不到: {r.stderr.strip() or r.stdout.strip()}")
                return False
        r = subprocess.run(["powercfg", "/setactive", "SCHEME_CURRENT"],
                           capture_output=True, text=True, creationflags=0x08000000)
        if r.returncode != 0:
            self._fail(f"CPU 設定套用不到: {r.stderr.strip() or r.stdout.strip()}")
            return False
        return True

    POWER_MIN_KEY = (r"SYSTEM\CurrentControlSet\Control\Power\PowerSettings"
                     r"\54533251-82be-4824-96c1-47b60b740d00"
                     r"\893dee8e-2bef-41e0-89c6-b55d0929964c"
                     r"\DefaultPowerSchemeValues")

    def _cpu_floor_default(self):
        """The processor minimum state Windows itself shipped for the scheme that
        is active, read out of the OS default table instead of guessed. This is
        the only honest answer when gamemode.json is gone, unreadable, or holds a
        floor of 100 - and 100 IS game mode, so writing that back would pin the
        CPU for good. Read on DESKTOP-PC: scheme 381b4222-f694-41f0-9685-ff5bb260df2e
        holds AC 5 and DC 5."""
        try:
            out = subprocess.run(["powercfg", "/getactivescheme"], capture_output=True,
                                 text=True, creationflags=0x08000000).stdout
            found = re.search(r"[0-9a-fA-F]{8}(?:-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}", out)
            if not found:
                return None
            with winreg.OpenKey(winreg.HKEY_LOCAL_MACHINE,
                                self.POWER_MIN_KEY) as parent:
                with winreg.OpenKey(parent, found.group(0)) as handle:
                    ac = int(winreg.QueryValueEx(handle, "ACSettingIndex")[0])
                    dc = int(winreg.QueryValueEx(handle, "DCSettingIndex")[0])
        except Exception:
            return None
        return self._sane_floor([ac, dc])

    def _sane_floor(self, pair):
        """A floor is only usable when it is two numbers and neither of them is a
        game mode value. A 100 in the state file means the panel was killed after
        it raised the floor and before it recorded the real one, and writing that
        back makes the pinned floor permanent - every later clean OFF would then
        restore 100 as if it had always been his normal setting."""
        try:
            ac, dc = int(pair[0]), int(pair[1])
        except Exception:
            return None
        if 0 <= ac < 100 and 0 <= dc < 100:
            return [ac, dc]
        return None

    DESKFLOW_LOG = r"C:\ProgramData\Deskflow\deskflow-daemon.log"
    LOCK_OPTION = "defaultLockToScreenState"

    def _deskflow_server_ready(self):
        """Only the machine running Deskflow as the server ever reads
        deskflow-server.conf. On the client the file can sit there and be ignored
        completely, so editing it there buys nothing while the service bounce
        still drops the live link for several seconds. Read from the two settings
        files: the laptop says coreMode=1 with externalConfig=true, the desktop
        says coreMode=2 and has no server section at all. Anything this cannot
        read counts as ready, so a missing settings file never disables the
        lock."""
        path = os.path.join(os.path.expandvars("%APPDATA%"), "Deskflow", "Deskflow.conf")
        try:
            with open(path, "r", encoding="utf-8", errors="replace") as fh:
                flat = fh.read().replace(" ", "")
        except Exception:
            return True, ""
        if "coreMode=2" in flat:
            return False, "這台機是 Deskflow client,滑鼠鎖要在 server 那台開,已經跳過"
        if "externalConfig=false" in flat:
            return False, "Deskflow 沒有在用設定檔,改了也沒有人讀,已經跳過"
        return True, ""

    def _is_lock_option(self, line):
        """Matches a line that ASSIGNS the option, so a hotkey binding such as
        keystroke(alt+shift+l) = lockCursorToScreen(toggle) survives. The old
        substring filter deleted that binding permanently. The dead
        lockCursorToScreen name is matched too, so a conf still carrying the line
        that made the parser throw the whole file away gets cleaned the next time
        this runs."""
        head = line.split("=", 1)[0].strip().lower()
        return head in ("defaultlocktoscreenstate", "lockcursortoscreen")

    def _write_conf(self, text):
        """Temp file, then os.replace. The old code opened the live conf in "w",
        which truncates the instant it succeeds, and only then tried to encode -
        so a single non ASCII byte anywhere in the file left a 0 byte
        deskflow-server.conf and nothing at all to put back. The newline argument
        keeps the file the way Deskflow wrote it instead of turning every line
        into CRLF."""
        tmp = DESKFLOW_CONF + ".new"
        with open(tmp, "w", encoding="utf-8", errors="surrogateescape",
                  newline="\n") as fh:
            fh.write(text)
            fh.flush()
            os.fsync(fh.fileno())
        os.replace(tmp, DESKFLOW_CONF)

    def _deskflow_log_offset(self):
        try:
            return os.path.getsize(self.DESKFLOW_LOG)
        except Exception:
            return None

    REJECTED = ("cannot read configuration", "failed to load config")
    ACCEPTED = ("started client", "started server", "waiting for clients",
                "connected to server", "locking cursor to screen",
                "accepted client connection")

    def _deskflow_core_rejected(self, offset):
        """Restart-Service returning 0 only says the daemon came up. The daemon
        stays Running while the core it spawns crash loops on a config it cannot
        parse, which is how a green ON button ended up sitting over a mouse link
        that was completely dead. This reads only the bytes the daemon appended
        after the write, so there is no clock and no log format to get wrong.

        The old 4 second deadline WAS the press. Measured on DESKTOP-PC across five ON
        presses, this function took 4000, 4015, 4000, 4016 and 4000 ms out of
        totals of 4110, 4140, 4125, 4109 and 4125 ms, and never once returned
        early. The two strings it waited for are one single message inside
        deskflow-core.exe 1.26.0.0 - the bytes at 547691 spell "started server,
        waiting for clients" - and the daemon prints it once, when the DAEMON
        starts. _deskflow_reload deliberately keeps the daemon alive and replaces
        only the core, so that message can never arrive and the early return was
        unreachable. The two changes cancelled each other out.

        What a respawned core really prints was read off the daemon log across
        five separate kills. A rejection shows up 78 to 110 ms after the core
        starts and a new core appears 204 to 313 ms after the kill, so 0.8 s is
        the real window with room over it. Rejection is tested before acceptance,
        so a tail holding both counts as a rejection."""
        if offset is None:
            return False
        deadline = time.monotonic() + 0.8
        while True:
            try:
                with open(self.DESKFLOW_LOG, "rb") as fh:
                    fh.seek(offset)
                    tail = fh.read().decode("utf-8", "replace")
            except Exception:
                return False
            if any(s in tail for s in self.REJECTED):
                return True
            if any(s in tail for s in self.ACCEPTED):
                return False
            if time.monotonic() >= deadline:
                return False
            time.sleep(0.025)

    def _deskflow_lock(self, locked):
        """Deskflow's own lock to screen, the only thing that actually stops the
        pointer leaving this machine. The panel runs at HighestAvailable so it can
        write ProgramData and bounce the service without a prompt.

        The option is defaultLockToScreenState, NOT lockCursorToScreen. Measured
        against this machine's own deskflow-core.exe 1.26.0.0: lockCursorToScreen
        exists in that binary only as an input filter action, in the strings
        "syntax for action: lockCursorToScreen" and "lockCursorToScreen(%s)",
        while defaultLockToScreenState sits inside the parser's own option name
        table between win32KeepForeground and disableLockToScreen, next to
        relativeMouseMoves which the live conf already uses. Writing an action
        name into section: options makes the parser reject the WHOLE file with
        unknown argument, so the server comes up with no screens and no links and
        the mouse stops crossing between the two machines at all. The daemon log
        recorded exactly that 50 times.

        The return value describes what the FILE now says, never whether the
        service restart worked. A conf that was rewritten while the service
        refused to bounce still locks the pointer at the next start, and the
        caller has to record that or nothing will ever take the line out again."""
        ready, why = self._deskflow_server_ready()
        if not ready:
            self._fail(why)
            return False
        if not os.path.exists(DESKFLOW_CONF):
            self._fail("找不到 deskflow-server.conf,這台機不是 server,滑鼠鎖跳過")
            return False
        try:
            with open(DESKFLOW_CONF, "r", encoding="utf-8",
                      errors="surrogateescape") as fh:
                original = fh.read()
            lines = [l for l in original.splitlines() if not self._is_lock_option(l)]
            if locked:
                out, seen = [], False
                for l in lines:
                    out.append(l)
                    if l.strip().replace(" ", "").lower() == "section:options":
                        out.append("\t" + self.LOCK_OPTION + " = true")
                        seen = True
                if not seen:
                    out += ["", "section: options",
                            "\t" + self.LOCK_OPTION + " = true", "end"]
                lines = out
            new = "\n".join(lines) + "\n"
        except Exception as exc:
            self._fail(f"讀不到 deskflow-server.conf,設定沒有改動: {exc}")
            return False
        if new == original:
            return locked
        try:
            shutil.copy2(DESKFLOW_CONF, DESKFLOW_CONF + ".gamemode-backup")
        except Exception:
            pass
        try:
            self._write_conf(new)
        except PermissionError:
            self._fail("改不到 deskflow-server.conf,面板沒有提權")
            return False
        except Exception as exc:
            self._fail(f"滑鼠鎖失敗,設定沒有改動: {exc}")
            return False
        offset = self._deskflow_log_offset()
        if not self._deskflow_reload():
            self._fail("Deskflow 重載失敗,設定已經寫好,下次啟動生效")
            return locked
        if self._deskflow_core_rejected(offset):
            try:
                self._write_conf(original)
                self._deskflow_reload()
            except Exception as exc:
                self._fail(f"Deskflow 不收這個設定,還原也失敗了: {exc}")
                return locked
            self._fail("Deskflow 不收這個設定,已經還原,滑鼠鎖沒有開")
            return not locked
        return locked

    def _deskflow_reload(self):
        """Deskflow reads its config once, at core start, so the config has to be
        reloaded somehow. Restart-Service is the obvious way and it is the slow
        way: measured 4.5 to 6.5 seconds, which is the whole reason pressing the
        button felt dead for five seconds.

        The daemon is a watchdog. Kill only deskflow-core and the daemon puts a
        new one back in about 0.39 seconds, ten times faster, and the service
        itself never goes down. Restart-Service is still here as the fallback for
        the case where there was no core running to kill, or where the daemon
        does not put one back."""
        alive = lambda: [p for p in psutil.process_iter(["name"])
                         if (p.info["name"] or "").lower() == "deskflow-core.exe"]
        try:
            victims = alive()
            for p in victims:
                try:
                    p.kill()
                except Exception:
                    pass
            if victims:
                deadline = time.monotonic() + 6.0
                while time.monotonic() < deadline:
                    time.sleep(0.10)
                    if alive():
                        return True
        except Exception:
            pass
        return self._powershell("Restart-Service -Name Deskflow -Force").returncode == 0

    GM_MISSES_BEFORE_OFF = 3
    GM_NO_ROBLOX_SECONDS = 600

    def _gamemode_restore_start(self):
        """Started from a timer, so the event loop is already running by the time
        the thread makes its first cross thread call."""
        threading.Thread(target=self._gamemode_restore_on_start, daemon=True).start()

    def _gamemode_restore_on_start(self):
        """Default off, and it means it. If the panel died or the machine was
        rebooted while game mode was on, everything goes back.

        It runs on its own thread now. It used to be called from __init__ before
        the window existed, which put a powercfg pair and a whole Restart-Service
        on the Tk thread with nothing on screen - measured at 2236 ms before the
        first widget was even built - and any failure inside it called _fail()
        while self.err did not exist yet.

        A state file that cannot be parsed is still proof that game mode was on,
        so it is not a reason to do nothing, and it is not a reason to leave the
        file behind either - the old code left it there and repeated the same
        failure on every start forever. The floor comes from the file when the
        file carries a usable one, and from the OS default table for the active
        scheme when it does not."""
        if not os.path.exists(GAMEMODE_STATE):
            return
        saved, why = None, ""
        try:
            with open(GAMEMODE_STATE, "r", encoding="utf-8-sig") as fh:
                saved = json.load(fh)
            if not isinstance(saved, dict):
                saved, why = None, "gamemode.json 格式不對"
        except Exception as exc:
            why = f"gamemode.json 讀不到: {exc}"
        with self._gm_lock:
            self.gamemode = False
            self._gm_saw_roblox = False
            self._gm_misses = 0
            self._tame_background(False)
            if (saved or {}).get("power_scheme"):
                self._power_scheme_set(saved["power_scheme"])
            if saved is None or saved.get("deskflow_locked", True):
                self._deskflow_lock(False)
            floor = self._sane_floor((saved or {}).get("cpu_floor"))
            source = "gamemode.json"
            if floor is None:
                floor = self._cpu_floor_default()
                source = "Windows default"
            if floor is None:
                self._fail("開機還原:找不到可信的 CPU 最低頻,CPU 沒有改動")
                note("game mode restore: no usable cpu floor, cpu left alone")
            elif self._cpu_floor_write(floor[0], floor[1]):
                note(f"game mode restore: cpu floor {floor} from {source}")
            try:
                os.remove(GAMEMODE_STATE)
            except OSError:
                pass
        self.root.after(0, self._gamemode_paint)
        if why:
            self._fail(f"開機還原:{why},已經照 Windows 預設值還原")
            note(f"game mode restore: {why}")
        else:
            note("game mode was still on at start, everything restored")

    def _write_state(self, saved):
        """A temp file and a swap, because a plain write that is interrupted
        leaves half a line of JSON on disk, and the restore that reads it on the
        next start cannot parse it."""
        try:
            tmp = GAMEMODE_STATE + ".new"
            with open(tmp, "w", encoding="utf-8") as fh:
                json.dump(saved, fh)
                fh.flush()
                os.fsync(fh.fileno())
            os.replace(tmp, GAMEMODE_STATE)
            return True
        except Exception as exc:
            self._fail(f"寫不到 gamemode.json,GAME MODE 沒有開: {exc}")
            return False

    HOTKEY_ID = 0xB0B
    MOD_ALT = 0x0001
    MOD_NOREPEAT = 0x4000
    VK_V = 0x56
    WM_HOTKEY = 0x0312

    def _hotkey_thread(self):
        """Alt and V toggles game mode from inside the game.

        Its own thread, because RegisterHotKey with a null window posts WM_HOTKEY
        to the message queue of the thread that registered it, and that thread
        then has to pump the queue itself. It cannot be the Tk thread: Tk owns
        that queue and never hands a raw WM_HOTKEY back to Python.

        Alt and V is a machine wide claim - exactly one process on Windows may
        hold a given combination - so a refusal is put on the panel rather than
        swallowed. A hotkey that silently did not register and a panel that
        simply ignores the keys look identical from the chair.

        MOD_NOREPEAT is what stops a held key firing the toggle forty times,
        which with a powercfg pair and a Deskflow reload behind it would queue
        forty of those."""
        user32 = ctypes.windll.user32
        if not user32.RegisterHotKey(None, self.HOTKEY_ID,
                                     self.MOD_ALT | self.MOD_NOREPEAT, self.VK_V):
            note("hotkey alt+v refused by windows, already held by something else")
            self._fail("ALT+V 被其他程式佔用了,GAME MODE 只能按這個掣")
            return
        note("hotkey alt+v registered")
        msg = ctypes.wintypes.MSG()
        while user32.GetMessageW(ctypes.byref(msg), None, 0, 0) > 0:
            if msg.message == self.WM_HOTKEY and msg.wParam == self.HOTKEY_ID:
                self.root.after(0, self._gamemode_toggle)

    def _gamemode_paint(self):
        if self.gmbtn is None:
            return
        on = self.gamemode
        # The state stays on the button's own face. The hotkey is a second way
        # in, never the only way to know which way it is pointing.
        self.gmbtn.configure(
            text="GAME MODE  ON  ALT+V" if on else "GAME MODE  OFF  ALT+V",
            bg=GM_ON if on else GM_OFF,
            activebackground=GM_ON_HOVER if on else GM_OFF_HOVER)

    def _gamemode_done(self):
        """The one place a finished game mode operation lands. Every path that
        changes self.gamemode ends here, so the button can never be left painted
        the way it was before the work ran."""
        self._gm_busy = False
        self._gamemode_paint()

    def _gamemode_auto_off(self, reason=""):
        """The watch loop's only way in. It used to hand _gamemode_off straight to
        root.after, which ran a powercfg pair and a whole Restart-Service ON the
        Tk thread - the exact freeze the button was moved onto a worker for,
        measured at 2.1 seconds dead out of a 3 second window - and it took no
        busy flag, so the five second sweep queued a second one on top of the
        first and the second restored a floor nobody had measured. It also never
        repainted, so the button read GAME MODE ON over a machine that was
        already back to normal, and pressing that green button turned game mode
        on again with no game running."""
        if self._gm_busy or not self.gamemode:
            return
        self._gm_busy = True
        if self.gmbtn is not None:
            self.gmbtn.configure(text="GAME MODE  ...", bg=GM_OFF)
        if reason:
            self._fail(reason)

        def work():
            try:
                self._gamemode_off()
            except Exception as exc:
                self.root.after(0, lambda e=exc: self._fail(f"GAME MODE: {e}"))
            finally:
                self.root.after(0, self._gamemode_done)

        threading.Thread(target=work, daemon=True).start()

    def _gamemode_toggle(self):
        """The work happens on a thread. Restarting the Deskflow service takes
        several seconds, and doing that on the Tk thread froze the whole panel -
        the button appeared not to respond at all until it was over. The button
        repaints immediately and says what it is doing while the thread runs."""
        if self._gm_busy:
            return
        self._gm_busy = True
        going_on = not self.gamemode
        self.gmbtn.configure(text="GAME MODE  ...",
                             bg=GM_ON if going_on else GM_OFF)

        def work():
            try:
                if going_on:
                    self._gamemode_on()
                else:
                    self._gamemode_off()
            except Exception as exc:
                self.root.after(0, lambda e=exc: self._fail(f"GAME MODE: {e}"))
            finally:
                self.root.after(0, self._gamemode_done)

        threading.Thread(target=work, daemon=True).start()

    def _refresh_panel(self):
        """Start the replacement first, then die. The newcomer blocks on the single
        instance mutex for up to four seconds, so it takes over the moment this
        process lets go. No PowerShell in the middle, because spawning a shell was
        most of the delay he was feeling."""
        try:
            exe = sys.executable
            if exe.lower().endswith("python.exe"):
                cand = exe[:-10] + "pythonw.exe"
                if os.path.exists(cand):
                    exe = cand
            flags = (getattr(subprocess, "DETACHED_PROCESS", 0)
                     | getattr(subprocess, "CREATE_NEW_PROCESS_GROUP", 0)
                     | getattr(subprocess, "CREATE_NO_WINDOW", 0))
            subprocess.Popen([exe, os.path.abspath(__file__)],
                             cwd=HERE, close_fds=True, creationflags=flags)
            note("panel refresh requested")
        except Exception as exc:
            self._fail("重新載入失敗,面板沒有動: " + str(exc))
            return
        self.root.destroy()

    HIGH_PERF_GUID = "8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c"
    TAME_NAMES = ("claude", "node", "Manus", "getscreen", "iCloudHome",
                  "iCloudServices", "OverlayHelper", "IntelGraphicsSoftware")
    BOOST_NAMES = ("RobloxPlayerBeta", "Windows10Universal")

    def _power_scheme_read(self):
        """The active scheme GUID, so the exit puts back exactly the one he was
        on rather than a guess. powercfg prints the label in the system language,
        so only the GUID is parsed."""
        try:
            out = subprocess.run(["powercfg", "/getactivescheme"],
                                 capture_output=True, text=True,
                                 creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0)).stdout
        except Exception:
            return None
        m = re.search(r"([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-"
                      r"[0-9a-fA-F]{4}-[0-9a-fA-F]{12})", out or "")
        return m.group(1).lower() if m else None

    def _power_scheme_set(self, guid):
        """High performance is a stock scheme and is present on this machine,
        measured. If it ever is not, duplicating it creates it, and a failure
        here is reported rather than swallowed - a game mode that quietly stayed
        on Balanced is the thing he asked me to fix."""
        if not guid:
            return False
        try:
            r = subprocess.run(["powercfg", "/setactive", guid],
                               capture_output=True, text=True,
                               creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0))
            if r.returncode == 0:
                return True
            subprocess.run(["powercfg", "/duplicatescheme", guid],
                           capture_output=True, text=True,
                           creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0))
            return subprocess.run(["powercfg", "/setactive", guid],
                                  capture_output=True, text=True,
                                  creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0)).returncode == 0
        except Exception as exc:
            self._fail(f"電源配置改不到: {exc}")
            return False

    def _tame_background(self, on):
        """Claude and the other background eaters drop below the game, and Roblox
        goes above it. Priority only - nothing is killed, because half of these
        are his own tools and a game mode that closes his work is worse than a
        slow frame.

        Windows resets a priority when a process restarts, so this is applied on
        every ON rather than once."""
        tamed = boosted = 0
        for p in psutil.process_iter(["name", "pid"]):
            name = (p.info["name"] or "").rsplit(".", 1)[0]
            try:
                if name in self.TAME_NAMES:
                    p.nice(psutil.BELOW_NORMAL_PRIORITY_CLASS if on
                           else psutil.NORMAL_PRIORITY_CLASS)
                    tamed += 1
                elif name in self.BOOST_NAMES:
                    p.nice(psutil.ABOVE_NORMAL_PRIORITY_CLASS if on
                           else psutil.NORMAL_PRIORITY_CLASS)
                    boosted += 1
            except Exception:
                pass
        note(f"game mode priorities: tamed {tamed}, boosted {boosted}, on={on}")
        return tamed, boosted

    def _gamemode_on(self):
        """Two things only, both asked for by name: the pointer cannot leave this
        machine, and the CPU stops idling at its minimum. Pointer speed, pointer
        acceleration, screen brightness and Windows Game Mode are not touched, and
        the power scheme itself is never switched.

        The record is written BEFORE the first setting is changed, and rewritten
        once the deskflow half is known. The old order changed both settings and
        wrote the file afterwards, so anything that killed the panel inside that
        window - a reboot, End Task, a crash - left the CPU pinned at 100 with
        nothing on disk that could ever put it back, and the next ON then saved
        that 100 as if it were his normal floor.

        It also refuses to report ON when a step did not happen. A red line
        saying the write failed underneath a green button saying ON is worse than
        no button at all."""
        with self._gm_lock:
            floor = self._sane_floor(self._cpu_floor_read())
            if floor is None:
                floor = self._cpu_floor_default()
            if floor is None:
                self._fail("讀不到可信的 CPU 最低頻,GAME MODE 沒有開")
                return
            saved = {"cpu_floor": floor, "deskflow_locked": False}
            if not self._write_state(saved):
                return
            if not self._cpu_floor_write(100, 100):
                try:
                    os.remove(GAMEMODE_STATE)
                except OSError:
                    pass
                return
            saved["deskflow_locked"] = self._deskflow_lock(True)
            saved["power_scheme"] = self._power_scheme_read()
            self._write_state(saved)
            if not self._power_scheme_set(self.HIGH_PERF_GUID):
                self._fail("電源配置轉不到高效能,其餘 GAME MODE 已經開了")
            self._tame_background(True)
            self.gamemode = True
            self._gm_saw_roblox = False
            self._gm_misses = 0
            self._gm_since = time.monotonic()

    def _gamemode_off(self):
        """self.gamemode goes down on the first line. It used to go down on the
        last one, which left a whole service restart during which the five second
        sweep still saw game mode as on and queued a second off on top of the
        running one - two Deskflow restarts and four powercfg writes for one exit.

        Nothing recorded means restore from the OS default, never from a number
        this program made up. The old fallback invented a floor of [5, 5] and
        wrote it into the live scheme, and invented deskflow_locked as true,
        which bounced the service for nothing."""
        self.gamemode = False
        with self._gm_lock:
            self._gm_saw_roblox = False
            self._gm_misses = 0
            saved = None
            if os.path.exists(GAMEMODE_STATE):
                try:
                    with open(GAMEMODE_STATE, "r", encoding="utf-8-sig") as fh:
                        saved = json.load(fh)
                except Exception as exc:
                    self._fail(f"讀不到 gamemode.json: {exc}")
            if not isinstance(saved, dict):
                saved = {"cpu_floor": None, "deskflow_locked": True}
            self._tame_background(False)
            if saved.get("power_scheme"):
                self._power_scheme_set(saved["power_scheme"])
            if saved.get("deskflow_locked", True):
                self._deskflow_lock(False)
            floor = self._sane_floor(saved.get("cpu_floor")) or self._cpu_floor_default()
            if floor is None:
                self._fail("找不到可信的 CPU 最低頻,CPU 設定沒有還原")
            else:
                self._cpu_floor_write(floor[0], floor[1])
            try:
                os.remove(GAMEMODE_STATE)
            except OSError:
                pass

    def _gamemode_watch(self, grouped):
        """Called once per sweep by the watch thread, with the process table it
        has already built.

        Three sweeps, not one. Roblox restarts itself, and a single missed sweep
        was enough to turn game mode off in the middle of play - measured, the
        auto off fires whenever the gap between the old process leaving and the
        new one arriving crosses a sweep boundary, which is certain for any gap
        of five seconds or more. Three misses in a row is fifteen seconds with no
        client at all, which no relaunch survives.

        The second arm covers turning it on and never launching the game. The
        only branch that could ever switch game mode off needed Roblox to have
        been seen first, so without this it stayed on for the rest of the session
        with both settings applied and nothing on screen saying so."""
        if not self.gamemode:
            self._gm_saw_roblox = False
            self._gm_misses = 0
            return
        if "RobloxPlayerBeta" in grouped:
            self._gm_saw_roblox = True
            self._gm_misses = 0
            return
        if self._gm_saw_roblox:
            self._gm_misses += 1
            if self._gm_misses >= self.GM_MISSES_BEFORE_OFF:
                self.root.after(0, self._gamemode_auto_off)
        elif self._gm_since and time.monotonic() - self._gm_since > self.GM_NO_ROBLOX_SECONDS:
            self.root.after(0, self._gamemode_auto_off,
                            "GAME MODE 開了十分鐘還沒有 Roblox,已經自己關掉")

    # --- launching ---------------------------------------------------------
    def _toggle(self, filename):
        proc = self.procs.get(filename)
        if proc and proc.poll() is None:
            self._stop(filename)
            return
        self._start(filename)

    def _start(self, filename):
        """Refuses to open a second copy of an .exe that is already up.

        Exactly one process on Windows can hold a given global hotkey. A second
        GOLDAUTOCLICKER loses CTRL+E to the first one silently - and if the copy
        that is clicking is the one that lost, the key toggles the wrong window
        and nothing stops the clicking. self.procs alone could not catch this:
        it only knows what THIS panel session started, so a copy opened before
        the panel restarted was invisible to it.
        """
        path = os.path.join(HERE, filename)
        if not os.path.exists(path):
            self._fail(f"找不到 {filename}")
            return
        if filename.lower().endswith(".exe"):
            base = os.path.basename(path)
            if self._running(os.path.splitext(base)[0].lower(), ""):
                self._fail(f"{base} 已經開著,不會再開多一個")
                return
        try:
            # Each tool elevates itself when it needs to, so this panel stays
            # unelevated and never asks for UAC on startup.
            # The tool's own folder, not this one. GOLDAUTOCLICKER resolves its
            # database beside the CURRENT DIRECTORY rather than beside its exe -
            # measured: same exe, cwd=its own folder runs and shows the window,
            # cwd=PyToolbox dies in 4 seconds with
            # "Failed to create database file: Os { code: 3, kind: NotFound }".
            # Every .py tool lives in this folder anyway, so nothing else moves.
            home = os.path.dirname(path) or HERE
            if filename.lower().endswith(".exe"):
                self.procs[filename] = subprocess.Popen([path], cwd=home)
            else:
                self.procs[filename] = subprocess.Popen([sys.executable, path], cwd=home)
            self._fail("")
        except Exception as exc:
            self._fail(f"{filename}: {exc}")

    def _stop(self, filename):
        proc = self.procs.get(filename)
        if not proc:
            return
        try:
            # A tool that elevated itself is no longer this process's child, so
            # terminate can fail. The failure is shown rather than swallowed.
            proc.terminate()
        except Exception as exc:
            self._fail(f"關不掉 {filename},自己按它的 X: {exc}")
        self.procs.pop(filename, None)

    def _player_path(self):
        """Newest RobloxPlayerBeta.exe, since the version folder changes on
        every Roblox update and hard coding one path breaks within a week."""
        roots = [
            os.path.expandvars(r"%LOCALAPPDATA%\Roblox\Versions"),
            r"C:\Program Files (x86)\Roblox\Versions",
            os.path.expandvars(r"%LOCALAPPDATA%\Fishstrap\Versions"),
        ]
        found = []
        for root in roots:
            if not os.path.isdir(root):
                continue
            for name in os.listdir(root):
                exe = os.path.join(root, name, "RobloxPlayerBeta.exe")
                if os.path.exists(exe):
                    found.append((os.path.getmtime(exe), exe))
        if not found:
            return None
        return max(found)[1]

    def _roblox(self):
        """Explorer opens it, so Roblox runs at normal integrity even though
        this panel might not be."""
        exe = self._player_path()
        if not exe:
            self._fail("找不到 RobloxPlayerBeta.exe")
            return
        try:
            subprocess.Popen(["explorer.exe", exe])
            self._fail("")
        except Exception as exc:
            self._fail(f"開不了 Roblox: {exc}")

    # A scheduled task registered to run with highest privileges can be started
    # without a UAC prompt. That is the whole trick: approve once when the task
    # is created, never again. ShellExecute "runas" cannot do that - it asks
    # every single time, which is what made this button not worth pressing.
    ADMIN_TASK = "ToolboxRobloxAdmin"

    def _admin_cmd_path(self):
        return os.path.join(HERE, "launch_roblox_admin.cmd")

    def _admin_task_exists(self):
        try:
            r = subprocess.run(["schtasks", "/Query", "/TN", self.ADMIN_TASK],
                               capture_output=True,
                               creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0))
            return r.returncode == 0
        except Exception:
            return False

    def _setup_admin_task(self):
        """One UAC prompt, once. After this the admin launch never asks again.

        The task points at a .cmd in this folder rather than at the player
        itself, because the player's path carries the Roblox version and changes
        under you on every update - a task pinned to today's path would quietly
        launch nothing next week. The .cmd is rewritten with the current path
        every time the button is pressed, and the task never has to change."""
        cmd = self._admin_cmd_path()
        try:
            with open(cmd, "w", encoding="utf-8") as fh:
                fh.write("@echo off\r\n")
            ps = (
                "$a = New-ScheduledTaskAction -Execute '{0}'; "
                "$p = New-ScheduledTaskPrincipal -UserId $env:USERNAME "
                "-LogonType Interactive -RunLevel Highest; "
                "$s = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries "
                "-DontStopIfGoingOnBatteries -ExecutionTimeLimit ([TimeSpan]::Zero); "
                "Register-ScheduledTask -TaskName '{1}' -Action $a -Principal $p "
                "-Settings $s -Force | Out-Null; Write-Output 'OK'"
            ).format(cmd.replace("'", "''"), self.ADMIN_TASK)
            r = subprocess.run(
                ["powershell", "-NoProfile", "-ExecutionPolicy", "Bypass",
                 "-Command",
                 "Start-Process powershell -Verb RunAs -Wait -WindowStyle Hidden "
                 "-ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-Command',"
                 + '"' + ps.replace('"', '`"') + '"'],
                capture_output=True, text=True, encoding="utf-8", errors="replace",
                creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0))
            if self._admin_task_exists():
                self._fail("設定好了,以後按管理員啟動不會再問你同意")
            else:
                err = (r.stderr or "").strip().replace("\n", " ")[:160]
                self._fail(f"設定失敗,你按了取消或者 UAC 沒過: {err or '沒有回應'}")
        except Exception as exc:
            self._fail(f"設定失敗: {exc}")

    def _roblox_admin(self):
        exe = self._player_path()
        if not exe:
            self._fail("找不到 RobloxPlayerBeta.exe")
            return
        if self._admin_task_exists():
            try:
                # Rewritten every time, so a Roblox update cannot leave the task
                # pointing at a version folder that no longer exists.
                with open(self._admin_cmd_path(), "w", encoding="utf-8") as fh:
                    fh.write(f'@echo off\r\nstart "" "{exe}"\r\n')
                subprocess.run(["schtasks", "/Run", "/TN", self.ADMIN_TASK],
                               capture_output=True,
                               creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0))
                self._fail("")
                return
            except Exception as exc:
                self._fail(f"排程啟動失敗,改用舊方法: {exc}")
        try:
            ctypes.windll.shell32.ShellExecuteW(None, "runas", exe, None, None, 1)
            self._fail("這次要按同意。按第 3 頁那個「不再問管理員」設定一次就不用再按")
        except Exception as exc:
            self._fail(f"開不了 Roblox: {exc}")

    def _fishstrap(self):
        if not os.path.exists(ROBLOX):
            self._fail("找不到 Fishstrap.exe")
            return
        try:
            subprocess.Popen(["explorer.exe", ROBLOX])
            self._fail("")
        except Exception as exc:
            self._fail(f"開不了 Fishstrap: {exc}")

    # --- status ------------------------------------------------------------
    def _watch(self):
        while True:
            try:
                m = psutil.virtual_memory()
                d = psutil.disk_usage("C:\\")
                # Used first, then total. "3.0 / 16 GB" was available-out-of-total
                # printed in the notation every other memory readout on Windows
                # uses for used-out-of-total, Task Manager included - so the panel
                # said 3.0 while Task Manager, open right beside it, said 12.7 for
                # the same machine at the same second. Same slash, opposite
                # meaning. Available is still shown, now with its own label, and
                # it is still what decides the colour.
                #
                # The total is no longer rounded to a whole number. 16 was
                # untrue the moment the iGPU took its slice out of the stick:
                # measured here, ullTotalPhys is 16917716992 bytes, which is
                # 15.8 GB, and it was being printed as 16.
                used = (m.total - m.available) / 2**30
                text = (f"用 {used:.1f}/{m.total / 2**30:.1f}"
                        f"  可用 {m.available / 2**30:.1f}"
                        f"  C {d.free / 2**30:.0f}")
                # The desktop is not one drive. C is the small system disk and E
                # is where everything actually lives - 1.8 TB of it - so a panel
                # that prints C alone reads as "nearly full" on a machine with
                # terabytes free. The laptop has no E, so it keeps the one number.
                if IS_DESKTOP:
                    try:
                        e = psutil.disk_usage("E:" + chr(92))
                        text += f"  E {e.free / 2**40:.2f}T"
                    except Exception:
                        pass
                colour = TEXT if m.available > 1.5 * 2**30 else "#ff8f6b"
                self.root.after(0, lambda t=text, c=colour: self.meter.config(text=t, fg=c))

                # One sweep, not two.
                #
                # This used to walk every process twice a cycle, and the second
                # walk asked for "cmdline" on all of them. On Windows reading a
                # command line means opening the process and reading its PEB, so
                # that was a couple of hundred process opens every two seconds,
                # all day, to find three python scripts. That is the background
                # drag that was here long before anything else.
                #
                # Now: one walk for the memory table, and the command line is
                # read only for processes whose name already starts with "py".
                grouped = {}
                running_scripts = set()
                for proc in psutil.process_iter(["name", "memory_info"]):
                    try:
                        info = proc.info
                        rss = info["memory_info"].rss if info["memory_info"] else 0
                        raw = info["name"] or "?"
                        name = raw.replace(".exe", "")
                        grouped[name] = grouped.get(name, 0) + rss
                        if raw.lower().startswith("py"):
                            for arg in (proc.cmdline() or []):
                                if arg.lower().endswith(".py"):
                                    running_scripts.add(os.path.basename(arg).lower())
                    except Exception:
                        continue
                now = time.time()
                with self._proc_lock:
                    for name in grouped:
                        slot = self._proc_seen.get(name)
                        if slot is None:
                            self._proc_seen[name] = [now, now]
                        else:
                            slot[1] = now
                    if len(self._proc_seen) > 4000:
                        cut = now - 3600
                        for name in [k for k, v in self._proc_seen.items()
                                     if v[1] < cut]:
                            self._proc_seen.pop(name, None)

                # The sink loop reads this. It is set from the sweep that is
                # already walking the table rather than by a second lookup.
                self._game_running = "RobloxPlayerBeta" in grouped
                self._gamemode_watch(grouped)

                top = sorted(grouped.items(), key=lambda kv: kv[1], reverse=True)[:6]
                lines = "\n".join(f"{n[:16]:<16}{b / 2**20:>6.0f} MB" for n, b in top)
                self.root.after(0, lambda t=lines: self.hogs.config(text=t))

                # A row is green if this panel started it OR if the script is
                # running at all. The watchdog is started by Windows at logon,
                # never by this panel, so the old self.procs-only test could
                # never light it up - the button sat black whether it was
                # running or not, which is exactly no information.
                for filename, btn in self.rows.items():
                    proc = self.procs.get(filename)
                    live = (proc is not None and proc.poll() is None)                         or os.path.basename(filename).lower() in running_scripts
                    self.root.after(0, lambda b=btn, s=live: b.config(
                        bg=ON if s else PANEL, fg="white" if s else TEXT))
            except Exception:
                pass
            # Five seconds, not two. Nothing on this panel changes fast enough to
            # be worth a full process sweep every two.
            #
            # Ten with a game up. A sweep opens every process on the machine to
            # read its memory counters - around three hundred of them - and the
            # panel is behind the game anyway, so nobody is reading the number it
            # produces. Auto off still fires, just three sweeps later.
            time.sleep(10 if self._game_running else 5)


_LOCK = None


def already_running():
    """A named mutex, so a second launch exits instead of stacking a second
    panel on top of the first. The startup shortcut and a manual double click
    firing close together is exactly how the duplicates kept appearing.

    The name is Local\\ and not Global\\. Creating anything in Global\\ needs
    SeCreateGlobalPrivilege, which an ordinary unelevated logon does not hold,
    so the old name failed with ERROR_ACCESS_DENIED rather than returning
    ERROR_ALREADY_EXISTS - meaning this check answered "no" every single time
    and guarded nothing. The handle is also kept alive in a module global now:
    a local would have been collectable, and Windows drops the mutex with its
    last handle."""
    global _LOCK
    try:
        deadline = time.monotonic() + 4.0
        while True:
            _LOCK = ctypes.windll.kernel32.CreateMutexW(
                None, False, "Local\\PyToolboxSingleInstance")
            if ctypes.windll.kernel32.GetLastError() != 183:
                return False
            if time.monotonic() >= deadline:
                return True
            time.sleep(0.02)
    except Exception:
        return False


def raise_priority():
    """Put the panel above the farm in the queue for the CPU.

    His words on 2026-08-20: "make sure the toolbox was the highest cmd that
    it was the hgihest so it wont able to lag or waht, adn also ti should be
    smooth, and i dont care how amny RAM it will use".

    Measured that evening with seven clients up: the machine sat at 100% CPU
    and the seven Roblox clients wanted 1165% of one core out of the 1200%
    this i7-8700 has. At that point every process on the box is queueing, and
    the panel is a single thread that only wants a few milliseconds every
    three seconds - it loses those milliseconds to whichever client is mid
    frame, and the button he pressed answers late.

    HIGH, not REALTIME. Realtime outranks the input and disk drivers, so a
    tight loop at that class can stop the mouse moving at all, and this
    process has loops in it. High is above every game client and below
    anything Windows needs to stay usable, which is exactly the position he
    is asking for.
    """
    try:
        psutil.Process(os.getpid()).nice(psutil.HIGH_PRIORITY_CLASS)
        return True
    except Exception:
        return False


if __name__ == "__main__":
    note(f"start pid={os.getpid()} exe={sys.executable}")
    if already_running():
        note("exit: another panel already has the lock")
        sys.exit()
    try:
        root = tk.Tk()
        Toolbox(root)
        note("panel up, priority raised" if raise_priority()
             else "panel up, priority stayed normal")
        root.mainloop()
        note("closed normally")
    except Exception:
        note("FATAL\n" + traceback.format_exc())
        raise
