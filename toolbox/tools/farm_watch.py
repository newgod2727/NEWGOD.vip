"""Outside-the-client watchdog for the three bots. Runs on its own, no Claude.

Why this cannot live inside the game
------------------------------------
On 2026-08-03 at 23:43 the whole party was teleported into a match server that
never answered. A teleport tears the Luau VM down before the new place loads, so
when the join failed there was no script left alive to notice. The three status
files stopped mid-sentence and the bots sat there until the machine was rebooted
twelve minutes later. Nothing written in Lua could ever have caught that, because
by the time it happened Lua was gone. The rescue has to come from the laptop.

How a stuck client is recognised
--------------------------------
FARM_SKYWARS_ABCD.lua rewrites RobloxComm/status_<account>.txt on a loop. While the
script is alive that file's timestamp moves every few seconds. A client process
that is still running while its status file has stopped moving is a client whose
script is dead - which is exactly the 23:43 signature and also covers a hung
renderer, a failed injection, and an error dialog nobody clicked.

Mapping a process to an account
-------------------------------
Roblox holds its own log file open, so the open handles of a pid lead to
<version>_Player_XXXXX_last.log, and that log's GameJoinLoadTime line carries
userid:<n>. That is the only reliable pid to account link on this machine; the
window title is not unique and the command line does not carry it.

Killing, and why that is safe now
---------------------------------
Real's Accounts > Options has "Recover crashed instances - bring a Roblox window
back after a crash, forced update, or external kill". With that on, killing a
client is not destructive: Real signs the same account back in. That toggle is
what makes the memory branch below usable, and it is OFF in the screenshot from
2026-08-04, so set REAL_RECOVERS once you have turned it on.

The two branches are deliberately not equally brave:

  stuck   - always killed. A client whose script is dead earns nothing. If Real
            does not bring it back you are exactly where you already were, so
            there is no downside to trying.
  memory  - killed only when REAL_RECOVERS is true, because that client is still
            farming and losing it for nothing would be a real cost. Until then it
            is trimmed and logged loudly.
"""

import ctypes
import datetime
import glob
import os
import re
import time
import traceback

import psutil

# Set to True only after "Recover crashed instances" is ON in Real.
REAL_RECOVERS = True

LOGDIR = r"C:\farm\logs\watch"
SAMPLES = os.path.join(LOGDIR, "farm_watch.csv")
EVENTS = os.path.join(LOGDIR, "farm_events.log")
COMM = os.path.expandvars(r"%LOCALAPPDATA%\Real\workspace\RobloxComm")
RBX_LOGS = os.path.expandvars(r"%LOCALAPPDATA%\Roblox\logs")

CLIENT = "robloxplayerbeta.exe"
EVERY = 15

# A client on the home page already holds 1.1 to 1.25 GB and Roblox's own
# AppMemUsageStatus reads about 3.78 GB for one that is mid match and perfectly
# healthy, so 2.4 GB is below normal, not above it. These come from the crash:
# Windows raised low-virtual-memory with two clients at 14.5 and 13.9 GB and
# killed both. 15.76 GB of RAM split three ways is about 4.5 GB each.
TRIM_GB = 5.0
KILL_GB = 7.5
# Warning threshold only. This used to be a kill trigger and that was a mistake:
# free RAM is a property of the machine, not of any one client, so it named no
# culprit - and with three clients at ~3.7 GB each on a 15.76 GB machine it is
# true most of the time, which would have meant killing the largest client over
# and over for the crime of being largest.
FLOOR_GB = 1.2
FLOOR_WARN_EVERY = 300

STALE_S = 100          # status file older than this while the process lives
GRACE_S = 180          # ignore a client younger than this, it is still loading
KILL_COOLDOWN = 120    # let Real finish recovering before judging anyone again
TRIM_COOLDOWN = 180

BOTS = {
    100000000001: "bot_account_one",
    100000000002: "bot_account_two",
    100000000003: "bot_account_three",
}

USERID = re.compile(r"userid:(\d+)")
PROC_ALL = 0x1F0FFF


def log(line):
    os.makedirs(LOGDIR, exist_ok=True)
    with open(EVENTS, "a", encoding="utf-8") as fh:
        fh.write(f"{datetime.datetime.now():%Y-%m-%d %H:%M:%S}  {line}\n")


def trim(pid):
    h = ctypes.windll.kernel32.OpenProcess(PROC_ALL, False, pid)
    if not h:
        return False
    try:
        return bool(ctypes.windll.psapi.EmptyWorkingSet(h))
    finally:
        ctypes.windll.kernel32.CloseHandle(h)


