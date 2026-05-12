# my-claude-skills

[Claude Code](https://claude.com/claude-code) skills + the CLI tooling some of them drive.

Each skill is a directory with a `SKILL.md` (YAML frontmatter + a body that orients Claude on a tool or workflow). The `rainbow` and `lascar` skills drive a real toolchain (Ledger Donjon's side-channel / fault-injection stack); the `bin/donjon-sca` CLI installs and runs that toolchain — Claude calls it via the skill, and you can call it from your shell.

## Skills

| Skill | What it does |
|-------|--------------|
| [`rainbow/`](rainbow/SKILL.md) | Ledger Donjon's [rainbow](https://github.com/Ledger-Donjon/rainbow) — emulate an embedded binary with Unicorn to generate side-channel leakage traces and sweep fault-injection models (instruction-skip / stuck-at). Pure software; no scope or glitcher needed. Pairs with `lascar`. |
| [`lascar/`](lascar/SKILL.md) | Ledger Donjon's [lascar](https://github.com/Ledger-Donjon/lascar) — side-channel analysis: CPA / DPA / MIA, TVLA (Welch t-test) leakage assessment, SNR / NICV, profiled & ML attacks, over traces from any source (ChipWhisperer, PicoScope, a scope dump, or rainbow). |

## Setup on a fresh machine

Prerequisites: `git`, `python3`, `python3-venv` (Debian/Ubuntu: `sudo apt install -y git python3 python3-venv`).

```bash
git clone https://github.com/Nicola-Ceornea/my-claude-skills.git ~/repos/my-claude-skills
~/repos/my-claude-skills/setup.sh
```

That one command, idempotently:

1. installs the **rainbow + lascar** toolchain into a dedicated venv at `~/.local/share/donjon-sca/` (clones both repos there as editable installs, so their `examples/` and `tutorial/` dirs are on disk) — *note: lascar pulls a heavy dep set incl. tensorflow/keras, so first run takes a few minutes;*
2. puts the **`donjon-sca`** CLI on your `PATH` (`~/.local/bin/donjon-sca`, and appends a `PATH` line to your shell rc if `~/.local/bin` isn't already there);
3. **symlinks every skill** in this repo into `~/.claude/skills/` so Claude Code discovers them.

Re-run `~/repos/my-claude-skills/setup.sh` (or `donjon-sca setup`) anytime to pull updates. Claude Code picks up new/changed skills on its next session start. Check it worked: `donjon-sca doctor`.

> Just want the skills, not the toolchain? Symlink the dirs you want into `~/.claude/skills/` yourself (`ln -s ~/repos/my-claude-skills/rainbow ~/.claude/skills/rainbow`, etc.) and skip `setup.sh`. Project-scoped alternative: drop a skill dir under `.claude/skills/` inside a repo to make it available only there.

## The `donjon-sca` CLI

A thin driver over the toolchain venv — Claude invokes it from the `rainbow`/`lascar` skills, and it's a normal command in your shell.

```
donjon-sca setup            bootstrap / update everything (idempotent)
donjon-sca doctor           diagnose the install (deps importable, versions, skill links, PATH)
donjon-sca new FILE.py      scaffold a harness template (side-channel + fault-injection skeleton)
donjon-sca run FILE.py ...  run a harness script inside the toolchain venv
donjon-sca python ...       the venv's python (e.g. donjon-sca python -c 'import rainbow; ...')
donjon-sca repl             interactive python with rainbow + lascar pre-imported
donjon-sca version          rainbow / lascar / unicorn / capstone versions
donjon-sca path             print the venv's bin dir (for `export PATH="$(donjon-sca path):$PATH"`)
```

Typical loop: `donjon-sca new attack.py` → edit the TODOs (target ELF, function symbol, what "leak" / "guard bypassed" means) → `donjon-sca run attack.py`. The scaffold's worked references are in `~/.local/share/donjon-sca/rainbow/examples/` (`CortexM_AES/`, `HW_analysis/pin_*.py`) and `~/.local/share/donjon-sca/lascar/examples/`.

Override the install root with `DONJON_SCA_HOME` (default `~/.local/share/donjon-sca`). The CLI lives at `bin/donjon-sca` in this repo and is symlinked onto `PATH` by setup; rename the symlink if you'd rather type something shorter.

## Notes

- `rainbow` makes the traces, `lascar` analyses them — designed to be used together. The fault-injection half of `rainbow` stands alone (no lascar needed).
- The skills describe *how to drive the tools*; `donjon-sca` is *how they're installed and run*. If a skill ever runs on a box without `donjon-sca`, that's the signal to run `setup.sh`.
- Licensed GPLv3 (see `LICENSE`).
