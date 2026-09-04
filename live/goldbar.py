"""His bar.

Any .py that puts a window on his screen imports this instead of drawing a raw
tk.Tk. It removes the native Windows title bar (which also removes the taskbar
button he calls the py bar), draws his own bar in its place, and carries an
icon so nothing ever shows the default Tk feather.

    import goldbar
    win = goldbar.window("GOLDMANO", 900, 360, mode="popup")
    tk.Label(win.body, text="hi", bg=win.t["bg"], fg=win.t["accent"]).pack()
    win.run()

mode="panel" is the toolbox palette, for a tool that lives on his desktop.
mode="popup" is the replydone palette, for something that talks to him once.
offscreen=True parks the window at 3000,3000 so a machine-only test window
never lands in front of him.
"""

import ctypes
import tkinter as tk

PANEL = {
    "bg": "#0b0b0e",
    "surface": "#16161d",
    "edge": "#2a2a35",
    "text": "#e6e6ee",
    "dim": "#78788a",
    "accent": "#ffb347",
    "btn": "#2a2a38",
    "btn_hot": "#3a3a48",
    "title_pt": 12,
    "frame_px": 1,
}

POPUP = {
    "bg": "#14110d",
    "surface": "#1c1811",
    "edge": "#33291d",
    "text": "#e7b173",
    "dim": "#8a7a63",
    "accent": "#e7b173",
    "btn": "#211c15",
    "btn_hot": "#33291d",
    "title_pt": 14,
    "frame_px": 3,
}

GOLD = {
    "bg": "#FCD241",
    "surface": "#FCE96B",
    "edge": "#F7DE72",
    "text": "#0B0905",
    "dim": "#7A5C12",
    "accent": "#0B0905",
    "btn": "#0B0905",
    "btn_hot": "#241E12",
    "title_pt": 15,
    "frame_px": 3,
}

THEMES = {"panel": PANEL, "popup": POPUP, "gold": GOLD}

OFFSCREEN_XY = (3000, 3000)

GWL_EXSTYLE = -20
WS_EX_APPWINDOW = 0x00040000
WS_EX_TOOLWINDOW = 0x00000080


def _toplevel_hwnd(widget):
    user32 = ctypes.windll.user32
    hwnd = widget.winfo_id()
    while True:
        parent = user32.GetParent(hwnd)
        if not parent:
            return hwnd
        hwnd = parent


def _icon(root, accent, bg):
    img = tk.PhotoImage(master=root, width=32, height=32)
    img.put(bg, to=(0, 0, 32, 32))
    img.put(accent, to=(3, 3, 29, 11))
    img.put(accent, to=(3, 14, 20, 20))
    img.put(accent, to=(3, 23, 25, 29))
    return img


class GoldWindow:
    def __init__(self, title, width=900, height=360, mode="popup",
                 offscreen=False, attention=False, closable=True,
                 on_close=None):
        self.t = dict(THEMES[mode])
        self.title_text = title
        self.on_close = on_close
        self.offscreen = offscreen

        self.root = tk.Tk()
        self.root.title(title)
        self._iconimg = _icon(self.root, self.t["accent"], self.t["bg"])
        try:
            self.root.wm_iconphoto(True, self._iconimg)
        except tk.TclError:
            pass
        self.root.configure(bg=self.t["bg"])
        self.root.overrideredirect(True)
        self.root.attributes("-topmost", bool(attention) and not offscreen)

        if offscreen:
            x, y = OFFSCREEN_XY
        else:
            sw = self.root.winfo_screenwidth()
            sh = self.root.winfo_screenheight()
            x, y = (sw - width) // 2, (sh - height) // 3
        self.root.geometry("%dx%d+%d+%d" % (width, height, x, y))

        self.shell = tk.Frame(self.root, bg=self.t["bg"],
                              highlightbackground=self.t["accent"],
                              highlightthickness=self.t["frame_px"])
        self.shell.pack(fill="both", expand=True)

        self.bar = tk.Frame(self.shell, bg=self.t["bg"])
        self.bar.pack(fill="x", padx=10, pady=(8, 0))

        self.bar_title = tk.Label(
            self.bar, text=title, bg=self.t["bg"], fg=self.t["accent"],
            font=("Segoe UI", self.t["title_pt"], "bold"), anchor="w")
        self.bar_title.pack(side="left")

        if closable:
            self.closebtn = tk.Label(
                self.bar, text=" \u2715 ", bg=self.t["btn"],
                fg=self.t["accent"],
                font=("Segoe UI", self.t["title_pt"], "bold"),
                cursor="hand2")
            self.closebtn.pack(side="right")
            self.closebtn.bind("<Button-1>", lambda e: self.close())
            self.closebtn.bind(
                "<Enter>",
                lambda e: self.closebtn.configure(bg=self.t["btn_hot"]))
            self.closebtn.bind(
                "<Leave>",
                lambda e: self.closebtn.configure(bg=self.t["btn"]))

        self.body = tk.Frame(self.shell, bg=self.t["bg"])
        self.body.pack(fill="both", expand=True, padx=10, pady=10)

        self._drag = [0, 0]
        for w in (self.bar, self.bar_title):
            w.bind("<Button-1>", self._grab)
            w.bind("<B1-Motion>", self._move)
        self.root.bind("<Escape>", lambda e: self.close())

    def _grab(self, ev):
        self._drag = [ev.x_root - self.root.winfo_x(),
                      ev.y_root - self.root.winfo_y()]

    def _move(self, ev):
        self.root.geometry("+%d+%d" % (ev.x_root - self._drag[0],
                                       ev.y_root - self._drag[1]))

    def measure(self):
        self.root.update_idletasks()
        hwnd = _toplevel_hwnd(self.root)
        ex = ctypes.windll.user32.GetWindowLongW(hwnd, GWL_EXSTYLE)
        return {
            "title": self.title_text,
            "overrideredirect": int(self.root.overrideredirect()),
            "geometry": self.root.winfo_geometry(),
            "bar_height_px": self.bar.winfo_reqheight(),
            "bar_width_px": self.bar.winfo_reqwidth(),
            "bar_bg": self.bar.cget("bg"),
            "bar_fg": self.bar_title.cget("fg"),
            "exstyle": hex(ex & 0xFFFFFFFF),
            "ws_ex_appwindow": int(bool(ex & WS_EX_APPWINDOW)),
            "ws_ex_toolwindow": int(bool(ex & WS_EX_TOOLWINDOW)),
            "taskbar_button": int(bool(ex & WS_EX_APPWINDOW)
                                  and not bool(ex & WS_EX_TOOLWINDOW)),
            "topmost": int(self.root.attributes("-topmost")),
            "has_icon": int(self._iconimg is not None),
        }

    def close(self, *_):
        if self.on_close:
            self.on_close()
        try:
            self.root.destroy()
        except tk.TclError:
            pass

    def run(self):
        self.root.mainloop()


def window(title, width=900, height=360, mode="popup", offscreen=False,
           attention=False, closable=True, on_close=None):
    return GoldWindow(title, width, height, mode, offscreen, attention,
                      closable, on_close)


def _selftest():
    import json
    import os
    out = []
    for mode in ("panel", "popup"):
        w = window("SELFTEST " + mode, 700, 300, mode=mode, offscreen=True)
        w.root.update()
        out.append(w.measure())
        w.close()
    path = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                        "goldbar_selftest.json")
    with open(path, "w", encoding="utf-8") as fh:
        json.dump(out, fh, indent=2)
    return path


if __name__ == "__main__":
    _selftest()
