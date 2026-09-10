"""PyToolbox first run.

The panel is started with pythonw.exe, which has no console. That is right for
a sidebar and wrong for a first run: when it dies before it draws, the traceback
goes nowhere, no log is written either, and the machine looks identical to one
where nothing was ever pressed. This file exists so that never happens. Every
check below ends in a sentence, and every sentence lands in FIRST-RUN.txt next
to this file as well as on the console.

The last check is the one that matters. It does not trust the launch, it goes
looking for the panel's real window handle and only then says it is up.
"""

import ctypes
import ctypes.wintypes
import os
import re
import subprocess
import sys
import tempfile
import time

HERE = os.path.dirname(os.path.abspath(__file__))
REPORT = os.path.join(HERE, "FIRST-RUN.txt")
PY_DOWNLOAD = "https://www.python.org/downloads/windows/"

_lines = []


def say(line):
    _lines.append(line)
    try:
        print(line)
    except Exception:
        try:
            print(line.encode("ascii", "replace").decode("ascii"))
        except Exception:
            pass
    try:
        with open(REPORT, "a", encoding="utf-8") as fh:
            fh.write(line + "\n")
    except Exception:
        pass


def head(line):
    say("")
    say("== " + line + " ==")


def die(reason, cure):
    head("停在這裡")
    say("原因　" + reason)
    say("做法　" + cure)
    say("")
    say("這幾行同時寫進了 " + REPORT)
    sys.exit(2)


def start_report():
    try:
        with open(REPORT, "w", encoding="utf-8") as fh:
            fh.write("PyToolbox 第一次啟動　" +
                     time.strftime("%Y-%m-%d %H:%M:%S") + "\n")
    except Exception:
        pass
    say("PyToolbox 第一次啟動")
    say("時間　" + time.strftime("%Y-%m-%d %H:%M:%S"))
    say("資料夾　" + HERE)
    say("這台機　" + os.environ.get("COMPUTERNAME", "?"))


def check_folder():
    head("一　這個資料夾是不是真的解壓出來過")
    low = HERE.lower()
    parts = low.split(os.sep)
    tmp = tempfile.gettempdir().lower()

    zipish = [p for p in parts if p.endswith(".zip")]
    tempish = re.search(r"\\temp\d*_", low) is not None
    under_tmp = low.startswith(tmp)

    if zipish or tempish:
        die("你是在 zip 的預覽視窗裡面直接按下去,Windows 只把檔案丟去一個暫存夾"
            "(" + HERE + ")。那個資料夾在你關掉 zip 視窗那一刻就會被刪走,"
            "面板存的設定同 log 會一齊不見。",
            "先把 PyToolbox 整個資料夾拉出來,放去例如 "
            + os.path.join(os.path.expanduser("~"), "Documents", "PyToolbox")
            + " ,再在那邊按 START.cmd。")
    if under_tmp:
        say("注意　這個資料夾在系統暫存區底下,Windows 會自己清走。建議搬去 Documents。")
    else:
        say("好　不是 zip 暫存路徑")

    probe = os.path.join(HERE, ".writetest")
    try:
        with open(probe, "w", encoding="utf-8") as fh:
            fh.write("x")
        os.remove(probe)
        say("好　這個資料夾寫得入 (面板要在這裡寫 toolbox_boot.log 同它的設定)")
    except Exception as exc:
        die("這個資料夾寫不入:" + type(exc).__name__ + " " + str(exc) +
            "。面板每次啟動都要在自己旁邊寫 toolbox_boot.log,寫不到就連它為什麼死"
            "都沒有人知道。",
            "把 PyToolbox 搬去 " +
            os.path.join(os.path.expanduser("~"), "Documents", "PyToolbox") +
            " ,不要放在 Program Files 或者任何要管理員權限的地方。")


def check_python():
    head("二　Python")
    say("執行檔　" + sys.executable)
    say("版本　" + sys.version.split()[0])
    if sys.version_info < (3, 10):
        die("這個 Python 是 " + sys.version.split()[0] + ",太舊。",
            "去 " + PY_DOWNLOAD + " 裝 3.12,裝的時候剔 Add python.exe to PATH。")
    if sys.version_info < (3, 12):
        say("注意　官方寫明 3.12。你這個是 " + sys.version.split()[0] +
            ",下面會先幫你驗一次它讀不讀得懂 toolbox.py。")
    for mod in ("tkinter", "ctypes", "winreg"):
        try:
            __import__(mod)
            say("好　" + mod)
        except Exception as exc:
            if mod == "tkinter":
                die("這個 Python 沒有 tkinter (" + str(exc) + "),面板整個是 tkinter 畫的。",
                    "去 " + PY_DOWNLOAD + " 重裝 Python,安裝畫面裡面 "
                    "tcl/tk and IDLE 那一格一定要剔。")
            die(mod + " 載不到:" + str(exc), "這個 Python 壞了,去 " + PY_DOWNLOAD + " 重裝。")


