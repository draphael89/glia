#!/usr/bin/env bash
# Build glia-context and register it with Claude Code (and print the snippet for
# any other MCP client). Idempotent — safe to re-run.
set -euo pipefail
cd "$(dirname "$0")"
DIST="$(pwd)/dist/index.js"

echo "→ installing deps + building…"
npm install --silent
npm run build --silent

echo "→ verifying…"
node --test dist/*.test.js >/dev/null 2>&1 && echo "  unit tests pass" || echo "  ⚠ unit tests failed (continuing)"

if command -v claude >/dev/null 2>&1; then
  # re-register cleanly at USER scope so it's available in every project/session
  claude mcp remove -s user glia-context >/dev/null 2>&1 || true
  claude mcp remove glia-context >/dev/null 2>&1 || true
  claude mcp add -s user glia-context node "$DIST"
  echo "  ✓ registered with Claude Code (user scope) as 'glia-context'"
else
  echo "  (claude CLI not found — skipping Claude Code registration)"
fi

cat <<EOF

Built: $DIST

For Hermes / other MCP clients, add this stdio server:

  {
    "mcpServers": {
      "glia-context": { "command": "node", "args": ["$DIST"] }
    }
  }

Optional env (see README): GLIA_PSYCHE, GBRAIN_SOURCE_DIR, GBRAIN_CMD.

Then in a session:  "prime_context with what I'm trying to do."
EOF
