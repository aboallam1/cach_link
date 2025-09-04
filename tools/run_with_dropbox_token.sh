#!/usr/bin/env bash
# Usage:
#   export DROPBOX_TOKEN='sl.u....'   # set in your shell (do NOT commit)
#   ./tools/run_with_dropbox_token.sh

if [ -z "${DROPBOX_TOKEN}" ]; then
  echo "ERROR: DROPBOX_TOKEN is not set. Export it first:"
  echo "  export DROPBOX_TOKEN='<your_token_here>'"
  exit 1
fi

echo "Launching Flutter web-server with DROPBOX_TOKEN from env (not saved to disk)..."
flutter run -d web-server --dart-define=DROPBOX_TOKEN="${DROPBOX_TOKEN}"
