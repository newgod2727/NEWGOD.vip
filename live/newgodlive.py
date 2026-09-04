"""NEWGOD LIVE. Screen only, no microphone, no webcam. Sends the desktop to YouTube
live or writes it to E:\\rec, and watches the live back: how many people are
looking now and who is typing in the chat. The stream key lives in key.txt and
is never printed anywhere."""

import os
import re
import subprocess
import sys
import threading
import time
import tkinter as tk
from collections import deque
from datetime import datetime

HERE = os.path.dirname(os.path.abspath(__file__))
for _p in (r"C:\Users\benbe\Documents\DeskRun", HERE):
    if os.path.isfile(os.path.join(_p, "goldbar.py")) and _p not in sys.path:
        sys.path.insert(0, _p)
import goldbar

ROOT = HERE
KEYFILE = os.path.join(ROOT, "key.txt")
VIDFILE = os.path.join(ROOT, "video.txt")
LOG = os.path.join(ROOT, "newgodlive.log")
POSFILE = os.path.join(ROOT, "pos.json")
RELIVE = os.path.join(ROOT, "relive.flag")
FROZEN = os.path.join(ROOT, "paused.png")
HLSFILE = os.path.join(ROOT, "hls.txt")
CHANFILE = os.path.join(ROOT, "channel.txt")
HOME = (1289, 557)
RECDIR = os.environ.get("NEWGODLIVE_REC") or (r"E:\rec" if os.path.isdir("E:\\") else os.path.join(HERE, "rec"))
def _find_ff():
    import shutil
    fixed = r"C:\Users\benbe\AppData\Local\Microsoft\WinGet\Links\ffmpeg.exe"
    if os.path.isfile(fixed):
        return fixed
    found = shutil.which("ffmpeg")
    if found:
        return found
    return os.path.join(HERE, "ffmpeg.exe")


FF = _find_ff()
INGEST = "rtmp://a.rtmp.youtube.com/live2"
FPS = 30
BITRATE = "6800k"
BUFSIZE = "6800k"
GOP = 30
NO_WIN = 0x08000000
DETACHED = 0x00000008
UA = ("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
      "(KHTML, like Gecko) Chrome/131.0 Safari/537.36")

BAD = "#e05c4a"

STATE = {"viewers": None, "chat": 0, "lines": deque(maxlen=40), "why": ""}
LOCK = threading.Lock()


def note(msg):
    try:
        with open(LOG, "a", encoding="utf-8") as f:
            f.write("[" + datetime.now().strftime("%Y-%m-%d %H:%M:%S") + "] " + msg + "\n")
    except Exception:
        pass


def first_line(path):
    try:
        with open(path, encoding="utf-8-sig") as f:
            for line in f:
                s = line.strip()
                if s and not s.startswith("<"):
                    return s
    except Exception:
        return ""
    return ""


def stream_key():
    return first_line(KEYFILE)


def hls_url():
    u = first_line(HLSFILE)
    if u.startswith("http") and "http_upload_hls" in u:
        return u
    return ""


def out_args():
    u = hls_url()
    if u:
        if not u.endswith("="):
            u = u + ("&" if "?" in u else "?") + "file="
        return ["-f", "hls", "-hls_time", "1", "-hls_list_size", "3",
                "-hls_flags", "delete_segments+omit_endlist+program_date_time",
                "-hls_segment_type", "mpegts", "-method", "POST",
                "-http_persistent", "0", "-rw_timeout", "5000000",
                "-ignore_io_errors", "1", u + "index.m3u8"], "HLS"
    key = stream_key()
    if key:
        return ["-f", "flv", INGEST + "/" + key], "RTMP"
    return [], ""


def id_from(raw):
    if not raw:
        return ""
    for pat in (r"[?&]v=([A-Za-z0-9_-]{11})",
                r"youtu\.be/([A-Za-z0-9_-]{11})",
                r"/live/([A-Za-z0-9_-]{11})"):
        m = re.search(pat, raw)
        if m:
            return m.group(1)
    if re.fullmatch(r"[A-Za-z0-9_-]{11}", raw):
        return raw
    return ""


