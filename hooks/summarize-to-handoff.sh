#!/usr/bin/env bash
# Общий суммаризатор для SessionEnd и PreCompact (L3 continuity).
# Читает JSON хука со stdin, берёт хвост транскрипта, делает краткий handoff
# через Haiku (дёшево, 1 вызов) и пишет его в handoff.md.
# Запускается с async:true — не блокирует Claude.

# --- Защита от рекурсии: дочерний `claude -p` тоже триггерит хуки ---
if [ -n "${MEMORY_SUMMARIZER:-}" ]; then
  exit 0
fi

export PATH="$HOME/.local/bin:$PATH"
MEM="$HOME/.claude/memory-system"
HANDOFF="$MEM/handoff.md"
LOG="$MEM/hooks.log"
HAIKU="claude-haiku-4-5-20251001"

input=$(cat 2>/dev/null || true)
transcript=$(printf '%s' "$input" | python3 -c 'import sys,json
try:
    print(json.load(sys.stdin).get("transcript_path",""))
except Exception:
    print("")' 2>/dev/null || true)

if [ -z "$transcript" ] || [ ! -f "$transcript" ]; then
  echo "$(date -Is) summarize: no transcript_path" >>"$LOG"
  exit 0
fi

tail_text=$(tail -n 200 "$transcript" 2>/dev/null | tail -c 24000 || true)
if [ -z "$tail_text" ]; then
  echo "$(date -Is) summarize: empty transcript tail" >>"$LOG"
  exit 0
fi

prompt="Ниже хвост транскрипта сессии Claude Code (формат JSONL). Сделай краткий handoff на русском (<=250 слов): чем занимались, что сделано, что осталось и следующие шаги, важные пути/команды/решения. Только сводка, без преамбулы и без markdown-заголовка верхнего уровня.

$tail_text"

summary=$(MEMORY_SUMMARIZER=1 timeout 120 claude -p --model "$HAIKU" "$prompt" 2>>"$LOG" || true)

if [ -n "$summary" ]; then
  {
    echo "# Handoff — $(date -Is)"
    echo
    echo "$summary"
  } >"$HANDOFF"
  echo "$(date -Is) summarize: handoff updated ($(printf '%s' "$summary" | wc -c) bytes)" >>"$LOG"

  # L4 авто-захват (balanced): одна значимая сводка сессии → Cognee (add + cognify)
  if [ -x "$MEM/venv/bin/python" ]; then
    ( cd "$MEM" && timeout 240 ./venv/bin/python push_to_cognee.py "Сессия $(date -Is): $summary" >>"$LOG" 2>&1 \
        && echo "$(date -Is) cognee: episode captured" >>"$LOG" \
        || echo "$(date -Is) cognee: push failed/timeout" >>"$LOG" ) &
  fi
else
  echo "$(date -Is) summarize: empty/failed summary" >>"$LOG"
fi
exit 0
