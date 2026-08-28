<h1 align="center">Claude Agent VPS</h1>

<p align="center">
  <b>Your own AI agent on your own server — in a single command.</b><br>
  Claude Code plus four-layer memory and tools that work the moment installation finishes.
</p>

<p align="center">
  <a href="#quick-start">Quick start</a> ·
  <a href="#what-you-get">What you get</a> ·
  <a href="#tool-presets">Presets</a> ·
  <a href="#troubleshooting">Troubleshooting</a> ·
  <a href="README.md">Русский</a>
</p>

---

## Quick start

On a clean Ubuntu box, as `root`:

```bash
curl -fsSL https://raw.githubusercontent.com/YLisov/claude-vps-autoinstall/main/setup-vps.sh | bash
```

The script asks everything up front, then runs unattended (~10–15 minutes). When it finishes:

```bash
ssh claude@<server-ip>
claude
```

Claude Code asks you to authenticate on first launch — open the link it prints in your browser. Then tell the agent `/onboarding-conductor` and it will interview you and fill in its own profile.

> The installer asks for: hostname, whether to grow the disk, the agent's username, which tools to install, and your access keys. Nothing else.

---

## What you get

```
Claude Code
├── Memory — four layers
│   ├── L1  Identity     CLAUDE.md + USER.md — always in context
│   ├── L2  Facts        auto-memory: MEMORY.md + files, loaded on demand
│   ├── L3  Continuity   hooks → handoff.md: where you left off, across sessions
│   └── L4  Semantic     Cognee: Neo4j graph + pgvector (optional)
│
├── MCP tools
│   ├── github        search repositories, code, issues and PRs
│   ├── crawl4ai      URL → clean markdown (−80% tokens versus raw HTML)
│   ├── searxng       self-hosted search in Docker, no third-party API keys
│   ├── playwright    headless browser: JS-heavy pages, screenshots
│   ├── figma         designs, variables and components → code
│   └── cognee        semantic search across accumulated memory
│
├── Plugins
│   ├── superpowers      TDD, debugging, planning, code review
│   ├── context7         live library documentation
│   ├── interface-design consistent design across sessions
│   └── ui-ux-pro-max    67 UI styles, 161 palettes
│
└── ~19 skills, including find-skills — discover new ones via the skills.sh registry
```

---

## What the installer does

| Step | What happens |
|------|--------------|
| **Hostname** | Asks for a new name and writes it to `/etc/hosts`, so `sudo` stops complaining |
| **Disk** | Detects space left unclaimed after you grew the disk in the hypervisor and expands the partition (`growpart` + `resize2fs`/`xfs_growfs`) |
| **User** | Creates `claude`, grants passwordless sudo, adds it to the docker group, copies root's SSH keys so you log in with the same key. For a different key: `EXTRA_SSH_KEY='ssh-ed25519 AAAA...' bash setup-vps.sh` |
| **Environment** | Docker, Node.js 22, uv, ripgrep, jq, fzf, tmux |
| **Claude Code** | Runs the native installer and sets up PATH |
| **Secrets** | Prompts for keys, writes them only to `~/.claude/memory-system/.env` (chmod 600) |
| **Infrastructure** | Starts containers, builds venvs, registers MCP servers, installs plugins and skills |
| **Verification** | Runs smoke tests and reports honestly what came up and what did not |

The script is **idempotent** — running it again breaks nothing and never overwrites an existing `.env`.

---

## Tool presets

The installer offers a choice:

| Preset | Includes | Best for |
|--------|----------|----------|
| **Full** | github, crawl4ai, searxng, playwright, figma + all plugins + skills | A general-purpose work machine |
| **Basic** | github, crawl4ai, searxng + superpowers, context7 + skills | No frontend work, no browser |
| **Minimal** | github, crawl4ai + superpowers. No Docker | Small VPS, 1–2 GB RAM |
| **Custom** | Pick item by item | When you know exactly what you need |

Separate options:

- **Cognee (L4)** — semantic memory. Needs ~4.5 GB RAM and an OpenAI key with credit. Off by default: L1–L3 covers most work.
- **docling** — enables `fetch_doc` for PDF/DOCX/PPTX. Pulls torch, +~2 GB.

Add either later with the same script:

```bash
cd ~/claude-installer && bash install.sh --with-cognee
```

---

## Which keys are needed, and why

The installer prompts for them with hidden input. They never reach the repository — the `.env` path is covered by `.gitignore`.

| Key | Purpose | Required |
|-----|---------|----------|
| **GitHub PAT** | The github MCP server. Needed even to search public repositories: without a token the GitHub API allows only 60 requests per hour | Only if you install the github MCP |
| **OpenAI API key** | Cognee: `gpt-4o-mini` + `text-embedding-3-small` | Only with `--with-cognee` |

Neo4j and Postgres passwords and the SearXNG secret are generated locally — you never type them.

