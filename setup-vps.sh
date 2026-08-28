#!/usr/bin/env bash
# ============================================================================
# setup-vps.sh — развёртывание агентской среды на чистом VPS. ОДНА КОМАНДА, ОТ ROOT.
#
#   curl -fsSL https://raw.githubusercontent.com/YLisov/claude-vps-autoinstall/main/setup-vps.sh | bash
#
# Делает: hostname → расширение диска → юзер+sudo+ssh → Docker/Node/uv →
#         Claude Code → MCP/плагины/скиллы → смоук-тесты.
# Все вопросы задаются в начале, дальше скрипт работает сам.
# Секреты спрашиваются здесь и пишутся только в ~/.claude/memory-system/.env (chmod 600).
# Идемпотентен: повторный запуск ничего не ломает.
# ============================================================================
set -euo pipefail

SELF_URL="${SELF_URL:-https://raw.githubusercontent.com/YLisov/claude-vps-autoinstall/main/setup-vps.sh}"

# При `curl ... | bash` сам скрипт приходит через stdin. Скрипту нужен stdin для
# вопросов, но забрать его (exec </dev/tty) нельзя: bash не дочитает собственный
# исходник и начнёт исполнять ввод пользователя как команды. Поэтому скачиваем
# себя в файл и перезапускаемся оттуда — тогда stdin свободен под диалог.
if [ ! -t 0 ] && [ -z "${SETUP_VPS_REEXEC:-}" ]; then
  _tmp="$(mktemp /tmp/setup-vps.XXXXXX.sh)"
  if command -v curl >/dev/null 2>&1 && curl -fsSL "$SELF_URL" -o "$_tmp" 2>/dev/null && [ -s "$_tmp" ]; then
    export SETUP_VPS_REEXEC=1
    exec bash "$_tmp" "$@" </dev/tty
  fi
  rm -f "$_tmp"
  echo "Скрипт запущен через пайп, а ему нужен диалог с тобой." >&2
  echo "Запусти так:" >&2
  echo "  curl -fsSL $SELF_URL -o setup-vps.sh && bash setup-vps.sh" >&2
  exit 1
fi

REPO_URL="${REPO_URL:-https://github.com/YLisov/claude-vps-autoinstall.git}"
REPO_BRANCH="${REPO_BRANCH:-main}"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; BOLD='\033[1m'; NC='\033[0m'
ok()   { echo -e "${GREEN}✓${NC} $1"; }
warn() { echo -e "${YELLOW}⚠${NC}  $1"; }
fail() { echo -e "${RED}✗${NC} $1"; exit 1; }
step() { echo -e "\n${BLUE}▶${NC} ${BOLD}$1${NC}"; }
ask()  { local p="$1" d="${2:-}" r; read -rp "$(echo -e "  ${BOLD}$p${NC}${d:+ [$d]}: ")" r </dev/tty; echo "${r:-$d}"; }
yes_no(){ local p="$1" d="${2:-y}" r; r=$(ask "$p (y/n)" "$d"); [[ "$r" =~ ^[Yy] ]]; }

[ "$(id -u)" -eq 0 ] || fail "Запускать от root."
[ -f /etc/os-release ] || fail "Не Linux?"
. /etc/os-release
[[ "$ID" == "ubuntu" || "$ID" == "debian" ]] || warn "Скрипт рассчитан на Ubuntu/Debian, у тебя $ID — продолжаю на свой страх"

clear 2>/dev/null || true
cat <<'BANNER'
╔══════════════════════════════════════════════════════════╗
║        Claude Agent VPS — развёртывание с нуля           ║
╚══════════════════════════════════════════════════════════╝
BANNER
echo "  Сначала несколько вопросов, потом скрипт работает сам."
echo

# ══════════════════════════════════════════════════════════
#  ОПРОС
# ══════════════════════════════════════════════════════════
step "1/5 · Hostname"
CUR_HOST="$(hostname)"
echo "  Сейчас: $CUR_HOST"
NEW_HOST="$(ask 'Новый hostname (Enter = не менять)' "$CUR_HOST")"

