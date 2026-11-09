#!/usr/bin/env bash
# Install claude-top and its Claude Code status line script for the current user.
#
#   ./install.sh                  install (or update) everything
#   ./install.sh --force          replace an existing, different status line
#   ./install.sh --no-statusline  install the files only; don't touch settings.json
#
# Environment overrides:
#   PYTHON=/path/to/python3   interpreter to use (default: /usr/bin/python3, else python3 on PATH)
#   BIN_DIR=~/bin             where the claude-top command goes (default: ~/.local/bin)
#   CLAUDE_CONFIG_DIR=...     Claude Code config folder (default: ~/.claude)
set -euo pipefail

FORCE=0
STATUSLINE=1
for arg in "$@"; do
  case "$arg" in
    --force) FORCE=1 ;;
    --no-statusline) STATUSLINE=0 ;;
    -h|--help) sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Unknown option: $arg (try --help)" >&2; exit 2 ;;
  esac
done

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
BIN_DIR="${BIN_DIR:-$HOME/.local/bin}"
APP_DIR="$CLAUDE_DIR/usage-monitor"

# --- pick a Python. A system Python is preferred so conda/venv changes can't break it.
if [[ -z "${PYTHON:-}" ]]; then
  if [[ -x /usr/bin/python3 ]]; then PYTHON=/usr/bin/python3
  else PYTHON="$(command -v python3 || true)"
  fi
fi
if [[ -z "$PYTHON" || ! -x "$PYTHON" ]]; then
  echo "Error: python3 not found. Install Python 3.8 or newer, or set PYTHON=/path/to/python3." >&2
  exit 1
fi
if ! "$PYTHON" -I -c 'import sys, curses; sys.exit(sys.version_info < (3, 8))' 2>/dev/null; then
  echo "Error: $PYTHON must be Python 3.8+ with the curses module." >&2
  echo "       (Native Windows Python has no curses; use WSL.)" >&2
  exit 1
fi
echo "Python:      $PYTHON ($("$PYTHON" -I -c 'import platform; print(platform.python_version())'))"

if ! command -v claude >/dev/null 2>&1; then
  echo "Note: the 'claude' command isn't on PATH. claude-top still installs, but it needs Claude Code to have data."
fi

# --- copy files
mkdir -p "$APP_DIR" "$BIN_DIR"
install -m 0755 "$REPO/src/statusline.py" "$APP_DIR/statusline.py"
# Point claude-top's first line at the chosen Python.
{ echo "#!$PYTHON -I"; tail -n +2 "$REPO/src/claude-top"; } > "$BIN_DIR/claude-top.tmp"
chmod 0755 "$BIN_DIR/claude-top.tmp"
mv "$BIN_DIR/claude-top.tmp" "$BIN_DIR/claude-top"
echo "Installed:   $BIN_DIR/claude-top"
echo "Installed:   $APP_DIR/statusline.py"

# --- register the status line in Claude Code's settings.json
if [[ "$STATUSLINE" == 1 ]]; then
  "$PYTHON" -I - "$CLAUDE_DIR/settings.json" "$PYTHON" "$APP_DIR/statusline.py" "$FORCE" <<'EOF'
import json, os, shlex, shutil, sys, time
path, python, script, force = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4] == "1"
settings = {}
if os.path.exists(path):
    try:
        with open(path) as f:
            settings = json.load(f)
    except ValueError as e:
        sys.exit(f"Error: {path} is not valid JSON ({e}). Fix it, or rerun with --no-statusline.")
wanted = {"type": "command", "command": f"{shlex.quote(python)} -I {shlex.quote(script)}", "padding": 0}
current = settings.get("statusLine")
if current == wanted:
    print(f"Settings:    status line already set in {path}")
    sys.exit(0)
if current and "usage-monitor/statusline.py" not in str(current.get("command", "")) and not force:
    print(f"Settings:    NOT changed. You already have a different status line in {path}:")
    print(f"             {current.get('command')}")
    print("             Rerun with --force to replace it. claude-top's plan-limit bars need this status line.")
    sys.exit(0)
if os.path.exists(path):
    backup, n = f"{path}.bak-{time.strftime('%Y%m%d-%H%M%S')}", 1
    while os.path.exists(backup):
        backup, n = f"{path}.bak-{time.strftime('%Y%m%d-%H%M%S')}-{n}", n + 1
    shutil.copy2(path, backup)
    print(f"Backup:      {backup}")
settings["statusLine"] = wanted
os.makedirs(os.path.dirname(path), exist_ok=True)
tmp = path + ".tmp"
with open(tmp, "w") as f:
    json.dump(settings, f, indent=2)
    f.write("\n")
os.replace(tmp, path)
print(f"Settings:    status line added to {path}")
EOF
fi

case ":$PATH:" in
  *":$BIN_DIR:"*) ;;
  *) echo
     echo "Note: $BIN_DIR is not on your PATH. Add this to ~/.bashrc or ~/.zshrc:"
     echo "      export PATH=\"$BIN_DIR:\$PATH\"" ;;
esac

echo
echo "Done. Run 'claude-top' in a separate terminal (q to quit)."
echo "Plan-limit bars fill in within a few seconds (checked every 60 s)."