**Ready-made link for the GitHub PAT** — the scopes are pre-selected, just press "Generate token":

```
https://github.com/settings/tokens/new?scopes=repo,read:user,read:org&description=Claude+Agent+VPS
```

The installer validates the token against the API right away and, if it is rejected, explains what went wrong and lets you retry.

---

## Tool-priority rule

`CLAUDE.md` makes the agent reach for MCP **first**, rather than after a failed attempt at the same thing through bash:

| Task | Tool |
|------|------|
| Fetch a page | `crawl4ai` → `fetch_url` |
| Search the web | `searxng` |
| GitHub | `github` MCP |
| JS pages, screenshots | `playwright` |
| PDF/DOCX | `crawl4ai` → `fetch_doc` |
| Design files | `figma` |
| Library documentation | `context7` |

Fallbacks are spelled out too: when `searxng` returns nothing because the IP is blocked, the agent switches to `crawl4ai` instead of hammering it with retries.

---

## Finding new skills

The `find-skills` skill plus the `skills` CLI open up the [skills.sh](https://skills.sh/) registry:

```
> find me a skill for SEO optimization
```

The agent runs `skills find seo`, ranks the results by install count, and offers to install one:

```bash
skills add coreyhaines31/marketingskills@seo-audit -g -y
```

A quality bar is baked into `CLAUDE.md`: only install skills with 1,000+ installs from a recognizable author. For a curated, category-based catalogue see [ComposioHQ/awesome-claude-skills](https://github.com/ComposioHQ/awesome-claude-skills).

---

## Requirements

- Ubuntu 22.04+ (tested on 24.04 LTS)
- 2 GB RAM for the basic preset, **8 GB** if you install Cognee
- Root access and an SSH key in `/root/.ssh/authorized_keys`
- A Claude account with Claude Code access

---

## Security

- Secrets live only in `~/.claude/memory-system/.env`, mode `600`. They are never passed as command arguments, which would expose them in `ps aux`.
- Docker ports bind to `127.0.0.1` — nothing is exposed externally.
- `.gitignore` covers `.env`, keys, `handoff.md`, logs and agent state.
- The summarizer hook has a recursion guard (`MEMORY_SUMMARIZER`).
- `CLAUDE.md` requires explicit confirmation for irreversible actions: `rm -rf`, `DROP`, `git push --force`, firewall changes, sending email.
- Passwordless sudo for the agent user is a deliberate trade-off for autonomy. Use a dedicated machine.

---

## Troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| `claude` segfaults, "CPU lacks AVX" | Hypervisor hides CPU flags | Set `CPU=host` in the VM settings |
| searxng returns 0 results | Search engines block datacenter IPs with captchas or 429s | Wait out the ban or work through `crawl4ai`. The smoke test names the engines that failed |
| playwright: "Chromium distribution 'chrome' is not found" | The MCP server looks for real Google Chrome by default | The installer already passes `--browser chromium` |
| `./venv/bin/pip: not found` | `uv venv` without `--seed` ships no pip | The installer always calls `uv venv --seed` |
| cognee and crawl4ai dependency clash | The packages cannot share a venv | Separate `venv` and `venv-crawl4ai` |
| Cognee hangs on `LLM ... timed out` | Empty OpenAI balance (429) | Top up billing |
| `plugin not found` | Name given without its marketplace | Install as `superpowers@superpowers-dev` |
| `docker` needs sudo | Group membership applies at next login | Log out and back in, or `sudo reboot` |

---

## Repository layout

```
.
├── setup-vps.sh                # Entry point: run as root, one command
├── install.sh                  # Environment, MCP, plugins, skills (as the claude user)
├── config/
│   ├── CLAUDE.md               # Agent identity, rules, tool priority
│   ├── USER.md                 # Owner profile template
│   ├── settings.json           # Claude Code settings: hooks, permissions
│   └── .env.example            # Secrets template (no values)
├── hooks/
│   ├── session-start.sh        # Loads handoff.md into context at startup
│   └── summarize-to-handoff.sh # Summarizes the session via Haiku → handoff.md
├── memory-system/
│   ├── docker-compose.yml      # SearXNG + (cognee profile) Neo4j, pgvector
│   ├── crawl4ai-mcp.py         # MCP server: fetch_url, fetch_doc
│   ├── *-mcp-server.sh         # MCP launcher wrappers
│   └── push_to_cognee.py       # Session summary → Cognee
└── skills/                     # Custom skills
```

---

## Cost

| Item | Cost |
|------|------|
| SearXNG, crawl4ai, playwright, github | Free |
| Summarizer hook (Haiku, once per session) | < $0.001 |
| Cognee (`gpt-4o-mini` + embeddings) | Depends on volume; invoke L4 deliberately |

---

<p align="center"><sub>Apache 2.0 · Individual skills carry their own licenses — check their repositories</sub></p>
