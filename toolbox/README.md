## PyToolbox

A sidebar panel for Windows. It pins itself to the left of the desktop and does
no work of its own. Every row on page 1 starts a separate tool in its own
process, and the pages behind the arrows hold the buttons I press every day.

## Two builds: admin and no admin

There are two zips and they hold the same tools.

`PyToolbox.zip` is the normal one. Six of the tools ask Windows for admin the
moment they start, which is right on a machine you own.

`PyToolbox-noadmin.zip` is for a machine where admin is switched off, like a
school PC. Nothing in it ever raises a UAC prompt. Every file keeps its normal
name, so every row on page 1 still works — the file behind the row is simply the
build that does not ask.

On the old zip, a machine that refuses admin killed four of the clickers in
0.03 seconds with no window and no message. That is what this second zip is for.

What you actually lose without admin is small, and it was measured rather than
guessed: MOUSE MIRROR, the one-time admin-Roblox setup, and launching Roblox as
admin. Everything else — the clicking, the typing, the hotkeys, the screen
dimming, dark mode, END TASK, HIGH priority, and the panel itself — works
exactly the same. The one behaviour that changes with no button attached to it
is that synthetic clicks cannot reach a window that is itself running as admin.
That is a Windows rule called UIPI, and it is the reason those tools asked for
elevation in the first place.

Full breakdown is in `NOADMIN.md` beside this file.

## What you need

Python 3.12 and one package, `psutil`.

```
pip install psutil
```

Nothing else. The two GOLDMACRO files also want `pynput`, but they install it
themselves the first time you run them, and if that install fails they put a
message box on screen telling you the exact pip command. The small clicker and
typer tools want `pynput`, `pyautogui` or `keyboard` depending on which one you
open, and unlike GOLDMACRO they do not install anything for you. Install all
four in one go if you want every row to work:

```
pip install psutil pynput pyautogui keyboard
```

## How to start it

```
pythonw.exe toolbox.py
```

Use `pythonw.exe`, not `python.exe`. `python.exe` leaves a black console window
sitting behind the panel.

## If psutil is missing, nothing happens at all

This is worth knowing before you waste time on it. `import psutil` is the last
import at the top of the file, and the logging is set up after it. So when
`psutil` is not installed the script dies on that line before it can write
anything, and because `pythonw.exe` has no console there is no error, no window
and no log file. It looks exactly like a program that did nothing.

Measured: exit code 1, `ImportError`, zero output.

If a start seems to do nothing, do not run it by hand. Run `START.cmd`, which
sits next to `toolbox.py`. It finds a Python, installs `psutil` if it is
missing, refuses to run out of a zip preview folder, starts the panel, and then
proves the panel is up by finding its window. Every step it takes is written to
`FIRST-RUN.txt` in plain English, so a failure can never look like nothing
happening.

## "It did not open" usually means it opened, and you have to reach for it

The panel lives underneath every other window on purpose. It comes up when you
reach for it: move the pointer into the first three columns of pixels at the
LEFT EDGE of the screen and it rises to the top; move away and it drops back
down. Once it is up, anywhere over the panel keeps it up, so the pointer never
crosses a gap on the way to a button.

Nobody guesses that gesture. If the panel seems missing, sweep the pointer hard
into the left edge of the screen first.

Two things suppress the reveal on purpose. While a game is running the panel
stays pinned down, because a topmost window over a fullscreen game costs frames.
And the layer is only re-asserted on a slow clock, so a window opened right
after the panel was raised can land on top of it for a few seconds.

Before deciding it is broken:

- look for a `pythonw` process in Task Manager
- read `toolbox_boot.log`, which is written next to `toolbox.py` on every start
  and on any fatal error
- minimise everything and look at the left edge of the desktop

It also runs behind a single instance mutex, so a second copy exits quietly
instead of drawing a second panel. That is another reason a start can look like
it did nothing.

## The two builds

There are two builds and they are not the same file. The differences are
switched on a hostname check rather than kept in two forks.

| | `laptop/toolbox.py` | `desktop/toolbox.py` |
|---|---|---|
| Disk readout | C only | C and E |
| GAME MODE button | yes | no |
| RELAUNCH button | no | yes |
| NVIDIA button | no | yes |
| Priority sweep | follows GAME MODE, boosts and tames | always on, boosts only |
| Page 4 | repair Claude | NEWGOD DUNGEON |
| Page 6 | remote desktop screen control | window layout slots A to G |
| Page 8 | remote screen control for the other machine | MIRROR |
| GOLDMACRO row | v3 | v4 |