step "2/5 · Диск"
ROOT_SRC="$(findmnt -no SOURCE / 2>/dev/null || echo '')"
ROOT_FS="$(findmnt -no FSTYPE / 2>/dev/null || echo '')"
DISK_FREE="$(df -h / | awk 'NR==2{print $2" всего, "$4" свободно"}')"
echo "  Корень: $ROOT_SRC ($ROOT_FS) — $DISK_FREE"
DO_RESIZE=0
if [[ "$ROOT_SRC" == /dev/mapper/* ]] || [[ "$ROOT_SRC" == *"vg"* ]]; then
  warn "Похоже на LVM — автоматическое расширение пропускаю (нужно pvresize/lvextend вручную)"
elif [ -n "$ROOT_SRC" ]; then
  PART_NUM="$(echo "$ROOT_SRC" | grep -oE '[0-9]+$' || true)"
  PARENT_DISK="/dev/$(lsblk -no PKNAME "$ROOT_SRC" 2>/dev/null | head -1)"
  if [ -n "$PART_NUM" ] && [ -b "$PARENT_DISK" ]; then
    DISK_TOTAL=$(lsblk -bno SIZE "$PARENT_DISK" | head -1)
    PART_TOTAL=$(lsblk -bno SIZE "$ROOT_SRC" | head -1)
    UNUSED=$(( (DISK_TOTAL - PART_TOTAL) / 1024 / 1024 ))
    if [ "$UNUSED" -gt 1024 ]; then
      echo -e "  ${YELLOW}На диске $PARENT_DISK не занято ~${UNUSED} МБ${NC} — раздел можно расширить."
      yes_no "  Расширить $ROOT_SRC на весь диск?" y && DO_RESIZE=1
    else
      ok "диск уже расширен полностью — нечего делать"
    fi
  else
    warn "не смог определить родительский диск для $ROOT_SRC — пропускаю"
  fi
fi

step "3/5 · Пользователь агента"
AGENT_USER="$(ask 'Имя пользователя' 'claude')"
[[ "$AGENT_USER" =~ ^[a-z_][a-z0-9_-]*$ ]] || fail "Недопустимое имя пользователя: $AGENT_USER"
ROOT_KEYS=$(grep -cvE '^[[:space:]]*(#|$)' /root/.ssh/authorized_keys 2>/dev/null || echo 0)
if [ "${ROOT_KEYS:-0}" -gt 0 ]; then
  ok "SSH: скопирую ключи root ($ROOT_KEYS шт.) — зайдёшь под $AGENT_USER тем же ключом"
else
  warn "у root нет SSH-ключей — зайти под $AGENT_USER по ключу будет нечем"
  echo "     Можно передать свой:  EXTRA_SSH_KEY='ssh-ed25519 AAAA...' bash setup-vps.sh"
fi

step "4/5 · Набор инструментов"
cat <<'MENU'
  1) Полный      — github, crawl4ai, searxng, playwright, figma
                   + плагины (superpowers, context7, interface-design, ui-ux-pro-max) + скиллы
  2) Базовый     — github, crawl4ai, searxng + superpowers, context7 + скиллы
  3) Минимальный — github, crawl4ai + superpowers. Без Docker-контейнеров
  4) Свой набор
MENU
PRESET="$(ask 'Выбор' '1')"
W_GITHUB=1; W_CRAWL4AI=1; W_SEARXNG=1; W_PLAYWRIGHT=1; W_FIGMA=1
W_PLUGINS=1; W_UIPLUGINS=1; W_SKILLS=1; W_COGNEE=0; W_DOCLING=0
case "$PRESET" in
  2) W_PLAYWRIGHT=0; W_FIGMA=0; W_UIPLUGINS=0 ;;
  3) W_SEARXNG=0; W_PLAYWRIGHT=0; W_FIGMA=0; W_UIPLUGINS=0; W_SKILLS=0 ;;
  4)
    yes_no "  github MCP (поиск репозиториев, код, issues)" y      || W_GITHUB=0
    yes_no "  crawl4ai MCP (URL → чистый markdown)" y              || W_CRAWL4AI=0
    yes_no "  searxng MCP (свой поиск, Docker)" y                  || W_SEARXNG=0
    yes_no "  playwright MCP (headless-браузер)" y                 || W_PLAYWRIGHT=0
    yes_no "  figma MCP (макеты → код, remote+OAuth)" y            || W_FIGMA=0
    yes_no "  UI-плагины (interface-design, ui-ux-pro-max)" y      || W_UIPLUGINS=0
    yes_no "  Внешние скиллы (~19 SKILL.md, вкл. find-skills)" y   || W_SKILLS=0
    yes_no "  docling — fetch_doc для PDF/DOCX (+~2 ГБ, torch)" n  && W_DOCLING=1
    ;;
esac
RAM_GB=$(( $(grep MemTotal /proc/meminfo | awk '{print $2}') / 1024 / 1024 ))
echo
echo "  L4 Cognee — семантическая память (Neo4j + pgvector)."
echo "  Нужно ~4,5 ГБ RAM (у тебя ${RAM_GB} ГБ) и OpenAI-ключ с балансом."
if [ "$RAM_GB" -lt 6 ]; then
  warn "меньше 6 ГБ RAM — Cognee не рекомендую"
  yes_no "  Всё равно ставить Cognee?" n && W_COGNEE=1
else
  yes_no "  Ставить Cognee?" n && W_COGNEE=1
fi

step "5/5 · Ключи доступа"
echo "  Пишутся только в /home/$AGENT_USER/.claude/memory-system/.env (chmod 600)."
echo "  В репозиторий не попадают и в выводе ps не светятся."
echo
GITHUB_PAT=""; OPENAI_API_KEY=""
if [ $W_GITHUB -eq 1 ]; then
  cat <<'GHHELP'

  ── GitHub PAT ──────────────────────────────────────────────────────
  Зачем: агент сможет искать по репозиториям и коду, читать issues и PR.
  Токен нужен даже для публичных репозиториев — без него GitHub отдаёт
  лишь 60 запросов в час, и MCP-сервер откажется работать.

  Как получить, это минута:

    1. Открой в браузере ссылку — нужные галочки в ней уже проставлены:

       https://github.com/settings/tokens/new?scopes=repo,read:user,read:org&description=Claude+Agent+VPS

    2. Пролистай вниз и нажми зелёную кнопку «Generate token»
    3. Скопируй строку вида ghp_xxxxxxxxxxxx — GitHub покажет её ОДИН раз
    4. Вставь сюда: правый клик или Ctrl+Shift+V

  Ввод скрыт — символы на экране не появятся, так и задумано.
  Можно пропустить (просто Enter) и вписать токен позже в .env.

GHHELP
  for _try in 1 2 3; do
    read -rsp "  GitHub PAT: " GITHUB_PAT </dev/tty; echo
    if [ -z "$GITHUB_PAT" ]; then
      warn "пропущено — github MCP не будет установлен"; W_GITHUB=0; break
    fi
    printf "  проверяю токен… "
    GH_LOGIN=$(curl -sf --max-time 20 -H "Authorization: Bearer $GITHUB_PAT" \
               https://api.github.com/user 2>/dev/null \
               | python3 -c "import sys,json;print(json.load(sys.stdin).get('login',''))" 2>/dev/null || echo "")
    if [ -n "$GH_LOGIN" ]; then
      echo -e "${GREEN}принят${NC} — аккаунт ${BOLD}$GH_LOGIN${NC}"
      break
    fi
    echo -e "${RED}не принят${NC}"
    if [ "$_try" -lt 3 ]; then
      echo "    Скорее всего скопирована не вся строка. Токен начинается с ghp_"
      echo "    и содержит около 40 символов. Попробуй ещё раз."
    else
      warn "три попытки подряд не прошли — ставлю без github MCP"
      echo "    Добавишь позже: впиши GITHUB_PAT в ~$AGENT_USER/.claude/memory-system/.env"
      echo "    и выполни: cd ~/claude-installer && bash install.sh"
      W_GITHUB=0; GITHUB_PAT=""
    fi
  done
fi
if [ $W_COGNEE -eq 1 ]; then
  cat <<'OAHELP'

  ── OpenAI API key ──────────────────────────────────────────────────
  Зачем: Cognee строит граф памяти через gpt-4o-mini и делает эмбеддинги
  через text-embedding-3-small. Без ключа L4-память не заработает.

    1. Открой https://platform.openai.com/api-keys
    2. Нажми «Create new secret key», скопируй строку вида sk-proj-...
    3. Убедись, что на аккаунте есть баланс: при нуле запросы падают
       с ошибкой 429, и Cognee молча зависает на таймауте

  Ввод скрыт — символы на экране не появятся.

OAHELP
  for _try in 1 2; do
    read -rsp "  OpenAI API key: " OPENAI_API_KEY </dev/tty; echo
    if [ -z "$OPENAI_API_KEY" ]; then
      warn "без ключа Cognee не заработает — выключаю L4"; W_COGNEE=0; break
    fi
    printf "  проверяю ключ… "
    if curl -sf --max-time 20 -H "Authorization: Bearer $OPENAI_API_KEY" \
         https://api.openai.com/v1/models >/dev/null 2>&1; then
      echo -e "${GREEN}принят${NC}"; break
    fi
    echo -e "${RED}не принят${NC}"
    if [ "$_try" -lt 2 ]; then
      echo "    Проверь, что скопирована вся строка целиком."
    else
      warn "ключ не прошёл проверку — ставлю без Cognee"
      W_COGNEE=0; OPENAI_API_KEY=""
    fi
  done
fi

EXTRA_SSH_KEY="${EXTRA_SSH_KEY:-}"

# ── Сводка ────────────────────────────────────────────────
echo
echo -e "${BOLD}  Что будет сделано:${NC}"
[ "$NEW_HOST" != "$CUR_HOST" ] && echo "    hostname:    $CUR_HOST → $NEW_HOST" || echo "    hostname:    без изменений"
[ $DO_RESIZE -eq 1 ] && echo "    диск:        расширить $ROOT_SRC" || echo "    диск:        без изменений"
echo "    юзер:        $AGENT_USER (sudo без пароля, группа docker)"
if [ "${ROOT_KEYS:-0}" -gt 0 ]; then
  echo "    SSH-доступ:  ключи root ($ROOT_KEYS шт.)$([ -n "$EXTRA_SSH_KEY" ] && echo ' + переданный ключ')"
else
  echo "    SSH-доступ:  $([ -n "$EXTRA_SSH_KEY" ] && echo 'только переданный ключ' || echo 'КЛЮЧЕЙ НЕТ — вход будет невозможен')"
fi
echo -n "    MCP:        "
  [ $W_GITHUB -eq 1 ]     && echo -n " github"
  [ $W_CRAWL4AI -eq 1 ]   && echo -n " crawl4ai"
  [ $W_SEARXNG -eq 1 ]    && echo -n " searxng"
  [ $W_PLAYWRIGHT -eq 1 ] && echo -n " playwright"
  [ $W_FIGMA -eq 1 ]      && echo -n " figma"
  [ $W_COGNEE -eq 1 ]     && echo -n " cognee"
  echo
echo "    скиллы:      $([ $W_SKILLS -eq 1 ] && echo 'да (~19)' || echo 'нет')"
echo "    Cognee L4:   $([ $W_COGNEE -eq 1 ] && echo 'да' || echo 'нет')"
echo
yes_no "Начинать?" y || { echo "Отменено."; exit 0; }

START_TS=$(date +%s)

# ══════════════════════════════════════════════════════════
#  ВЫПОЛНЕНИЕ
# ══════════════════════════════════════════════════════════
export DEBIAN_FRONTEND=noninteractive

step "Базовые пакеты"
apt-get update -qq
apt-get install -y -qq --no-install-recommends \
  curl ca-certificates git ripgrep jq fzf tmux \
  python3 python3-venv python3-pip build-essential \
  cloud-guest-utils >/dev/null
ok "curl, git, ripgrep, jq, fzf, tmux, python3, build-essential"

# ── Hostname ──────────────────────────────────────────────
if [ "$NEW_HOST" != "$CUR_HOST" ]; then
  step "Hostname"
  hostnamectl set-hostname "$NEW_HOST"
  # /etc/hosts: чтобы sudo не ругался на неразрешимое имя
  if grep -qE "^127\.0\.1\.1" /etc/hosts; then
    sed -i -E "s|^(127\.0\.1\.1\s+).*|\1$NEW_HOST|" /etc/hosts
  else
    echo "127.0.1.1	$NEW_HOST" >> /etc/hosts
  fi
  ok "hostname: $CUR_HOST → $NEW_HOST"
fi

# ── Расширение диска ──────────────────────────────────────
if [ $DO_RESIZE -eq 1 ]; then
  step "Расширение диска"
  echo "  до: $(df -h / | awk 'NR==2{print $2" ("$5" занято)"}')"
  if growpart "$PARENT_DISK" "$PART_NUM" 2>&1 | grep -vq NOCHANGE; then
    ok "раздел $ROOT_SRC расширен"
  else
    warn "growpart: изменений нет"
  fi
  case "$ROOT_FS" in
    ext2|ext3|ext4) resize2fs "$ROOT_SRC" >/dev/null 2>&1 && ok "ФС ext расширена" || warn "resize2fs не сработал" ;;
    xfs)            xfs_growfs / >/dev/null 2>&1 && ok "ФС xfs расширена" || warn "xfs_growfs не сработал" ;;
    btrfs)          btrfs filesystem resize max / >/dev/null 2>&1 && ok "ФС btrfs расширена" || warn "resize не сработал" ;;
    *)              warn "неизвестная ФС $ROOT_FS — расширь вручную" ;;
  esac
  echo "  после: $(df -h / | awk 'NR==2{print $2" ("$5" занято)"}')"
fi

# ── Пользователь ──────────────────────────────────────────
step "Пользователь $AGENT_USER"
if id "$AGENT_USER" &>/dev/null; then
  ok "$AGENT_USER уже существует"
else
  adduser --disabled-password --gecos "" "$AGENT_USER" >/dev/null
  ok "создан $AGENT_USER (пароль отключён, вход по ключу)"
fi
usermod -aG sudo "$AGENT_USER"
printf '%s ALL=(ALL) NOPASSWD: ALL\n' "$AGENT_USER" > "/etc/sudoers.d/90-$AGENT_USER"
chmod 440 "/etc/sudoers.d/90-$AGENT_USER"
visudo -cf "/etc/sudoers.d/90-$AGENT_USER" >/dev/null || fail "sudoers-файл невалиден"
ok "sudo без пароля"

HOME_DIR="$(getent passwd "$AGENT_USER" | cut -d: -f6)"
install -d -m700 -o "$AGENT_USER" -g "$AGENT_USER" "$HOME_DIR/.ssh"
AUTH="$HOME_DIR/.ssh/authorized_keys"; touch "$AUTH"
if [ -f /root/.ssh/authorized_keys ]; then
  while IFS= read -r key; do
    [ -z "$key" ] && continue; case "$key" in \#*) continue ;; esac
    grep -qxF "$key" "$AUTH" || echo "$key" >> "$AUTH"
  done < /root/.ssh/authorized_keys
  ok "SSH-ключи root перенесены"
else
  warn "у root нет authorized_keys"
fi
if [ -n "$EXTRA_SSH_KEY" ]; then
  grep -qxF "$EXTRA_SSH_KEY" "$AUTH" || echo "$EXTRA_SSH_KEY" >> "$AUTH"
  ok "доп. SSH-ключ добавлен"
fi
chown -R "$AGENT_USER:$AGENT_USER" "$HOME_DIR/.ssh"; chmod 600 "$AUTH"
[ -s "$AUTH" ] || warn "authorized_keys ПУСТ — под $AGENT_USER по ключу не зайти!"

# ── Docker + Node ─────────────────────────────────────────
step "Docker"
if command -v docker >/dev/null; then
  ok "уже стоит: $(docker --version | cut -d' ' -f3 | tr -d ',')"
else
  curl -fsSL https://get.docker.com | sh >/dev/null 2>&1
  ok "установлен"
fi
systemctl enable --now docker >/dev/null 2>&1 || warn "не удалось включить docker"
usermod -aG docker "$AGENT_USER"; ok "$AGENT_USER в группе docker"

step "Node.js"
NODE_VER=$(node --version 2>/dev/null | sed 's/v//' | cut -d. -f1 || echo 0)
if [ "${NODE_VER:-0}" -lt 20 ] 2>/dev/null; then
  curl -fsSL https://deb.nodesource.com/setup_22.x | bash - >/dev/null 2>&1
  apt-get install -y -qq nodejs >/dev/null
fi
ok "Node.js $(node --version)"

# ── Репозиторий + Claude Code (от юзера) ──────────────────
step "Репозиторий установщика"
INST_DIR="$HOME_DIR/claude-installer"
if [ -d "$INST_DIR/.git" ]; then
  sudo -u "$AGENT_USER" git -C "$INST_DIR" pull --ff-only >/dev/null 2>&1 || warn "git pull не прошёл, беру что есть"
  ok "обновлён $INST_DIR"
else
  # если скрипт запущен из уже склонированного репо — копируем локальную версию
  SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd || echo '')"
  if [ -n "$SELF_DIR" ] && [ -f "$SELF_DIR/install.sh" ]; then
    cp -r "$SELF_DIR" "$INST_DIR"; chown -R "$AGENT_USER:$AGENT_USER" "$INST_DIR"
    ok "скопирован из $SELF_DIR"
  else
    sudo -u "$AGENT_USER" git clone -q --branch "$REPO_BRANCH" "$REPO_URL" "$INST_DIR" \
      || fail "не смог склонировать $REPO_URL"
    ok "склонирован в $INST_DIR"
  fi
fi

step "Claude Code"
if sudo -u "$AGENT_USER" bash -lc 'command -v claude' >/dev/null 2>&1; then
  ok "уже стоит: $(sudo -u "$AGENT_USER" bash -lc 'claude --version' 2>/dev/null | head -1)"
else
  sudo -u "$AGENT_USER" bash -lc 'curl -fsSL https://claude.ai/install.sh | bash' >/dev/null 2>&1 || true
  sudo -u "$AGENT_USER" bash -lc 'grep -q ".local/bin" ~/.bashrc || echo "export PATH=\"\$HOME/.local/bin:\$PATH\"" >> ~/.bashrc'
  if sudo -u "$AGENT_USER" bash -lc 'export PATH="$HOME/.local/bin:$PATH"; command -v claude' >/dev/null 2>&1; then
    ok "установлен: $(sudo -u "$AGENT_USER" bash -lc 'export PATH="$HOME/.local/bin:$PATH"; claude --version' 2>/dev/null | head -1)"
  else
    fail "Claude Code не установился. Если видел segfault про AVX — в гипервизоре нужен CPU=host."
  fi
fi

# ── Секреты: пишем файлом, не через argv (иначе видно в ps) ─
step "Секреты"
MEM_DIR="$HOME_DIR/.claude/memory-system"
install -d -m755 -o "$AGENT_USER" -g "$AGENT_USER" "$HOME_DIR/.claude" "$MEM_DIR"
if [ -f "$MEM_DIR/.env" ]; then
  ok ".env уже есть — не трогаю"
else
  NEO4J_PW="$(python3 -c 'import secrets;print(secrets.token_hex(20))')"
  PG_PW="$(python3 -c 'import secrets;print(secrets.token_hex(20))')"
  SRX_SECRET="$(python3 -c 'import secrets;print(secrets.token_hex(32))')"
  umask 077
  cat > "$MEM_DIR/.env" <<EOF
# Секреты агента. chmod 600. НЕ коммитить — этот путь в .gitignore.

# --- LLM & Embeddings (нужны только для L4 Cognee) ---
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

# --- Vector DB (pgvector) — cognee читает именно *_NAME ---
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
SEARXNG_SECRET=${SRX_SECRET}

ENABLE_BACKEND_ACCESS_CONTROL=false
EOF
  umask 022
  chown "$AGENT_USER:$AGENT_USER" "$MEM_DIR/.env"; chmod 600 "$MEM_DIR/.env"
  ok ".env создан (chmod 600), пароли БД сгенерированы"
fi
unset OPENAI_API_KEY GITHUB_PAT

# ── Пользовательская часть ────────────────────────────────
step "Установка окружения (от $AGENT_USER)"
FLAGS=""
[ $W_COGNEE -eq 1 ]     && FLAGS="$FLAGS --with-cognee"
[ $W_DOCLING -eq 1 ]    && FLAGS="$FLAGS --with-docling"
[ $W_SKILLS -eq 0 ]     && FLAGS="$FLAGS --no-skills"
[ $W_SEARXNG -eq 0 ]    && FLAGS="$FLAGS --no-searxng"
[ $W_PLAYWRIGHT -eq 0 ] && FLAGS="$FLAGS --no-playwright"
[ $W_FIGMA -eq 0 ]      && FLAGS="$FLAGS --no-figma"
[ $W_CRAWL4AI -eq 0 ]   && FLAGS="$FLAGS --no-crawl4ai"
[ $W_UIPLUGINS -eq 0 ]  && FLAGS="$FLAGS --no-ui-plugins"
echo "  install.sh$FLAGS"
echo
sudo -u "$AGENT_USER" bash -lc "cd '$INST_DIR' && export PATH=\"\$HOME/.local/bin:\$PATH\" && bash install.sh$FLAGS" \
  || warn "install.sh отработал с ошибками — смотри вывод выше"

# ── Итог ──────────────────────────────────────────────────
ELAPSED=$(( ($(date +%s) - START_TS) / 60 ))
echo
echo -e "${GREEN}══════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}${BOLD} Готово за ~${ELAPSED} мин${NC}"
echo -e "${GREEN}══════════════════════════════════════════════════════════${NC}"
cat <<EOF

  Подключайся и начинай работу:

    ssh $AGENT_USER@$(hostname -I 2>/dev/null | awk '{print $1}')
    claude

  При первом запуске claude попросит авторизацию — откроешь ссылку в браузере.
  Затем скажи агенту:  /onboarding-conductor

EOF
[ $W_FIGMA -eq 1 ] && cat <<'EOF'
  Figma требует разовой авторизации (OAuth, автоматом нельзя):
    /mcp → figma → Authenticate → ссылка в браузере → Allow Access

EOF
echo "  Перелогинься или сделай 'sudo reboot', чтобы применилась группа docker."
echo
