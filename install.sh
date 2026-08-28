#!/usr/bin/env bash
# ============================================================
# Claude Agent VPS — установщик окружения
# Запускать ОТ ЮЗЕРА claude (не root), после bootstrap-root.sh.
# Идемпотентен. Секреты только в ~/.claude/memory-system/.env (chmod 600).
#
#   bash install.sh                  # L1-L3 + crawl4ai/searxng/github/playwright
#   bash install.sh --with-cognee    # + L4 (Neo4j + pgvector, нужен OpenAI-ключ)
#   bash install.sh --with-docling   # + fetch_doc для PDF/DOCX (тянет torch, ~2 ГБ)
#   bash install.sh --no-skills      # без внешних SKILL.md
# ============================================================
set -euo pipefail

WITH_COGNEE=0; WITH_DOCLING=0; WITH_SKILLS=1
WITH_CRAWL4AI=1; WITH_SEARXNG=1; WITH_PLAYWRIGHT=1; WITH_FIGMA=1; WITH_UI_PLUGINS=1
for arg in "$@"; do
  case "$arg" in
    --with-cognee)   WITH_COGNEE=1 ;;
    --with-docling)  WITH_DOCLING=1 ;;
    --no-skills)     WITH_SKILLS=0 ;;
    --no-crawl4ai)   WITH_CRAWL4AI=0 ;;
    --no-searxng)    WITH_SEARXNG=0 ;;
    --no-playwright) WITH_PLAYWRIGHT=0 ;;
    --no-figma)      WITH_FIGMA=0 ;;
    --no-ui-plugins) WITH_UI_PLUGINS=0 ;;
    -h|--help) sed -n '2,20p' "$0"; exit 0 ;;
    *) echo "Неизвестный флаг: $arg (см. --help)"; exit 1 ;;
  esac
done

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
ok()   { echo -e "${GREEN}✓${NC} $1"; }
warn() { echo -e "${YELLOW}⚠${NC}  $1"; }
fail() { echo -e "${RED}✗${NC} $1"; exit 1; }
step() { echo -e "\n${BLUE}▶${NC} ${YELLOW}$1${NC}"; }

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="$HOME/.claude"
MEM_DIR="$CLAUDE_DIR/memory-system"
L2_DIR="$CLAUDE_DIR/projects/-home-$(id -un)/memory"
VENV_COGNEE="$MEM_DIR/venv"
VENV_CRAWL="$MEM_DIR/venv-crawl4ai"

echo -e "\n${BLUE}╔════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║   Claude Agent VPS — Installer         ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════╝${NC}"
echo "  L4 Cognee: $([ $WITH_COGNEE -eq 1 ] && echo 'да' || echo 'пропускаем')   docling: $([ $WITH_DOCLING -eq 1 ] && echo 'да' || echo 'нет')"

# ── 0. Prerequisites ──────────────────────────────────────
step "Проверка окружения"
[ "$(id -u)" -eq 0 ] && fail "Запускать от обычного юзера, не от root."
command -v python3 >/dev/null || fail "нужен python3"
command -v curl    >/dev/null || fail "нужен curl"
command -v git     >/dev/null || fail "нужен git"
sudo -n true 2>/dev/null      || fail "нужен sudo без пароля (см. bootstrap-root.sh)"

export PATH="$HOME/.local/bin:$PATH"
if ! command -v claude >/dev/null; then
  step "Устанавливаю Claude Code"
  curl -fsSL https://claude.ai/install.sh | bash
  grep -q '.local/bin' "$HOME/.bashrc" 2>/dev/null \
    || echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$HOME/.bashrc"
  command -v claude >/dev/null || fail "Claude Code не установился"
fi
ok "Claude Code: $(claude --version 2>/dev/null | head -1)"

# ── 1. Системные пакеты ───────────────────────────────────
step "Системные пакеты"
sudo apt-get update -qq
sudo apt-get install -y -qq --no-install-recommends \
  ripgrep jq fzf tmux python3-venv build-essential libssl-dev >/dev/null 2>&1 || true