def pythonw_for(exe):
    base = os.path.basename(exe).lower()
    if base == "pythonw.exe":
        return exe
    cand = os.path.join(os.path.dirname(exe), "pythonw.exe")
    if os.path.exists(cand):
        return cand
    return None


def check_psutil():
    head("三　psutil")
    try:
        import psutil
        say("好　psutil " + psutil.__version__ + " 已經在")
        return True
    except Exception:
        say("沒有 psutil。面板第 32 行就是 import psutil,缺了它 pythonw 會靜靜死掉,"
            "連 toolbox_boot.log 都不會出現。現在裝。")

    for args in (["-m", "pip", "install", "--user", "psutil"],
                 ["-m", "pip", "install", "psutil"]):
        cmd = [sys.executable] + args
        say("跑　" + " ".join(cmd))
        try:
            r = subprocess.run(cmd, capture_output=True, text=True, timeout=300,
                               creationflags=0x08000000)
        except Exception as exc:
            say("失敗　" + type(exc).__name__ + " " + str(exc))
            continue
        tail = (r.stdout or "").strip().splitlines()[-3:]
        for t in tail:
            say("　　" + t)
        if r.returncode != 0:
            for t in (r.stderr or "").strip().splitlines()[-4:]:
                say("　　" + t)
            say("這一次 pip 回 " + str(r.returncode) + ",試下一個方法。")
            continue
        chk = subprocess.run([sys.executable, "-c",
                              "import psutil;print(psutil.__version__)"],
                             capture_output=True, text=True,
                             creationflags=0x08000000)
        if chk.returncode == 0:
            say("好　psutil " + chk.stdout.strip() + " 裝好了")
            return True

    die("psutil 裝不到。學校的機通常是把 pip 的網路擋住了。",
        "自己開一個 cmd 貼這一句看它講什麼:" +
        sys.executable + " -m pip install --user psutil" +
        "  。如果是被擋,叫學校放行 pypi.org 同 files.pythonhosted.org。")


def find_panel():
    head("四　找 toolbox.py")
    here_name = os.environ.get("COMPUTERNAME", "").upper()
    cands = [
        os.path.join(HERE, "toolbox.py"),
        os.path.join(HERE, "laptop", "toolbox.py"),
        os.path.join(HERE, "PyToolbox", "laptop", "toolbox.py"),
        os.path.join(HERE, "desktop", "toolbox.py"),
        os.path.join(HERE, "PyToolbox", "desktop", "toolbox.py"),
    ]
    found = [c for c in cands if os.path.exists(c)]
    if not found:
        die("這個資料夾裡面找不到 toolbox.py。",
            "解壓的時候要把整個 PyToolbox 資料夾拉出來,"
            "START.cmd 要同 laptop 同 desktop 兩個資料夾放在一起。")
    for f in found:
        say("有　" + f)
    pick = found[0]
    say("")
    say("用　" + pick)
    src = open(pick, "r", encoding="utf-8", errors="replace").read()
    m = re.search(r'IS_DESKTOP\s*=.*?startswith\("(.*?)"\)', src)
    if m:
        pref = m.group(1)
        is_d = here_name.startswith(pref)
        say("這份檔用 hostname 來揀樣式:開頭是 " + pref + " 就當 desktop。")
        say("這台機叫 " + (here_name or "?") + " ,所以 IS_DESKTOP = " + str(is_d) +
            " ,畫出來的是 " + ("desktop" if is_d else "laptop") + " 樣式。")
        if not is_d:
            say("那個 " + pref + " 只是原作者機器的名,不是你的。要換樣式就自己改那一行。")
    return pick


