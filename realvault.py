import os
import sys
import json
import base64
import ctypes
import ctypes.wintypes as wt

APP_TITLE = "Real → Volt account export"
ENTROPY = b"Real-UI account vault key v1"
BG = "#0b0b0e"
CARD = "#141418"
GOLD = "#ffb347"
GOLD2 = "#ffd27f"
DIM = "#8a8a93"
OKC = "#6fe28c"
BADC = "#ff6f6f"

crypt32 = ctypes.WinDLL("crypt32", use_last_error=True)
kernel32 = ctypes.WinDLL("kernel32", use_last_error=True)
bcrypt = ctypes.WinDLL("bcrypt", use_last_error=True)


class DATA_BLOB(ctypes.Structure):
    _fields_ = [("cbData", wt.DWORD), ("pbData", ctypes.POINTER(ctypes.c_char))]


def blob(b):
    return DATA_BLOB(len(b), ctypes.cast(ctypes.c_char_p(b), ctypes.POINTER(ctypes.c_char)))


def dpapi_unprotect(data, entropy):
    out = DATA_BLOB()
    ok = crypt32.CryptUnprotectData(ctypes.byref(blob(data)), None,
                                    ctypes.byref(blob(entropy)), None, None, 0,
                                    ctypes.byref(out))
    if not ok:
        raise OSError("DPAPI unprotect failed, error %d" % ctypes.get_last_error())
    n = out.cbData
    buf = ctypes.string_at(out.pbData, n)
    kernel32.LocalFree(out.pbData)
    return buf


class AUTH_INFO(ctypes.Structure):
    _fields_ = [("cbSize", wt.DWORD), ("dwInfoVersion", wt.DWORD),
                ("pbNonce", ctypes.c_void_p), ("cbNonce", wt.DWORD),
                ("pbAuthData", ctypes.c_void_p), ("cbAuthData", wt.DWORD),
                ("pbTag", ctypes.c_void_p), ("cbTag", wt.DWORD),
                ("pbMacContext", ctypes.c_void_p), ("cbMacContext", wt.DWORD),
                ("cbAAD", wt.DWORD), ("cbData", ctypes.c_ulonglong), ("dwFlags", wt.DWORD)]


def aes_gcm_decrypt(key, nonce, ciphertext, tag):
    halg = ctypes.c_void_p()
    if bcrypt.BCryptOpenAlgorithmProvider(ctypes.byref(halg),
                                          "AES", None, 0) != 0:
        raise OSError("BCryptOpenAlgorithmProvider failed")
    try:
        mode = "ChainingModeGCM".encode("utf-16-le") + b"\x00\x00"
        if bcrypt.BCryptSetProperty(halg, "ChainingMode",
                                    mode, len(mode), 0) != 0:
            raise OSError("BCryptSetProperty failed")
        hkey = ctypes.c_void_p()
        keybuf = (ctypes.c_char * len(key)).from_buffer_copy(key)
        if bcrypt.BCryptGenerateSymmetricKey(halg, ctypes.byref(hkey), None, 0,
                                             keybuf, len(key), 0) != 0:
            raise OSError("BCryptGenerateSymmetricKey failed")
        try:
            ai = AUTH_INFO()
            ai.cbSize = ctypes.sizeof(AUTH_INFO)
            ai.dwInfoVersion = 1
            nbuf = (ctypes.c_char * len(nonce)).from_buffer_copy(nonce)
            tbuf = (ctypes.c_char * len(tag)).from_buffer_copy(tag)
            ai.pbNonce = ctypes.cast(nbuf, ctypes.c_void_p)
            ai.cbNonce = len(nonce)
            ai.pbTag = ctypes.cast(tbuf, ctypes.c_void_p)
            ai.cbTag = len(tag)
            outlen = wt.DWORD(0)
            inbuf = (ctypes.c_char * len(ciphertext)).from_buffer_copy(ciphertext)
            st = bcrypt.BCryptDecrypt(hkey, inbuf, len(ciphertext), ctypes.byref(ai),
                                      None, 0, None, 0, ctypes.byref(outlen), 0)
            if st != 0:
                raise OSError("BCryptDecrypt sizing failed 0x%08X" % (st & 0xffffffff))
            out = (ctypes.c_char * outlen.value)()
            st = bcrypt.BCryptDecrypt(hkey, inbuf, len(ciphertext), ctypes.byref(ai),
                                      None, 0, out, outlen.value, ctypes.byref(outlen), 0)
            if st != 0:
                raise OSError("auth tag rejected 0x%08X" % (st & 0xffffffff))
            return bytes(out[:outlen.value])
        finally:
            bcrypt.BCryptDestroyKey(hkey)
    finally:
        bcrypt.BCryptCloseAlgorithmProvider(halg, 0)