`toolbox.py` in the top folder is a copy of the laptop build, so the zip runs
straight out of the box. The two originals are kept in `desktop/` and `laptop/`
if you want the other one, in which case copy it over `toolbox.py`.

## Page 1 and where the files have to sit

Every row on page 1 launches a file that must sit in the same folder as
`toolbox.py`. The launcher does `os.path.join(HERE, filename)` and prints
找不到 on the panel if it is not there. This is why the tools are shipped
alongside it and must not be moved into a subfolder.

| Row | File | What it does |
|---|---|---|
| 左鍵連點 | `autoclicker21.py` | holds a left click at a chosen rate, Shift+E toggles |
| 右鍵連點 | `minecraft_rightclicker.py` | same for the right button, Shift+R toggles |
| 按住左鍵 | `minecraft_mining_holder.py` | keeps the left button pressed, Shift+T toggles |
| 右鍵加序列 | `minecraft_sequence_clicker.py` | right clicks while cycling number keys you pick |
| 定點連點 | `clcik with chosing.py` | drag red dots onto the screen, it clicks each in turn |
| 循環打字 | `pc_autotyper.py` | types a line, waits, spams Enter, repeats |
| 右鍵觸發打字 | `typewordinf.py` | types your text every time you release the right button |
| GOLDMACRO | `GOLDMACRO_v3.py` and `GOLDMACRO_v4.py` | full macro recorder and player |
| GOLD 自動點擊 | `GOLDAUTOCLICKER.exe` | see below, it is not loaded from this folder |
| BOT 看門狗 | `farm_watch.py` | watches Roblox clients and restarts stuck ones |
| 產生現況報告 | none | a window built into `toolbox.py`, there is no file for it |

The filename `clcik with chosing.py` really is spelled that way. The panel
launches that exact name, so it has to keep the typo. A copy called
`clcik-with-chosing.py` is also shipped because a web link with spaces in it is
a trap; the two files are byte for byte identical and you only need the spaced
one for the button to work.

Both GOLDMACRO files are shipped because the two builds disagree: the laptop
build's row points at v3 and the desktop build's row points at v4.

## GOLDAUTOCLICKER

That row is the one exception. It is an absolute path, not a sibling file:

```
%USERPROFILE%\Documents\GOLDAUTOCLICKER\GOLDAUTOCLICKER.exe
```

So unzipping does not put it where the button looks. Move the `GOLDAUTOCLICKER`
folder out of the zip into your `Documents` folder and the row starts working.
It is also available on its own from the tools folder on the site if you do not
want the whole zip.

It refuses to open a second copy of itself. Only one process on Windows can hold
a given global hotkey, and a second copy silently steals the key from the first.

## What to change before you run it

Both builds carry my machine layout. Everything below is a placeholder in this
copy and these are the only lines you need to touch:

- `IS_DESKTOP` at line 35, the hostname prefix that decides which build you are
  on. It reads `DESKTOP-PC` here.
- `SSH_HOST`, `SSH_KEY`, `DIM_PEER_HOST`, `DIM_PEER_KEY` and `MIRROR_PEER`, used
  only by the buttons that reach the other machine. They read `192.168.1.50` and
  `192.168.1.51` here.
- Any absolute path under `C:\Users\desktop\...`, which is where the other
  machine's files live for me.
- The tool paths in `TOOLS` and `OPEN_APPS`.

`farm_watch.py` has a `BOTS` dictionary near the top mapping Roblox user ids to
account names. The three entries in this copy are placeholders. Put your own in
or that tool cannot name the client it is looking at, and it will log every
process as `?`.

`farm_watch.py` also writes its logs to a fixed `C:\farm\logs\watch`. Change
`LOGDIR` if you do not want a folder at the root of C.

## Notes

Every failure is shown on the panel itself. Nothing here reports success into a
console you are not watching, because the panel is normally started without one.

Page 5 reads `accounts.txt` from next to the script, one `name | password` per
line. No file is shipped, and nothing is stored inside the scripts.