def get_page(url):
    import requests
    return requests.get(url, headers={"User-Agent": UA, "Accept-Language": "en-US,en"},
                        timeout=12).text


def learn_channel(vid):
    if first_line(CHANFILE).startswith("UC"):
        return
    try:
        m = re.search(r'"channelId":"(UC[A-Za-z0-9_-]{20,})"',
                      get_page("https://www.youtube.com/watch?v=" + vid))
        if m:
            with open(CHANFILE, "w", encoding="utf-8") as f:
                f.write(m.group(1) + "\n")
            note("learned channel " + m.group(1))
    except Exception as exc:
        note("channel learn failed " + str(exc)[:70])


LIVEID = {"id": "", "at": 0.0}


def live_now():
    ch = first_line(CHANFILE)
    if not ch.startswith("UC"):
        return ""
    if LIVEID["id"] and time.time() - LIVEID["at"] < 30:
        return LIVEID["id"]
    try:
        h = get_page("https://www.youtube.com/channel/" + ch + "/live")
        if '"isLive":true' not in h and '"isLiveNow":true' not in h:
            LIVEID["id"] = ""
            LIVEID["at"] = time.time()
            return ""
        m = re.search(r'"videoId":"([A-Za-z0-9_-]{11})"', h)
        LIVEID["id"] = m.group(1) if m else ""
        LIVEID["at"] = time.time()
        return LIVEID["id"]
    except Exception:
        LIVEID["at"] = time.time()
        return LIVEID["id"]


def video_id():
    manual = id_from(first_line(VIDFILE))
    auto = live_now()
    if auto:
        if manual and manual != auto and LIVEID.get("said") != auto:
            LIVEID["said"] = auto
            note("channel is live on " + auto + ", video.txt says " + manual
                 + ", using the live one")
        return auto
    if manual:
        learn_channel(manual)
    return manual


def read_viewers(vid):
    html = get_page("https://www.youtube.com/watch?v=" + vid)
    m = re.search(r'"originalViewCount"\s*:\s*"(\d+)"', html)
    if m:
        return int(m.group(1))
    m = re.search(r'"concurrentViewers"\s*:\s*"(\d+)"', html)
    if m:
        return int(m.group(1))
    m = re.search(r'([\d,]+)\s+watching now', html)
    if m:
        return int(m.group(1).replace(",", ""))
    return None


def viewer_worker():
    while True:
        vid = video_id()
        if not vid:
            with LOCK:
                STATE["viewers"] = None
                STATE["why"] = "video.txt \u672a\u586b\uff0c\u8cbc\u500b\u76f4\u64ad\u7db2\u5740\u843d\u53bb\u5c31\u6578\u5230"
            time.sleep(10)
            continue
        try:
            n = read_viewers(vid)
            with LOCK:
                STATE["viewers"] = n
                STATE["why"] = "" if n is not None else "\u9801\u9762\u6c92\u6709\u4eba\u6578\uff0c\u76f4\u64ad\u53ef\u80fd\u672a\u958b\u59cb\u6216\u8005\u8a2d\u6210 Private"
        except Exception as exc:
            with LOCK:
                STATE["viewers"] = None
                STATE["why"] = "\u8b80\u4eba\u6578\u5931\u6557\uff1a" + str(exc)[:70]
        time.sleep(8)


def chat_worker():
    chat = None
    live_for = ""
    while True:
        vid = video_id()
        if not vid:
            time.sleep(10)
            continue
        try:
            if chat is None or live_for != vid:
                import pytchat
                chat = pytchat.create(video_id=vid, interruptable=False)
                live_for = vid
                note("chat reader attached to " + vid)
            if not chat.is_alive():
                time.sleep(30)
                chat = None
                continue
            for c in chat.get().sync_items():
                with LOCK:
                    STATE["chat"] += 1
                    STATE["lines"].append((str(c.datetime)[11:19], c.author.name, c.message))
        except Exception as exc:
            chat = None
            with LOCK:
                STATE["why"] = "\u8b80 chat \u5931\u6557\uff1a" + str(exc)[:70]
            time.sleep(30)
        time.sleep(1)


