# llm-skills

> Reusable skills for AI coding assistants. One command to install, auto-updates on every run.

```bash
curl -fsSL https://raw.githubusercontent.com/creasydude/llm-skills/main/llm-skills.sh | bash
```

## Quick Start

```bash
# Install everything to all detected tools
llm-skills install

# Pick a specific tool
llm-skills install --tool claude-code

# Pick a specific skill
llm-skills install --skill telegram-serverless

# See what's available and what's installed
llm-skills list

# Remove something
llm-skills remove telegram-serverless
```

## Skills

### `telegram-serverless`

Build Telegram bots that run entirely on Telegram's infrastructure — no VPS, no cloud functions, no containers. You write JavaScript modules, deploy with `npx tgcloud push`, and Telegram handles the rest.

**What's inside:**

- **Bot API & Handlers** — message, callback, inline query, shipping, pre-checkout — every update type mapped to a file
- **Built-in Database** — SQLite-backed, schema defined in code, migrations reviewed before deploy
- **SDK** — typed wrappers for the Bot API, DB queries, outbound HTTP, secrets
- **Mini Apps** — serve web frontends from the same project, with session state tied to Telegram users
- **BotFather integration** — create and configure bots from the chat interface itself
- **CLI (`tgcloud`)** — push, pull, logs, rollback, env management — the full dev loop

**When to use it:** Anytime you're building a Telegram bot and don't want to deal with infrastructure. Works for simple reply bots, payment flows, mini apps, and anything in between.

---

## Supported Tools

| Tool | Install Path | Symlink | Notes |
|------|-------------|---------|-------|
| **Claude Code** | `.claude/skills/` | Yes | Full support |
| **OpenCode** | `.opencode/skills/` | Unknown | — |
| **MiMo Code** | `.mimocode/skills/` | Unknown | Also scans `.claude/skills/`, `.agents/skills/` |
| **Codex CLI** | `.agents/skills/` | Yes | Full support |
| **Cursor** | `.cursor/rules/` | No | Auto-converted to `.mdc` format |
| **Windsurf/Devin** | `.windsurf/skills/` | Unknown | — |
| **Cline** | `.cline/skills/` | Unknown | — |
| **GitHub Copilot** | `.github/instructions/` | No | Auto-converted to `.instructions.md` |

## Adding a Skill

1. Create `skills/<name>/SKILL.md`
2. Add it to the `SKILLS` array in `llm-skills.sh`
3. Push to GitHub — everyone gets it automatically on next run

## How It Works

The installer (`llm-skills.sh`) is a single bash script that:

1. **Installs itself** to `~/.local/bin/llm-skills`
2. **Auto-updates** on every run — fetches the latest version from GitHub before executing
3. **Discovers skills** via GitHub API — new skills show up without reinstalling
4. **Detects tools** — finds what's installed on your machine and installs to the right paths
5. **Symlinks where possible** — Claude Code and Codex get symlinks, others get copies
