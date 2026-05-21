#!/usr/bin/env bash
# ============================================================
# Claude Agent VPS — One-command installer
# Usage: bash install.sh
# Requirements: Ubuntu 22.04+, Claude Code CLI installed
# ============================================================
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
ok()   { echo -e "${GREEN}✓${NC} $1"; }
warn() { echo -e "${YELLOW}⚠${NC}  $1"; }
fail() { echo -e "${RED}✗${NC} $1"; exit 1; }
step() { echo -e "\n${BLUE}▶${NC} ${YELLOW}$1${NC}"; }

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="$HOME/.claude"
MEM_DIR="$CLAUDE_DIR/memory-system"
VENV="$MEM_DIR/venv"

echo -e "\n${BLUE}╔════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║   Claude Agent VPS — Installer         ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════╝${NC}\n"

# ── 0. Prerequisites ──────────────────────────────────────
step "Checking prerequisites"
command -v claude >/dev/null || fail "Claude Code CLI not found. Install: https://claude.ai/download"
command -v python3 >/dev/null || fail "python3 required"
command -v curl    >/dev/null || fail "curl required"
command -v git     >/dev/null || fail "git required"
ok "Claude Code CLI found: $(claude --version 2>/dev/null | head -1)"

# ── 1. System packages ────────────────────────────────────
step "Installing system packages"
sudo apt-get update -qq
sudo apt-get install -y --no-install-recommends \
  curl git ripgrep jq fzf tmux python3-pip python3-venv \
  build-essential libssl-dev 2>/dev/null | grep -E "^(Setting up|Unpacking)" | head -10 || true

# Node.js 22+
NODE_VER=$(node --version 2>/dev/null | sed 's/v//' | cut -d. -f1 || echo 0)
if [ "${NODE_VER}" -lt 20 ] 2>/dev/null; then
  step "Installing Node.js 22"
  curl -fsSL https://deb.nodesource.com/setup_22.x | sudo bash - >/dev/null
  sudo apt-get install -y nodejs >/dev/null
fi
ok "Node.js $(node --version)"

# uv (fast Python package manager)
if ! command -v uv >/dev/null; then
  curl -LsSf https://astral.sh/uv/install.sh | sh >/dev/null
  export PATH="$HOME/.local/bin:$PATH"
fi
ok "uv $(uv --version 2>/dev/null)"

# ── 2. Docker ─────────────────────────────────────────────
step "Checking Docker"
if ! command -v docker >/dev/null; then
  echo "Installing Docker..."
  curl -fsSL https://get.docker.com | sudo bash >/dev/null
  sudo systemctl enable docker >/dev/null
  sudo systemctl start docker
fi
if ! groups | grep -q docker; then
  sudo usermod -aG docker "$USER"
  warn "Added $USER to docker group. Re-login may be needed for non-sudo docker."
fi
ok "Docker $(sudo docker --version | cut -d' ' -f3 | tr -d ',')"

# ── 3. Directory structure ─────────────────────────────────
step "Creating directory structure"
mkdir -p "$CLAUDE_DIR"/{hooks,skills,plans}
mkdir -p "$MEM_DIR"/searxng/settings
ok "Directories created"

# ── 4. API Keys & .env ────────────────────────────────────
step "Configuring secrets"
if [ ! -f "$MEM_DIR/.env" ]; then
  echo
  echo "  Required API keys (will be saved to $MEM_DIR/.env):"
  echo
  read -rp "  OpenAI API Key (gpt-4o-mini + text-embedding-3-small): " OPENAI_KEY
  echo
  read -rp "  GitHub PAT (scopes: public_repo, read:user, read:org): " GITHUB_PAT
  echo

  NEO4J_PW=$(python3 -c "import secrets; print(secrets.token_hex(20))")
  PG_PW=$(python3   -c "import secrets; print(secrets.token_hex(20))")
  SRXNG_SECRET=$(python3 -c "import secrets; print(secrets.token_hex(32))")

  cat > "$MEM_DIR/.env" <<EOF