def account_of(proc, cache):
    """pid -> account name, via the client log the process is holding open."""
    if proc.pid in cache:
        return cache[proc.pid]
    name = None
    try:
        for f in proc.open_files():
            if f.path.endswith("_last.log") and "Roblox" in f.path:
                try:
                    with open(f.path, encoding="utf-8", errors="ignore") as src:
                        for row in src:
                            m = USERID.search(row)
                            if m:
                                name = BOTS.get(int(m.group(1)))
                                break
                except Exception:
                    pass
                break
    except Exception:
        # open_files needs the same integrity level; a client started with the
        # ADMIN button is simply not readable from here and stays unmapped.
        pass
    if name:
        cache[proc.pid] = name
    return name


def status_age(account):
    """Seconds since the farm last wrote this account's status file."""
    if not account:
        return None
    path = os.path.join(COMM, f"status_{account}.txt")
    if not os.path.exists(path):
        return None
    return time.time() - os.path.getmtime(path)


def farm_switched_off():
    """The farm's own on/off switch, RobloxComm/ew_panels.txt - "1" on, "0" off.

    This guard is the whole reason the file is read here. Pressing OFF on the panel
    stops the farm, which stops the status writes, which to a watchdog looking only
    at timestamps is indistinguishable from a client whose script has died. Without
    this check, switching the farm off by hand would have made the watchdog kill all
    three clients about a hundred seconds later - turning a deliberate action into
    an incident.

    Unreadable or missing is treated as OFF. Standing down when unsure is the safe
    direction for something that kills processes.

    Read as utf-8-sig, not utf-8. The farm writes this file from Lua with no BOM,
    but anything on Windows that rewrites it by hand is liable to add one, and a
    leading BOM survives .strip() - so a plain utf-8 read sees a different string,
    compares unequal, and silently disarms the watchdog forever. Found exactly that
    way while testing this guard.
    """
    try:
        with open(os.path.join(COMM, "ew_panels.txt"), encoding="utf-8-sig") as fh:
            return fh.read().strip() != "1"
    except Exception:
        return True


