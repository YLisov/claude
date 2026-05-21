#!/usr/bin/env bash
set -a
# shellcheck source=.env
source "$(dirname "$0")/.env"
set +a
exec npx -y @modelcontextprotocol/server-github
