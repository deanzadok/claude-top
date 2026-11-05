#!/usr/bin/env python3
"""Claude Code status line.

Claude Code runs this after each reply and passes session info as JSON on stdin.
It prints one short line for the bottom of the Claude Code screen, and saves the
data under ~/.claude/usage-monitor/state/ (or $CLAUDE_CONFIG_DIR/usage-monitor/state/) so `claude-top` can show it live.
"""
import json
import os
import re
import sys
import time

CLAUDE_DIR = os.environ.get("CLAUDE_CONFIG_DIR") or os.path.expanduser("~/.claude")
STATE = os.path.join(CLAUDE_DIR, "usage-monitor", "state")


def atomic_write(path, obj):
    tmp = f"{path}.{os.getpid()}.tmp"
    with open(tmp, "w") as f:
        json.dump(obj, f)
    os.replace(tmp, path)


def pct(window):
    if not isinstance(window, dict) or window.get("used_percentage") is None:
        return None
    if window.get("resets_at") and window["resets_at"] < time.time():
        return None  # window already reset; the next reply brings fresh numbers
    return window["used_percentage"]


def main():
    try:
        d = json.load(sys.stdin)
    except Exception:
        print("Claude")
        return

    now = time.time()
    sid = re.sub(r"[^A-Za-z0-9_-]", "", str(d.get("session_id") or ""))[:80]
    model = (d.get("model") or {}).get("display_name") or (d.get("model") or {}).get("id") or "?"
    ctx = d.get("context_window") or {}
    rl = d.get("rate_limits")

    try:
        os.makedirs(os.path.join(STATE, "sessions"), exist_ok=True)
        if sid:  # no session id (e.g. a manual test run): don't save a session entry
            atomic_write(os.path.join(STATE, "sessions", sid + ".json"), {
                "captured_at": now,
                "session_id": sid,
                "session_name": d.get("session_name"),
                "cwd": (d.get("workspace") or {}).get("current_dir") or d.get("cwd"),
                "model": model,
                "effort": (d.get("effort") or {}).get("level"),
                "context": ctx,
                "cost": d.get("cost"),
            })
        if rl:
            atomic_write(os.path.join(STATE, "rate_limits.json"),
                         {"captured_at": now, "session_id": sid, "rate_limits": rl})
        elif os.path.exists(os.path.join(STATE, "rate_limits.json")):
            with open(os.path.join(STATE, "rate_limits.json")) as f:
                rl = json.load(f).get("rate_limits")
    except Exception:
        pass  # never break the status line over a file problem

    parts = [model]
    rl = rl or {}
    five, week = pct(rl.get("five_hour")), pct(rl.get("seven_day"))
    if five is not None:
        reset = time.strftime("%H:%M", time.localtime(rl["five_hour"]["resets_at"]))
        parts.append(f"5h {five:.0f}% (resets {reset})")
    if week is not None:
        parts.append(f"week {week:.0f}%")
    if ctx.get("used_percentage") is not None:
        parts.append(f"ctx {ctx['used_percentage']:.0f}%")
    print(" │ ".join(parts))


if __name__ == "__main__":
    main()