ok "базовые пакеты"

NODE_VER=$(node --version 2>/dev/null | sed 's/v//' | cut -d. -f1 || echo 0)
if [ "${NODE_VER:-0}" -lt 20 ] 2>/dev/null; then
  curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash - >/dev/null 2>&1
  sudo apt-get install -y -qq nodejs >/dev/null
fi
ok "Node.js $(node --version)"

command -v uv >/dev/null || curl -LsSf https://astral.sh/uv/install.sh | sh >/dev/null 2>&1
export PATH="$HOME/.local/bin:$PATH"
command -v uv >/dev/null || fail "uv не установился"
ok "uv $(uv --version 2>/dev/null | cut -d' ' -f2)"

# skills CLI — реестр skills.sh, движок для скилла find-skills
if ! command -v skills >/dev/null; then
  sudo npm install -g skills >/dev/null 2>&1 || warn "skills CLI глобально не встал — останется npx skills"
fi
command -v skills >/dev/null && ok "skills CLI $(skills --version 2>/dev/null || echo '')" \
  || ok "skills доступен через npx"

# Docker: группа могла ещё не примениться в текущей сессии
if ! command -v docker >/dev/null; then
  curl -fsSL https://get.docker.com | sudo sh >/dev/null
  sudo systemctl enable --now docker >/dev/null 2>&1 || true
  sudo usermod -aG docker "$USER"
fi
DOCKER="docker"; docker ps >/dev/null 2>&1 || DOCKER="sudo docker"
ok "Docker $($DOCKER --version | cut -d' ' -f3 | tr -d ',') (команда: $DOCKER)"

# ── 2. Каталоги ───────────────────────────────────────────
step "Каталоги"
mkdir -p "$CLAUDE_DIR"/{hooks,skills,plans} "$MEM_DIR/searxng/settings" "$L2_DIR"
ok "$CLAUDE_DIR"

# ── 3. Секреты (.env) ─────────────────────────────────────
step "Секреты (.env)"
gen() { python3 -c "import secrets; print(secrets.token_hex(${1:-20}))"; }
if [ -f "$MEM_DIR/.env" ]; then
  ok ".env уже есть — не трогаю"
else
  : "${OPENAI_API_KEY:=}"; : "${GITHUB_PAT:=}"
  if [ $WITH_COGNEE -eq 1 ] && [ -z "$OPENAI_API_KEY" ]; then
    read -rsp "  OpenAI API key (нужен для Cognee): " OPENAI_API_KEY; echo
  fi
  if [ -z "$GITHUB_PAT" ]; then
    read -rsp "  GitHub PAT (scopes: repo/read:user/read:org; Enter = пропустить): " GITHUB_PAT; echo
  fi
  NEO4J_PW="$(gen 20)"; PG_PW="$(gen 20)"; SEARXNG_SECRET="$(gen 32)"
  cat > "$MEM_DIR/.env" <<EOF
# Секреты агента. chmod 600, НЕ коммитить.

# --- LLM & Embeddings (OpenAI) — нужны только для L4 Cognee ---
LLM_PROVIDER=openai
LLM_MODEL=gpt-4o-mini
LLM_API_KEY=${OPENAI_API_KEY}
EMBEDDING_PROVIDER=openai
EMBEDDING_MODEL=text-embedding-3-small
EMBEDDING_DIMENSIONS=1536
EMBEDDING_API_KEY=${OPENAI_API_KEY}

# --- Graph DB (Neo4j) ---
GRAPH_DATABASE_PROVIDER=neo4j
GRAPH_DATABASE_URL=bolt://localhost:7687
GRAPH_DATABASE_USERNAME=neo4j
GRAPH_DATABASE_PASSWORD=${NEO4J_PW}

# --- Vector DB (pgvector) ---
VECTOR_DB_PROVIDER=pgvector
VECTOR_DB_HOST=localhost
VECTOR_DB_PORT=5432
VECTOR_DB_USERNAME=cognee
VECTOR_DB_PASSWORD=${PG_PW}
VECTOR_DB_NAME=cognee

