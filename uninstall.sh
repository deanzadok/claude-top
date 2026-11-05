#!/usr/bin/env bash
# Remove claude-top, its status line script and saved data, and the status line entry
# in Claude Code's settings.json (only if it points at this tool; settings are backed up first).
# Uses the same BIN_DIR / CLAUDE_CONFIG_DIR / PYTHON overrides as install.sh.
set -euo pipefail

CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
BIN_DIR="${BIN_DIR:-$HOME/.local/bin}"
APP_DIR="$CLAUDE_DIR/usage-monitor"
PYTHON="${PYTHON:-$(command -v python3 || echo /usr/bin/python3)}"

if [[ -f "$CLAUDE_DIR/settings.json" ]]; then
  "$PYTHON" -I - "$CLAUDE_DIR/settings.json" <<'EOF'
import json, os, shutil, sys, time
path = sys.argv[1]
with open(path) as f:
    settings = json.load(f)
cmd = str((settings.get("statusLine") or {}).get("command", ""))
if "usage-monitor/statusline.py" not in cmd:
    print("Settings:    no claude-top status line found; left unchanged")
    sys.exit(0)
backup, n = f"{path}.bak-{time.strftime('%Y%m%d-%H%M%S')}", 1
while os.path.exists(backup):
    backup, n = f"{path}.bak-{time.strftime('%Y%m%d-%H%M%S')}-{n}", n + 1
shutil.copy2(path, backup)
del settings["statusLine"]
tmp = path + ".tmp"
with open(tmp, "w") as f:
    json.dump(settings, f, indent=2)
    f.write("\n")
os.replace(tmp, path)
print(f"Settings:    status line removed (backup: {backup})")
EOF
fi

rm -f "$BIN_DIR/claude-top" && echo "Removed:     $BIN_DIR/claude-top"
rm -rf "$APP_DIR" && echo "Removed:     $APP_DIR"
echo "Done."