def check_rows(panel):
    head("五　第一頁那些掣指住的工具")
    src = open(panel, "r", encoding="utf-8", errors="replace").read()
    m = re.search(r"^TOOLS = \[(.*?)^\]", src, re.S | re.M)
    if not m:
        say("讀不到 TOOLS 那張表,跳過。")
        return
    rows = re.findall(r'\(\s*(.+?),\s*"(.*?)"\s*\)', m.group(1), re.S)
    base = os.path.dirname(panel)
    missing = 0
    total = 0
    for raw, label in rows:
        raw = raw.strip()
        if raw.startswith('"') or raw.startswith("'"):
            fn = raw.strip('"').strip("'")
            p = fn if os.path.isabs(fn) else os.path.join(base, fn)
        elif "expanduser" in raw:
            p = os.path.join(os.path.expanduser("~"), "Documents",
                             "GOLDAUTOCLICKER", "GOLDAUTOCLICKER.exe")
        else:
            continue
        total += 1
        if not os.path.exists(p):
            missing += 1
    if missing:
        say(str(total) + " 個掣裡面有 " + str(missing) +
            " 個指住的檔不在這個下載裡面。")
        say("那些掣按下去不會當機,面板會自己寫一行「找不到 xxx」出來,但它們是空的。")
        say("面板本身照樣行,第 2 到第 7 頁全部正常。")
    else:
        say("好　" + str(total) + " 個掣全部找得到自己的檔")


def compile_check(panel):
    head("六　這個 Python 讀不讀得懂 toolbox.py")
    r = subprocess.run([sys.executable, "-c",
                        "import py_compile,sys;py_compile.compile(sys.argv[1],"
                        "doraise=True);print('OK')", panel],
                       capture_output=True, text=True, creationflags=0x08000000)
    if r.returncode == 0:
        say("好　語法過得了 " + sys.version.split()[0])
    else:
        say((r.stderr or "").strip()[-500:])
        die("這個 Python 讀不懂 toolbox.py。",
            "去 " + PY_DOWNLOAD + " 裝 Python 3.12。")


class PROCESSENTRY32(ctypes.Structure):
    _fields_ = [("dwSize", ctypes.wintypes.DWORD),
                ("cntUsage", ctypes.wintypes.DWORD),
                ("th32ProcessID", ctypes.wintypes.DWORD),
                ("th32DefaultHeapID", ctypes.POINTER(ctypes.c_ulong)),
                ("th32ModuleID", ctypes.wintypes.DWORD),
                ("cntThreads", ctypes.wintypes.DWORD),
                ("th32ParentProcessID", ctypes.wintypes.DWORD),
                ("pcPriClassBase", ctypes.c_long),
                ("dwFlags", ctypes.wintypes.DWORD),
                ("szExeFile", ctypes.c_char * 260)]


def family(pid):
    """Every pid in the tree under this one, plus this one.

    A venv's pythonw.exe is a shim: it re-launches the real interpreter as a
    child, and the panel then lives in that child, not in the pid Popen handed
    back. Watching only the launched pid finds no window and reports a working
    panel as dead.
    """
    kernel32 = ctypes.windll.kernel32
    kids = {}
    snap = kernel32.CreateToolhelp32Snapshot(0x00000002, 0)
    if snap == -1:
        return {pid}
    try:
        e = PROCESSENTRY32()
        e.dwSize = ctypes.sizeof(PROCESSENTRY32)
        ok = kernel32.Process32First(snap, ctypes.byref(e))
        while ok:
            kids.setdefault(e.th32ParentProcessID, []).append(e.th32ProcessID)
            ok = kernel32.Process32Next(snap, ctypes.byref(e))
    finally:
        kernel32.CloseHandle(snap)
    out = set()
    stack = [pid]
    while stack:
        cur = stack.pop()
        if cur in out:
            continue
        out.add(cur)
        stack.extend(kids.get(cur, []))
    return out


def windows_of(pids):
    user32 = ctypes.windll.user32
    found = []
    pids = set(pids)

    CB = ctypes.WINFUNCTYPE(ctypes.c_bool, ctypes.wintypes.HWND,
                            ctypes.wintypes.LPARAM)

    def cb(hwnd, _):
        owner = ctypes.wintypes.DWORD()
        user32.GetWindowThreadProcessId(hwnd, ctypes.byref(owner))
        if owner.value in pids:
            buf = ctypes.create_unicode_buffer(256)
            user32.GetClassNameW(hwnd, buf, 256)
            rect = ctypes.wintypes.RECT()
            user32.GetWindowRect(hwnd, ctypes.byref(rect))
            found.append((hwnd, buf.value, rect.left, rect.top,
                          rect.right - rect.left, rect.bottom - rect.top,
                          bool(user32.IsWindowVisible(hwnd)), owner.value))
        return True

    user32.EnumWindows(CB(cb), 0)
    return found