# LLM & Embeddings
LLM_PROVIDER=openai
LLM_MODEL=gpt-4o-mini
LLM_API_KEY=${OPENAI_KEY}
EMBEDDING_PROVIDER=openai
EMBEDDING_MODEL=openai/text-embedding-3-small
EMBEDDING_DIMENSIONS=1536

# Graph DB (Neo4j)
GRAPH_DATABASE_PROVIDER=neo4j
GRAPH_DATABASE_URL=bolt://localhost:7687
GRAPH_DATABASE_USERNAME=neo4j
GRAPH_DATABASE_PASSWORD=${NEO4J_PW}

# Vector + Relational DB (Postgres/pgvector)
VECTOR_DB_PROVIDER=pgvector
VECTOR_DB_HOST=localhost
VECTOR_DB_PORT=5432
VECTOR_DB_USERNAME=cognee
VECTOR_DB_PASSWORD=${PG_PW}
VECTOR_DB_DATABASE=cognee
DB_PROVIDER=postgres
DB_HOST=localhost
DB_PORT=5432
DB_USERNAME=cognee
DB_PASSWORD=${PG_PW}
DB_DATABASE=cognee

# GitHub MCP
GITHUB_PAT=${GITHUB_PAT}
GITHUB_PERSONAL_ACCESS_TOKEN=${GITHUB_PAT}

# SearXNG
SEARXNG_SECRET=${SRXNG_SECRET}

# Misc
ENABLE_BACKEND_ACCESS_CONTROL=false
EOF
  chmod 600 "$MEM_DIR/.env"
  ok ".env created with generated passwords"
else
  ok ".env already exists — skipping"
fi

set -a; source "$MEM_DIR/.env"; set +a

# ── 5. Config files ───────────────────────────────────────
step "Copying config files"
cp "$REPO_DIR/config/CLAUDE.md" "$CLAUDE_DIR/CLAUDE.md"
cp "$REPO_DIR/config/USER.md"   "$CLAUDE_DIR/USER.md"

# settings.json — replace placeholder with actual path
sed "s|CLAUDE_DIR|${CLAUDE_DIR}|g" "$REPO_DIR/config/settings.json" \
  > "$CLAUDE_DIR/settings.json"
ok "CLAUDE.md, USER.md, settings.json"

# ── 6. Hooks ─────────────────────────────────────────────
step "Installing hooks"
cp "$REPO_DIR/hooks/session-start.sh"       "$CLAUDE_DIR/hooks/"
cp "$REPO_DIR/hooks/summarize-to-handoff.sh" "$CLAUDE_DIR/hooks/"
chmod +x "$CLAUDE_DIR/hooks/"*.sh
ok "Hooks installed"

# ── 7. Memory-system scripts ──────────────────────────────
step "Installing memory-system scripts"
cp "$REPO_DIR/memory-system/cognee-mcp-server.sh"   "$MEM_DIR/"
cp "$REPO_DIR/memory-system/crawl4ai-mcp.py"        "$MEM_DIR/"
cp "$REPO_DIR/memory-system/crawl4ai-mcp-server.sh" "$MEM_DIR/"
cp "$REPO_DIR/memory-system/github-mcp-server.sh"   "$MEM_DIR/"
cp "$REPO_DIR/memory-system/push_to_cognee.py"      "$MEM_DIR/"
chmod +x "$MEM_DIR/"*.sh

# docker-compose.yml uses ${VAR} from .env — copy as-is
cp "$REPO_DIR/memory-system/docker-compose.yml" "$MEM_DIR/"
ok "Memory-system scripts"

# SearXNG config
if [ ! -f "$MEM_DIR/searxng/settings/settings.yml" ]; then
  cat > "$MEM_DIR/searxng/settings/settings.yml" <<EOF
use_default_settings: true
general:
  debug: false
  instance_name: "local-searxng"
search:
  safe_search: 0
  default_lang: "ru"
  formats:
    - html
    - json
