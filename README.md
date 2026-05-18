# my-claude-skills

[Claude Code](https://claude.com/claude-code) skills + the CLI tooling some of them drive.

Each skill is a directory with a `SKILL.md` (YAML frontmatter + a body that orients Claude on a tool or workflow). Most skills here drive a real toolchain (Ledger Donjon's `rainbow` + `lascar`, and eShard's `scared`); the `bin/donjon-sca` and `bin/scared-sca` CLIs install and run those toolchains — Claude calls them via the skill, and you can call them from your shell.

## Skills

| Skill | What it does |
|-------|--------------|
| [`rainbow/`](rainbow/SKILL.md) | Ledger Donjon's [rainbow](https://github.com/Ledger-Donjon/rainbow) — emulate an embedded binary with Unicorn to generate side-channel leakage traces and sweep fault-injection models (instruction-skip / stuck-at). Pure software; no scope or glitcher needed. Pairs with `lascar` / `scared`. |
| [`lascar/`](lascar/SKILL.md) | Ledger Donjon's [lascar](https://github.com/Ledger-Donjon/lascar) — side-channel analysis: CPA / DPA / MIA, TVLA (Welch t-test) leakage assessment, SNR / NICV, profiled & ML attacks, over traces from any source (ChipWhisperer, PicoScope, a scope dump, or rainbow). Low-level Engine/Session/OutputMethod toolkit; TF/Keras profiled-NN engines. |
| [`scared/`](scared/SKILL.md) | eShard's [scared](https://github.com/eshard/scared) — higher-level CPA / DPA / ANOVA / NICV / SNR / MIA / TVLA / template attacks over `estraces` trace sets (ETS / ChipWhisperer / HDF5 / raw-bin / numpy). Built-in AES & DES round selection functions, `Synchronizer` for trace resync (writes a realigned `.ets`), `convergence_step=` rank-vs-#traces curves. Overlaps `lascar`; pick by workflow — `scared`'s "vs lascar" section in the SKILL.md spells out the tradeoffs. |

## Setup on a fresh machine

Prerequisites: `git`, `python3`, `python3-venv`, and **Python ≥ 3.11** for `scared` (Debian/Ubuntu: `sudo apt install -y git python3 python3-venv python3.11 python3.11-venv`).

```bash
git clone https://github.com/Nicola-Ceornea/my-claude-skills.git ~/repos/my-claude-skills
~/repos/my-claude-skills/setup.sh
```

That one command, idempotently:

1. installs the **rainbow + lascar** toolchain into a dedicated venv at `~/.local/share/donjon-sca/` (clones both repos there as editable installs, so their `examples/` and `tutorial/` dirs are on disk);
2. installs eShard's **`scared`** into a separate venv at `~/.local/share/scared-sca/` (scared requires `numpy>=2` + python≥3.11, incompatible with the lascar/rainbow stack — hence the second venv);
3. puts both CLIs on your `PATH` (`~/.local/bin/donjon-sca`, `~/.local/bin/scared-sca`), and appends a `PATH` line to your shell rc if needed;
4. **symlinks every skill** in this repo into `~/.claude/skills/` so Claude Code discovers them.

First run takes several minutes and a few hundred MB. Re-run `~/repos/my-claude-skills/setup.sh` (or each CLI's own `setup`) anytime to pull updates. Claude Code picks up new/changed skills on its next session start. Check it worked: `donjon-sca doctor` and `scared-sca doctor`.

> Just want the skills, not the toolchain? Symlink the dirs you want into `~/.claude/skills/` yourself (`ln -s ~/repos/my-claude-skills/rainbow ~/.claude/skills/rainbow`, etc.) and skip `setup.sh`. Project-scoped alternative: drop a skill dir under `.claude/skills/` inside a repo to make it available only there.

## The CLIs

Thin drivers over each toolchain's venv — Claude invokes them from the matching skill, and they're normal commands in your shell.

### `donjon-sca` — rainbow + lascar

```
donjon-sca setup            bootstrap / update everything (idempotent)
donjon-sca doctor           diagnose the install
donjon-sca new FILE.py      scaffold a harness template (side-channel + fault-injection skeleton)
donjon-sca run FILE.py ...  run a harness script inside the toolchain venv
donjon-sca python ...       the venv's python (e.g. donjon-sca python -c 'import rainbow; ...')
donjon-sca repl             interactive python with rainbow + lascar pre-imported
donjon-sca version          rainbow / lascar / unicorn / capstone versions
donjon-sca path             print the venv's bin dir
```

Typical loop: `donjon-sca new attack.py` → edit the TODOs (target ELF, function symbol, what "leak" / "guard bypassed" means) → `donjon-sca run attack.py`. Worked references in `~/.local/share/donjon-sca/{rainbow,lascar}/examples/`. Override the install root with `DONJON_SCA_HOME`.

### `scared-sca` — scared

```
scared-sca setup            bootstrap / update (idempotent; needs python>=3.11)
scared-sca doctor           diagnose the install
scared-sca run FILE.py ...  run a scared analysis script inside the venv
scared-sca python ...       the venv's python
scared-sca repl             interactive python with scared + numpy pre-imported
scared-sca version          scared / estraces / numpy versions
scared-sca path             print the venv's bin dir
```

No `new` scaffold — scared's API is small enough that the `scared/SKILL.md` recipes (CPA / TVLA / SNR / `Synchronizer`) are the template. Override the install root with `SCARED_SCA_HOME`.

## Notes

- `rainbow` makes the traces, `lascar` *or* `scared` analyses them. The fault-injection half of `rainbow` stands alone (no analyser needed).
- `lascar` and `scared` overlap on CPA/DPA/TVLA/SNR. Pick by workflow — `scared/SKILL.md`'s "scared vs lascar" section breaks down when each one wins.
- The skills describe *how to drive the tools*; the CLIs are *how they're installed and run*. If a skill ever runs on a box without its CLI, that's the signal to re-run `setup.sh`.
- Licensed GPLv3 (see `LICENSE`).
