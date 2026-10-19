#!/usr/bin/env python3
"""
Backend helper for gothe92.omatap.
- `targets`: returns focused monitor geometry + smart clickable targets from Hyprland windows,
  and ensures the persistent background uinput pointer daemon is running for instant 0ms clicks.
- `act <local_x> <local_y> <action>`: moves cursor to target via Hyprland 0.56 Lua dispatcher
  (`hl.dsp.cursor.move`) and emits hardware mouse clicks / scroll via persistent `/dev/uinput`
  daemon (or direct fast UInput fallback).
"""

import fcntl
import json
import os
import socket
import subprocess
import sys
import time

SOCK_PATH = f"/run/user/{os.getuid()}/omatap-uinput.sock"
LOCK_PATH = SOCK_PATH + ".lock"
LOG_PATH = os.path.join(
    os.environ.get("XDG_STATE_HOME") or os.path.expanduser("~/.local/state"),
    "omatap",
    "daemon.log",
)
# The daemon exits after this many idle seconds; the next overlay open restarts it
DAEMON_IDLE_TIMEOUT = 600


def log(msg):
    print(f"omatap: {msg}", file=sys.stderr, flush=True)


def run_json(cmd):
    try:
        out = subprocess.check_output(cmd, stderr=subprocess.DEVNULL, text=True)
        return json.loads(out)
    except Exception:
        return None


def get_focused_monitor(name=None):
    monitors = run_json(["hyprctl", "monitors", "-j"]) or []
    for m in monitors:
        if (m.get("name") == name) if name else m.get("focused"):
            return m
    return monitors[0] if monitors else {
        "name": "default",
        "x": 0,
        "y": 0,
        "width": 1920,
        "height": 1080,
        "scale": 1.0,
        "activeWorkspace": {"id": 1},
    }


def ensure_daemon_running():
    """Ensure the persistent UInput pointer daemon is running so clicks have zero udev delay."""
    if os.path.exists(SOCK_PATH):
        try:
            with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as s:
                s.settimeout(0.05)
                s.connect(SOCK_PATH)
                s.sendall(b"ping\n")
                if s.recv(16).startswith(b"ok"):
                    return True
        except Exception:
            # Stale socket; the daemon that wins the lock removes and rebinds it
            pass

    try:
        os.makedirs(os.path.dirname(LOG_PATH), exist_ok=True)
        with open(LOG_PATH, "a") as log_file:
            subprocess.Popen(
                [sys.executable, os.path.abspath(__file__), "daemon"],
                stdout=subprocess.DEVNULL,
                stderr=log_file,
                start_new_session=True,
            )
    except Exception as exc:
        log(f"failed to start uinput daemon: {exc}")
    return False


def open_uinput():
    from evdev import UInput, ecodes as e

    # Bypass python-evdev's 2-second _find_device sleep on non-root /dev/input/event* nodes
    UInput._find_device = lambda self, fd: None
    capabilities = {
        e.EV_KEY: [e.BTN_LEFT, e.BTN_RIGHT, e.BTN_MIDDLE],
        e.EV_REL: [e.REL_X, e.REL_Y, e.REL_WHEEL],
    }
    return UInput(capabilities, name="omatap-pointer")


def emit(ui, action):
    from evdev import ecodes as e

    def click(btn):
        ui.write(e.EV_KEY, btn, 1)
        ui.syn()
        time.sleep(0.016)
        ui.write(e.EV_KEY, btn, 0)
        ui.syn()

    buttons = {"left": e.BTN_LEFT, "right": e.BTN_RIGHT, "middle": e.BTN_MIDDLE}
    wheel = {"scroll-up": 3, "scroll-down": -3}

    # Nudge 0 on EV_REL so wlroots/Aquamarine refreshes pointer focus if needed
    ui.write(e.EV_REL, e.REL_X, 0)
    ui.syn()
    if action in buttons:
        click(buttons[action])
    elif action == "double":
        click(e.BTN_LEFT)
        time.sleep(0.04)
        click(e.BTN_LEFT)
    elif action in wheel:
        ui.write(e.EV_REL, e.REL_WHEEL, wheel[action])
        ui.syn()


def cmd_daemon():
    """Persistent UInput virtual mouse daemon so Hyprland keeps the pointer attached."""
    # Only one daemon may own the socket; a second one started in a race just exits
    lock = open(LOCK_PATH, "w")
    try:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except OSError:
        return

    try:
        os.unlink(SOCK_PATH)
    except OSError:
        pass

    with open_uinput() as ui:
        srv = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        srv.bind(SOCK_PATH)
        os.chmod(SOCK_PATH, 0o600)
        srv.listen(8)
        srv.settimeout(DAEMON_IDLE_TIMEOUT)

        while True:
            try:
                conn, _ = srv.accept()
            except socket.timeout:
                break
            with conn:
                conn.settimeout(1.0)
                try:
                    data = conn.recv(128).decode("utf-8", errors="ignore").strip()
                    if data != "ping":
                        emit(ui, data or "left")
                    conn.sendall(b"ok\n")
                except OSError:
                    pass

        srv.close()
        try:
            os.unlink(SOCK_PATH)
        except OSError:
            pass


