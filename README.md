# my-claude-skills

A collection of [Claude Code](https://claude.com/claude-code) skills I use. Each skill is a directory containing a `SKILL.md` (YAML frontmatter + a body that orients Claude on a tool or workflow).

## Skills

| Skill | What it does |
|-------|--------------|
| [`rainbow/`](rainbow/SKILL.md) | Ledger Donjon's [rainbow](https://github.com/Ledger-Donjon/rainbow) — emulate an embedded binary with Unicorn to generate side-channel leakage traces and sweep fault-injection models (instruction-skip / stuck-at). Pure software; no scope or glitcher needed. Pairs with `lascar`. |
| [`lascar/`](lascar/SKILL.md) | Ledger Donjon's [lascar](https://github.com/Ledger-Donjon/lascar) — side-channel analysis: CPA / DPA / MIA, TVLA (Welch t-test) leakage assessment, SNR / NICV, profiled & ML attacks, over traces from any source (ChipWhisperer, PicoScope, a scope dump, or rainbow). |

## Install

Claude Code discovers skills in `~/.claude/skills/`. Symlink (so `git pull` updates them in place) or copy:

```bash
git clone https://github.com/Nicola-Ceornea/my-claude-skills.git
mkdir -p ~/.claude/skills
# symlink each skill you want:
ln -s "$PWD/my-claude-skills/rainbow" ~/.claude/skills/rainbow
ln -s "$PWD/my-claude-skills/lascar"  ~/.claude/skills/lascar
# (or: cp -r my-claude-skills/rainbow my-claude-skills/lascar ~/.claude/skills/)
```

Skills are loaded at session start; restart Claude Code (or start a new session) after adding one. Verify it's picked up by checking the available-skills list, or just mention the tool by name and Claude should invoke it.

Project-scoped alternative: drop a skill directory under `.claude/skills/` inside a repo to make it available only there.

## Notes

- These skills describe *how to drive a tool* — they don't install it. Each `SKILL.md` has the install command for its underlying tool (rainbow: `pip install .` from a clone; lascar: `pip install "git+https://github.com/Ledger-Donjon/lascar.git"`).
- `rainbow` and `lascar` are designed to be used together: rainbow makes the traces, lascar analyses them. The fault-injection half of rainbow stands alone (no lascar needed).
- Licensed GPLv3 (see `LICENSE`).
