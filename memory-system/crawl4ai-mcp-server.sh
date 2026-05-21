#!/usr/bin/env bash
cd /home/claude/.claude/memory-system || exit 1
exec ./venv/bin/python crawl4ai-mcp.py "$@"