def b64pad(s):
    return base64.b64decode(s + "=" * (-len(s) % 4))


def decrypt_cookie(master, value):
    parts = value.split(":")
    if len(parts) != 4 or parts[0] != "dev" or parts[1] != "v1":
        raise ValueError("not a dev:v1 value")
    nonce = b64pad(parts[2])
    body = b64pad(parts[3])
    ct, tag = body[:-16], body[-16:]
    return aes_gcm_decrypt(master, nonce, ct, tag)


def real_data_dir():
    la = os.environ.get("LOCALAPPDATA", "")
    return os.path.join(la, "Real", "data")


def load_master(datadir):
    vp = os.path.join(datadir, "account-vault.dpapi")
    return dpapi_unprotect(open(vp, "rb").read(), ENTROPY)


def export(datadir, out_path):
    master = load_master(datadir)
    raw = json.load(open(os.path.join(datadir, "accounts.json"), "r", encoding="utf-8"))
    arr = raw if isinstance(raw, list) else raw.get("accounts", list(raw.values()))
    rows = []
    cookies = []
    for a in arr:
        user = a.get("username", "") or a.get("user_id", "")
        disp = a.get("display_name", "") or user
        try:
            pt = decrypt_cookie(master, a["cookie"]).decode("latin1")
            good = pt.startswith("_|WARNING:-DO-NOT-SHARE-THIS") and len(pt) > 200
            if good:
                cookies.append(pt)
                rows.append((disp, user, "OK", ""))
            else:
                rows.append((disp, user, "BAD", "unexpected cookie shape"))
        except Exception as e:
            rows.append((disp, user, "FAIL", str(e)[:40]))
    with open(out_path, "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(cookies) + ("\n" if cookies else ""))
    return rows, len(cookies), out_path


def run_gui(default_out):
    import tkinter as tk

    state = {"datadir": real_data_dir(), "out": default_out}

    root = tk.Tk()
    root.overrideredirect(True)
    root.configure(bg=BG)
    w, h = 640, 520
    sw = root.winfo_screenwidth()
    sh = root.winfo_screenheight()
    root.geometry("%dx%d+%d+%d" % (w, h, (sw - w) // 2, (sh - h) // 3))

    bar = tk.Frame(root, bg=BG, height=34)
    bar.pack(fill="x")
    tk.Label(bar, text="  " + APP_TITLE, bg=BG, fg=GOLD,
             font=("Segoe UI Semibold", 12)).pack(side="left", pady=6)
    tk.Label(bar, text="✕  ", bg=BG, fg=DIM, font=("Segoe UI", 12),
             cursor="hand2").pack(side="right")
    for c in bar.winfo_children():
        if c.cget("text").strip() == "✕":
            c.bind("<Button-1>", lambda e: root.destroy())

    def start_drag(e):
        root._x, root._y = e.x, e.y

    def on_drag(e):
        root.geometry("+%d+%d" % (root.winfo_pointerx() - root._x,
                                  root.winfo_pointery() - root._y))
    bar.bind("<Button-1>", start_drag)
    bar.bind("<B1-Motion>", on_drag)

    body = tk.Frame(root, bg=BG)
    body.pack(fill="both", expand=True, padx=16, pady=(4, 14))

    tk.Label(body, text="Reads your local Real account vault and writes one",
             bg=BG, fg=DIM, font=("Segoe UI", 10), anchor="w").pack(fill="x")
    tk.Label(body, text="Roblox cookie per line — the file Volt “Load from File” takes.",
             bg=BG, fg=DIM, font=("Segoe UI", 10), anchor="w").pack(fill="x", pady=(0, 10))

    src = tk.Label(body, text="Real vault:  " + state["datadir"], bg=BG, fg=GOLD2,
                   font=("Consolas", 9), anchor="w")
    src.pack(fill="x")
    dst = tk.Label(body, text="Output:  " + state["out"], bg=BG, fg=GOLD2,
                   font=("Consolas", 9), anchor="w")
    dst.pack(fill="x", pady=(0, 8))

    status = tk.Label(body, text="Ready.", bg=BG, fg=GOLD,
                      font=("Segoe UI Semibold", 11), anchor="w")
    status.pack(fill="x")

    listwrap = tk.Frame(body, bg=CARD)
    listwrap.pack(fill="both", expand=True, pady=8)
    txt = tk.Text(listwrap, bg=CARD, fg="#e8e8ec", bd=0, font=("Consolas", 10),
                  padx=12, pady=10, highlightthickness=0)
    txt.pack(fill="both", expand=True)
    txt.tag_config("ok", foreground=OKC)
    txt.tag_config("bad", foreground=BADC)
    txt.tag_config("dim", foreground=DIM)

    def do_export():
        txt.delete("1.0", "end")
        try:
            rows, n, path = export(state["datadir"], state["out"])
        except Exception as e:
            status.config(text="FAILED: " + str(e)[:70], fg=BADC)
            txt.insert("end", str(e) + "\n", "bad")
            return
        for disp, user, st, note in rows:
            tag = "ok" if st == "OK" else "bad"
            txt.insert("end", "%-3s " % ("✓" if st == "OK" else "✗"), tag)
            txt.insert("end", "%-22s " % disp[:22], None)
            txt.insert("end", "@%-18s " % user[:18], "dim")
            if note:
                txt.insert("end", note, "bad")
            txt.insert("end", "\n")
        status.config(text="Wrote %d cookies  →  %s" % (n, path),
                      fg=OKC if n else BADC)

    def choose_out():
        from tkinter import filedialog
        p = filedialog.asksaveasfilename(defaultextension=".txt",
                                         initialfile=os.path.basename(state["out"]),
                                         initialdir=os.path.dirname(state["out"]))
        if p:
            state["out"] = p
            dst.config(text="Output:  " + p)

    btns = tk.Frame(body, bg=BG)
    btns.pack(fill="x")

    def mkbtn(parent, text, cmd, fg=BG, bgc=GOLD):
        b = tk.Label(parent, text=text, bg=bgc, fg=fg, font=("Segoe UI Semibold", 11),
                     padx=18, pady=9, cursor="hand2")
        b.bind("<Button-1>", lambda e: cmd())
        return b

    mkbtn(btns, "Export cookies", do_export).pack(side="left")
    mkbtn(btns, "Change output…", choose_out, fg=GOLD, bgc=CARD).pack(side="left", padx=8)
    mkbtn(btns, "Close", root.destroy, fg=DIM, bgc=CARD).pack(side="right")

    root.mainloop()


def main():
    default_out = os.path.join(os.path.expanduser("~"), "real-cookies.txt")
    args = sys.argv[1:]
    if "--out" in args:
        default_out = args[args.index("--out") + 1]
    if "--cli" in args:
        rows, n, path = export(real_data_dir(), default_out)
        for disp, user, st, note in rows:
            print("%-4s %-22s @%-18s %s" % (st, disp, user, note))
        print("wrote %d cookies to %s" % (n, path))
        return
    run_gui(default_out)


if __name__ == "__main__":
    main()