# --- Relational store (тот же Postgres) ---
DB_PROVIDER=postgres
DB_HOST=localhost
DB_PORT=5432
DB_USERNAME=cognee
DB_PASSWORD=${PG_PW}
DB_NAME=cognee

# --- GitHub MCP ---
GITHUB_PAT=${GITHUB_PAT}
GITHUB_PERSONAL_ACCESS_TOKEN=${GITHUB_PAT}

# --- SearXNG ---
SEARXNG_SECRET=${SEARXNG_SECRET}

# --- Single-agent: без мультитенантности ---
ENABLE_BACKEND_ACCESS_CONTROL=false
EOF
  chmod 600 "$MEM_DIR/.env"
  ok ".env создан, пароли сгенерированы"
fi
set -a; . "$MEM_DIR/.env"; set +a

# ── 4. Конфиги + хуки + скрипты ───────────────────────────
step "Конфиги, хуки, memory-system"
cp "$REPO_DIR/config/CLAUDE.md" "$CLAUDE_DIR/CLAUDE.md"
cp "$REPO_DIR/config/USER.md"   "$CLAUDE_DIR/USER.md"
[ -f "$CLAUDE_DIR/settings.json" ] && cp "$CLAUDE_DIR/settings.json" "$CLAUDE_DIR/settings.json.bak.$(date +%s)"
sed "s|CLAUDE_DIR|${CLAUDE_DIR}|g" "$REPO_DIR/config/settings.json" > "$CLAUDE_DIR/settings.json"
cp "$REPO_DIR/hooks/"*.sh "$CLAUDE_DIR/hooks/"; chmod +x "$CLAUDE_DIR/hooks/"*.sh
cp "$REPO_DIR/memory-system/"*.sh "$REPO_DIR/memory-system/"*.py "$MEM_DIR/"
cp "$REPO_DIR/memory-system/docker-compose.yml" "$MEM_DIR/"
chmod +x "$MEM_DIR/"*.sh
ok "CLAUDE.md, USER.md, settings.json, хуки, MCP-врапперы"

# SearXNG config — секрет подставляем из .env.
# Движки: на датацентровых IP Google/DDG/Startpage massively отдают капчу, а Brave —
# 429. Поэтому явно поднимаем те, что обычно живы (bing, mojeek, wikipedia, github),
# капчёвые оставляем включёнными на случай свежего IP, и щедро даём таймаут.
if [ $WITH_SEARXNG -eq 1 ] && [ ! -f "$MEM_DIR/searxng/settings/settings.yml" ]; then
  cat > "$MEM_DIR/searxng/settings/settings.yml" <<EOF
use_default_settings: true
general:
  debug: false
  instance_name: "local-searxng"
search:
  safe_search: 0
  autocomplete: ""
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
outgoing:
  request_timeout: 10.0
  max_request_timeout: 15.0
  pool_connections: 100
  pool_maxsize: 20
engines:
  - name: bing
    disabled: false
  - name: mojeek
    disabled: false
  - name: wikipedia
    disabled: false
  - name: wikidata
    disabled: false
  - name: github
    disabled: false
ui:
  default_locale: "ru"
  default_theme: "simple"
EOF
  ok "searxng settings.yml (пул движков под датацентровый IP)"
fi

# ── 5. Docker-контейнеры ──────────────────────────────────
step "Docker-контейнеры"
if [ $WITH_SEARXNG -eq 0 ] && [ $WITH_COGNEE -eq 0 ]; then
  ok "контейнеры не нужны — пропускаю"
else
cd "$MEM_DIR"
COMPOSE_SVC=""
[ $WITH_SEARXNG -eq 1 ] && COMPOSE_SVC="searxng"
COMPOSE_PROFILES=""
[ $WITH_COGNEE -eq 1 ] && COMPOSE_PROFILES="--profile cognee" && COMPOSE_SVC=""
$DOCKER compose $COMPOSE_PROFILES up -d $COMPOSE_SVC 2>&1 | grep -E "Started|Running|Created|Pulling" | head -10 || true