def cmd_targets():
    ensure_daemon_running()
    mon = get_focused_monitor()
    mon_x = float(mon.get("x", 0))
    mon_y = float(mon.get("y", 0))
    scale = float(mon.get("scale", 1.0)) or 1.0
    lw = int(round(float(mon.get("width", 1920)) / scale))
    lh = int(round(float(mon.get("height", 1080)) / scale))
    ws_id = (mon.get("activeWorkspace") or {}).get("id", 1)

    clients = run_json(["hyprctl", "clients", "-j"]) or []
    windows = []

    for c in clients:
        if not c.get("mapped", False) or c.get("hidden", False):
            continue
        c_ws = (c.get("workspace") or {}).get("id")
        if c_ws != ws_id:
            continue
        at = c.get("at") or [0, 0]
        size = c.get("size") or [0, 0]
        wx = float(at[0]) - mon_x
        wy = float(at[1]) - mon_y
        ww = float(size[0])
        wh = float(size[1])
        if ww < 40 or wh < 40:
            continue

        cls = str(c.get("class") or c.get("initialClass") or "Window")
        cx = int(max(12, min(lw - 12, round(wx + ww * 0.5))))
        cy = int(max(12, min(lh - 12, round(wy + wh * 0.5))))
        ty = int(max(12, min(lh - 12, round(wy + min(42.0, wh * 0.12)))))
        windows.append((cls, cx, cy, ty))

    # Centers first so every window (up to 9) gets a hint; headers fill leftover slots
    candidates = [(f"{cls}: Center", cx, cy, "window-center") for cls, cx, cy, _ in windows]
    candidates += [(f"{cls}: Header", cx, ty, "window-header") for cls, cx, _, ty in windows]

    smart_targets = [
        {"hint": str(i), "label": label, "x": x, "y": y, "kind": kind}
        for i, (label, x, y, kind) in enumerate(candidates[:9], start=1)
    ]

    print(json.dumps({
        "monitor": {
            "name": mon.get("name", ""),
            "x": mon_x,
            "y": mon_y,
            "logicalWidth": lw,
            "logicalHeight": lh,
            "scale": scale,
        },
        "smartTargets": smart_targets,
    }))


def send_to_daemon(action):
    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as s:
        s.settimeout(0.25)
        s.connect(SOCK_PATH)
        s.sendall(f"{action}\n".encode("utf-8"))
        return s.recv(16).startswith(b"ok")


def emit_via_daemon(action):
    if ensure_daemon_running():
        try:
            return send_to_daemon(action)
        except OSError:
            pass

    # Freshly started daemon: wait up to ~1s for it to create its uinput device and socket
    deadline = time.monotonic() + 1.0
    while time.monotonic() < deadline:
        time.sleep(0.03)
        try:
            return send_to_daemon(action)
        except OSError:
            continue
    log("uinput daemon unreachable, falling back to direct uinput")
    return False


def emit_uinput_direct(action):
    try:
        with open_uinput() as ui:
            # Wait ~70ms so udev + libinput in Hyprland attaches the virtual device
            time.sleep(0.07)
            emit(ui, action)
            time.sleep(0.02)
        return True
    except Exception as exc:
        log(f"direct uinput click failed (is python-evdev installed and /dev/uinput writable?): {exc}")
        return False


def move_hyprland_cursor(gx: int, gy: int):
    # Hyprland 0.56+ uses Lua dispatcher syntax: hl.dsp.cursor.move({ x = ..., y = ... })
    res = subprocess.run(
        ["hyprctl", "dispatch", f"hl.dsp.cursor.move({{ x = {gx}, y = {gy} }})"],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    if res.returncode != 0 or "error:" in (res.stdout + res.stderr):
        # Fallback for older Hyprland versions
        subprocess.run(
            ["hyprctl", "dispatch", "movecursor", f"{gx} {gy}"],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )


def cmd_act(local_x_str, local_y_str, action="left", monitor_name=None):
    mon = get_focused_monitor(monitor_name)
    mon_x = float(mon.get("x", 0))
    mon_y = float(mon.get("y", 0))

    gx = int(round(mon_x + float(local_x_str)))
    gy = int(round(mon_y + float(local_y_str)))

    # Let the overlay close first so the click lands on the underlying window
    time.sleep(0.035)
    move_hyprland_cursor(gx, gy)

    if action == "move":
        return

    time.sleep(0.015)
    if not emit_via_daemon(action):
        emit_uinput_direct(action)


if __name__ == "__main__":
    verb = sys.argv[1] if len(sys.argv) > 1 else "targets"
    if verb == "targets":
        cmd_targets()
    elif verb == "daemon":
        cmd_daemon()
    elif verb == "act" and len(sys.argv) >= 4:
        act_type = sys.argv[4] if len(sys.argv) >= 5 else "left"
        monitor_name = sys.argv[5] if len(sys.argv) >= 6 and sys.argv[5] else None
        cmd_act(sys.argv[2], sys.argv[3], act_type, monitor_name)
    else:
        print("Usage: omatap-helper.py {targets | daemon | act <x> <y> [left|right|middle|double|move|scroll-up|scroll-down] [monitor]}", file=sys.stderr)
        sys.exit(2)