def main():
    os.makedirs(LOGDIR, exist_ok=True)
    if not os.path.exists(SAMPLES):
        with open(SAMPLES, "w", encoding="utf-8") as fh:
            fh.write("time,pid,account,ws_mb,uptime_min,status_age_s,"
                     "sys_avail_mb,action\n")

    log(f"watch start  trim>{TRIM_GB}GB  kill>{KILL_GB}GB  stale>{STALE_S}s  "
        f"REAL_RECOVERS={REAL_RECOVERS}")
    if not REAL_RECOVERS:
        log("NOTE: Real 'Recover crashed instances' is recorded as OFF. Stuck "
            "clients will still be killed, bloated ones will only be trimmed. "
            "Turn that toggle on in Real, then set REAL_RECOVERS = True here.")

    cache, trimmed, seen = {}, {}, {}
    last_kill = 0
    last_off = None
    last_floor = 0

    while True:
        try:
            now = time.time()
            stamp = f"{datetime.datetime.now():%Y-%m-%d %H:%M:%S}"
            avail_mb = psutil.virtual_memory().available / 2 ** 20

            clients = []
            for p in psutil.process_iter(["name", "pid", "create_time"]):
                try:
                    if (p.info["name"] or "").lower() != CLIENT:
                        continue
                    clients.append((p, p.memory_info().rss,
                                    (now - p.info["create_time"]) / 60))
                except Exception:
                    continue

            live = {p.pid for p, _, _ in clients}
            for pid in [x for x in seen if x not in live]:
                log(f"pid={pid} ({seen[pid]}) gone")
                seen.pop(pid, None)
                cache.pop(pid, None)
                trimmed.pop(pid, None)

            clients.sort(key=lambda c: c[1], reverse=True)
            # Never judge anyone while the farm is switched off - see farm_switched_off.
            off = farm_switched_off()
            if off != last_off:
                log("farm switch is OFF - watching only, nothing will be killed" if off
                    else "farm switch is ON - watchdog armed")
                last_off = off
            calm = (now - last_kill > KILL_COOLDOWN) and not off

            # Machine-wide starvation no longer kills anything, but it is still
            # the thing that ended the farm on 2026-08-03, so it must be visible.
            if avail_mb / 1024 < FLOOR_GB and now - last_floor > FLOOR_WARN_EVERY:
                last_floor = now
                log(f"LOW MEMORY: {avail_mb / 1024:.2f} GB free across the whole "
                    f"machine, {len(clients)} client(s) up, biggest "
                    f"{(clients[0][1] / 2 ** 30) if clients else 0:.2f} GB. Not "
                    f"killing anything on this signal alone - it names no culprit.")

            for p, rss, up in clients:
                gb = rss / 2 ** 30
                who = account_of(p, cache) or "?"
                seen[p.pid] = who
                age = status_age(who)
                action = ""

                # Still booting: no status file yet is normal, not a fault.
                young = up * 60 < GRACE_S

                if age is not None and age > STALE_S and not young and calm:
                    log(f"STUCK pid={p.pid} {who} - status file has not moved for "
                        f"{age:.0f}s while the client is still running. Script is "
                        f"dead, this is the 23:43 signature. Killing so Real can "
                        f"bring the account back.")
                    try:
                        p.kill()
                        action, last_kill = "killed-stuck", now
                        # At most ONE kill per pass. Without this the branch was
                        # lethal: on 2026-08-03 all three status files stopped
                        # within three seconds of each other, so a single pass
                        # would have found all three stale and killed the entire
                        # farm at once. Only a kill that actually happened may
                        # clear calm.
                        calm = False
                    except Exception as exc:
                        log(f"kill pid={p.pid} FAILED: {exc}")
                        action = "kill-failed"

                elif gb >= KILL_GB and calm and not young:
                    # Deliberately NOT triggered by machine-wide free RAM any more.
                    # That condition names no particular client, and on 15.76 GB
                    # with three clients at ~3.7 GB each it is true most of the
                    # time - it would have killed the largest client over and over
                    # for the crime of being largest. Only the per-client figure
                    # identifies an abnormal client. The young guard is here too:
                    # it was on the stuck branch only, so a client three minutes
                    # into loading could still be killed on size alone.
                    if REAL_RECOVERS:
                        log(f"BLOAT pid={p.pid} {who} after {up:.0f} min at "
                            f"{gb:.2f} GB. Killing the worst one so Windows does "
                            f"not pick two.")
                        try:
                            p.kill()
                            action, last_kill = "killed-bloat", now
                            calm = False
                        except Exception as exc:
                            log(f"kill pid={p.pid} FAILED: {exc}")
                            action = "kill-failed"
                    elif now - trimmed.get(p.pid, 0) > TRIM_COOLDOWN:
                        trim(p.pid)
                        trimmed[p.pid] = now
                        log(f"BLOAT pid={p.pid} {who} at {gb:.2f} GB. Trimmed only, "
                            f"because REAL_RECOVERS is False. This client will "
                            f"keep growing until it or Windows gives out.")
                        action = "trim-only"

                elif gb >= TRIM_GB and now - trimmed.get(p.pid, 0) > TRIM_COOLDOWN:
                    ok = trim(p.pid)
                    trimmed[p.pid] = now
                    log(f"trim pid={p.pid} {who} at {gb:.2f} GB after {up:.0f} min "
                        f"-> {'ok' if ok else 'refused'}")
                    action = "trim" if ok else "trim-failed"

                with open(SAMPLES, "a", encoding="utf-8") as fh:
                    fh.write(f"{stamp},{p.pid},{who},{rss / 2 ** 20:.0f},{up:.1f},"
                             f"{'' if age is None else f'{age:.0f}'},"
                             f"{avail_mb:.0f},{action}\n")

        except Exception as exc:
            log(f"watch error: {exc}")

        time.sleep(EVERY)


_LOCK = None


def already_running():
    """Same Local\\ mutex trick as the panel. This one is started both by a logon
    scheduled task and by a row on the toolbox, and two watchdogs bidding to kill
    the same client would be a genuinely bad time."""
    global _LOCK
    try:
        _LOCK = ctypes.windll.kernel32.CreateMutexW(None, False, "Local\\FarmWatchSingle")
        return ctypes.windll.kernel32.GetLastError() == 183
    except Exception:
        return False


if __name__ == "__main__":
    if already_running():
        # Normal and expected: the scheduled task repeats every five minutes, so
        # most launches find the real one already up and stand down silently.
        raise SystemExit
    try:
        main()
    except KeyboardInterrupt:
        log("watch stopped by hand")
    except BaseException as exc:
        # A watchdog that dies quietly is worse than no watchdog, because the
        # panel still says it is running. One of these vanished on 2026-08-04
        # between 03:08 and 03:15 leaving nothing in any log, which is exactly
        # the hole this closes. SystemExit and KeyboardInterrupt are BaseException
        # too, hence the broad catch and the re-raise.
        log(f"watch DIED: {type(exc).__name__}: {exc}")
        log("".join(traceback.format_exception(exc))[:1500])
        raise