server:
  secret_key: "${SEARXNG_SECRET}"
  bind_address: "0.0.0.0"
  port: 8080
  limiter: false
  public_instance: false
ui:
  default_locale: "ru"
  default_theme: "simple"
EOF
  ok "SearXNG config created"
fi

# ── 8. Docker containers ──────────────────────────────────
step "Starting Docker containers (Neo4j, Postgres, SearXNG)"
cd "$MEM_DIR"
sudo docker compose up -d 2>&1 | grep -E "Started|Running|Created|Pulling|healthy" | head -10 || true

echo "  Waiting for containers to be healthy..."
for i in $(seq 1 24); do
  NEO_OK=$(sudo docker inspect cognee-neo4j  --format '{{.State.Health.Status}}' 2>/dev/null || echo "missing")
  PG_OK=$(sudo docker inspect cognee-postgres --format '{{.State.Health.Status}}' 2>/dev/null || echo "missing")
  [ "$NEO_OK" = "healthy" ] && [ "$PG_OK" = "healthy" ] && break
  sleep 5
done
ok "Neo4j + Postgres + SearXNG running"
cd "$REPO_DIR"

# ── 9. Python venv ────────────────────────────────────────
step "Creating Python venv and installing packages"
if [ ! -d "$VENV" ]; then
  uv venv "$VENV" --python python3 >/dev/null
fi
uv pip install --python "$VENV/bin/python" \
  "cognee[postgres-binary]" fastmcp crawl4ai docling 2>&1 | tail -3

# Playwright browsers for crawl4ai
"$VENV/bin/python" -m playwright install chromium 2>&1 | tail -2
ok "Python packages installed"

# MCP server scripts need execute permission
chmod +x "$MEM_DIR/cognee-mcp-server.sh" \
         "$MEM_DIR/crawl4ai-mcp-server.sh" \
         "$MEM_DIR/github-mcp-server.sh"

# ── 10. MCP servers ───────────────────────────────────────
step "Registering MCP servers"
_mcp_add() {
  local name="$1"; shift
  claude mcp list 2>/dev/null | grep -q "^${name}:" && { ok "MCP $name already registered"; return; }
  claude mcp add "$name" --scope user "$@" 2>/dev/null && ok "MCP $name" || warn "MCP $name — skipped"
}
_mcp_add cognee             -- "$MEM_DIR/cognee-mcp-server.sh"
_mcp_add crawl4ai           -- "$MEM_DIR/crawl4ai-mcp-server.sh"
_mcp_add github             -- "$MEM_DIR/github-mcp-server.sh"
_mcp_add searxng            -e SEARXNG_URL=http://localhost:8080 -- npx -y mcp-searxng
_mcp_add sequential-thinking -- npx -y @modelcontextprotocol/server-sequential-thinking
_mcp_add playwright          -- npx @playwright/mcp@latest --headless

# ── 11. Claude Code plugins ───────────────────────────────
step "Installing Claude Code plugins"
_marketplace_add() {
  local url="$1"
  GIT_ASKPASS=/bin/true claude plugin marketplace add "$url" --scope user 2>/dev/null \
    && ok "Marketplace: $url" || warn "Marketplace already added or failed: $url"
}
_plugin_install() {
  local name="$1"
  GIT_ASKPASS=/bin/true claude plugin install "$name" --scope user 2>/dev/null \
    && ok "Plugin: $name" || warn "Plugin $name — skipped (may already be installed)"
}

_marketplace_add https://github.com/obra/superpowers
_marketplace_add https://github.com/upstash/context7
_marketplace_add https://github.com/nextlevelbuilder/ui-ux-pro-max-skill
_marketplace_add https://github.com/Dammyjay93/interface-design
_marketplace_add https://github.com/anthropics/skills

_plugin_install superpowers
_plugin_install context7-plugin
_plugin_install ui-ux-pro-max
_plugin_install interface-design

