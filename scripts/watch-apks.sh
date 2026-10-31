#!/usr/bin/env bash
# Keep the NAS copy of build/app/outputs/flutter-apk in step with the build dir.
#
# Polls rather than using inotify: inotify-tools is not installed on this node,
# and a five-second poll costs nothing when nothing changed (the publisher
# compares mtime+size before doing any work).
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INTERVAL="${APK_WATCH_INTERVAL:-5}"

while true; do
  "$REPO_DIR/scripts/publish-apk-to-nas.sh" || true
  sleep "$INTERVAL"
done
