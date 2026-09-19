#!/usr/bin/env bash
set -euo pipefail

REPO="${T3_PATCHED_REPO:-lucas-varjao/t3code-patched}"
REMOTE_HOST="${T3_PATCHED_REMOTE_HOST:-}"

ROOT="$HOME/.local/opt/t3code-patched"
RELEASES="$ROOT/releases"
CURRENT="$ROOT/current.AppImage"
CURRENT_RELEASE="$ROOT/current-release"

BIN_DIR="$HOME/.local/bin"
APPS_DIR="$HOME/.local/share/applications"
ICON_DIR="$HOME/.local/share/icons/hicolor/512x512/apps"

API="https://api.github.com/repos/$REPO/releases?per_page=100"

mkdir -p "$RELEASES" "$BIN_DIR" "$APPS_DIR" "$ICON_DIR"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo '=== T3 PATCHED CACHYOS UPDATE ==='

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
        "User-Agent": "t3code-patched-cachyos-updater",
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

curl -fsSL "$BASE/manifest.json" -o "$TMP/manifest.json"
curl -fsSL "$BASE/SHA256SUMS" -o "$TMP/SHA256SUMS"

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
APPIMAGE="T3-Code-${VERSION}-x86_64.AppImage"

if [[ "$TAG" != "$EXPECTED_TAG" ]]; then
  echo "Release/manifest inconsistentes:" >&2
  echo "  release:  $TAG" >&2
  echo "  esperado: $EXPECTED_TAG" >&2
  exit 1
fi

if [[ "$UPSTREAM_TAG" != "v$VERSION" ]]; then
  echo "upstreamTag inesperada: $UPSTREAM_TAG" >&2
  exit 1
fi

echo "Versao upstream: $VERSION"
echo "Patch revision:  $PATCH_REVISION"

if [[ -L "$CURRENT" \
   && -f "$CURRENT_RELEASE" \
   && "$(cat "$CURRENT_RELEASE")" == "$TAG" \
   && -x "$CURRENT" ]]
then
  echo
  echo "UP TO DATE: $TAG"
  exit 0
fi

if [[ -z "$REMOTE_HOST" ]]; then
  echo
  echo 'DEFERRED: T3_PATCHED_REMOTE_HOST nao foi configurado.'
  exit 75
fi

echo
echo '=== VERIFICANDO DEVBOX ==='
echo "Host: $REMOTE_HOST"

set +e
REMOTE_TAG="$(
  ssh \
    -o BatchMode=yes \
    -o ConnectTimeout=5 \
    -o ConnectionAttempts=1 \
    "$REMOTE_HOST" \
    bash -s -- "$VERSION" <<'REMOTE'
version="$1"
cat "$HOME/.t3/runtime/versions/$version/.patched-release" 2>/dev/null || true
REMOTE
)"
SSH_STATUS=$?
set -e

if [[ "$SSH_STATUS" -ne 0 ]]; then
  echo
  echo "DEFERRED: nao foi possivel verificar a devbox."
  exit 75
fi

if [[ "$REMOTE_TAG" != "$TAG" ]]; then
  echo
  echo "DEFERRED: a devbox ainda nao possui $TAG."
  echo "Encontrado: ${REMOTE_TAG:-nenhum}"
  exit 75
fi

echo "Devbox pronta: $REMOTE_TAG"

echo
echo '=== DOWNLOAD ==='

curl -fL \
  "$BASE/$APPIMAGE" \
  -o "$TMP/$APPIMAGE"

EXPECTED_SHA="$(
  awk -v file="$APPIMAGE" '
    $2 == file || $2 == "*" file {
      print $1
      exit
    }
  ' "$TMP/SHA256SUMS"
)"

if [[ -z "$EXPECTED_SHA" ]]; then
  echo "$APPIMAGE nao encontrado em SHA256SUMS." >&2
  exit 1
fi

ACTUAL_SHA="$(sha256sum "$TMP/$APPIMAGE" | awk '{print $1}')"

if [[ "$ACTUAL_SHA" != "$EXPECTED_SHA" ]]; then
  echo "Checksum invalido para $APPIMAGE." >&2
  echo "Esperado: $EXPECTED_SHA" >&2
  echo "Obtido:   $ACTUAL_SHA" >&2
  exit 1
