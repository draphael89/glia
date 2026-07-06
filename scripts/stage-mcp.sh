#!/usr/bin/env bash
# Stage the prebuilt glia-context MCP server for bundling into a distributed
# Glia.app. Produces build-mcp/glia-context-mcp/{dist,node_modules,package.json}.
# The app's MCPProvision.ensureStaged() copies this to a stable ~/.glia/mcp at
# "Enable MCP" time. Pure-JS only — a native binary would break notarization.
#
# Used by make-dmg.sh (NOT the CI Xcode build, which stays Node-free).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT/mcp"

echo "→ building glia-context server…"
npm ci                       # full deps incl. typescript (a devDependency)
npm run build                # tsc → dist/
npm prune --omit=dev         # drop devDeps; keep the runtime (@modelcontextprotocol/sdk)

# Guard: the bundled node_modules must be pure JS. A Mach-O (.node/.dylib) would
# need its own signature and could slip past notarization — fail loudly instead.
if find node_modules \( -name '*.node' -o -name '*.dylib' \) -print -quit | grep -q .; then
  echo "✗ native binary found in mcp/node_modules — would break notarization. Aborting." >&2
  npm ci >/dev/null 2>&1 || true
  exit 1
fi

DEST="$ROOT/build-mcp/glia-context-mcp"
rm -rf "$DEST"; mkdir -p "$DEST"
cp -R dist "$DEST/dist"
cp -R node_modules "$DEST/node_modules"
cp package.json "$DEST/package.json"
echo "✓ staged glia-context server → $DEST ($(du -sh "$DEST" | cut -f1))"

# restore full dev deps so local development/tests keep working
npm ci >/dev/null 2>&1 || true
