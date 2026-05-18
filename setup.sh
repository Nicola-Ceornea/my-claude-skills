#!/usr/bin/env bash
# Fresh-machine bootstrap for the my-claude-skills repo.
#
# What it does (all idempotent — safe to re-run to update):
#   1. installs the Ledger Donjon side-channel/fault toolchain (rainbow + lascar)
#      into a dedicated venv under ~/.local/share/donjon-sca/  (via `donjon-sca setup`)
#   2. installs eShard's scared framework into a separate venv under
#      ~/.local/share/scared-sca/  (via `scared-sca setup` — needs numpy>=2 + python>=3.11,
#      hence the second venv; the two stacks would fight over numpy otherwise)
#   3. puts the `donjon-sca` and `scared-sca` CLIs on PATH (~/.local/bin/)
#   4. symlinks every skill in this repo into ~/.claude/skills/ so Claude Code picks them up
#
# Usage on a brand-new computer:
#   git clone https://github.com/Nicola-Ceornea/my-claude-skills.git ~/repos/my-claude-skills
#   ~/repos/my-claude-skills/setup.sh
#
# Prerequisites: git, python3 (>=3.11 for scared), python3-venv
#   Debian/Ubuntu: sudo apt install -y git python3 python3-venv  (+ python3.11 if your distro default is older)
# Note: first install pulls several hundred MB — lascar (numpy/scipy/scikit-learn/numba/h5py)
# and scared (numpy>=2/scipy/numba/estraces).

set -euo pipefail
HERE="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}" 2>/dev/null || echo "${BASH_SOURCE[0]}")")" && pwd)"

printf '\033[1;36m==>\033[0m my-claude-skills bootstrap (%s)\n' "$HERE"

# Make sure both CLIs are executable in case git stripped the bit.
[ -x "$HERE/bin/donjon-sca" ] || chmod +x "$HERE/bin/donjon-sca" 2>/dev/null || true
[ -x "$HERE/bin/scared-sca" ] || chmod +x "$HERE/bin/scared-sca" 2>/dev/null || true

# Run each CLI's own setup. Each one is idempotent, manages its own venv,
# and symlinks its own skill(s) into ~/.claude/skills/.
"$HERE/bin/donjon-sca" setup
echo
"$HERE/bin/scared-sca" setup

printf '\033[1;36m==>\033[0m all skills installed. Claude Code picks them up on next session start.\n'
