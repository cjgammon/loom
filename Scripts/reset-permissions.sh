#!/usr/bin/env bash
#
# reset-permissions.sh — clear Spool's stale TCC (privacy) permission entries.
#
# macOS keys Screen Recording / Camera / Microphone grants to an app's code-signing
# identity. When Spool is built with an unstable (ad-hoc) signature, every rebuild
# looks like a "new" app and macOS re-prompts even though an entry already exists.
# Resetting the entries here lets you grant them cleanly once you're signing with a
# stable Development Team (see README → First-run permissions).
#
# Usage: ./Scripts/reset-permissions.sh

set -euo pipefail

BUNDLE_ID="${1:-com.cjgammon.Spool}"

echo "Resetting privacy permissions for ${BUNDLE_ID}…"

# Each reset is best-effort; a service with no existing entry is not an error here.
for service in ScreenCapture Camera Microphone; do
  if tccutil reset "$service" "$BUNDLE_ID" 2>/dev/null; then
    echo "  ✓ reset $service"
  else
    echo "  • $service had nothing to reset"
  fi
done

cat <<'EOF'

Done. Next:
  1. Quit Spool if it is running.
  2. Make sure the target is signed with your Development Team (not ad-hoc).
  3. Rebuild & run, grant Screen Recording when prompted, then relaunch Spool.
EOF