def video_in():
    return ["-f", "gdigrab", "-framerate", str(FPS), "-draw_mouse", "1", "-i", "desktop"]


def silent_in():
    return ["-f", "lavfi", "-i", "anullsrc=channel_layout=stereo:sample_rate=44100"]


NVENC = [None]


def nvenc_ok():
    if NVENC[0] is None:
        try:
            r = subprocess.run([FF, "-hide_banner", "-loglevel", "error", "-f", "lavfi",
                                "-i", "color=c=black:s=320x240:d=1", "-c:v", "h264_nvenc",
                                "-f", "null", "-"], capture_output=True, text=True,
                               timeout=40, creationflags=NO_WIN)
            NVENC[0] = (r.returncode == 0)
            note("nvenc usable = " + str(NVENC[0]))
        except Exception as exc:
            NVENC[0] = False
            note("nvenc probe failed " + str(exc)[:90])
    return NVENC[0]


def encode(cbr=False):
    if nvenc_ok():
        v = ["-c:v", "h264_nvenc", "-preset", "p5"]
        if cbr:
            v += ["-rc", "cbr"]
    else:
        v = ["-c:v", "libx264", "-preset", "veryfast", "-tune", "zerolatency"]
        if cbr:
            v += ["-x264-params", "nal-hrd=cbr:filler=1"]
    rate = ["-b:v", BITRATE, "-maxrate", BITRATE, "-bufsize", BUFSIZE]
    if cbr:
        rate = ["-b:v", BITRATE, "-minrate", BITRATE, "-maxrate", BITRATE,
                "-bufsize", BUFSIZE]
    return v + rate + ["-g", str(GOP), "-keyint_min", str(GOP),
                       "-sc_threshold", "0", "-pix_fmt", "yuv420p",
                       "-flush_packets", "1", "-max_delay", "0",
                       "-c:a", "aac", "-b:a", "128k", "-ar", "44100"]


