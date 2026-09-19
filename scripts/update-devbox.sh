#!/usr/bin/env bash
set -euo pipefail

REPO="${T3_PATCHED_REPO:-lucas-varjao/t3code-patched}"
T3_HOME="${T3CODE_HOME:-$HOME/.t3}"
VERSIONS="$T3_HOME/runtime/versions"
API="https://api.github.com/repos/$REPO/releases?per_page=100"

mkdir -p "$VERSIONS"

TMP="$(mktemp -d)"
STAGE=""

cleanup() {
  rm -rf "$TMP"
  if [[ -n "$STAGE" && -d "$STAGE" ]]; then
    rm -rf "$STAGE"
  fi
}
trap cleanup EXIT

echo '=== T3 PATCHED DEVBOX UPDATE ==='

TAG="$(
  python3 - "$API" <<'PY'
import json
import re
import sys
import urllib.request

url = sys.argv[1]

request = urllib.request.Request(
    url,
    headers={
        "Accept": "application/vnd.github+json",
        "User-Agent": "t3code-patched-devbox-updater",
    },
)

with urllib.request.urlopen(request, timeout=30) as response:
    releases = json.load(response)

pattern = re.compile(
    r"^v\d+\.\d+\.\d+-nightly\.\d{8}\.\d+-patch\.\d+$"
)

candidates = [
    release
    for release in releases
    if not release.get("draft")
    and pattern.fullmatch(release.get("tag_name", ""))
    and release.get("published_at")
]

if not candidates:
    raise SystemExit("Nenhuma release patched encontrada.")

candidates.sort(key=lambda r: r["published_at"])
print(candidates[-1]["tag_name"])
PY
)"

echo "Release mais recente: $TAG"

BASE="https://github.com/$REPO/releases/download/$TAG"

curl -fsSL \
  "$BASE/manifest.json" \
  -o "$TMP/manifest.json"

curl -fsSL \
  "$BASE/SHA256SUMS" \
  -o "$TMP/SHA256SUMS"

read -r VERSION UPSTREAM_TAG PATCH_REVISION < <(
  python3 - "$TMP/manifest.json" <<'PY'
import json
import sys

with open(sys.argv[1]) as f:
    manifest = json.load(f)

print(
    manifest["upstreamVersion"],
    manifest["upstreamTag"],
    manifest["patchRevision"],
)
PY
)

EXPECTED_TAG="v${VERSION}-patch.${PATCH_REVISION}"

if [[ "$TAG" != "$EXPECTED_TAG" ]]; then
  echo "Release/manifest inconsistentes:" >&2
  echo "  release:  $TAG" >&2
  echo "  esperado: $EXPECTED_TAG" >&2
  exit 1
fi

if [[ "$UPSTREAM_TAG" != "v$VERSION" ]]; then
  echo "upstreamTag inesperada no manifest: $UPSTREAM_TAG" >&2
  exit 1
fi

ARCHIVE="t3-${VERSION}-linux-x64.tar.gz"
TARGET="$VERSIONS/$VERSION"

echo "Versao upstream: $VERSION"
echo "Patch revision:  $PATCH_REVISION"

if [[ -x "$TARGET/t3" \
   && -f "$TARGET/.install-complete" \
   && -f "$TARGET/.patched-release" \
   && "$(cat "$TARGET/.install-complete")" == "$VERSION" \
   && "$(cat "$TARGET/.patched-release")" == "$TAG" ]]
then
  INSTALLED_VERSION="$("$TARGET/t3" --version)"

  if [[ "$INSTALLED_VERSION" != "t3 v$VERSION" ]]; then
    echo "Runtime marcado como instalado, mas --version diverge:" >&2
    echo "  $INSTALLED_VERSION" >&2
    exit 1
  fi

  echo
  echo "UP TO DATE: $TAG"
  exit 0
fi

RUNNING_PIDS=()

for PROC in /proc/[0-9]*; do
  [[ -r "$PROC/cmdline" ]] || continue

  CMD0="$(
    tr '\0' '\n' < "$PROC/cmdline" 2>/dev/null \
      | head -n 1 \
      || true
  )"

  if [[ "$CMD0" == "$TARGET/t3" ]]; then
    RUNNING_PIDS+=("${PROC##*/}")
  fi
done

if (( ${#RUNNING_PIDS[@]} > 0 )); then
  echo
  echo "DEFERRED: a versao $VERSION esta em execucao e ainda nao e a release $TAG."
  echo "PIDs: ${RUNNING_PIDS[*]}"
  echo "Nenhum processo foi interrompido."
  exit 75
fi

echo
echo '=== DOWNLOAD ==='

curl -fL \
  "$BASE/$ARCHIVE" \
  -o "$TMP/$ARCHIVE"

EXPECTED_SHA="$(
  awk -v file="$ARCHIVE" '
    $2 == file || $2 == "*" file {
      print $1
      exit
    }
  ' "$TMP/SHA256SUMS"
)"

if [[ -z "$EXPECTED_SHA" ]]; then
  echo "$ARCHIVE nao encontrado em SHA256SUMS." >&2
  exit 1
fi

ACTUAL_SHA="$(sha256sum "$TMP/$ARCHIVE" | awk '{print $1}')"

if [[ "$ACTUAL_SHA" != "$EXPECTED_SHA" ]]; then
  echo "Checksum invalido para $ARCHIVE." >&2
  echo "Esperado: $EXPECTED_SHA" >&2
  echo "Obtido:   $ACTUAL_SHA" >&2
  exit 1
fi

echo "Checksum: OK"

echo
echo '=== PREPARANDO RUNTIME ==='

STAGE="$VERSIONS/.staging-${VERSION}-$$"

rm -rf "$STAGE"
mkdir -p "$STAGE"

tar -xzf "$TMP/$ARCHIVE" \
  -C "$STAGE" \
  --strip-components=1

test -x "$STAGE/t3"

BUILT_VERSION="$("$STAGE/t3" --version)"

if [[ "$BUILT_VERSION" != "t3 v$VERSION" ]]; then
  echo "Versao inesperada no archive: $BUILT_VERSION" >&2
  exit 1
fi

printf '%s\n' "$VERSION" > "$STAGE/.install-complete"
printf '%s\n' "$TAG" > "$STAGE/.patched-release"

echo
echo '=== INSTALANDO ==='

if [[ -e "$TARGET" ]]; then
  BACKUP="$VERSIONS/.replaced-${VERSION}-$(date +%Y%m%d-%H%M%S)"
  mv "$TARGET" "$BACKUP"
  echo "Runtime anterior preservado em:"
  echo "  $BACKUP"
fi

mv "$STAGE" "$TARGET"
STAGE=""

echo
echo '=== VALIDACAO ==='

"$TARGET/t3" --version
cat "$TARGET/.patched-release"

echo
echo "INSTALLED: $TAG"