def launch(panel):
    head("七　開面板")
    pyw = pythonw_for(sys.executable)
    if not pyw:
        say("注意　旁邊沒有 pythonw.exe,唯有用 " + sys.executable +
            " ,面板後面會多一個黑色 console 視窗。")
        pyw = sys.executable
    say("用　" + pyw)
    folder = os.path.dirname(panel)
    log = os.path.join(folder, "toolbox_boot.log")
    before = os.path.getsize(log) if os.path.exists(log) else 0

    flags = 0x08000000 | 0x00000008
    proc = subprocess.Popen([pyw, panel], cwd=folder, creationflags=flags,
                            close_fds=True)
    say("開了　pid " + str(proc.pid))

    hwnds = []
    tree = {proc.pid}
    deadline = time.time() + 25
    while time.time() < deadline:
        tree = family(proc.pid)
        hwnds = windows_of(tree)
        if hwnds:
            break
        if proc.poll() is not None and len(tree) <= 1:
            break
        time.sleep(0.4)

    head("八　證明它真的畫了出來")
    if hwnds:
        for h in hwnds:
            say("視窗　hwnd=" + str(h[0]) + " class=" + h[1] +
                " 位置=" + str(h[2]) + "," + str(h[3]) +
                " 大細=" + str(h[4]) + "x" + str(h[5]) +
                " 畫住=" + str(h[6]) + " pid=" + str(h[7]))
        say("")
        say("面板真是開了,上面那個 hwnd 是它的窗。")
        if not any(h[6] for h in hwnds):
            say("(畫住那一欄是 False。在一個沒有互動桌面的 session 裡面,"
                "連一個最普通的 tkinter 窗都會回 False,所以這一欄靠不住;"
                "數得到 hwnd 同一個 236 闊的位置才是證據。)")
        if len(tree) > 1:
            say("(開出來的 pid " + str(proc.pid) +
                " 只是一層 shim,真身在 " + str(sorted(tree)) + " 裡面。)")
        say("")
        say("重要　它是貼在螢幕最左邊那一條,而且它故意壓在所有視窗底下。")
        say("要它上來,把滑鼠移去螢幕最左邊那三格像素,它就會自己升上來。")
        say("移開就跌返落去。看不見它不等於它沒有開。")
        tail(log, before)
        return 0

    still = [q for q in family(proc.pid) if q != proc.pid]
    if proc.poll() is None or still:
        say("那個 process 仍然在跑,但二十五秒內數不到一個屬於它的視窗。")
        tail(log, before)
        say("如果 toolbox_boot.log 寫住 panel up,那就是它畫了而這裡數不到,"
            "去螢幕最左邊掃一下滑鼠。")
        return 0

    code = proc.returncode
    say("那個 process 已經死了,exit code " + str(code) + "。")
    grew = tail(log, before)

    if grew and "another panel already has the lock" in grew:
        say("")
        say("這不是壞。它自己講了:已經有一塊面板在跑,所以這一個故意退出。")
        say("同一時間只可以有一塊。要看見在跑那一塊,滑鼠掃去螢幕最左邊。")
        return 0

    if not grew:
        say("")
        say("連 toolbox_boot.log 都沒有寫過一行 —— 即是它在 import 那一步就死了,"
            "而 pythonw 沒有 console,那個錯誤本來會消失得無影無蹤。")
        say("現在用有 console 那個再跑一次,把真正的錯誤挖出來:")
        r = subprocess.run([sys.executable, panel], cwd=folder,
                           capture_output=True, text=True, timeout=60,
                           creationflags=0x08000000)
        err = (r.stderr or "").strip()
        if err:
            for line in err.splitlines()[-8:]:
                say("　　" + line)
        else:
            say("　　(它第二次沒有出錯,可能是偶發)")
    say("")
    say("面板開不到。上面幾行就是原因,整份也寫在 " + REPORT)
    return 3


def tail(log, before):
    say("")
    say("toolbox_boot.log　" + log)
    if not os.path.exists(log):
        say("　　沒有這個檔")
        return ""
    with open(log, "r", encoding="utf-8", errors="replace") as fh:
        fh.seek(before)
        grew = fh.read().strip()
    if not grew:
        say("　　這次啟動一行都沒有加")
        return ""
    for line in grew.splitlines():
        say("　　" + line)
    return grew


def main():
    if os.name != "nt":
        print("This tool is Windows only.")
        return 2
    for stream in (sys.stdout, sys.stderr):
        try:
            stream.reconfigure(encoding="utf-8", errors="replace")
        except Exception:
            pass
    start_report()
    check_folder()
    check_python()
    check_psutil()
    panel = find_panel()
    compile_check(panel)
    check_rows(panel)
    rc = launch(panel)
    head("完")
    say("整份紀錄在　" + REPORT)
    return rc


if __name__ == "__main__":
    sys.exit(main())