if [ $WITH_COGNEE -eq 1 ]; then
  echo "  жду healthy Neo4j + Postgres…"
  for _ in $(seq 1 24); do
    NEO=$($DOCKER inspect cognee-neo4j    --format '{{.State.Health.Status}}' 2>/dev/null || echo missing)
    PG=$( $DOCKER inspect cognee-postgres --format '{{.State.Health.Status}}' 2>/dev/null || echo missing)
    [ "$NEO" = healthy ] && [ "$PG" = healthy ] && break
    sleep 5
  done
  [ "${NEO:-}" = healthy ] && [ "${PG:-}" = healthy ] && ok "Neo4j + Postgres healthy" \
    || warn "БД не дошли до healthy — проверь: $DOCKER compose logs"
fi
if [ $WITH_SEARXNG -eq 1 ]; then
  for _ in $(seq 1 12); do curl -sf -o /dev/null "http://localhost:8080/" && break; sleep 5; done
  curl -sf -o /dev/null "http://localhost:8080/" && ok "SearXNG отвечает на :8080" || warn "SearXNG не отвечает"
fi
cd "$REPO_DIR"
fi

# ── 6. Python venv — РАЗДЕЛЬНЫЕ ───────────────────────────
# cognee и crawl4ai конфликтуют по зависимостям. Один venv на оба ставить нельзя.
step "Python venv"
if [ $WITH_CRAWL4AI -eq 1 ]; then
[ -d "$VENV_CRAWL" ] || uv venv --seed "$VENV_CRAWL" --python 3.12 >/dev/null 2>&1
"$VENV_CRAWL/bin/pip" -q install crawl4ai fastmcp httpx mcp 2>&1 | tail -2 || fail "crawl4ai не поставился"
"$VENV_CRAWL/bin/python" -m playwright install --with-deps chromium >/dev/null 2>&1 \
  || warn "playwright chromium не доустановился — fetch_url может падать"
if [ $WITH_DOCLING -eq 1 ]; then
  "$VENV_CRAWL/bin/pip" -q install docling 2>&1 | tail -2 && ok "docling (fetch_doc активен)" \
    || warn "docling не поставился — fetch_doc работать не будет"
fi
ok "venv-crawl4ai готов"
fi

# Playwright MCP тянет браузеры отдельно от crawl4ai — своя версия, свой кэш.
if [ $WITH_PLAYWRIGHT -eq 1 ]; then
  npx -y playwright@latest install --with-deps chromium >/dev/null 2>&1 \
    && ok "chromium для playwright MCP" || warn "chromium для playwright не доустановился"
fi

if [ $WITH_COGNEE -eq 1 ]; then
  [ -d "$VENV_COGNEE" ] || uv venv --seed "$VENV_COGNEE" --python 3.12 >/dev/null 2>&1
  "$VENV_COGNEE/bin/pip" -q install "cognee[postgres-binary]==1.1.0" cognee-mcp 2>&1 | tail -2 \
    || fail "cognee не поставился"
  ok "venv cognee готов"
fi

# ── 7. MCP-серверы ────────────────────────────────────────
step "Регистрация MCP"
reg() {
  local name="$1"; shift
  claude mcp remove "$name" --scope user >/dev/null 2>&1 || true
  claude mcp add "$name" --scope user "$@" >/dev/null 2>&1 && ok "MCP $name" || warn "MCP $name — не зарегистрирован"
}
[ $WITH_CRAWL4AI -eq 1 ] && reg crawl4ai -- "$MEM_DIR/crawl4ai-mcp-server.sh"
[ $WITH_SEARXNG -eq 1 ]  && reg searxng  -e SEARXNG_URL=http://localhost:8080 -- npx -y mcp-searxng
# --browser chromium обязателен: по умолчанию MCP ищет канал "chrome",
# то есть настоящий Google Chrome в /opt/google/chrome — на VPS его нет.
[ $WITH_PLAYWRIGHT -eq 1 ] && reg playwright -- npx -y @playwright/mcp@latest --headless --browser chromium
if [ -n "${GITHUB_PAT:-}" ]; then
  reg github -- "$MEM_DIR/github-mcp-server.sh"