# ── 12. SKILL.md files ────────────────────────────────────
step "Installing SKILL.md skills"
_skill() {
  local name="$1" url="$2"
  mkdir -p "$CLAUDE_DIR/skills/$name"
  curl -fsSL "$url" -o "$CLAUDE_DIR/skills/$name/SKILL.md" 2>/dev/null \
    && ok "Skill: $name" || warn "Skill $name — failed to fetch"
}

# Anthropic official
_skill frontend-design   "https://raw.githubusercontent.com/anthropics/skills/main/skills/frontend-design/SKILL.md"
_skill theme-factory     "https://raw.githubusercontent.com/anthropics/skills/main/skills/theme-factory/SKILL.md"
_skill brand-guidelines  "https://raw.githubusercontent.com/anthropics/skills/main/skills/brand-guidelines/SKILL.md"
_skill canvas-design     "https://raw.githubusercontent.com/anthropics/skills/main/skills/canvas-design/SKILL.md"
_skill skill-creator     "https://raw.githubusercontent.com/anthropics/skills/main/skills/skill-creator/SKILL.md"

# Taste Skill (design)
_skill taste-skill      "https://raw.githubusercontent.com/Leonxlnx/taste-skill/main/skills/taste-skill/SKILL.md"
_skill redesign-skill   "https://raw.githubusercontent.com/Leonxlnx/taste-skill/main/skills/redesign-skill/SKILL.md"
_skill minimalist-skill "https://raw.githubusercontent.com/Leonxlnx/taste-skill/main/skills/minimalist-skill/SKILL.md"
_skill soft-skill       "https://raw.githubusercontent.com/Leonxlnx/taste-skill/main/skills/soft-skill/SKILL.md"

# Wondelai skills
BASE="https://raw.githubusercontent.com/wondelai/skills/main"
for s in ux-heuristics refactoring-ui design-sprint hooked-ux microinteractions top-design web-typography; do
  _skill "$s" "$BASE/$s/SKILL.md"
done

# Vercel skills
BASE="https://raw.githubusercontent.com/vercel-labs/agent-skills/main/skills"
_skill web-design-guidelines "$BASE/web-design-guidelines/SKILL.md"
_skill react-best-practices   "$BASE/react-best-practices/SKILL.md"

# Skill-finder (agent tool)
_skill skill-finder "https://raw.githubusercontent.com/qwwiwi/skill-finder/main/SKILL.md"

# Agent skills (custom)
cp "$REPO_DIR/skills/self-compiler/SKILL.md"        "$CLAUDE_DIR/skills/self-compiler/SKILL.md" 2>/dev/null \
  && ok "Skill: self-compiler" || warn "self-compiler not found in repo"
cp "$REPO_DIR/skills/onboarding-conductor/SKILL.md" "$CLAUDE_DIR/skills/onboarding-conductor/SKILL.md" 2>/dev/null \
  && ok "Skill: onboarding-conductor" || warn "onboarding-conductor not found in repo"
cp "$REPO_DIR/skills/present/SKILL.md"              "$CLAUDE_DIR/skills/present/SKILL.md" 2>/dev/null \
  && ok "Skill: present" || warn "present not found in repo"

# ── 13. Verification ──────────────────────────────────────
step "Verification"
echo
echo "  MCP servers:"
claude mcp list 2>/dev/null | grep -E "✓|✗|Connected|Failed" | head -10 || true
echo
echo "  Plugins:"
GIT_ASKPASS=/bin/true claude plugin list 2>/dev/null | grep -E "✔|✘|enabled|disabled" | head -10 || true
echo
echo "  Skills installed: $(ls "$CLAUDE_DIR/skills/" | wc -l)"
echo

echo -e "${GREEN}════════════════════════════════════════${NC}"
echo -e "${GREEN} Installation complete!${NC}"
echo -e "${GREEN}════════════════════════════════════════${NC}"
echo
echo "  Next steps:"
echo "  1. Start a new Claude Code session (MCP tools appear in next session)"
echo "  2. Run /onboarding-conductor to fill in your profile"
echo "  3. Add your GitHub PAT if not done: see config/.env.example"
echo
