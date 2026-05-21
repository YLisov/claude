#!/usr/bin/env bash
# Обёртка запуска cognee MCP-сервера (L4): cwd = memory-system (для .env), venv cognee, stdio.
cd /home/claude/.claude/memory-system || exit 1
exec ./venv/bin/cognee-mcp --transport stdio --log-level warning "$@"