else
  warn "MCP github пропущен — в .env нет GITHUB_PAT"
fi
[ $WITH_COGNEE -eq 1 ] && reg cognee -- "$MEM_DIR/cognee-mcp-server.sh"

# ── 8. Плагины ────────────────────────────────────────────
# Имя плагина ОБЯЗАТЕЛЬНО с @<маркетплейс>, иначе "plugin not found".
step "Плагины"
mp() { claude plugin marketplace add "$1" >/dev/null 2>&1 && ok "маркетплейс: $2" || warn "маркетплейс $2 — уже есть или недоступен"; }
pl() { claude plugin install "$1" >/dev/null 2>&1 && ok "плагин: $1" || warn "плагин $1 — не установился"; }
mp https://github.com/obra/superpowers.git  superpowers-dev
mp https://github.com/upstash/context7.git  context7-marketplace
pl superpowers@superpowers-dev
pl context7-plugin@context7-marketplace
if [ $WITH_UI_PLUGINS -eq 1 ]; then
  mp https://github.com/Dammyjay93/interface-design.git          interface-design
  mp https://github.com/nextlevelbuilder/ui-ux-pro-max-skill.git ui-ux-pro-max-skill
  pl interface-design@interface-design
  pl ui-ux-pro-max@ui-ux-pro-max-skill
fi

# Figma. Официальный путь — плагин из встроенного маркетплейса Anthropic
# (MCP + скиллы в комплекте). Если не встал — регистрируем remote MCP вручную.
# Dev Mode MCP тут не годится: он требует десктопное приложение Figma.
if [ $WITH_FIGMA -eq 0 ]; then
  FIGMA_MODE=""
elif claude plugin install figma@claude-plugins-official >/dev/null 2>&1; then
  ok "плагин: figma@claude-plugins-official"
  FIGMA_MODE="плагин"
else
  warn "плагин figma недоступен — ставлю remote MCP напрямую"
  claude mcp remove figma --scope user >/dev/null 2>&1 || true
  if claude mcp add --scope user --transport http figma https://mcp.figma.com/mcp >/dev/null 2>&1; then
    ok "MCP figma (remote, https://mcp.figma.com/mcp)"
    FIGMA_MODE="MCP"
  else
    warn "figma не подключился"
    FIGMA_MODE=""
  fi
fi

# ── 9. Внешние SKILL.md ───────────────────────────────────
if [ $WITH_SKILLS -eq 1 ]; then
  step "Внешние SKILL.md"
  SKILL_OK=0; SKILL_FAIL=0
  _skill() {
    local name="$1" url="$2" tmp
    tmp=$(mktemp)
    if curl -fsSL --max-time 20 "$url" -o "$tmp" 2>/dev/null && [ -s "$tmp" ]; then
      mkdir -p "$CLAUDE_DIR/skills/$name"; mv "$tmp" "$CLAUDE_DIR/skills/$name/SKILL.md"
      SKILL_OK=$((SKILL_OK+1))
    else
      rm -f "$tmp"; SKILL_FAIL=$((SKILL_FAIL+1)); echo "    ✗ $name"
    fi
  }
  A="https://raw.githubusercontent.com/anthropics/skills/main/skills"
  for s in frontend-design theme-factory brand-guidelines canvas-design skill-creator; do
    _skill "$s" "$A/$s/SKILL.md"; done
  T="https://raw.githubusercontent.com/Leonxlnx/taste-skill/main/skills"
  for s in taste-skill redesign-skill minimalist-skill soft-skill; do
    _skill "$s" "$T/$s/SKILL.md"; done
  W="https://raw.githubusercontent.com/wondelai/skills/main"
  for s in ux-heuristics refactoring-ui design-sprint hooked-ux microinteractions top-design web-typography; do
    _skill "$s" "$W/$s/SKILL.md"; done
  V="https://raw.githubusercontent.com/vercel-labs/agent-skills/main/skills"
  _skill web-design-guidelines "$V/web-design-guidelines/SKILL.md"
  _skill react-best-practices  "$V/react-best-practices/SKILL.md"
  # find-skills живёт в ДРУГОМ репо (vercel-labs/skills), не в agent-skills.
  # Даёт агенту умение искать скиллы в реестре skills.sh: "найди скилл для SEO".
  _skill find-skills "https://raw.githubusercontent.com/vercel-labs/skills/main/skills/find-skills/SKILL.md"
  ok "скачано $SKILL_OK, недоступно $SKILL_FAIL"