class Live:
    def __init__(self):
        self.pid = None
        self.what = ""
        self.paused = False
        self.win = goldbar.window("NEWGOD LIVE", 660, 470, mode="panel", on_close=self.bye)
        self.t = self.win.t
        t = self.t

        self.collapsed = False
        self._full_geom = None
        self.minbtn = tk.Button(self.win.bar, text=" - ", bg=t["btn"], fg=t["accent"],
                                relief="flat", bd=0, highlightthickness=0,
                                font=("Consolas", 11, "bold"), padx=6, pady=0,
                                activebackground=t["btn"], activeforeground=t["accent"],
                                command=self.toggle_collapse, cursor="hand2")
        self.minbtn.pack(side="right", padx=(0, 6))

        b = self.win.body
        row = tk.Frame(b, bg=t["bg"])
        row.pack(fill="x", pady=(2, 8))
        self.viewbig = tk.Label(row, text="--", bg=t["bg"], fg=t["accent"],
                                font=("Consolas", 26, "bold"))
        self.viewbig.pack(side="left")
        tk.Label(row, text="  \u4eba\u55ba\u5ea6\u770b", bg=t["bg"], fg=t["dim"],
                 font=("Segoe UI", 11, "bold")).pack(side="left", pady=(12, 0))
        self.chatbig = tk.Label(row, text="0", bg=t["bg"], fg=t["accent"],
                                font=("Consolas", 26, "bold"))
        self.chatbig.pack(side="left", padx=(24, 0))
        tk.Label(row, text="  \u53e5 chat", bg=t["bg"], fg=t["dim"],
                 font=("Segoe UI", 11, "bold")).pack(side="left", pady=(12, 0))

        btns = tk.Frame(b, bg=t["bg"])
        btns.pack(fill="x")
        self.livebtn = tk.Button(btns, text="LIVE", bg=t["btn"], fg=t["accent"],
                                 activebackground=t["btn_hot"], activeforeground=t["accent"],
                                 font=("Segoe UI", 13, "bold"), relief="flat", height=2,
                                 command=self.go_live)
        self.livebtn.pack(side="left", expand=True, fill="x", padx=(0, 3))
        self.recbtn = tk.Button(btns, text="REC", bg=t["btn"], fg=t["accent"],
                                activebackground=t["btn_hot"], activeforeground=t["accent"],
                                font=("Segoe UI", 13, "bold"), relief="flat", height=2,
                                command=self.go_rec)
        self.recbtn.pack(side="left", expand=True, fill="x", padx=3)
        self.pausebtn = tk.Button(btns, text="PAUSE", bg=t["btn"], fg=t["accent"],
                                  activebackground=t["btn_hot"], activeforeground=t["accent"],
                                  font=("Segoe UI", 13, "bold"), relief="flat", height=2,
                                  command=self.toggle_pause)
        self.pausebtn.pack(side="left", expand=True, fill="x", padx=3)
        self.stopbtn = tk.Button(btns, text="STOP", bg=t["surface"], fg=t["text"],
                                 activebackground=t["btn_hot"], activeforeground=t["text"],
                                 font=("Segoe UI", 13, "bold"), relief="flat", height=2,
                                 command=self.stop)
        self.stopbtn.pack(side="left", expand=True, fill="x", padx=(3, 0))

        wrap = tk.Frame(b, bg=t["surface"], highlightbackground=t["edge"], highlightthickness=1)
        wrap.pack(fill="both", expand=True, pady=(8, 0))
        tk.Label(wrap, text="\u908a\u500b\u55ba\u5ea6\u8b1b\u55ee", bg=t["surface"], fg=t["dim"],
                 anchor="w", font=("Segoe UI", 10, "bold")).pack(fill="x", padx=8, pady=(6, 2))
        self.chatbox = tk.Label(wrap, text="", bg=t["surface"], fg=t["text"], anchor="nw",
                                justify="left", font=("Consolas", 10), wraplength=570)
        self.chatbox.pack(fill="both", expand=True, padx=8, pady=(0, 6))

        self.say = tk.Label(b, text="", bg=t["bg"], fg=t["dim"], anchor="w", justify="left",
                            font=("Consolas", 9), wraplength=580)
        self.say.pack(fill="x", pady=(6, 0))

        self._last_pos = None
        self._pos_ready = 0
        try:
            self.win.root.attributes("-topmost", True)
        except Exception:
            pass
        self.adopt()
        threading.Thread(target=viewer_worker, daemon=True).start()
        threading.Thread(target=chat_worker, daemon=True).start()
        self.tick()

    def restore_pos(self):
        x, y = HOME
        try:
            import json
            with open(POSFILE, encoding="utf-8") as f:
                d = json.load(f)
            x, y = int(d["x"]), int(d["y"])
        except Exception:
            pass
        try:
            self.win.root.geometry("+%d+%d" % (x, y))
        except Exception:
            pass

    def save_pos(self):
        r = self.win.root
        here = (r.winfo_x(), r.winfo_y())
        if here == self._last_pos or here == (0, 0):
            return
        self._last_pos = here
        try:
            import json
            with open(POSFILE, "w", encoding="utf-8") as f:
                json.dump({"x": here[0], "y": here[1]}, f)
        except Exception:
            pass

    def toggle_collapse(self):
        r = self.win.root
        if not self.collapsed:
            self._full_geom = r.geometry().split("+")[0]
            try:
                self.win.body.pack_forget()
            except Exception:
                pass
            r.update_idletasks()
            w = max(r.winfo_width(), 300)
            h = max(self.win.bar.winfo_height() + 20, 34)
            r.geometry("%dx%d+%d+%d" % (w, h, r.winfo_x(), r.winfo_y()))
            self.minbtn.config(text=" + ")
            self.collapsed = True
        else:
            self.win.body.pack(fill="both", expand=True, padx=10, pady=10)
            if self._full_geom:
                try:
                    r.geometry("%s+%d+%d" % (self._full_geom, r.winfo_x(), r.winfo_y()))
                except Exception:
                    pass
            self.minbtn.config(text=" - ")
            self.collapsed = False

    def msg(self, text, bad=False):
        self.say.configure(text=text, fg=BAD if bad else self.t["dim"])

    def adopt(self):
        try:
            import psutil
        except Exception:
            return
        for p in psutil.process_iter(["pid", "name", "cmdline"]):
            try:
                if (p.info["name"] or "").lower() != "ffmpeg.exe":
                    continue
                line = " ".join(p.info["cmdline"] or [])
                if "gdigrab" not in line:
                    continue
                self.pid = p.pid
                low = line.lower()
                self.what = "REC" if (RECDIR.lower() in low) else "LIVE"
                note("adopted running " + self.what + " pid " + str(p.pid))
                return
            except Exception:
                continue

    def running(self):
        if self.pid is None:
            return False
        try:
            import psutil
            p = psutil.Process(self.pid)
            return p.is_running() and p.name().lower() == "ffmpeg.exe"
        except Exception:
            return False

    def start(self, args, what):
        if self.running():
            self.msg(self.what + " \u5df2\u7d93\u5728\u8dd1\uff0c\u5148\u6309 STOP")
            return
        if not os.path.isdir(RECDIR):
            try:
                os.makedirs(RECDIR)
            except Exception:
                pass
        try:
            proc = subprocess.Popen([FF, "-hide_banner", "-loglevel", "error"] + args,
                                    stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                                    stderr=open(LOG, "a", encoding="utf-8"),
                                    creationflags=NO_WIN | DETACHED, close_fds=True)
            self.pid = proc.pid
            self.what = what
            note(what + " started pid " + str(proc.pid))
            self.msg(what + " \u958b\u4e86\uff0cpid " + str(proc.pid))
        except Exception as exc:
            self.pid = None
            note(what + " failed " + str(exc))
            self.msg(what + " \u958b\u4e0d\u5230\uff1a" + str(exc)[:90], True)

    def go_live(self):
        out, how = out_args()
        if not out:
            self.msg("key.txt \u540c hls.txt \u5169\u500b\u90fd\u7a7a\uff0c"
                     "\u8cbc\u4e00\u500b\u5165\u53bb\u5148", True)
            return
        self.paused = False
        self.pausebtn.config(text="PAUSE")
        self.how = how
        self.start(video_in() + silent_in() + encode(cbr=True) + out, "LIVE")

    def grab_still(self):
        try:
            r = subprocess.run([FF, "-hide_banner", "-loglevel", "error", "-f", "gdigrab",
                                "-framerate", "1", "-i", "desktop", "-frames:v", "1",
                                "-y", FROZEN], capture_output=True, text=True, timeout=30,
                               creationflags=NO_WIN)
            return r.returncode == 0 and os.path.exists(FROZEN)
        except Exception as exc:
            note("still grab failed " + str(exc)[:80])
            return False

    def toggle_pause(self):
        if self.what == "REC":
            self.msg("\u9304\u843d\u78c1\u789f\u5514\u7528 PAUSE\uff0c"
                     "\u6309 STOP \u518d\u6309 REC \u5c31\u53e6\u958b\u4e00\u689d\u7247")
            return
        out, how = out_args()
        if not out:
            self.msg("key.txt \u540c hls.txt \u5169\u500b\u90fd\u7a7a", True)
            return
        if not self.paused:
            if not self.grab_still():
                self.msg("\u5f71\u5514\u5230\u5f0f\u5b9a\u683c\uff0c\u4e0d\u6562 PAUSE", True)
                return
            self.hard_stop()
            time.sleep(0.4)
            self.start(["-loop", "1", "-framerate", str(FPS), "-i", FROZEN]
                       + silent_in() + encode(cbr=True) + out, "LIVE")
            self.paused = True
            self.pausebtn.config(text="RESUME")
            self.msg("\u505c\u55ba\u5b9a\u683c\uff0c\u76f4\u64ad\u6c92\u6709\u65b7")
        else:
            self.hard_stop()
            time.sleep(0.4)
            self.start(video_in() + silent_in() + encode(cbr=True) + out, "LIVE")
            self.paused = False
            self.pausebtn.config(text="PAUSE")
            self.msg("\u63a5\u56de\u87a2\u5e55")

    def hard_stop(self):
        if not self.running():
            return
        try:
            import psutil
            p = psutil.Process(self.pid)
            p.terminate()
            for _ in range(20):
                if not p.is_running():
                    break
                time.sleep(0.2)
            if p.is_running():
                p.kill()
        except Exception:
            pass
        self.pid = None

    def go_rec(self):
        out = os.path.join(RECDIR, time.strftime("screen-%Y%m%d-%H%M%S.mp4"))
        self.start(video_in() + silent_in() + encode() + ["-shortest", out], "REC")

    def stop(self):
        if not self.running():
            self.msg("\u672c\u4f86\u5c31\u6c92\u6709\u5728\u8dd1")
            return
        try:
            import psutil
            p = psutil.Process(self.pid)
            p.terminate()
            for _ in range(20):
                if not p.is_running():
                    break
                time.sleep(0.2)
            if p.is_running():
                p.kill()
        except Exception:
            pass
        note(self.what + " stopped")
        self.msg(self.what + " \u505c\u4e86")
        self.pid = None

    def tick(self):
        with LOCK:
            v = STATE["viewers"]
            c = STATE["chat"]
            lines = list(STATE["lines"])[-9:]
            why = STATE["why"]
        live = self.running()
        head = "NEWGOD LIVE" + (("  " + ("PAUSED" if self.paused else self.what)) if live else "")
        head = head + "   \u770b " + ("--" if v is None else str(v)) + "   chat " + str(c)
        try:
            self.win.bar_title.config(text=head)
        except Exception:
            pass
        if not self.collapsed:
            self.viewbig.config(text="--" if v is None else str(v))
            self.chatbig.config(text=str(c))
            self.chatbox.config(
                text="\n".join("%s  %s: %s" % (a, b, d) for a, b, d in lines)
                     or "\u672a\u6709\u4eba\u8b1b\u55ee")
            if why:
                self.msg(why, True)
            self.livebtn.config(state="disabled" if live else "normal")
            self.recbtn.config(state="disabled" if live else "normal")
            self.pausebtn.config(state="normal" if (live and self.what == "LIVE") else "disabled")
        try:
            self.win.root.attributes("-topmost", True)
        except Exception:
            pass
        if self._pos_ready == 0:
            self._pos_ready = 1
            self.restore_pos()
        elif self._pos_ready == 1:
            self._pos_ready = 2
            self._last_pos = (self.win.root.winfo_x(), self.win.root.winfo_y())
        else:
            self.save_pos()
        if os.path.exists(RELIVE):
            try:
                os.remove(RELIVE)
            except Exception:
                pass
            was = self.what
            self.stop()
            if was == "REC":
                self.go_rec()
            else:
                self.go_live()
        self.win.root.after(1000, self.tick)

    def bye(self):
        self.stop()

    def run(self):
        def boom(exc, val, tb):
            import traceback
            note("TK CRASH " + "".join(traceback.format_exception(exc, val, tb))[-400:])
        try:
            self.win.root.report_callback_exception = boom
        except Exception:
            pass
        self.win.run()


