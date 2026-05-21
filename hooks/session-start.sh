#!/usr/bin/env bash
# SessionStart hook (L3 continuity): подгружает handoff прошлой сессии в контекст.
# stdout этого хука Claude Code добавляет в контекст на старте сессии.
HANDOFF="$HOME/.claude/memory-system/handoff.md"
if [ -s "$HANDOFF" ]; then
  echo "## Контекст из прошлой сессии (L3 handoff)"
  echo
  cat "$HANDOFF"
fi
exit 0
