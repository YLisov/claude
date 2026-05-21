# Claude Agent VPS

Personal AI agent on a dedicated VPS — one-command installer for Claude Code with 4-layer memory, semantic search, MCP tools, and 20+ design skills.

## What you get

```
Claude Code
├── 4-layer memory system
│   ├── L1 IDENTITY     — CLAUDE.md + USER.md (always in context)
│   ├── L2 STRUCTURED   — auto-memory (MEMORY.md + typed facts)
│   ├── L3 CONTINUITY   — session hooks → handoff.md (Haiku summarizer)
│   └── L4 SEMANTIC     — Cognee MCP (Neo4j graph + pgvector + OpenAI)
├── MCP servers
│   ├── crawl4ai        — URL → clean markdown (−80% tokens)
│   ├── searxng         — self-hosted web search
│   ├── github          — repo/code/issues search
│   ├── sequential-thinking — structured reasoning
│   ├── playwright      — headless browser + screenshots
│   └── cognee          — semantic graph memory
├── Plugins
│   ├── superpowers     — 14 dev skills (TDD, debug, plan, review)
│   ├── context7        — live library documentation
│   ├── ui-ux-pro-max   — 67 UI styles, 161 palettes
│   └── interface-design — consistent design across sessions
└── 20+ SKILL.md files
    ├── Design: frontend-design, taste-skill, redesign-skill, minimalist-skill,
    │          soft-skill, theme-factory, brand-guidelines, canvas-design,
    │          web-design-guidelines, ux-heuristics, refactoring-ui,
    │          microinteractions, web-typography, top-design
    └── Agent: skill-finder, self-compiler, onboarding-conductor, present,
               design-sprint, hooked-ux, react-best-practices, skill-creator
```

## Requirements

- Ubuntu 22.04+ VPS (4 GB RAM minimum, 8 GB recommended)
- [Claude Code CLI](https://claude.ai/download) installed
- OpenAI API key (for Cognee LLM + embeddings)
- GitHub PAT with `public_repo`, `read:user`, `read:org` scopes

## Quick start

```bash
git clone https://github.com/YLisov/claude.git
cd claude
bash install.sh
```

The installer will prompt for your API keys, generate secure passwords, and set everything up automatically (~10 minutes).

## Architecture

### Memory layers

| Layer | What | When |
|-------|------|-------|
| **L1** | CLAUDE.md + USER.md | Always in context |
| **L2** | auto-memory files | Auto-saved facts, loaded on demand |
| **L3** | handoff.md | Session continuity via hooks |
| **L4** | Cognee (graph+vector) | Deep semantic search, on demand only |

### MCP tool usage rules (in CLAUDE.md)

- **Web page** → `crawl4ai` MCP, not curl
- **Web search** → `searxng` MCP, not bash
- **GitHub** → `github` MCP, not curl to api.github.com
- **JS-heavy pages** → `playwright` if crawl4ai fails
- **PDF/DOCX** → `crawl4ai` fetch_doc or docling CLI

### Infrastructure (Docker)

| Container | Image | Port | Purpose |
|-----------|-------|------|---------|
| `cognee-neo4j` | neo4j:5-community | 127.0.0.1:7474/7687 | Graph DB |
| `cognee-postgres` | pgvector/pgvector:pg16 | 127.0.0.1:5432 | Vector + relational |
| `searxng` | searxng/searxng | 127.0.0.1:8080 | Web search |

All ports are bound to localhost only.

## Security

- All secrets in `~/.claude/memory-system/.env` (chmod 600)
- Docker ports bound to `127.0.0.1` only (no external exposure)
- Hooks have recursion guard (`MEMORY_SUMMARIZER` env var)
- CLAUDE.md has explicit confirmation requirements for destructive actions

## After installation

1. Start a new Claude Code session (MCP tools activate on next session)
2. Run `/onboarding-conductor` to fill in your profile
3. Try `/skill-finder` to search for more skills

## Structure

```
.
├── install.sh                  # Main installer
├── config/
│   ├── CLAUDE.md               # Agent identity + rules (generic template)
│   ├── USER.md                 # User profile template
│   ├── settings.json           # Claude Code settings
│   └── .env.example            # API keys template
├── hooks/
│   ├── session-start.sh        # Loads handoff.md into context
│   └── summarize-to-handoff.sh # Summarizes session → handoff.md + Cognee
├── memory-system/
│   ├── docker-compose.yml      # Neo4j + Postgres + SearXNG
│   ├── cognee-mcp-server.sh    # Cognee MCP launcher
│   ├── crawl4ai-mcp.py         # Crawl4AI + docling MCP server
│   ├── crawl4ai-mcp-server.sh  # Crawl4AI MCP launcher
│   ├── github-mcp-server.sh    # GitHub MCP launcher (reads PAT from .env)
│   └── push_to_cognee.py       # Session episode → Cognee (used by hook)
└── skills/
    ├── self-compiler/SKILL.md
    ├── onboarding-conductor/SKILL.md
    └── present/SKILL.md
```

## Cost notes

- **OpenAI**: Haiku summarizer runs once per session (< $0.001). Cognee cognify runs once per session (cost depends on session length).
- **SearXNG**: Self-hosted, free.
- **Cognee**: Uses `gpt-4o-mini` + `text-embedding-3-small`. Keep L4 queries intentional.