_ONE = None


def only_one():
    global _ONE
    import ctypes
    k32 = ctypes.WinDLL("kernel32", use_last_error=True)
    k32.CreateMutexW.restype = ctypes.c_void_p
    k32.CreateMutexW.argtypes = [ctypes.c_void_p, ctypes.c_int, ctypes.c_wchar_p]
    ctypes.set_last_error(0)
    _ONE = k32.CreateMutexW(None, False, "Global\\NEWGODLIVE_ONE")
    err = ctypes.get_last_error()
    if not _ONE:
        return True
    return err != 183


if __name__ == "__main__":
    try:
        sys.stderr = open(os.path.join(ROOT, "newgodlive.err"), "a",
                          encoding="utf-8", buffering=1)
        sys.stdout = sys.stderr
    except Exception:
        pass
    if not only_one():
        sys.exit(0)
    if not os.path.isdir(ROOT):
        os.makedirs(ROOT)
    if not os.path.exists(KEYFILE):
        with open(KEYFILE, "w", encoding="utf-8") as f:
            f.write("<paste your youtube stream key on this line, nothing else>\n")
    if not os.path.exists(VIDFILE):
        with open(VIDFILE, "w", encoding="utf-8") as f:
            f.write("<paste the live video link or the 11 character video id here>\n")
    Live().run()
