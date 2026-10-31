#!/usr/bin/env bash
# Publish built APKs to the NAS hermes share.
#
# Idempotent: a build whose bytes are already on the NAS is not copied again.
# Every copy is named by content hash, verified after the write, and pointed at
# by latest.txt. Designed to be run by watch-apks.sh after every build, but safe
# to run by hand.
#
# Env overrides (used by the tests):
#   APK_DIR   directory holding *.apk        (default: <repo>/build/app/outputs/flutter-apk)
#   DEST      destination directory on NAS   (default: /srv/share/conduit/apks)
#   RETAIN    how many content builds to keep (default: 10)
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APK_DIR="${APK_DIR:-$REPO_DIR/build/app/outputs/flutter-apk}"
DEST="${DEST:-/srv/share/conduit/apks}"
RETAIN="${RETAIN:-10}"
STATE_DIR="${STATE_DIR:-$HOME/.hermes/state}"
STATE_FILE="$STATE_DIR/apk-publish.state"
LOG_FILE="${LOG_FILE:-$HOME/.hermes/logs/apk-publish.log}"
LOCK_FILE="$STATE_DIR/apk-publish.lock"

mkdir -p "$STATE_DIR" "$(dirname "$LOG_FILE")" "$DEST"
exec 9>"$LOCK_FILE"
flock -n 9 || exit 0

log() { printf '%s %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*" | tee -a "$LOG_FILE"; }

VERSION="$(sed -n 's/^version: *\([^+ ]*\).*/\1/p' "$REPO_DIR/pubspec.yaml" | head -1)"
GITSHORT="$(git -C "$REPO_DIR" rev-parse --short HEAD 2>/dev/null || echo nogit)"

# state: "<path>\t<mtime>\t<size>\t<sha>"
state_get() {
  [ -f "$STATE_FILE" ] || return 0
  awk -F'\t' -v p="$1" '$1==p {print $2"\t"$3"\t"$4; exit}' "$STATE_FILE"
}
state_put() {
  local path="$1" mtime="$2" size="$3" sha="$4" tmp
  tmp="$(mktemp "$STATE_DIR/.state.XXXXXX")"
  { [ -f "$STATE_FILE" ] && awk -F'\t' -v p="$path" '$1!=p' "$STATE_FILE" || true
    printf '%s\t%s\t%s\t%s\n' "$path" "$mtime" "$size" "$sha"
  } > "$tmp"
  mv -f "$tmp" "$STATE_FILE"
}

published=0
shopt -s nullglob
for apk in "$APK_DIR"/*.apk; do
  [ -f "$apk" ] || continue
  mtime="$(stat -c %.9Y "$apk")"
  size="$(stat -c %s "$apk")"
  read -r old_mtime old_size old_sha <<<"$(state_get "$apk" || true)"
  if [ "${old_mtime:-}" = "$mtime" ] && [ "${old_size:-}" = "$size" ]; then
    continue
  fi

  # A build in progress writes a growing file. Wait until two reads agree and
  # the file has been quiet for a second.
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    s1="$(stat -c %s "$apk")"; sleep 1; s2="$(stat -c %s "$apk")"
    m2="$(stat -c %Y "$apk")"
    [ "$s1" = "$s2" ] && [ $(( $(date +%s) - m2 )) -ge 1 ] && break
  done
  size="$(stat -c %s "$apk")"; mtime="$(stat -c %.9Y "$apk")"

  sha="$(sha256sum "$apk" | awk '{print $1}')"
  sha8="${sha:0:8}"
  name="conduit-hermes-${VERSION}-${GITSHORT}-${sha8}.apk"
  target="$DEST/$name"

  if [ -f "$target" ] && [ "$(stat -c %s "$target")" = "$size" ] && \
     [ "$(sha256sum "$target" | awk '{print $1}')" = "$sha" ]; then
    log "already published $name"
  else
    tmp="$DEST/.${name}.part.$$"
    log "publishing $(basename "$apk") ($size bytes) -> $name"
    cp -f "$apk" "$tmp"
    got="$(sha256sum "$tmp" | awk '{print $1}')"
    if [ "$got" != "$sha" ]; then
      rm -f "$tmp"
      log "ERROR checksum mismatch after copy: expected $sha got $got"
      exit 1
    fi
    mv -f "$tmp" "$target"
    printf '%s  %s\n' "$sha" "$name" > "$target.sha256"
    log "published $name sha256=$sha"
    published=$((published + 1))
  fi

  # latest.txt is a pointer, not a duplicate: the NAS holds one copy per build.
  cat > "$DEST/.latest.tmp.$$" <<EOF
file=$name
sha256=$sha
bytes=$size
version=$VERSION
commit=$(git -C "$REPO_DIR" rev-parse HEAD 2>/dev/null || echo unknown)
built=$(date -u -d "@$mtime" +%Y-%m-%dT%H:%M:%SZ)
published=$(date -u +%Y-%m-%dT%H:%M:%SZ)
EOF
  mv -f "$DEST/.latest.tmp.$$" "$DEST/latest.txt"

  state_put "$apk" "$mtime" "$size" "$sha"
done

# Retention: only ever delete this publisher's own content-named builds.
mapfile -t built < <(ls -1t "$DEST"/conduit-hermes-*.apk 2>/dev/null || true)
if [ "${#built[@]}" -gt "$RETAIN" ]; then
  for old in "${built[@]:$RETAIN}"; do
    log "retiring $(basename "$old")"
    rm -f "$old" "$old.sha256"
  done
fi

if [ "$published" -eq 0 ]; then
  exit 0
fi
log "done: $published new build(s) on $DEST"