fi

# Собственные скиллы из репо
for s in self-compiler onboarding-conductor present; do
  if [ -f "$REPO_DIR/skills/$s/SKILL.md" ]; then
    mkdir -p "$CLAUDE_DIR/skills/$s"; cp "$REPO_DIR/skills/$s/SKILL.md" "$CLAUDE_DIR/skills/$s/"
  fi
done
ok "локальные скиллы: self-compiler, onboarding-conductor, present"

# ── 10. Смоук-тесты: инструменты должны работать СРАЗУ ─────
step "Смоук-тесты"
PASS=0; FAIL=0
tpass(){ echo -e "  ${GREEN}✓${NC} $1"; PASS=$((PASS+1)); }
tfail(){ echo -e "  ${RED}✗${NC} $1"; FAIL=$((FAIL+1)); }

# github: токен валиден и видит публичные репозитории
if [ -n "${GITHUB_PAT:-}" ]; then
  GH_USER=$(curl -sf --max-time 20 -H "Authorization: Bearer $GITHUB_PAT" \
            https://api.github.com/user 2>/dev/null | python3 -c "import sys,json;print(json.load(sys.stdin).get('login',''))" 2>/dev/null || echo "")
  if [ -n "$GH_USER" ]; then
    GH_CNT=$(curl -sf --max-time 20 -H "Authorization: Bearer $GITHUB_PAT" \
             "https://api.github.com/search/repositories?q=claude+code&per_page=1" 2>/dev/null \
             | python3 -c "import sys,json;print(json.load(sys.stdin).get('total_count',0))" 2>/dev/null || echo 0)
    [ "${GH_CNT:-0}" -gt 0 ] && tpass "github: токен ок (юзер $GH_USER), поиск публичных репо — $GH_CNT совпадений" \
                             || tfail "github: токен принят, но поиск репозиториев не работает"
  else
    tfail "github: токен отклонён (истёк или не те scopes)"
  fi
fi

# searxng: реальный поиск + какие движки живы
if [ $WITH_SEARXNG -eq 1 ]; then
  SRX=$(curl -sf --max-time 40 "http://localhost:8080/search?q=nginx&format=json" 2>/dev/null || echo "")
  if [ -n "$SRX" ]; then
    N=$(printf '%s' "$SRX" | python3 -c "import sys,json;print(len(json.load(sys.stdin).get('results',[])))" 2>/dev/null || echo 0)
    if [ "${N:-0}" -gt 0 ]; then
      tpass "searxng: поиск вернул $N результатов"
    else
      tfail "searxng: 0 результатов — движки блокируют IP этого сервера"
      printf '%s' "$SRX" | python3 -c "
import sys,json
for e in (json.load(sys.stdin).get('unresponsive_engines') or []): print('      -', e[0], ':', e[1])" 2>/dev/null || true
      echo "      Лечится: дождаться снятия бана, сменить IP или включить движки с API-ключом."
      echo "      Пока не чинится — агент будет ходить в веб через crawl4ai."
    fi
  else
    tfail "searxng: не отвечает на :8080"
  fi
fi

# crawl4ai: реальная выкачка страницы
if [ $WITH_CRAWL4AI -eq 1 ]; then
  C4=$("$VENV_CRAWL/bin/python" - <<'PYEOF' 2>/dev/null || echo FAIL
import asyncio
from crawl4ai import AsyncWebCrawler, BrowserConfig, CrawlerRunConfig, CacheMode
async def m():
    async with AsyncWebCrawler(config=BrowserConfig(headless=True, verbose=False)) as c:
        r = await c.arun(url="https://example.com", config=CrawlerRunConfig(cache_mode=CacheMode.BYPASS))
        print("OK" if r.success and r.markdown else "FAIL")
asyncio.run(m())
PYEOF
)
  [ "$C4" = "OK" ] && tpass "crawl4ai: example.com выкачан в markdown" \
                   || tfail "crawl4ai: не смог выкачать страницу (chromium?)"
fi

# playwright: проверяем сам бинарь браузера из кэша ms-playwright.
# Через `node -e` нельзя: npx ставит пакет во временный каталог, require его не найдёт.
if [ $WITH_PLAYWRIGHT -eq 1 ]; then
  PW_BIN=$(find "$HOME/.cache/ms-playwright" -type f \( -name headless_shell -o -name chrome \) 2>/dev/null | head -1)
  if [ -n "$PW_BIN" ] && "$PW_BIN" --version >/dev/null 2>&1; then
    tpass "playwright: $("$PW_BIN" --version 2>/dev/null | head -1) запускается"
  elif [ -n "$PW_BIN" ]; then
    tfail "playwright: браузер есть, но не стартует — не хватает системных библиотек"
    echo "      Лечится: npx -y playwright@latest install-deps chromium"
  else
    tfail "playwright: браузер не установлен"
    echo "      Лечится: npx -y playwright@latest install --with-deps chromium"
  fi
fi

# cognee: полный round-trip
if [ $WITH_COGNEE -eq 1 ]; then
  CG=$(cd "$MEM_DIR" && timeout 300 ./venv/bin/python - <<'PYEOF' 2>/dev/null || echo FAIL
import asyncio, cognee
async def m():
    await cognee.add("Смоук-тест: агент развёрнут и память работает.")
    await cognee.cognify()
    r = await cognee.search("смоук-тест")
    print("OK" if r else "FAIL")
asyncio.run(m())
PYEOF
)
  [ "$CG" = "OK" ] && tpass "cognee: add → cognify → search прошёл" \
                   || tfail "cognee: round-trip не прошёл (частая причина — пустой баланс OpenAI, ошибка 429)"
fi

echo
echo "  MCP-серверы:"; claude mcp list 2>&1 | tail -n +2 | head -10
echo "  Контейнеры:";  $DOCKER ps --format '    {{.Names}}\t{{.Status}}' 2>/dev/null || true
echo "  Скиллов:      $(ls "$CLAUDE_DIR/skills/" 2>/dev/null | wc -l)"
echo
echo -e "  Тесты: ${GREEN}$PASS пройдено${NC}$([ $FAIL -gt 0 ] && echo -e ", ${RED}$FAIL провалено${NC}")"

echo
echo -e "${GREEN}════════════════════════════════════════${NC}"
echo -e "${GREEN} Установка завершена${NC}"
echo -e "${GREEN}════════════════════════════════════════${NC}"
cat <<EOF

Дальше:
  1. sudo reboot         — закрепит группу docker и автоподъём контейнеров
  2. claude              — новая сессия, MCP подхватятся
  3. /onboarding-conductor — заполнить профиль в USER.md

EOF
if [ -n "${FIGMA_MODE:-}" ]; then
  cat <<'EOF'
  Figma требует разовой авторизации (автоматом нельзя — нужен браузер):
    claude → /mcp → figma → Authenticate → открыть ссылку в своём браузере → Allow Access

EOF
fi
echo "  Поиск скиллов: скажи агенту «найди скилл для SEO-оптимизации» (скилл find-skills + npx skills find)"
echo
[ $WITH_COGNEE -eq 0 ] && echo "  L4 Cognee не ставился. Добавить позже: bash install.sh --with-cognee"
[ -z "${GITHUB_PAT:-}" ] && echo "  GitHub PAT не задан — впиши в $MEM_DIR/.env и перерегистрируй MCP github"
exit 0
