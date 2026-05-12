#!/usr/bin/env bash
# Fresh-machine bootstrap for the my-claude-skills repo.
#
# What it does (all idempotent — safe to re-run to update):
#   1. installs the Ledger Donjon side-channel/fault toolchain (rainbow + lascar)
#      into a dedicated venv under ~/.local/share/donjon-sca/
#   2. puts the `donjon-sca` CLI on PATH (~/.local/bin/donjon-sca, + a PATH line in your shell rc if needed)
#   3. symlinks every skill in this repo into ~/.claude/skills/ so Claude Code picks them up
#
# Usage on a brand-new computer:
#   git clone https://github.com/Nicola-Ceornea/my-claude-skills.git ~/repos/my-claude-skills
#   ~/repos/my-claude-skills/setup.sh
#
# Prerequisites: git, python3, python3-venv  (on Debian/Ubuntu: sudo apt install -y git python3 python3-venv).
# Note: lascar pulls a heavy dependency set (numpy/scipy/scikit-learn/numba/h5py/PyQt5 and tensorflow/keras
# for its ML engines) — first install can take several minutes and a few hundred MB.

set -euo pipefail
HERE="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}" 2>/dev/null || echo "${BASH_SOURCE[0]}")")" && pwd)"

printf '\033[1;36m==>\033[0m my-claude-skills bootstrap (%s)\n' "$HERE"
[ -x "$HERE/bin/donjon-sca" ] || chmod +x "$HERE/bin/donjon-sca" 2>/dev/null || true
exec "$HERE/bin/donjon-sca" setup