fi

echo "Checksum: OK"

chmod +x "$TMP/$APPIMAGE"

# Confirma que o arquivo e um AppImage executavel valido.
"$TMP/$APPIMAGE" --appimage-offset >/dev/null

echo
echo '=== INSTALANDO ==='

TARGET_DIR="$RELEASES/$TAG"
TARGET="$TARGET_DIR/$APPIMAGE"

mkdir -p "$TARGET_DIR"

mv "$TMP/$APPIMAGE" "$TARGET"
cp "$TMP/manifest.json" "$TARGET_DIR/manifest.json"
cp "$TMP/SHA256SUMS" "$TARGET_DIR/SHA256SUMS"

chmod +x "$TARGET"

NEW_LINK="$ROOT/.current.AppImage.new"
rm -f "$NEW_LINK"
ln -s "$TARGET" "$NEW_LINK"
mv -Tf "$NEW_LINK" "$CURRENT"

printf '%s\n' "$TAG" > "$CURRENT_RELEASE"

echo
echo '=== EXTRAINDO ICONE ==='

rm -rf "$TMP/squashfs-root"

(
  cd "$TMP"

  "$CURRENT" \
    --appimage-extract \
    usr/share/icons/hicolor/512x512/apps/t3code.png \
    >/dev/null
)

install -Dm644 \
  "$TMP/squashfs-root/usr/share/icons/hicolor/512x512/apps/t3code.png" \
  "$ICON_DIR/t3code-patched.png"

echo
echo '=== LAUNCHER ==='

cat > "$BIN_DIR/t3code-nightly" <<LAUNCHER
#!/bin/sh
export T3CODE_DISABLE_AUTO_UPDATE=1
exec "$CURRENT" "\$@"
LAUNCHER

chmod +x "$BIN_DIR/t3code-nightly"

ln -sfn \
  t3code-nightly \
  "$BIN_DIR/t3-code-nightly-desktop"

echo
echo '=== DESKTOP ENTRY ==='

cat > "$APPS_DIR/t3code.desktop" <<DESKTOP
[Desktop Entry]
Name=T3 Code Nightly
Comment=Nightly desktop control surface for local coding agents
Exec=$BIN_DIR/t3code-nightly %U
TryExec=$BIN_DIR/t3code-nightly
Terminal=false
Type=Application
Icon=t3code-patched
StartupWMClass=t3code
Categories=Development;
MimeType=x-scheme-handler/t3code;
DESKTOP

# Mantem deep links apontando para a release selecionada pelo nosso updater.
cat > "$APPS_DIR/com.t3tools.T3Code.desktop" <<HANDLER
[Desktop Entry]
Type=Application
Name=T3 Code (Nightly)
Exec="$CURRENT" %U
Terminal=false
NoDisplay=true
StartupNotify=false
MimeType=x-scheme-handler/t3code;
HANDLER

# Handler legado criado pela instalacao anterior do AUR.
rm -f "$APPS_DIR/t3code-url-handler.desktop"

if command -v xdg-mime >/dev/null 2>&1; then
  xdg-mime default     com.t3tools.T3Code.desktop     x-scheme-handler/t3code     >/dev/null 2>&1 || true
fi

if command -v update-desktop-database >/dev/null 2>&1; then
  update-desktop-database "$APPS_DIR" >/dev/null 2>&1 || true
fi

if command -v gtk-update-icon-cache >/dev/null 2>&1; then
  gtk-update-icon-cache \
    -f \
    -t \
    "$HOME/.local/share/icons/hicolor" \
    >/dev/null 2>&1 || true
fi

if command -v kbuildsycoca6 >/dev/null 2>&1; then
  kbuildsycoca6 >/dev/null 2>&1 || true
fi

echo
echo '=== VALIDACAO ==='
echo "Release: $(cat "$CURRENT_RELEASE")"
echo "Current: $(readlink -f "$CURRENT")"
echo "Launcher: $(readlink -f "$BIN_DIR/t3-code-nightly-desktop")"

echo
echo "INSTALLED: $TAG"
